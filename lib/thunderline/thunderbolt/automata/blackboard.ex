defmodule Thunderline.Thunderbolt.Automata.Blackboard do
  @moduledoc """
  Thunderbolt Automata Blackboard - Shared Knowledge Space

  (Moved from legacy `Thunderline.Automata.Blackboard`). This relocation aligns Automata runtime constructs under the Thunderbolt domain.
  The legacy wrapper module has been removed; use this canonical namespace directly.
  """
  use GenServer
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "automata:blackboard"

  @typedoc "Blackboard key"
  @type key :: term()
  @typedoc "Arbitrary value stored in blackboard"
  @type value :: term()
  @typedoc "Result for fetch operations"
  @type fetch_result :: {:ok, value()} | :error

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(key(), value(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.cast(__MODULE__, {:put, scope, key, value})
  end

  @spec fetch(key(), keyword()) :: fetch_result()
  def fetch(key, opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.call(__MODULE__, {:fetch, scope, key})
  end

  @spec get(key(), value(), keyword()) :: value()
  def get(key, default \\ nil, opts \\ []) do
    case fetch(key, opts) do
      {:ok, v} -> v
      :error -> default
    end
  end

  @spec keys(keyword()) :: [key()]
  def keys(opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.call(__MODULE__, {:keys, scope})
  end

  def snapshot(scope \\ :global), do: GenServer.call(__MODULE__, {:snapshot, scope})

  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  # GenServer callbacks
  @impl true
  def init(_opts) do
    global = :ets.new(:thunderbolt_automata_blackboard_global, [:named_table, :public, read_concurrency: true])
    local = :ets.new(:thunderbolt_automata_blackboard_node, [:named_table, :public, read_concurrency: true])
    state = %{data: %{global: %{}, node: %{}}, tables: %{global: global, node: local}}
    {:ok, state}
  end

  @impl true
  def handle_cast({:put, scope, key, value}, state) when scope in [:global, :node] do
    ts = System.system_time(:millisecond)
    new_state = put_in(state, [:data, scope, key], value)
    :ets.insert(state.tables[scope], {key, value})
    notify(scope, key, value, ts)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:fetch, scope, key}, _from, state) do
    case :ets.lookup(state.tables[scope], key) do
      [{^key, value}] -> {:reply, {:ok, value}, state}
      [] -> {:reply, :error, state}
    end
  end

  def handle_call({:keys, scope}, _from, state) do
    ks = :ets.tab2list(state.tables[scope]) |> Enum.map(&elem(&1, 0))
    {:reply, ks, state}
  end

  def handle_call({:snapshot, scope}, _from, state) do
    {:reply, Map.get(state.data, scope), state}
  end

  defp notify(scope, key, value, ts) do
    PubSub.broadcast(@pubsub, @topic, {:blackboard_update, %{scope: scope, key: key, value: value, ts: ts}})
  end
end
