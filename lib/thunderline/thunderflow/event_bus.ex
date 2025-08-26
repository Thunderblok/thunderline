defmodule Thunderline.EventBus do
  @moduledoc """
  Centralized event emission interface for Thunderline application.

  This module provides a unified API for emitting events throughout the application,
  replacing scattered PubSub.broadcast calls with structured Broadway pipeline routing.

  ## Usage

      # General domain events
      EventBus.emit(:agent_created, %{agent_id: "123", domain: "thunderchief"})

      # Cross-domain events
      EventBus.emit_cross_domain(:orchestration_complete, %{
        from_domain: "thunderchief",
        to_domain: "thunderbridge",
        payload: orchestration_data
      })

      # Real-time events
      EventBus.emit_realtime(:agent_status_update, %{
        agent_id: "123",
        status: "online",
        priority: :high
      })

  ## Event Types

  - `:general` - Domain events, background processing, non-critical updates
  - `:cross_domain` - Inter-domain communication, orchestration events
  - `:realtime` - Agent updates, dashboard updates, WebSocket broadcasts

  ## Pipeline Routing

  Events are automatically routed to appropriate Broadway pipelines:
  - General events → EventPipeline (batching, background processing)
  - Cross-domain events → CrossDomainPipeline (domain routing, transformation)
  - Real-time events → RealTimePipeline (low latency, high throughput)
  """

  require Logger
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub

  @doc """
  Subscribe to events on a given topic.

  This is a compatibility function for ThunderBridge and other legacy components.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) when is_binary(topic) do
    PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Emit a general domain event through Broadway EventPipeline.

  General events are batched and processed in the background with retries
  and dead letter queue handling.
  """
  @spec emit(atom(), map()) :: :ok | {:error, term()}
  def emit(event_type, payload) when is_atom(event_type) and is_map(payload) do
    source_atom = map_source_domain(extract_domain(payload))
    name = build_name(source_atom, event_type)
    base_attrs = %{
      name: name,
      type: event_type,
      payload: payload,
      source: source_atom,
      correlation_id: generate_correlation_id(),
      priority: Map.get(payload, :priority, :normal)
    }

    event =
      case Thunderline.Event.new(base_attrs) do
        {:ok, ev} -> ev
        {:error, errs} ->
          Logger.warning("Failed taxonomy construction for #{inspect(event_type)}: #{inspect(errs)}; falling back to legacy map")
          Map.merge(base_attrs, %{timestamp: DateTime.utc_now(), pipeline: :general})
      end

    priority = Map.get(payload, :priority, :normal)

    try do
      Thunderflow.MnesiaProducer.enqueue_event(
        Thunderflow.MnesiaProducer,
        event,
        pipeline_type: :general,
        priority: priority
      )
    rescue
      error ->
        Logger.warning("MnesiaProducer not available, falling back to PubSub: #{inspect(error)}")
        PubSub.broadcast(@pubsub, "events:#{event_type}", event)
        :ok
    end
  end

  @doc """
  Emit a cross-domain event through Broadway CrossDomainPipeline.

  Cross-domain events are routed between domains with automatic transformation
  and structured error handling.
  """
  @spec emit_cross_domain(atom(), map()) :: :ok | {:error, term()}
  def emit_cross_domain(event_type, %{from_domain: from_domain, to_domain: to_domain} = payload)
      when is_atom(event_type) and is_binary(from_domain) and is_binary(to_domain) do
    source_atom = map_source_domain(from_domain)
    name = build_name(source_atom, event_type)
    base_attrs = %{
      name: name,
      type: event_type,
      payload: payload,
      source: source_atom,
      correlation_id: generate_correlation_id(),
      priority: Map.get(payload, :priority, :normal),
      source_domain: from_domain,
      target_domain: to_domain
    }

    event = case Thunderline.Event.new(base_attrs) do
      {:ok, ev} -> ev
      {:error, _} -> Map.merge(base_attrs, %{timestamp: DateTime.utc_now(), pipeline: :cross_domain})
    end

    # Enqueue to Mnesia cross-domain table
    priority = Map.get(payload, :priority, :normal)

    Thunderflow.MnesiaProducer.enqueue_event(
      Thunderflow.CrossDomainEvents,
      event,
      pipeline_type: :cross_domain,
      priority: priority
    )
  end

  @doc """
  Emit a real-time event through Broadway RealTimePipeline.

  Real-time events are processed with minimal latency for agent updates,
  dashboard updates, and WebSocket broadcasts.
  """
  @spec emit_realtime(atom(), map()) :: :ok | {:error, term()}
  def emit_realtime(event_type, payload) when is_atom(event_type) and is_map(payload) do
    priority = Map.get(payload, :priority, :normal)
    source_atom = :flow
    name = build_name(source_atom, event_type)
    base_attrs = %{
      name: name,
      type: event_type,
      payload: payload,
      source: source_atom,
      correlation_id: generate_correlation_id(),
      priority: priority
    }

    event = case Thunderline.Event.new(base_attrs) do
      {:ok, ev} -> ev
      {:error, _} -> Map.merge(base_attrs, %{timestamp: DateTime.utc_now(), pipeline: :realtime})
    end

    # Enqueue to Mnesia real-time table
    Thunderflow.MnesiaProducer.enqueue_event(
      Thunderflow.RealTimeEvents,
      event,
      pipeline_type: :realtime,
      priority: priority
    )
  end

  @doc """
  Emit multiple events in a batch for high-efficiency processing.

  This is useful for bulk operations where many related events need to be processed.
  """
  @spec emit_batch([{atom(), map()}], atom()) :: :ok | {:error, term()}
  def emit_batch(events, pipeline_type \\ :general)
      when is_list(events) and pipeline_type in [:general, :cross_domain, :realtime] do
    correlation_id = generate_correlation_id()
    timestamp = DateTime.utc_now()

    event_list =
      Enum.map(events, fn {event_type, payload} ->
        %{
          type: event_type,
          payload: payload,
          timestamp: timestamp,
          correlation_id: correlation_id
        }
      end)

    # Enqueue events in batch to appropriate Mnesia table
    {table, priority} =
      case pipeline_type do
        :general -> {Thunderflow.MnesiaProducer, :normal}
        :cross_domain -> {Thunderflow.CrossDomainEvents, :normal}
        :realtime -> {Thunderflow.RealTimeEvents, :high}
      end

    Thunderflow.MnesiaProducer.enqueue_events(
      table,
      event_list,
      pipeline_type: pipeline_type,
      priority: priority
    )
  end

  # Migration helpers for existing broadcast patterns

  @doc """
  Migration helper: Convert existing PubSub.broadcast calls to EventBus.emit.

  This function maintains backward compatibility while routing through Broadway.
  """
  @spec broadcast_via_eventbus(String.t(), atom(), map()) :: :ok | {:error, term()}
  def broadcast_via_eventbus(topic, event_type, payload) do
    # Determine pipeline type based on topic pattern
    pipeline_type = determine_pipeline_from_topic(topic)

    case pipeline_type do
      :realtime ->
        emit_realtime(event_type, payload)

      :cross_domain ->
        # Extract domain info from topic for cross-domain routing
        case extract_domains_from_topic(topic) do
          {from_domain, to_domain} ->
            emit_cross_domain(
              event_type,
              Map.merge(payload, %{
                from_domain: from_domain,
                to_domain: to_domain
              })
            )

          _ ->
            emit(event_type, payload)
        end

      _ ->
        emit(event_type, payload)
    end
  end

  @doc """
  Legacy PubSub broadcast for immediate migration compatibility.

  This allows gradual migration from direct PubSub to Broadway pipelines.
  """
  @spec legacy_broadcast(String.t(), map()) :: :ok | {:error, term()}
  def legacy_broadcast(topic, payload) do
    # Route to appropriate Broadway pipeline via Mnesia
    event_type = :legacy_event

    pipeline_result =
      case determine_pipeline_from_topic(topic) do
        :realtime -> emit_realtime(event_type, Map.put(payload, :topic, topic))
        :cross_domain -> emit(event_type, Map.put(payload, :topic, topic))
        _ -> emit(event_type, Map.put(payload, :topic, topic))
      end

    # For transition period, also broadcast to legacy PubSub
    pubsub_result = PubSub.broadcast(@pubsub, topic, payload)

    case {pipeline_result, pubsub_result} do
      {:ok, :ok} -> :ok
      {error, _} -> error
      {_, error} -> error
    end
  end

  # Private helper functions

  defp extract_domain(payload) do
    cond do
      Map.has_key?(payload, :domain) -> payload.domain
      Map.has_key?(payload, :agent_id) -> "thunderchief"
      Map.has_key?(payload, :message_id) -> "thunderblock"
      Map.has_key?(payload, :chunk_id) -> "thundergrid"
      Map.has_key?(payload, :bridge_id) -> "thunderbridge"
      true -> "unknown"
    end
  end

  defp determine_pipeline_from_topic(topic) do
    cond do
      String.contains?(topic, "agent") or String.contains?(topic, "dashboard") or
          String.contains?(topic, "live") ->
        :realtime

      String.contains?(topic, "domain") or String.contains?(topic, "orchestration") ->
        :cross_domain

      true ->
        :general
    end
  end

  defp extract_domains_from_topic(topic) do
    # Parse topic patterns like "thunderchief:to:thunderbridge" or "domain:from:to"
    case String.split(topic, ":") do
      [from_domain, "to", to_domain] -> {from_domain, to_domain}
      ["domain", from_domain, to_domain] -> {from_domain, to_domain}
      _ -> nil
    end
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  # Map legacy or ad-hoc domain strings to taxonomy source atoms.
  # This is a best-effort transitional mapping; refine as taxonomy hardens.
  defp map_source_domain(nil), do: :unknown
  defp map_source_domain("thundergate" <> _), do: :gate
  defp map_source_domain("thunderflow" <> _), do: :flow
  defp map_source_domain("thundercrown" <> _), do: :crown
  defp map_source_domain("thunderbolt" <> _), do: :bolt
  defp map_source_domain("thunderblock" <> _), do: :block
  defp map_source_domain("thunderbridge" <> _), do: :bridge
  defp map_source_domain("thunderlink" <> _), do: :link
  defp map_source_domain(other) when is_binary(other), do: :unknown
  defp map_source_domain(atom) when is_atom(atom), do: atom

  defp build_name(source, type) when is_atom(source) and is_atom(type) do
    # Basic naming: system.<source>.<type>
    "system." <> Atom.to_string(source) <> "." <> Atom.to_string(type)
  end

  # Event validation and transformation

  @doc """
  Validate event structure before emission.
  """
  @spec validate_event(atom(), map()) :: {:ok, map()} | {:error, String.t()}
  def validate_event(event_type, payload) when is_atom(event_type) and is_map(payload) do
    cond do
      # Required fields validation
      is_nil(event_type) ->
        {:error, "Event type cannot be nil"}

      not is_atom(event_type) ->
        {:error, "Event type must be an atom"}

      not is_map(payload) ->
        {:error, "Payload must be a map"}

      # Payload size validation (prevent memory issues)
      :erlang.external_size(payload) > 100_000 ->
        {:error, "Payload too large (>100KB)"}

      true ->
        {:ok, %{type: event_type, payload: payload}}
    end
  end

  def validate_event(_event_type, _payload) do
    {:error, "Invalid event type or payload format"}
  end

  @doc """
  Transform legacy event formats to Broadway-compatible structure.
  """
  @spec transform_legacy_event(map()) :: map()
  def transform_legacy_event(%{event: event_type, data: payload} = legacy_event) do
    %{
      type: event_type,
      payload: payload,
      timestamp: DateTime.utc_now(),
      legacy: true,
      original_format: Map.drop(legacy_event, [:event, :data])
    }
  end

  def transform_legacy_event(event) when is_map(event) do
    # If already in new format, pass through
    if Map.has_key?(event, :type) and Map.has_key?(event, :payload) do
      event
    else
      # Transform old format to new format
      %{
        type: Map.get(event, :type, :unknown_event),
        payload: event,
        timestamp: DateTime.utc_now(),
        legacy: true
      }
    end
  end

  @doc """
  Compatibility function for ThunderMemory and other modules.

  Accepts events in the format:
  %{type: event_type, data: payload, source: source, timestamp: timestamp}
  """
  @spec publish_event(map()) :: :ok | {:error, term()}
  def publish_event(%{type: event_type, data: data} = event) when is_atom(event_type) do
    # Persist-first pathway
    persisted =
      event
      |> Map.put(:payload, data)
  |> Thunderline.Thunderflow.EventStore.append()

    case persisted do
      :ok ->
        Phoenix.PubSub.broadcast(@pubsub, "events:all", {:event, Map.put(event, :payload, data)})
  priority = Map.get(event, :priority, :normal)
        source = Map.get(event, :source, :unknown)
        pipeline_type = case {event_type, source} do
          {:agent_spawned, :thunder_memory} -> :realtime
          {:agent_updated, :thunder_memory} -> :realtime
          {:chunk_created, :thunder_memory} -> :general
          {_, :thunder_memory} -> :general
          _ -> :general
        end
        payload_ext = Map.merge(data, %{source: source, priority: priority, original_timestamp: Map.get(event, :timestamp)})
        case pipeline_type do
          :realtime -> emit_realtime(event_type, payload_ext)
          _ -> emit(event_type, payload_ext)
        end
      other -> other
    end
  end

  def publish_event(%{type: event_type, payload: payload} = event) when is_atom(event_type) do
    # Already in new format, route directly
    source = Map.get(event, :source, :unknown)
    priority = Map.get(event, :priority, :normal)

    case source do
      :thunder_bridge -> emit_realtime(event_type, payload)
      _ -> emit(event_type, payload)
    end
  end

  def publish_event(event) when is_map(event) do
    Logger.warning("EventBus.publish_event received unsupported event format: #{inspect(event)}")
    {:error, "Unsupported event format"}
  end
end
