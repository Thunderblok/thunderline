defmodule Thundergate.ThunderBridge do
  @moduledoc """
  A high-performance event bridge for Thunderline Automata.

  The ThunderBridge coordinates real-time communication between:
  - Distributed nodes in the Thunderline cluster
  - In-memory automata and agents
  - WebSocket clients and dashboard
  - Event streams and state changes

  Uses the ThunderMemory system for persistent, fast state management.

  This module is part of Thundergate domain for integration & interoperability.
  """
  use GenServer
  require Logger

  @topics [
    "agent_events",
    "chunk_events",
    "system_events",
    "node_events",
    "memory_events"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Public API

  def get_agent_state(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_state, agent_id})
  end

  def spawn_agent(agent_data) do
    GenServer.call(__MODULE__, {:spawn_agent, agent_data})
  end

  def update_agent(agent_id, updates) do
    GenServer.call(__MODULE__, {:update_agent, agent_id, updates})
  end

  def list_agents(filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_agents, filters})
  end

  def get_chunks(filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_chunks, filters})
  end

  def create_chunk(chunk_data) do
    GenServer.call(__MODULE__, {:create_chunk, chunk_data})
  end

  def get_system_metrics do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  def broadcast_event(topic, event) do
    GenServer.cast(__MODULE__, {:broadcast_event, topic, event})
  end

  # Legacy API compatibility
  def subscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  def get_agents_json do
    GenServer.call(__MODULE__, :get_agents_json)
  end

  def get_chunks_json do
    GenServer.call(__MODULE__, :get_chunks_json)
  end

  def get_system_state do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  @doc """
  Publish an event through the EventBus system.

  This is a compatibility function for Thunderbit and other modules
  that need to publish events.

  Instrumented with OpenTelemetry for T-72h telemetry heartbeat.
  """
  def publish(event) when is_map(event) do
    alias Thunderline.Thunderflow.Telemetry.OtelTrace
    require OtelTrace

    OtelTrace.with_span "gate.publish", %{event_name: event[:name] || "unknown"} do
      Process.put(:current_domain, :gate)

      OtelTrace.set_attributes(%{
        "thunderline.domain" => "gate",
        "thunderline.component" => "thunder_bridge"
      })

      # Route through EventBus for Broadway pipeline processing
      build_and_publish = fn attrs ->
        with {:ok, ev} <- Thunderline.Event.new(attrs) do
          # Inject trace context into event for cross-domain propagation
          ev_with_trace = OtelTrace.inject_trace_context(ev)

          case Thunderline.EventBus.publish_event(ev_with_trace) do
            {:ok, _} ->
              OtelTrace.add_event("gate.event_published", %{event_id: ev.id})
              :ok

            {:error, reason} ->
              Logger.warning(
                "[ThunderBridge] publish failed: #{inspect(reason)} name=#{attrs.name}"
              )

              OtelTrace.set_status(:error, "Event publish failed: #{inspect(reason)}")
          end
        end
      end

    case event do
      %{type: event_type, payload: payload} ->
        build_and_publish.(%{
          name: Map.get(payload, :event_name, "system.bridge.#{event_type}"),
          type: event_type,
          source: :bridge,
          payload: payload,
          meta: %{pipeline: :realtime},
          priority: Map.get(payload, :priority, :normal)
        })

      %{event: event_type, data: payload} ->
        build_and_publish.(%{
          name: Map.get(payload, :event_name, "system.bridge.#{event_type}"),
          type: event_type,
          source: :bridge,
          payload: payload,
          meta: %{pipeline: :realtime},
          priority: Map.get(payload, :priority, :normal)
        })

      %{topic: topic, event: event_data} ->
        build_and_publish.(%{
          name: "system.bridge.bridge_event",
          type: :bridge_event,
          source: :bridge,
          payload: Map.merge(event_data, %{topic: topic}),
          meta: %{pipeline: infer_pipeline_from_topic(topic)}
        })

      _ ->
        build_and_publish.(%{
          name: "system.bridge.generic_event",
          type: :generic_event,
          source: :bridge,
          payload: event,
          meta: %{pipeline: :realtime}
        })
    end
    end
  end

  # GenServer Callbacks

  def init(opts) do
    Logger.info("Starting ThunderBridge with options: #{inspect(opts)}")

    # Subscribe to all event topics
    Enum.each(@topics, fn topic ->
      Phoenix.PubSub.subscribe(Thunderline.PubSub, topic)
    end)

    # Subscribe to memory events
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunder_events")

    # Initial state
    state = %{
      opts: opts,
      connected_nodes: [],
      active_agents: 0,
      total_chunks: 0,
      last_heartbeat: :os.system_time(:millisecond),
      performance_metrics: %{},
      subscribers: []
    }

    # Schedule periodic tasks
    :timer.send_interval(5000, :heartbeat)
    :timer.send_interval(1000, :update_metrics)

    {:ok, state}
  end

  def handle_call({:get_agent_state, agent_id}, _from, state) do
    case Thunderline.ThunderMemory.get_agent(agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      agent -> {:reply, {:ok, agent}, state}
    end
  end

  def handle_call({:spawn_agent, agent_data}, _from, state) do
    case Thunderline.ThunderMemory.spawn_agent(agent_data) do
      {:ok, agent} ->
        # Update metrics
        new_state = %{state | active_agents: state.active_agents + 1}

        # Broadcast spawn event
        broadcast_event_internal("agent_events", {:agent_spawned, agent})

        {:reply, {:ok, agent}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:update_agent, agent_id, updates}, _from, state) do
    case Thunderline.ThunderMemory.update_agent(agent_id, updates) do
      {:ok, agent} ->
        # Broadcast update event
        broadcast_event_internal("agent_events", {:agent_updated, agent})

        {:reply, {:ok, agent}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:list_agents, filters}, _from, state) do
    case Thunderline.ThunderMemory.list_agents(filters) do
      {:ok, agents} -> {:reply, {:ok, agents}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get_chunks, filters}, _from, state) do
    case Thunderline.ThunderMemory.get_chunks(filters) do
      {:ok, chunks} -> {:reply, {:ok, chunks}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:create_chunk, chunk_data}, _from, state) do
    case Thunderline.ThunderMemory.create_chunk(chunk_data) do
      {:ok, chunk} ->
        # Update metrics
        new_state = %{state | total_chunks: state.total_chunks + 1}

        # Broadcast chunk event
        broadcast_event_internal("chunk_events", {:chunk_created, chunk})

        {:reply, {:ok, chunk}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_system_metrics, _from, state) do
    metrics = %{
      active_agents: state.active_agents,
      total_chunks: state.total_chunks,
      connected_nodes: length(state.connected_nodes),
      last_heartbeat: state.last_heartbeat,
      uptime: :os.system_time(:millisecond) - state.last_heartbeat,
      memory_usage: get_memory_usage(),
      performance: state.performance_metrics
    }

    {:reply, {:ok, metrics}, state}
  end

  # Legacy API compatibility
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    new_subscribers = [pid | state.subscribers]
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_agents_json, _from, state) do
    case Thunderline.ThunderMemory.list_agents() do
      {:ok, agents} ->
        json_agents =
          Enum.map(agents, fn agent ->
            %{
              id: agent.id,
              name: agent.name,
              state: agent.state,
              capabilities: agent.capabilities,
              last_seen: agent.last_seen
            }
          end)

        {:reply, json_agents, state}

      _ ->
        {:reply, [], state}
    end
  end

  def handle_call(:get_chunks_json, _from, state) do
    case Thunderline.ThunderMemory.get_chunks() do
      {:ok, chunks} ->
        json_chunks =
          Enum.map(chunks, fn chunk ->
            %{
              id: chunk.id,
              # Truncate for JSON
              content: String.slice(chunk.content, 0, 100),
              agent_id: chunk.agent_id,
              timestamp: chunk.timestamp
            }
          end)

        {:reply, json_chunks, state}

      _ ->
        {:reply, [], state}
    end
  end

  def handle_cast({:broadcast_event, topic, event}, state) do
    broadcast_event_internal(topic, event)
    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    timestamp = :os.system_time(:millisecond)

    # Record heartbeat metric
    Thunderline.ThunderMemory.record_metric(:heartbeat, timestamp, %{node: Node.self()})

    # Update connected nodes
    connected_nodes = Node.list(:connected)

    # Broadcast heartbeat
    broadcast_event_internal(
      "system_events",
      {:heartbeat,
       %{
         node: Node.self(),
         timestamp: timestamp,
         connected_nodes: connected_nodes
       }}
    )

    new_state = %{state | last_heartbeat: timestamp, connected_nodes: connected_nodes}

    {:noreply, new_state}
  end

  def handle_info(:update_metrics, state) do
    # Get current counts from memory
    {:ok, agents} = Thunderline.ThunderMemory.list_agents()
    {:ok, chunks} = Thunderline.ThunderMemory.get_chunks()

    # Calculate performance metrics
    performance_metrics = %{
      agents_per_second: calculate_rate(:agents_spawned),
      chunks_per_second: calculate_rate(:chunks_created),
      memory_efficiency: calculate_memory_efficiency(),
      response_time: calculate_avg_response_time()
    }

    new_state = %{
      state
      | active_agents: length(agents),
        total_chunks: length(chunks),
        performance_metrics: performance_metrics
    }

    {:noreply, new_state}
  end

  def handle_info({:event, event}, state) do
    # Handle events from ThunderMemory
    case event.type do
      :agent_spawned ->
        broadcast_event_internal("agent_events", {:agent_spawned, event.data.agent})

      :chunk_created ->
        broadcast_event_internal("chunk_events", {:chunk_created, event.data.chunk})

      _ ->
        broadcast_event_internal("memory_events", {event.type, event.data})
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = List.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("ThunderBridge received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp broadcast_event_internal(topic, event) do
    pipeline = infer_pipeline_from_topic(topic)

    attrs = %{
      name: "system.bridge.thunder_bridge_event",
      type: :thunder_bridge_event,
      source: :bridge,
      payload: %{topic: topic, event: event, timestamp: DateTime.utc_now()},
      meta: %{pipeline: pipeline}
    }

    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[ThunderBridge] publish internal failed: #{inspect(reason)} topic=#{topic}"
          )
      end
    end
  end

  defp infer_pipeline_from_topic(topic) do
    cond do
      String.contains?(topic, "agent") or String.contains?(topic, "live") -> :realtime
      String.contains?(topic, "domain") -> :cross_domain
      true -> :general
    end
  end

  defp get_memory_usage do
    :erlang.memory(:total)
  end

  defp calculate_rate(metric) do
    # Get metrics from last minute
    case Thunderline.ThunderMemory.get_metrics(metric, :minute) do
      {:ok, metrics} -> length(metrics) / 60.0
      _ -> 0.0
    end
  end

  defp calculate_memory_efficiency do
    total_mem = :erlang.memory(:total)
    process_mem = :erlang.memory(:processes)

    case total_mem do
      0 -> 0.0
      _ -> process_mem / total_mem * 100
    end
  end

  defp calculate_avg_response_time do
    # This would be calculated from actual request timing metrics
    # For now, return a placeholder
    1.5
  end
end
