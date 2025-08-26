defmodule Thunderline.Thundercrown.Daisy.Base do
  @moduledoc "Canonical Crown namespace: Daisy base swarm logic (migrated from Thunderline.Daisy.Base)."
  use GenServer

  @doc """
  Macro injected into Daisy swarm modules (Affect/Identity/Novelty/Ponder).

  Provides:
  * `start_link/1` – starts a GenServer registered under the swarm module name
  * `child_spec/1` – so swarm modules can be added directly to supervision trees
  * Delegates: `preview/0`, `commit/2`, `update/2`, `snapshot/0`, `restore/1`

  Each swarm maintains an in-memory bounded list of scored shards with decay.
  Configuration options (passed at supervision start):
    * `:max_mem` (default 8)
    * `:decay` (default 0.85)
  """
  defmacro __using__(_opts) do
    quote do
      @doc false
      def start_link(opts \\ []), do: Thunderline.Thundercrown.Daisy.Base.start_link(Keyword.merge(opts, name: __MODULE__))

      @doc false
      def child_spec(arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [List.wrap(arg)]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end

      # Convenience zero-arity delegates using the module itself as the name
      def preview, do: Thunderline.Thundercrown.Daisy.Base.preview(__MODULE__)
      def commit(inj, del), do: Thunderline.Thundercrown.Daisy.Base.commit(__MODULE__, inj, del)
      def update(shard, score), do: Thunderline.Thundercrown.Daisy.Base.update(__MODULE__, shard, score)
      def snapshot, do: Thunderline.Thundercrown.Daisy.Base.snapshot(__MODULE__)
      def restore(mem), do: Thunderline.Thundercrown.Daisy.Base.restore(__MODULE__, mem)
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  def init(opts), do: {:ok, %{mem: [], max_mem: opts[:max_mem] || 8, decay: opts[:decay] || 0.85}}

  def preview(name), do: GenServer.call(name, :preview)
  def commit(name, inj, del), do: GenServer.cast(name, {:commit, inj, del})
  def update(name, shard, score), do: GenServer.cast(name, {:update, shard, score})
  def snapshot(name), do: GenServer.call(name, :snapshot)
  def restore(name, mem), do: GenServer.cast(name, {:restore, mem})

  def handle_call(:snapshot, _from, %{mem: mem} = s), do: {:reply, mem, s}
  def handle_cast({:restore, mem}, s) when is_list(mem), do: {:noreply, %{s | mem: mem}}
  def handle_cast({:update, shard, score}, %{mem: mem, max_mem: k} = s) do
    m1 = (mem ++ [%{shard: shard, score: score, ts: System.monotonic_time()}]) |> Enum.take(-k)
    {:noreply, %{s | mem: m1}}
  end
  def handle_call(:preview, _from, %{mem: mem, decay: d} = s) do
    dec = Enum.with_index(mem) |> Enum.map(fn {m, i} -> %{m | score: m.score * :math.pow(d, length(mem)-1-i)} end)
    inj = dec |> Enum.max_by(& &1.score, fn -> nil end)
    del = dec |> Enum.min_by(& &1.score, fn -> nil end)
    {:reply, {inj, del}, s}
  end
  def handle_cast({:commit, _inj, _del}, s), do: {:noreply, s}
end
