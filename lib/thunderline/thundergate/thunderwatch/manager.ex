defmodule Thundergate.Thunderwatch.Manager do
  @moduledoc """
  (Moved from `Thunderline.Thunderwatch.Manager` – now part of Thundergate domain)

  See original module docs in deprecated shim. This file is a verbatim relocation; future
  Thundergate-specific policy (e.g., security event enrichment) will extend here.
  """
  use GenServer
  require Logger
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "thunderwatch:events"
  @index_table __MODULE__.Index
  @events_table __MODULE__.Events

  # Public API --------------------------------------------------------------
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)
  def current_seq, do: :persistent_term.get({@index_table, :seq}, 0)

  def snapshot do
    case :ets.info(@index_table) do
      :undefined -> %{}
      _ -> :ets.tab2list(@index_table) |> Enum.into(%{}) |> Map.drop([:__meta__])
    end
  end

  def changes_since(seq) when is_integer(seq) do
    case :ets.info(@events_table) do
      :undefined -> []
      _ ->
        :ets.tab2list(@events_table)
        |> Enum.map(fn {_k, ev} -> ev end)
        |> Enum.filter(&(&1.seq > seq))
        |> Enum.sort_by(& &1.seq)
    end
  end

  def rescan, do: GenServer.cast(__MODULE__, :rescan)

  # GenServer ---------------------------------------------------------------
  @impl true
  def init(_opts) do
    cfg = Application.get_env(:thunderline, :thunderwatch, [])
    roots = Keyword.get(cfg, :roots, ["lib", "priv"]) |> Enum.filter(&File.dir?/1)
    ignore = Keyword.get(cfg, :ignore, [~r{/_build/}, ~r{/deps/}, ~r{/.git/}])
    hash? = Keyword.get(cfg, :hash?, false)
    max_events = Keyword.get(cfg, :max_events, 5_000)

    :ets.new(@index_table, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@events_table, [:named_table, :public, :ordered_set, read_concurrency: true])
    put_seq(0)
    :ets.insert(@index_table, {:__meta__, %{roots: roots, started_at: System.system_time()}})

    watchers = Enum.map(roots, &start_fs_watcher/1)
    Enum.each(roots, &scan_dir(&1, ignore, hash?))

    state = %{roots: roots, ignore: ignore, hash?: hash?, max_events: max_events, watchers: watchers}
    Logger.info("[Thunderwatch] started roots=#{inspect(roots)} hash?=#{hash?} (Thundergate domain)")
    {:ok, state}
  end

  @impl true
  def handle_cast(:rescan, %{roots: roots, ignore: ignore, hash?: hash?} = state) do
    Enum.each(roots, &scan_dir(&1, ignore, hash?))
    {:noreply, state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) when is_list(events) do
    if File.regular?(path) and not ignored?(path, state.ignore) do
      meta = file_meta(path, state.hash?) |> Map.put(:events, events)
      update_index(path, meta)
    end
    {:noreply, state}
  end
  def handle_info({:file_event, _watcher_pid, :stop}, state), do: {:noreply, state}
  def handle_info(msg, state) do
    Logger.debug("[Thunderwatch] unknown message #{inspect(msg)}")
    {:noreply, state}
  end

  # Internal ---------------------------------------------------------------
  defp start_fs_watcher(root) do
    try do
      {:ok, pid} = FileSystem.start_link(dirs: [root], name: via_name(root))
      FileSystem.subscribe(pid)
      pid
    rescue
      e -> Logger.error("[Thunderwatch] failed watcher start root=#{root} error=#{Exception.message(e)}"); nil
    end
  end

  defp via_name(root), do: String.to_atom("thunderwatch_" <> Base.encode16(:erlang.phash2(root) |> :erlang.term_to_binary()))

  defp scan_dir(dir, ignore, hash?) do
    pattern = Path.join([dir, "**", "*"])
    for path <- Path.wildcard(pattern, match_dot: true), File.regular?(path), not ignored?(path, ignore) do
      update_index(path, file_meta(path, hash?))
    end
  rescue
    e -> Logger.warning("[Thunderwatch] scan_dir error dir=#{dir} error=#{inspect(e)}")
  end

  defp ignored?(path, patterns) do
    Enum.any?(patterns, fn
      %Regex{} = r -> path =~ r
      fun when is_function(fun, 1) -> fun.(path)
      {m,f,a} -> apply(m,f,[path|a])
      _ -> false
    end)
  end

  defp file_meta(path, hash?) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime, size: size, type: type}} -> %{mtime: mtime, size: size, type: type, hash: if(hash?, do: safe_hash(path), else: nil)}
      _ -> %{deleted: true}
    end
  end

  defp safe_hash(path) do
    try do
      path
      |> File.stream!([], 64 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc -> :crypto.hash_update(acc, chunk) end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    rescue
      _ -> nil
    end
  end

  defp update_index(path, meta) do
    seq = bump_seq()
    domain = infer_domain(path)
    enriched_meta = meta |> Map.put(:domain, domain)
    :ets.insert(@index_table, {path, Map.put(enriched_meta, :seq, seq)})
    ring_store_event(%{path: path, seq: seq, meta: enriched_meta, at: System.system_time(:microsecond)})
    broadcast(%{type: :file_changed, path: path, seq: seq, meta: enriched_meta, domain: domain})
  end

  defp ring_store_event(event) do
    :ets.insert(@events_table, {event.seq, event})
    max = Application.get_env(:thunderline, :thunderwatch, []) |> Keyword.get(:max_events, 5_000)
    size = :ets.info(@events_table, :size)
    if size && size > max do
      case :ets.first(@events_table) do
        :'$end_of_table' -> :ok
        oldest -> :ets.delete(@events_table, oldest)
      end
    end
  end

  defp broadcast(evt) do
    PubSub.broadcast(@pubsub, @topic, {:thunderwatch, evt})
    try do
      domain = evt.domain || :thundergate
      Thunderline.Thunderflow.EventBuffer.put({:domain_event, domain, %{
        message: "#{domain} file changed: #{Path.basename(evt.path)}",
        type: :thunderwatch_update,
        status: :info,
        path: evt.path,
        domain: domain,
        timestamp: System.system_time(:microsecond)
      }})
    rescue
      _ -> :ok
    end
  end

  @domain_markers [
    thunderbolt: "/thunderbolt/",
    thunderblock: "/thunderblock/",
    thunderflow: "/thunderflow/",
    thundergate: "/thundergate/",
    thunderlink: "/thunderlink/",
    thundercrown: "/thundercrown/",
    thunderguard: "/thunderguard/",
    thundergrid: "/thundergrid/"
  ]
  defp infer_domain(path), do: Enum.find_value(@domain_markers, :system, fn {dom, marker} -> if String.contains?(path, marker), do: dom end)

  defp bump_seq do
    seq = current_seq() + 1
    put_seq(seq)
    seq
  end
  defp put_seq(seq), do: :persistent_term.put({@index_table, :seq}, seq)
end
