defmodule Thunderline.Thunderbolt.StreamManager.PubSubBridge do
  @moduledoc """
  PubSub Bridge for StreamManager.

  Subscribes to Thunderbolt PubSub topics and routes events to the appropriate
  streams. Acts as a GenStage producer that can be consumed by downstream
  processors.

  ## Topic → Stream Mapping

  - `thunderbolt:chunks` → `:chunk_updates`
  - `thunderbolt:topology` → `:topology_events`
  - `thunderbolt:ml` → `:ml_events`
  - `thunderbolt:lanes` → `:lane_events`
  - `thunderbolt:ca` → `:ca_events`
  - `thunderbolt:events` → `:general`
  - `thunderbolt:alerts` → `:alerts`
  """

  use GenStage
  require Logger

  alias Phoenix.PubSub
  alias Thunderline.Thunderbolt.StreamManager

  @pubsub Thunderline.PubSub

  # Topic to stream name mapping
  @topic_stream_map %{
    "thunderbolt:chunks" => :chunk_updates,
    "thunderbolt:topology" => :topology_events,
    "thunderbolt:ml" => :ml_events,
    "thunderbolt:lanes" => :lane_events,
    "thunderbolt:ca" => :ca_events,
    "thunderbolt:events" => :general,
    "thunderbolt:alerts" => :alerts
  }

  ## Public API

  @doc """
  Starts the PubSubBridge as a GenStage producer.

  ## Options
    - `:topics` - List of PubSub topics to subscribe to
    - `:name` - Process name (default: `#{inspect(__MODULE__)}`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Manually inject an event into the bridge.

  Useful for testing or external integrations.
  """
  @spec inject(term()) :: :ok
  def inject(event) do
    GenServer.cast(__MODULE__, {:inject, event})
  end

  ## GenStage callbacks

  @impl GenStage
  def init(opts) do
    topics = Keyword.get(opts, :topics, Map.keys(@topic_stream_map))

    # Subscribe to all configured topics
    Enum.each(topics, fn topic ->
      :ok = PubSub.subscribe(@pubsub, topic)
      Logger.debug("[PubSubBridge] Subscribed to topic: #{topic}")
    end)

    Logger.info("[PubSubBridge] Started, subscribed to #{length(topics)} topics")

    :telemetry.execute(
      [:thunderline, :thunderbolt, :stream, :bridge, :start],
      %{topics: length(topics)},
      %{topics: topics}
    )

    state = %{
      topics: topics,
      demand: 0,
      buffer: :queue.new(),
      stats: %{
        events_received: 0,
        events_dispatched: 0,
        started_at: DateTime.utc_now()
      }
    }

    {:producer, state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, state) do
    total_demand = state.demand + incoming_demand
    {events, new_buffer} = take_from_buffer(state.buffer, total_demand)

    new_state = %{
      state
      | demand: total_demand - length(events),
        buffer: new_buffer,
        stats: update_dispatch_stats(state.stats, length(events))
    }

    {:noreply, events, new_state}
  end

  @impl GenStage
  def handle_info({event_type, payload}, state) when is_atom(event_type) do
    # Route PubSub message based on event type
    stream_name = infer_stream_from_event(event_type)
    route_to_stream(stream_name, event_type, payload)
    add_to_buffer({event_type, payload}, state)
  end

  def handle_info({:pubsub_event, topic, payload}, state) do
    # Handle explicit pubsub routing
    stream_name = Map.get(@topic_stream_map, topic, :general)
    route_to_stream(stream_name, :pubsub_event, payload)
    add_to_buffer({:pubsub_event, topic, payload}, state)
  end

  def handle_info(message, state) do
    # Handle any unstructured message
    Logger.debug("[PubSubBridge] Received unstructured message: #{inspect(message)}")
    route_to_stream(:general, :unknown, message)
    add_to_buffer(message, state)
  end

  @impl GenStage
  def handle_cast({:inject, event}, state) do
    route_to_stream(:general, :injected, event)
    add_to_buffer({:injected, event}, state)
  end

  ## Private helpers

  defp infer_stream_from_event(event_type) do
    event_str = Atom.to_string(event_type)

    cond do
      String.contains?(event_str, "chunk") -> :chunk_updates
      String.contains?(event_str, "topology") -> :topology_events
      String.contains?(event_str, "ml") or String.contains?(event_str, "model") -> :ml_events
      String.contains?(event_str, "lane") -> :lane_events
      String.contains?(event_str, "ca") or String.contains?(event_str, "automata") -> :ca_events
      String.contains?(event_str, "alert") or String.contains?(event_str, "error") -> :alerts
      true -> :general
    end
  end

  defp route_to_stream(stream_name, event_type, payload) do
    event_data = %{
      type: event_type,
      payload: payload,
      routed_at: DateTime.utc_now()
    }

    StreamManager.ingest(stream_name, event_data)
  end

  defp add_to_buffer(event, state) do
    wrapped = wrap_for_stage(event)
    new_buffer = :queue.in(wrapped, state.buffer)
    new_stats = %{state.stats | events_received: state.stats.events_received + 1}

    # Try to satisfy pending demand
    {events, remaining_buffer} = take_from_buffer(new_buffer, state.demand)

    new_state = %{
      state
      | buffer: remaining_buffer,
        demand: state.demand - length(events),
        stats: update_dispatch_stats(new_stats, length(events))
    }

    {:noreply, events, new_state}
  end

  defp wrap_for_stage(event) do
    %{
      event: event,
      timestamp: DateTime.utc_now(),
      id: Thunderline.UUID.v7()
    }
  end

  defp take_from_buffer(buffer, demand) when demand > 0 do
    take_from_buffer(buffer, demand, [])
  end

  defp take_from_buffer(buffer, _demand), do: {[], buffer}

  defp take_from_buffer(buffer, 0, acc), do: {Enum.reverse(acc), buffer}

  defp take_from_buffer(buffer, demand, acc) do
    case :queue.out(buffer) do
      {{:value, event}, remaining} ->
        take_from_buffer(remaining, demand - 1, [event | acc])

      {:empty, buffer} ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp update_dispatch_stats(stats, count) do
    %{stats | events_dispatched: stats.events_dispatched + count}
  end
end
