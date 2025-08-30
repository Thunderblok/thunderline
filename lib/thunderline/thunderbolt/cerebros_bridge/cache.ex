defmodule Thunderline.Thunderbolt.CerebrosBridge.Cache do
  @moduledoc "Lightweight ETS cache (time-based TTL) for Cerebros bridge calls."
  use GenServer
  @table :cerebros_bridge_cache

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec put(term, term) :: true
  def put(key, val), do: :ets.insert(@table, {key, {System.monotonic_time(:millisecond), val}})

  @spec get(term, non_neg_integer) :: {:hit, term} | {:miss, nil}
  def get(key, ttl_ms \\ 30_000) do
    case :ets.lookup(@table, key) do
      [{^key, {ts, v}}] ->
        if System.monotonic_time(:millisecond) - ts <= ttl_ms do
          :telemetry.execute([:cerebros, :bridge, :cache, :hit], %{}, %{key: key})
          {:hit, v}
        else
          :telemetry.execute([:cerebros, :bridge, :cache, :miss], %{}, %{key: key})
          {:miss, nil}
        end

      _ ->
        :telemetry.execute([:cerebros, :bridge, :cache, :miss], %{}, %{key: key})
        {:miss, nil}
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}
    }
  end
end
