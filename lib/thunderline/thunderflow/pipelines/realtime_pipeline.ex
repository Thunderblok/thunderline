defmodule Thunderline.Thunderflow.Pipelines.RealTimePipeline do
  @moduledoc """
  Broadway Pipeline for Real-Time Event Processing

  Handles high-frequency, low-latency events that need immediate processing
  such as agent state changes, system alerts, and live dashboard updates.
  """

  use Broadway

  alias Broadway.Message
  alias Phoenix.PubSub
  alias Thunderline.Thunderflow.EventBuffer
  alias Thunderline.Event
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
  def handle_message(_processor, %Message{} = message, _context) do
    canonical =
      case message.data do
        %Event{} = ev -> ev
        bin when is_binary(bin) -> bin |> Jason.decode!() |> Event.normalize!()
        map when is_map(map) -> Event.normalize!(map)
        other -> Event.new!(name: "system.unknown.event", source: :flow, payload: %{data: other})
      end

    try do
      processed_event = canonical |> enrich_for_realtime()

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

    # Process agent updates with minimal latency (currently infallible)
    :ok = process_agent_updates_batch(events)
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
  end

  @impl Broadway
  def handle_batch(:system_metrics, messages, _batch_info, _context) do
    Logger.debug("Processing #{length(messages)} system metrics")

  events = Enum.map(messages, & &1.data)

    :ok = process_system_metrics_batch(events)
    aggregated_metrics = aggregate_metrics(events)
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderline:metrics:update",
      {:metrics_batch_processed, aggregated_metrics}
    )
    messages
  end

  @impl Broadway
  def handle_batch(:dashboard_updates, messages, _batch_info, _context) do
    count = length(messages)
    types =
      messages
      |> Enum.map(& &1.data.name)
      |> Enum.frequencies()
      |> Enum.map(fn {t,c} -> "#{t}:#{c}" end)
      |> Enum.join(",")
    Logger.debug("Processing #{count} dashboard updates (types=#{types})")

  events = Enum.map(messages, & &1.data)

    :ok = process_dashboard_updates_batch(events)
    dashboard_payload = optimize_dashboard_payload(events)
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderline_web:dashboard",
      {:dashboard_batch_update, dashboard_payload}
    )
    messages
  end

  @impl Broadway
  def handle_batch(:websocket_broadcasts, messages, _batch_info, _context) do
    count = length(messages)
    topics =
      messages
      |> Enum.map(& (get_in(&1.data.payload, ["websocket_topic"]) || get_in(&1.data.payload, [:websocket_topic]) || "general"))
      |> Enum.frequencies()
      |> Enum.map(fn {t,c} -> "#{t}:#{c}" end)
      |> Enum.join(",")
    Logger.debug("Processing #{count} WebSocket broadcasts (topics=#{topics})")

  events = Enum.map(messages, & &1.data)

    :ok = process_websocket_broadcasts_batch(events)
    Enum.each(events, fn %Event{name: name, payload: data} ->
      if name == "ai.timeseries.embedding" do
        Phoenix.PubSub.broadcast(Thunderline.PubSub, "drift:embedding", {:timeseries_embedding, data})
      end
    end)
    messages
  end

  # Event enrichment and optimization on canonical struct
  defp enrich_for_realtime(%Event{} = ev) do
    ev
    |> Event.put_metadata(:processed_at, System.system_time(:microsecond))
    |> Event.put_metadata(:processing_node, Node.self())
    |> Event.put_metadata(:latency_budget_ms, calculate_latency_budget(ev))
  end

  defp calculate_latency_budget(%Event{name: name}) do
    cond do
      String.contains?(name, "agent_state_change") -> 10
      String.contains?(name, "system_alert") -> 5
      String.contains?(name, "dashboard_update") -> 50
      true -> 100
    end
  end

  defp determine_realtime_batcher(%Event{name: name}) do
    cond do
      String.contains?(name, "agent_spawned") or String.contains?(name, "agent_updated") or String.contains?(name, "agent_terminated") -> :agent_updates
      String.contains?(name, "system_metrics") or String.contains?(name, "performance_update") or String.contains?(name, "health_check") -> :system_metrics
      String.contains?(name, "dashboard_update") or String.contains?(name, "chart_data") or String.contains?(name, "live_stats") -> :dashboard_updates
      String.contains?(name, "websocket_message") or String.contains?(name, "live_notification") or String.contains?(name, "chat_message") -> :websocket_broadcasts
      true -> :dashboard_updates
    end
  end

  # Batch processing implementations
  defp process_agent_updates_batch(events) do
    # Group by agent_id for efficient processing
    agent_updates =
      events
      |> Enum.group_by(fn %Event{payload: p} -> p["agent_id"] || p[:agent_id] end)
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
      Enum.group_by(events, fn %Event{payload: p} -> p["subsystem"] || p[:subsystem] end)

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

    Enum.each(optimized_updates, fn update ->
      # Broadcast component-specific update if component present
      if component = (update.payload["component"] || update.payload[:component]) do
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline_web:dashboard:#{component}",
          {:component_update, update.payload}
        )
      end

      # Feed central EventBuffer (normalized route for LiveView stream)
      EventBuffer.put({:dashboard_update, update.payload})
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
    |> Enum.max_by(fn %Event{metadata: md, timestamp: ts} -> md[:processed_at] || ts || 0 end)
    |> Map.get(:payload)
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
      "updates" => Enum.map(events, &Event.to_map/1),
      "optimized_at" => DateTime.utc_now(),
      "update_count" => length(events),
      "compressed_size" => estimate_payload_size(events)
    }
  end

  defp deduplicate_dashboard_events(events) do
    # Remove duplicate dashboard events to reduce payload
    events
    |> Enum.group_by(fn %Event{payload: p} -> {p["component"] || p[:component], p["key"] || p[:key]} end)
    |> Enum.map(fn {_key, group} ->
      Enum.max_by(group, fn %Event{timestamp: ts} -> ts end)
    end)
  end

  defp compress_dashboard_payload(events) do
    # Apply payload compression for large dashboard updates
    events
  end

  defp prepare_websocket_message(%Event{} = event) do
    %{
      topic: get_in(event.payload, ["websocket_topic"]) || get_in(event.payload, [:websocket_topic]) || "general",
      payload: event.payload,
      timestamp: event.timestamp
    }
  end

  defp extract_latest_metric_values(metrics) do
    # Extract the most recent values for each metric type
    metrics
    |> Enum.group_by(fn %Event{payload: p} -> p["metric_name"] || p[:metric_name] end)
    |> Enum.map(fn {metric_name, values} ->
      latest = Enum.max_by(values, fn %Event{timestamp: ts} -> ts end)
      {metric_name, (latest.payload["value"] || latest.payload[:value])}
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
      |> Enum.map(fn %Event{metadata: md, timestamp: ts} ->
        processed_at = md[:processed_at] || System.system_time(:microsecond)
        base_ts =
          case ts do
            %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
            _ -> processed_at
          end
        abs(processed_at - base_ts) / 1000
      end)

    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      0
    end
  end

  defp count_event_types(events) do
    events
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {type, events} -> {type, length(events)} end)
    |> Enum.into(%{})
  end

  defp estimate_payload_size(events) do
    # Rough estimate of payload size for optimization decisions
    events
    |> Enum.map(&Event.to_map/1)
    |> Jason.encode!()
    |> byte_size()
  end
end
