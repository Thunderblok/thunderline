defmodule Thunderlink.ThunderWebsocketClient do
  @moduledoc """
  WebSocket client for connecting to Thunder system components.
  Now uses the ThunderBridge for local system integration instead of
  attempting distributed node connections.
  """

  use GenServer
  require Logger

  alias Thundergate.ThunderBridge
  alias Phoenix.PubSub

  @websocket_topic "thunder:websocket"
  @update_interval 1000

  defstruct [
    :connection_state,
    :last_message,
    :subscribers,
    :metrics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end

  def unsubscribe do
    GenServer.call(__MODULE__, :unsubscribe)
  end

  def get_system_state do
    GenServer.call(__MODULE__, :get_system_state)
  end

  def get_agents do
    GenServer.call(__MODULE__, :get_agents)
  end

  def get_chunks do
    GenServer.call(__MODULE__, :get_chunks)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      connection_state: :initializing,
      last_message: nil,
      subscribers: [],
      metrics: %{
        messages_processed: 0,
        start_time: System.system_time(:millisecond)
      }
    }

    # Subscribe to Thunder Bridge events
    ThunderBridge.subscribe(self())

    # Start periodic updates
    :timer.send_interval(@update_interval, self(), :fetch_updates)

    Logger.info("🔌 Thunder WebSocket Client initialized")

    {:ok, %{state | connection_state: :connected}}
  end

  @impl true
  def handle_call(:subscribe, {pid, _tag}, state) do
    Process.monitor(pid)
    new_subscribers = [pid | state.subscribers]
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  def handle_call(:unsubscribe, {pid, _tag}, state) do
    new_subscribers = List.delete(state.subscribers, pid)
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  def handle_call(:get_system_state, _from, state) do
    case ThunderBridge.get_system_state() do
      {:ok, system_state} when is_map(system_state) ->
        {:reply, {:ok, system_state}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      other ->
        # Unexpected shape; log for visibility and treat as error
        Logger.debug("Unexpected system state response: #{inspect(other)}")
        {:reply, {:error, :unexpected_response}, state}
    end
  end

  def handle_call(:get_agents, _from, state) do
    case ThunderBridge.get_agents_json() do
      agents when is_list(agents) ->
        {:reply, {:ok, agents}, state}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:get_chunks, _from, state) do
    case ThunderBridge.get_chunks_json() do
      chunks when is_list(chunks) ->
        {:reply, {:ok, chunks}, state}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_info(:fetch_updates, %{connection_state: :connected} = state) do
    # Fetch and broadcast system updates
    fetch_and_broadcast_system_state()
    fetch_and_broadcast_agents()
    fetch_and_broadcast_chunks()

    # Update metrics
    new_metrics = %{state.metrics | messages_processed: state.metrics.messages_processed + 1}

    {:noreply, %{state | metrics: new_metrics}}
  end

  def handle_info(:fetch_updates, state) do
    # Not connected, skip updates
    {:noreply, state}
  end

  def handle_info({:thunder_event, event_data}, state) do
    # Handle events from ThunderBridge
    Logger.debug("Received Thunder event: #{event_data.event}")

    # Broadcast to WebSocket subscribers
    broadcast_update(:thunder_event, event_data)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp fetch_and_broadcast_system_state do
    case ThunderBridge.get_system_state() do
      {:ok, system_state} when is_map(system_state) ->
        broadcast_update(:system_state, system_state)

      {:error, reason} ->
        Logger.debug("Failed to fetch system state: #{inspect(reason)}")

      other ->
        Logger.debug("Unexpected system state response: #{inspect(other)}")
    end
  end

  defp fetch_and_broadcast_agents do
    case ThunderBridge.get_agents_json() do
      agents when is_list(agents) ->
        broadcast_update(:agents_update, agents)

      error ->
        Logger.debug("Failed to fetch agents: #{inspect(error)}")
    end
  end

  defp fetch_and_broadcast_chunks do
    case ThunderBridge.get_chunks_json() do
      chunks when is_list(chunks) ->
        broadcast_update(:chunks_update, chunks)

      error ->
        Logger.debug("Failed to fetch chunks: #{inspect(error)}")
    end
  end

  defp broadcast_update(event_type, data) do
    message = %{
      event: event_type,
      data: data,
      timestamp: System.system_time(:millisecond),
      source: :thunder_bridge
    }

    # Broadcast to Phoenix PubSub
    PubSub.broadcast(
      Thunderline.PubSub,
      @websocket_topic,
      {:thunder_update, message}
    )
  end
end
