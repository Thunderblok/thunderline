defmodule Thunderline.Thunderbolt.CerebrosBridge.Cache do
  @moduledoc """
  Feature-gated ETS-backed cache for Cerebros bridge results.

  Reads runtime configuration from `:thunderline, :cerebros_bridge` (the `:cache`
  keyword list) so we can adjust TTL and maximum entries without recompilation.
  """
  use GenServer

  require Logger

  @table :cerebros_bridge_cache

  @type ttl_ms :: non_neg_integer() | nil

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args),
    do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec get(term, ttl_ms()) :: {:hit, term} | {:miss, nil}
  def get(key, ttl_override \\ nil) do
    call(__MODULE__, {:get, key, ttl_override})
  end

  @spec put(term, term, ttl_ms()) :: :ok
  def put(key, value, ttl_override \\ nil) do
    cast(__MODULE__, {:put, key, value, ttl_override})
  end

  @spec purge() :: :ok
  def purge, do: cast(__MODULE__, :purge)

  @spec refresh() :: :ok
  def refresh, do: cast(__MODULE__, :refresh)

  @spec stats() :: %{enabled?: boolean(), max_entries: integer() | nil, size: non_neg_integer()}
  def stats do
    call(__MODULE__, :stats)
  end

  @spec enabled?() :: boolean()
  def enabled? do
    case Process.whereis(__MODULE__) do
      nil -> false
      _ -> call(__MODULE__, :enabled?)
    end
  catch
    :exit, _ -> false
  end

  @impl true
  def init(:ok) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [
            :ordered_set,
            :named_table,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])

        tid ->
          tid
      end

    {:ok, load_config(%{table: table})}
  end

  @impl true
  def handle_call({:get, _key, _ttl_override}, _from, %{enabled?: false} = state) do
    {:reply, {:miss, nil}, state}
  end

  def handle_call({:get, key, ttl_override}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, inserted_ms, value}] ->
        ttl_ms = ttl_override || state.ttl_ms

        if stale?(inserted_ms, ttl_ms) do
          :ets.delete(state.table, key)
          :telemetry.execute([:cerebros, :bridge, :cache, :miss], %{}, %{key: key, reason: :ttl})
          {:reply, {:miss, nil}, state}
        else
          :telemetry.execute([:cerebros, :bridge, :cache, :hit], %{}, %{key: key})
          {:reply, {:hit, value}, state}
        end

      _ ->
        :telemetry.execute([:cerebros, :bridge, :cache, :miss], %{}, %{key: key, reason: :absent})
        {:reply, {:miss, nil}, state}
    end
  end

  def handle_call(:stats, _from, state) do
    size = :ets.info(state.table, :size) || 0
    {:reply, %{enabled?: state.enabled?, max_entries: state.max_entries, size: size}, state}
  end

  def handle_call(:enabled?, _from, state), do: {:reply, state.enabled?, state}

  @impl true
  def handle_cast({:put, _key, _value, _ttl}, %{enabled?: false} = state), do: {:noreply, state}

  def handle_cast({:put, key, value, ttl_override}, state) do
    ttl_ms = ttl_override || state.ttl_ms
    inserted_ms = now_ms()
    :ets.insert(state.table, {key, inserted_ms, value})

    maybe_evict(state)

    :telemetry.execute([:cerebros, :bridge, :cache, :store], %{ttl_ms: ttl_ms}, %{key: key})
    {:noreply, state}
  end

  def handle_cast(:purge, state) do
    :ets.delete_all_objects(state.table)
    :telemetry.execute([:cerebros, :bridge, :cache, :purge], %{}, %{})
    {:noreply, state}
  end

  def handle_cast(:refresh, state), do: {:noreply, load_config(state)}

  @impl true
  def handle_info({:ETS, _tid, _event, _pid, _data}, state), do: {:noreply, state}

  defp load_config(%{table: table} = state) do
    raw = Application.get_env(:thunderline, :cerebros_bridge, [])
    cache = Keyword.get(raw, :cache, [])

    state
    |> Map.put(:table, table)
    |> Map.put(:enabled?, truthy?(Keyword.get(cache, :enabled, true)))
    |> Map.put(:ttl_ms, Keyword.get(cache, :ttl_ms, 30_000))
    |> Map.put(:max_entries, Keyword.get(cache, :max_entries, 512))
  end

  defp maybe_evict(%{max_entries: max, table: table}) when is_integer(max) and max > 0 do
    size = :ets.info(table, :size) || 0

    if size > max do
      drop = size - max
      evict_oldest(table, drop)
      :telemetry.execute([:cerebros, :bridge, :cache, :evict], %{count: drop}, %{})
    end
  end

  defp maybe_evict(_state), do: :ok

  defp evict_oldest(table, count) do
    table
    |> :ets.foldl(fn {key, inserted_ms, _value}, acc -> [{key, inserted_ms} | acc] end, [])
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.take(count)
    |> Enum.each(fn {key, _} -> :ets.delete(table, key) end)
  end

  defp call(server, message) do
    GenServer.call(server, message)
  catch
    :exit, _ -> {:miss, nil}
  end

  defp cast(server, message) do
    GenServer.cast(server, message)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp truthy?(value) when value in [false, "false", "FALSE", 0, "0", nil], do: false
  defp truthy?(_), do: true

  defp stale?(_inserted_ms, nil), do: false
  defp stale?(_inserted_ms, ttl_ms) when ttl_ms <= 0, do: false
  defp stale?(inserted_ms, ttl_ms), do: now_ms() - inserted_ms > ttl_ms

  defp now_ms, do: System.monotonic_time(:millisecond)
end
