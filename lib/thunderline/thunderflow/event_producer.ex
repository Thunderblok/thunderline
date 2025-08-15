defmodule Thunderflow.EventProducer do
  @moduledoc """
  Event Producer for Broadway Pipelines

  Captures events from Phoenix PubSub and feeds them into Broadway pipelines
  for structured processing with proper batching and error handling.
  """

  use GenStage
  alias Phoenix.PubSub
  require Logger

  @pubsub_name Thunderline.PubSub

  # Topic subscriptions for different event types
  @event_topics [
    "thunderline:agents",
    "thunderline:chunks",
    "thunderline:system",
    "thunderline:metrics",
    "thunderline:dashboard",
    "thunderline:websocket",
    "thunderbolt:events",
    "thunderbolt:alerts",
    "thunderblock:channels",
    "thunderblock:communities",
    "thundergrid:zones",
    "thundergrid:resources",
    "thunderblock:memory",
    "thundercore:pulse",
    "thunderchief:orchestration",
    "thunderflow:streams"
  ]

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenStage
  def init(opts) do
    # Subscribe to all relevant PubSub topics
    Enum.each(@event_topics, fn topic ->
      PubSub.subscribe(@pubsub_name, topic)
    end)

    Logger.info(
      "Thunderflow EventProducer started, subscribed to #{length(@event_topics)} topics"
    )

    {:producer,
     %{
       demand: 0,
       events: :queue.new(),
       pipeline_routing: opts[:pipeline_routing] || :auto
     }}
  end

  @impl GenStage
  def handle_demand(incoming_demand, %{demand: pending_demand} = state) do
    total_demand = incoming_demand + pending_demand
    {events_to_send, remaining_events} = take_events(state.events, total_demand)

    new_state = %{state | demand: total_demand - length(events_to_send), events: remaining_events}

    {:noreply, events_to_send, new_state}
  end

  @impl GenStage
  def handle_info({event_type, payload}, state) when is_atom(event_type) do
    # Convert PubSub events to Broadway messages
    broadway_event = transform_pubsub_to_broadway(event_type, payload)
    route_event_to_pipeline(broadway_event, state)
  end

  def handle_info({:thunder_event, event_data}, state) do
    # Handle ThunderBridge events
    broadway_event = transform_thunder_event(event_data)
    route_event_to_pipeline(broadway_event, state)
  end

  def handle_info({:batch_websocket_update, messages}, state) do
    # Handle batch websocket updates
    events = Enum.map(messages, &transform_websocket_message/1)
    add_events_to_queue(events, state)
  end

  def handle_info(message, state) do
    Logger.debug("EventProducer received unhandled message: #{inspect(message)}")
    {:noreply, [], state}
  end

  # Event transformation functions
  defp transform_pubsub_to_broadway(event_type, payload) do
    %{
      "event_type" => Atom.to_string(event_type),
      "data" => normalize_payload(payload),
      "timestamp" => DateTime.utc_now(),
      "source" => "pubsub",
      "pipeline_hint" => determine_pipeline_hint(event_type, payload)
    }
  end

  defp transform_thunder_event(event_data) do
    %{
      "event_type" => Map.get(event_data, :event, "thunder_event"),
      "data" => Map.get(event_data, :data, %{}),
      "timestamp" => DateTime.utc_now(),
      "source" => "thunder_bridge",
      "pipeline_hint" => "realtime"
    }
  end

  defp transform_websocket_message(message) do
    %{
      "event_type" => "websocket_message",
      "data" => message,
      "timestamp" => DateTime.utc_now(),
      "source" => "websocket",
      "pipeline_hint" => "realtime"
    }
  end

  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(payload) when is_list(payload), do: %{"items" => payload}
  defp normalize_payload(payload) when is_binary(payload), do: %{"message" => payload}
  defp normalize_payload(payload), do: %{"value" => payload}

  # Pipeline routing logic
  defp determine_pipeline_hint(event_type, payload) do
    cond do
      # Real-time events
      event_type in [
        :agent_spawned,
        :agent_updated,
        :agent_terminated,
        :chunk_created,
        :chunk_updated,
        :system_metrics,
        :websocket_message,
        :dashboard_update
      ] ->
        "realtime"

      # Cross-domain events
      has_cross_domain_routing?(payload) ->
        "cross_domain"

      # Default to general event processing
      true ->
        "event"
    end
  end

  defp has_cross_domain_routing?(payload) when is_map(payload) do
    Map.has_key?(payload, "target_domain") or
      Map.has_key?(payload, "route_to") or
      Map.has_key?(payload, "cross_domain")
  end

  defp has_cross_domain_routing?(_), do: false

  defp route_event_to_pipeline(broadway_event, state) do
    case state.pipeline_routing do
      :auto ->
        # Route based on pipeline hint
        route_to_appropriate_pipeline(broadway_event, state)

      specific_pipeline when is_atom(specific_pipeline) ->
        # Route to specific pipeline
        add_event_to_queue(broadway_event, state)

      _ ->
        # Default routing
        add_event_to_queue(broadway_event, state)
    end
  end

  defp route_to_appropriate_pipeline(broadway_event, state) do
    pipeline_hint = Map.get(broadway_event, "pipeline_hint", "event")

    case pipeline_hint do
      "realtime" ->
        send_to_realtime_pipeline(broadway_event)
        {:noreply, [], state}

      "cross_domain" ->
        send_to_cross_domain_pipeline(broadway_event)
        {:noreply, [], state}

      "event" ->
        add_event_to_queue(broadway_event, state)

      _ ->
        add_event_to_queue(broadway_event, state)
    end
  end

  defp send_to_realtime_pipeline(event) do
    # Send directly to RealTimePipeline
    try do
      GenStage.call(Thunderflow.Pipelines.RealTimePipeline, {:send_event, event})
    rescue
      error ->
        Logger.error("Failed to send event to RealTimePipeline: #{inspect(error)}")
    end
  end

  defp send_to_cross_domain_pipeline(event) do
    # Send directly to CrossDomainPipeline
    try do
      GenStage.call(Thunderflow.Pipelines.CrossDomainPipeline, {:send_event, event})
    rescue
      error ->
        Logger.error("Failed to send event to CrossDomainPipeline: #{inspect(error)}")
    end
  end

  defp add_event_to_queue(event, state) do
    add_events_to_queue([event], state)
  end

  defp add_events_to_queue(events, state) do
    new_events_queue =
      Enum.reduce(events, state.events, fn event, queue ->
        :queue.in(encode_event(event), queue)
      end)

    {events_to_send, remaining_events} = take_events(new_events_queue, state.demand)

    new_state = %{state | demand: state.demand - length(events_to_send), events: remaining_events}

    {:noreply, events_to_send, new_state}
  end

  defp take_events(queue, demand) when demand > 0 do
    take_events(queue, demand, [])
  end

  defp take_events(queue, _demand), do: {[], queue}

  defp take_events(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_events(queue, demand, acc) do
    case :queue.out(queue) do
      {{:value, event}, remaining_queue} ->
        take_events(remaining_queue, demand - 1, [event | acc])

      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp encode_event(event) do
    # Convert event to Broadway message format
    Jason.encode!(event)
  end
end
