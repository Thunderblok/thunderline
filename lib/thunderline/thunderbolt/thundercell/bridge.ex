defmodule Thunderline.Thunderbolt.ThunderCell.Bridge do
  @moduledoc """
  Bridge to Thunderlane

  Provides communication interface between THUNDERCELL Elixir compute layer
  and Thunderlane Elixir orchestration layer. Handles node discovery,
  RPC calls, and state synchronization.
  """

  use GenServer
  require Logger

  alias Thunderline.ThunderMemory
  alias Phoenix.PubSub

  # 30 seconds
  @heartbeat_interval 30_000
  # 10 seconds
  @metrics_interval 10_000

  defstruct [
    :thunderlane_node,
    :heartbeat_timer,
    :metrics_timer,
    connection_status: :disconnected
  ]

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init_thunderlane_connection do
    GenServer.call(__MODULE__, :init_connection)
  end

  def register_compute_node do
    GenServer.call(__MODULE__, :register_node)
  end

  def disconnect_thunderlane do
    GenServer.call(__MODULE__, :disconnect)
  end

  def send_metrics_to_thunderlane(metrics) do
    GenServer.cast(__MODULE__, {:send_metrics, metrics})
  end

  def receive_ca_rules_from_thunderlane do
    GenServer.call(__MODULE__, :get_ca_rules)
  end

  def notify_cluster_status(cluster_id, status) do
    GenServer.cast(__MODULE__, {:cluster_status, cluster_id, status})
  end

  # ====================================================================
  # GenServer callbacks
  # ====================================================================

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    state = %__MODULE__{}
    {:ok, state}
  end

  @impl true
  def handle_call(:init_connection, _from, state) do
    # Discover Thunderlane Elixir node
    case discover_thunderlane_node() do
      {:ok, node} ->
        case Node.ping(node) do
          :pong ->
            heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_interval)
            metrics_timer = Process.send_after(self(), :send_metrics, @metrics_interval)

            new_state = %{
              state
              | thunderlane_node: node,
                connection_status: :connected,
                heartbeat_timer: heartbeat_timer,
                metrics_timer: metrics_timer
            }

            {:reply, :ok, new_state}

          :pang ->
            {:reply, {:error, :connection_failed}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:register_node, _from, %{thunderlane_node: node} = state) when node != nil do
    # Register this THUNDERCELL node with Thunderlane orchestration
    case :rpc.call(node, Thunderline.ErlangBridge, :register_compute_node, [Node.self()]) do
      {:ok, :registered} ->
        {:reply, :ok, state}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:register_node, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:disconnect, _from, state) do
    # Clean disconnect from Thunderlane
    case state.thunderlane_node do
      nil ->
        :ok

      node ->
        :rpc.call(node, Thunderline.ErlangBridge, :unregister_compute_node, [Node.self()])
    end

    # Cancel timers
    cancel_timer(state.heartbeat_timer)
    cancel_timer(state.metrics_timer)

    new_state = %{
      state
      | thunderlane_node: nil,
        connection_status: :disconnected,
        heartbeat_timer: nil,
        metrics_timer: nil
    }

    {:reply, :ok, new_state}
  end

  def handle_call(:get_ca_rules, _from, %{thunderlane_node: node} = state) when node != nil do
    # Fetch current CA rules from Thunderlane
    case :rpc.call(node, Thunderline.Thunderbolt.Resources.LaneRuleSet, :get_active_rules, []) do
      {:ok, rules} ->
        {:reply, {:ok, rules}, state}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:get_ca_rules, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  # Provide a status query used by ErlangBridge aggregation
  def handle_call(:get_status, _from, state) do
    uptime_ms = System.monotonic_time(:millisecond)

    status = %{
      node: Node.self(),
      connection_status: state.connection_status,
      thunderlane_node: state.thunderlane_node,
      uptime_ms: uptime_ms,
      metrics_supported?: true
    }

    {:reply, {:ok, status}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:send_metrics, metrics}, %{thunderlane_node: node} = state) when node != nil do
    # Send performance metrics to Thunderlane
    Task.start(fn ->
      :rpc.cast(node, Thunderline.ThunderLink.DashboardMetrics, :receive_thundercell_metrics, [
        metrics
      ])
    end)

    {:noreply, state}
  end

  def handle_cast({:cluster_status, cluster_id, status}, %{thunderlane_node: node} = state)
      when node != nil do
    # Notify Thunderlane of cluster status changes
    Task.start(fn ->
      :rpc.cast(node, Thunderline.ThunderLink.DashboardMetrics, :receive_cluster_status, [
        cluster_id,
        status
      ])
    end)

    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, %{thunderlane_node: node} = state) when node != nil do
    # Send heartbeat to Thunderlane
    case Node.ping(node) do
      :pong ->
        heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_interval)
        {:noreply, %{state | heartbeat_timer: heartbeat_timer}}

      :pang ->
        # Connection lost, attempt reconnection
        {:noreply, %{state | connection_status: :disconnected}}
    end
  end

  def handle_info(:send_metrics, state) do
    # Collect and send metrics to Thunderlane
    metrics = Thunderline.Thunderbolt.ThunderCell.Telemetry.get_compute_metrics()
    send_metrics_to_thunderlane(metrics)
    metrics_timer = Process.send_after(self(), :send_metrics, @metrics_interval)
    {:noreply, %{state | metrics_timer: metrics_timer}}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up timers
    cancel_timer(state.heartbeat_timer)
    cancel_timer(state.metrics_timer)
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # ====================================================================
  # Internal functions
  # ====================================================================

  defp discover_thunderlane_node do
    # Discover Thunderlane Elixir node via various methods
    case System.get_env("THUNDERLANE_NODE") do
      nil ->
        # Try default naming convention
        try_default_thunderlane_nodes()

      node_str ->
        node = String.to_atom(node_str)
        {:ok, node}
    end
  end

  defp try_default_thunderlane_nodes do
    # Try common Thunderlane node names
    possible_nodes = [
      :thunderlane@localhost,
      :"thunderlane@127.0.0.1",
      String.to_atom("thunderlane@#{:net_adm.localhost()}")
    ]

    case find_reachable_node(possible_nodes) do
      {:ok, node} -> {:ok, node}
      :not_found -> {:error, :thunderlane_node_not_found}
    end
  end

  defp find_reachable_node([]), do: :not_found

  defp find_reachable_node([node | rest]) do
    case Node.ping(node) do
      :pong -> {:ok, node}
      :pang -> find_reachable_node(rest)
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
