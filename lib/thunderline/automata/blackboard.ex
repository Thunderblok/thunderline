defmodule Thunderline.Automata.Blackboard do
  @moduledoc """
  Automata Blackboard - Shared Knowledge Space

  Provides a hierarchical blackboard with two scopes:
  - :global (cluster-wide logical singleton - this process instance)
  - :node (per-node ephemeral data)

  Features:
  * Lock-free reads via ETS (read_concurrency)
  * Single writer process (this GenServer) for consistency
  * PubSub notifications on every update (topic: "automata:blackboard")
  * Simple put/fetch/get/keys/snapshot API
  * Mapping to Automata Features (concurrency, modularity, simplicity)

  Roadmap:
  * CRDT replication across nodes (Horde / delta-CRDT)
  * Persistence snapshots
  * Filtered subscriptions by key prefix
  * TTL / eviction policies
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "automata:blackboard"

  @typedoc "Blackboard key"
  @type key :: term()
  @typedoc "Arbitrary value stored in blackboard"
  @type value :: term()
  @typedoc "Result for fetch operations"
  @type fetch_result :: {:ok, value()} | :error

  # -- Public API --

  @doc "Start the blackboard under a supervisor"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Put a value in the blackboard for scope (:global | :node)."
  @spec put(key(), value(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.cast(__MODULE__, {:put, scope, key, value})
  end

  @doc "Fetch a value returning {:ok, value} | :error"
  @spec fetch(key(), keyword()) :: fetch_result()
  def fetch(key, opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.call(__MODULE__, {:fetch, scope, key})
  end

  @doc "Get a value or default"
  @spec get(key(), value(), keyword()) :: value()
  def get(key, default \\ nil, opts \\ []) do
    case fetch(key, opts) do
      {:ok, v} -> v
      :error -> default
    end
  end

  @doc "List keys for a scope"
  @spec keys(keyword()) :: [key()]
  def keys(opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    GenServer.call(__MODULE__, {:keys, scope})
  end

  @doc "Return snapshot map for scope"
  def snapshot(scope \\ :global), do: GenServer.call(__MODULE__, {:snapshot, scope})

  @doc "Subscribe to all updates. Messages: {:blackboard_update, %{scope: scope, key: key, value: value, ts: ts}}"
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  # -- GenServer callbacks --
  @impl true
  def init(_opts) do
    global = :ets.new(:automata_blackboard_global, [:named_table, :public, read_concurrency: true])
    local = :ets.new(:automata_blackboard_node, [:named_table, :public, read_concurrency: true])
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
