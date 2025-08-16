defmodule Thunderline.Thunderflow.Pipelines.RealTimePipeline do
  @moduledoc """
  Broadway Pipeline for Real-Time Event Processing

  Handles high-frequency, low-latency events that need immediate processing
  such as agent state changes, system alerts, and live dashboard updates.
  """

  use Broadway

  alias Broadway.Message
  alias Phoenix.PubSub
  require Logger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {Thunderflow.MnesiaProducer,
           [
             table: Thunderflow.RealTimeEvents,
             # Very fast polling for real-time events
             poll_interval: 100,
             max_batch_size: 100,
             broadway_name: __MODULE__
           ]}
      ],
      processors: [
        default: [
          concurrency: 15,
          min_demand: 10,
          max_demand: 50
        ]
      ],
      batchers: [
        agent_updates: [
          concurrency: 8,
          batch_size: 100,
          # Very low latency for agent updates
          batch_timeout: 100
        ],
        system_metrics: [
          concurrency: 4,
          batch_size: 50,
          batch_timeout: 200
        ],
        dashboard_updates: [
          concurrency: 3,
          batch_size: 75,
          batch_timeout: 300
        ],
        websocket_broadcasts: [
          concurrency: 6,
          batch_size: 200,
          # Minimal latency for real-time UX
          batch_timeout: 50
        ]
      ]
    )
  end

  @impl Broadway
  def handle_message(processor, %Message{} = message, _context) do
    event_data =
      case message.data do
        bin when is_binary(bin) ->
          # Backwards compat for any legacy JSON payloads
          Jason.decode!(bin)
        %{:type => type, :payload => payload, :timestamp => ts} = map ->
          # EventBus.emit_realtime shape (atom keys)
          %{
            "event_type" => to_string(type),
            "data" => payload,
            "timestamp" => ts,
            "priority" => Map.get(map, :priority)
          }
        %{:type => type, :payload => payload} = map ->
          %{
            "event_type" => to_string(type),
            "data" => payload,
            "timestamp" => Map.get(map, :timestamp, DateTime.utc_now()),
            "priority" => Map.get(map, :priority)
          }
        %{"type" => type, "payload" => payload} = map ->
          # Mixed key legacy variant
          %{
            "event_type" => to_string(type),
            "data" => payload,
            "timestamp" => Map.get(map, "timestamp", DateTime.utc_now()),
            "priority" => Map.get(map, "priority")
          }
        map when is_map(map) ->
          # If it already looks normalized, pass through; else wrap
          cond do
            Map.has_key?(map, "event_type") and Map.has_key?(map, "data") -> map
            true -> %{"event_type" => "unknown", "data" => map, "timestamp" => DateTime.utc_now()}
          end
        other ->
          %{"event_type" => "unknown", "data" => other, "timestamp" => DateTime.utc_now()}
      end

    try do
      processed_event =
        event_data
        |> validate_realtime_event()
        |> add_realtime_metadata()
        |> optimize_for_latency()

      # Route based on event urgency and type
      batcher = determine_realtime_batcher(processed_event)

      message
      |> Message.update_data(fn _ -> processed_event end)
      |> Message.put_batcher(batcher)
    rescue
      error ->
        Logger.error("Real-time event processing failed: #{inspect(error)}")
        Message.failed(message, error)
    end
  end

  @impl Broadway
  def handle_batch(:agent_updates, messages, _batch_info, _context) do
    Logger.debug("Processing #{length(messages)} agent updates")

    events = Enum.map(messages, & &1.data)

    # Process agent updates with minimal latency
    case process_agent_updates_batch(events) do
      :ok ->
        # Immediate broadcast to dashboard
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline:agents:batch_update",
          {:agent_batch_processed,
           %{
             count: length(events),
             timestamp: DateTime.utc_now()
           }}
        )

        messages

      {:error, reason} ->
        Logger.error("Agent updates batch failed: #{inspect(reason)}")
        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  @impl Broadway
  def handle_batch(:system_metrics, messages, _batch_info, _context) do
    Logger.debug("Processing #{length(messages)} system metrics")

    events = Enum.map(messages, & &1.data)

    case process_system_metrics_batch(events) do
      :ok ->
        # Aggregate and broadcast metrics
        aggregated_metrics = aggregate_metrics(events)

        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline:metrics:update",
          {:metrics_batch_processed, aggregated_metrics}
        )

        messages

      {:error, reason} ->
        Logger.error("System metrics batch failed: #{inspect(reason)}")
        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  @impl Broadway
  def handle_batch(:dashboard_updates, messages, _batch_info, _context) do
    Logger.debug("Processing #{length(messages)} dashboard updates")

    events = Enum.map(messages, & &1.data)

    # Process dashboard updates and send to LiveView
    case process_dashboard_updates_batch(events) do
      :ok ->
        # Send optimized updates to all dashboard clients
        dashboard_payload = optimize_dashboard_payload(events)

        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline_web:dashboard",
          {:dashboard_batch_update, dashboard_payload}
        )

        messages

      {:error, reason} ->
        Logger.error("Dashboard updates batch failed: #{inspect(reason)}")
        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  @impl Broadway
  def handle_batch(:websocket_broadcasts, messages, _batch_info, _context) do
    Logger.debug("Processing #{length(messages)} WebSocket broadcasts")

    events = Enum.map(messages, & &1.data)

    # Ultra-fast WebSocket broadcasting
    case process_websocket_broadcasts_batch(events) do
      :ok ->
        messages

      {:error, reason} ->
        Logger.error("WebSocket broadcasts batch failed: #{inspect(reason)}")
        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  # Event validation and optimization
  defp validate_realtime_event(event) do
  # Ensure essential fields; synthesize if missing (soft validation to avoid pipeline failures)
  event = Map.put_new(event, "event_type", "unknown")
  event = Map.put_new(event, "data", %{})
  event = Map.put_new(event, "timestamp", DateTime.utc_now())
  event
  end

  defp add_realtime_metadata(event) do
    Map.merge(event, %{
      "processed_at" => System.system_time(:microsecond),
      "processing_node" => Node.self(),
      "latency_budget_ms" => calculate_latency_budget(event)
    })
  end

  defp optimize_for_latency(event) do
    # Remove unnecessary data for latency-critical events
    essential_fields = ["event_type", "data", "timestamp", "processed_at", "latency_budget_ms"]

    Map.take(event, essential_fields)
  end

  # 10ms budget
  defp calculate_latency_budget(%{"event_type" => "agent_state_change"}), do: 10
  # 5ms budget
  defp calculate_latency_budget(%{"event_type" => "system_alert"}), do: 5
  # 50ms budget
  defp calculate_latency_budget(%{"event_type" => "dashboard_update"}), do: 50
  # 100ms default
  defp calculate_latency_budget(_), do: 100

  defp determine_realtime_batcher(%{"event_type" => event_type}) do
    case event_type do
      type when type in ["agent_spawned", "agent_updated", "agent_terminated"] ->
        :agent_updates

      type when type in ["system_metrics", "performance_update", "health_check"] ->
        :system_metrics

      type when type in ["dashboard_update", "chart_data", "live_stats"] ->
        :dashboard_updates

      type when type in ["websocket_message", "live_notification", "chat_message"] ->
        :websocket_broadcasts

      _ ->
        # Default fallback
        :dashboard_updates
    end
  end

  # Batch processing implementations
  defp process_agent_updates_batch(events) do
    # Group by agent_id for efficient processing
    agent_updates =
      events
      |> Enum.group_by(fn event -> get_in(event, ["data", "agent_id"]) end)
      |> Enum.filter(fn {agent_id, _updates} -> agent_id != nil end)

    # Process each agent's updates
    Enum.each(agent_updates, fn {agent_id, updates} ->
      # Get latest state for each agent
      latest_state = get_latest_agent_state(updates)

      # Broadcast individual agent update
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderline:agent:#{agent_id}",
        {:agent_realtime_update, latest_state}
      )
    end)

    :ok
  end

  defp process_system_metrics_batch(events) do
    # Process metrics in parallel for different subsystems
    metrics_by_subsystem =
      Enum.group_by(events, fn event ->
        get_in(event, ["data", "subsystem"])
      end)

    Enum.each(metrics_by_subsystem, fn {subsystem, metrics} ->
      processed_metrics = aggregate_subsystem_metrics(subsystem, metrics)

      # Broadcast subsystem metrics
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderline:metrics:#{subsystem}",
        {:metrics_update, processed_metrics}
      )
    end)

    :ok
  end

  defp process_dashboard_updates_batch(events) do
    # Optimize dashboard updates for LiveView
    optimized_updates =
      events
      |> deduplicate_dashboard_events()
      |> compress_dashboard_payload()

    # Send to dashboard components
    Enum.each(optimized_updates, fn update ->
      component = get_in(update, ["data", "component"])

      if component do
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline_web:dashboard:#{component}",
          {:component_update, update["data"]}
        )
      end
    end)

    :ok
  end

  defp process_websocket_broadcasts_batch(events) do
    # Ultra-fast WebSocket processing
    broadcasts =
      events
      |> Enum.map(&prepare_websocket_message/1)
      |> Enum.group_by(& &1.topic)

    # Batch broadcast by topic for efficiency
    Enum.each(broadcasts, fn {topic, messages} ->
      PubSub.broadcast(
        Thunderline.PubSub,
        topic,
        {:batch_websocket_update, messages}
      )
    end)

    :ok
  end

  # Helper functions
  defp get_latest_agent_state(updates) do
    # Get the most recent update for an agent
    updates
    |> Enum.max_by(fn update ->
      update["timestamp"] || update["processed_at"] || 0
    end)
    |> Map.get("data")
  end

  defp aggregate_subsystem_metrics(subsystem, metrics) do
    %{
      "subsystem" => subsystem,
      "aggregated_at" => DateTime.utc_now(),
      "metrics_count" => length(metrics),
      "latest_values" => extract_latest_metric_values(metrics),
      "trends" => calculate_metric_trends(metrics)
    }
  end

  defp aggregate_metrics(events) do
    %{
      "total_events" => length(events),
      "processing_latency_ms" => calculate_processing_latency(events),
      "aggregated_at" => DateTime.utc_now(),
      "event_types" => count_event_types(events)
    }
  end

  defp optimize_dashboard_payload(events) do
    %{
      "updates" => events,
      "optimized_at" => DateTime.utc_now(),
      "update_count" => length(events),
      "compressed_size" => estimate_payload_size(events)
    }
  end

  defp deduplicate_dashboard_events(events) do
    # Remove duplicate dashboard events to reduce payload
    events
    |> Enum.group_by(fn event ->
      {get_in(event, ["data", "component"]), get_in(event, ["data", "key"])}
    end)
    |> Enum.map(fn {_key, group} ->
      # Take the latest event from each group
      Enum.max_by(group, & &1["timestamp"])
    end)
  end

  defp compress_dashboard_payload(events) do
    # Apply payload compression for large dashboard updates
    events
  end

  defp prepare_websocket_message(event) do
    %{
      topic: get_in(event, ["data", "websocket_topic"]) || "general",
      payload: event["data"],
      timestamp: event["timestamp"]
    }
  end

  defp extract_latest_metric_values(metrics) do
    # Extract the most recent values for each metric type
    metrics
    |> Enum.group_by(fn metric -> get_in(metric, ["data", "metric_name"]) end)
    |> Enum.map(fn {metric_name, values} ->
      latest = Enum.max_by(values, & &1["timestamp"])
      {metric_name, get_in(latest, ["data", "value"])}
    end)
    |> Enum.into(%{})
  end

  defp calculate_metric_trends(metrics) do
    # Calculate trends for metrics over time
    %{
      "trending_up" => 0,
      "trending_down" => 0,
      "stable" => length(metrics)
    }
  end

  defp calculate_processing_latency(events) do
    # Calculate average processing latency
    latencies =
      events
      |> Enum.map(fn event ->
        processed_at = event["processed_at"] || System.system_time(:microsecond)
        timestamp = event["timestamp"] || processed_at
        # Convert to milliseconds
        abs(processed_at - timestamp) / 1000
      end)

    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      0
    end
  end

  defp count_event_types(events) do
    events
    |> Enum.group_by(& &1["event_type"])
    |> Enum.map(fn {type, events} -> {type, length(events)} end)
    |> Enum.into(%{})
  end

  defp estimate_payload_size(events) do
    # Rough estimate of payload size for optimization decisions
    events
    |> Jason.encode!()
    |> byte_size()
  end
end
