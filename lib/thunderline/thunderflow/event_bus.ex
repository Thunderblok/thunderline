defmodule Thunderline.EventBus do
  @moduledoc """
  WARHORSE Unified EventBus (P0).

  Public surface collapsed to a single publishing API:
    * publish_event(%Thunderline.Event{}) :: {:ok, event} | {:error, reason}
    * publish_event!(%Thunderline.Event{}) :: %Thunderline.Event{} | no_return()

  Callers MUST construct events via `Thunderline.Event.new/1`.
  All prior multi-variant emission helpers and compatibility wrappers have now been REMOVED
  (emit/2, emit_realtime/2, emit_cross_domain/2, broadcast_via_eventbus/3, legacy_broadcast/2) are gone.
  If you find yourself recreating them, STOP: build the event explicitly & publish.

  Validation semantics (delegated to EventValidator):
    * dev (:warn)  -> validator returns {:error, reason}; we propagate {:error, reason}
    * test (:raise)-> validator raises; publish_event!/1 surfaces exception; publish_event/1 never returns {:error, reason} for invalid (process crashes in test, enforcing green)
    * prod (:drop) -> validator returns {:error, reason}; drop telemetry already emitted; we return {:error, reason}

  Telemetry emitted here:
    * [:thunderline, :event, :publish] measurements: %{duration: native} metadata: %{status, name, pipeline}
    * [:thunderline, :event, :enqueue] measurements: %{count: 1} metadata: %{pipeline, name, priority}

  Pipeline classification heuristic (unless event.meta.pipeline preset):
    * meta.pipeline in [:realtime,:cross_domain,:general] respected
    * name starts with "ai." or "grid." => :realtime
    * target_domain != "broadcast" => :cross_domain
    * priority == :high => :realtime
    * fallback :general
  """

  require Logger
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub

  @doc "Subscribe to a PubSub topic (legacy compatibility)."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) when is_binary(topic) do
    PubSub.subscribe(@pubsub, topic)
  end

  @doc "Publish a canonical %Thunderline.Event{} (unified API)."
  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def publish_event(%Thunderline.Event{} = ev) do
    start = System.monotonic_time()
    case Thunderline.Thunderflow.EventValidator.validate(ev) do
      :ok -> do_enqueue(ev, start)
      {:error, reason} ->
        telemetry_publish(start, ev, :error, pipeline_for(ev))
        {:error, reason}
    end
  end
  def publish_event(other), do: {:error, {:unsupported_event, other}}

  @doc "Bang version raising on failure."
  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  def publish_event!(%Thunderline.Event{} = ev) do
    case publish_event(ev) do
      {:ok, ev} -> ev
      {:error, reason} -> raise ArgumentError, "publish_event!/1 failed: #{inspect(reason)}"
    end
  end


  # Batch helpers removed for unification phase (can be reintroduced as separate module if needed).

  @doc """
  Emit an AI-related real-time event with standardized naming.

  Stages supported:
    * :tool_start
    * :tool_result
    * :conversation_delta
    * :model_token

  Naming pattern:
    payload[:event_name] (if provided) OR "ai." <> Atom.to_string(stage)

  The event is routed via the realtime pipeline. Correlation propagation occurs
  if the payload already contains :correlation_id.
  """
  @spec ai_emit(atom(), map()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def ai_emit(stage, payload) when stage in [:tool_start, :tool_result, :conversation_delta, :model_token] and is_map(payload) do
    payload = payload |> Map.put(:domain, "thunderai") |> Map.put_new(:event_name, "ai." <> Atom.to_string(stage)) |> Map.put(:ai_stage, stage)
    base_attrs = %{
      name: Map.fetch!(payload, :event_name),
      type: :ai_event,
      payload: payload,
      source: :flow,
      correlation_id: Map.get(payload, :correlation_id, generate_correlation_id()),
      priority: Map.get(payload, :priority, :normal),
      meta: %{pipeline: :realtime}
    }
    with {:ok, ev} <- Thunderline.Event.new(base_attrs), res <- publish_event(ev) do
      case res do
        {:ok, %Thunderline.Event{} = ev2} ->
          :telemetry.execute(
            [:thunderline, :ai, :emit],
            %{count: 1},
            %{stage: stage, name: ev2.name, correlation_id: ev2.correlation_id, source: ev2.source}
          )
          res
        _ -> res
      end
    end
  end
  def ai_emit(_stage, _payload), do: {:error, :unsupported_ai_stage}

  # Migration helpers for existing broadcast patterns

  # All legacy wrapper and broadcast helpers removed; only explicit event construction allowed.

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
    Thunderline.UUID.v7()
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

  defp build_event(event_type, payload) do
    source_atom = map_source_domain(extract_domain(payload))
    name =
      cond do
        is_binary(Map.get(payload, :event_name)) -> Map.get(payload, :event_name)
        is_binary(Map.get(payload, :name_override)) -> Map.get(payload, :name_override)
        true -> build_name(source_atom, event_type)
      end
    attrs = %{
      name: name,
      type: event_type,
      payload: payload,
      source: source_atom,
      correlation_id: Map.get(payload, :correlation_id, generate_correlation_id()),
      priority: Map.get(payload, :priority, :normal)
    }
    Thunderline.Event.new(attrs)
  end

  # Shared batch construction returning {correlation_id, events, built_count}
  defp build_batch(events, pipeline_type) do
    inferred_correlation =
      events
      |> List.first()
      |> case do
        {_, %{correlation_id: cid}} when is_binary(cid) -> cid
        _ -> generate_correlation_id()
      end

    timestamp = DateTime.utc_now()

    {event_list, built_count} =
      Enum.map_reduce(events, 0, fn {event_type, payload}, acc ->
        source_atom = map_source_domain(extract_domain(payload))
        name =
          cond do
            is_binary(Map.get(payload, :event_name)) -> Map.get(payload, :event_name)
            is_binary(Map.get(payload, :name_override)) -> Map.get(payload, :name_override)
            true -> build_name(source_atom, event_type)
          end

        base = %{
          name: name,
          type: event_type,
          payload: payload,
          source: source_atom,
          correlation_id: Map.get(payload, :correlation_id, inferred_correlation),
          timestamp: timestamp
        }

        case Thunderline.Event.new(base) do
          {:ok, ev} -> {ev, acc + 1}
          {:error, _} -> {Map.put(base, :pipeline, pipeline_type), acc}
        end
      end)

    {inferred_correlation, event_list, built_count}
  end

  defp batch_table_and_priority(pipeline_type) do
    case pipeline_type do
      :general -> {Thunderflow.MnesiaProducer, :normal}
      :cross_domain -> {Thunderflow.CrossDomainEvents, :normal}
      :realtime -> {Thunderflow.RealTimeEvents, :high}
    end
  end

  # Compatibility helper for legacy map-form publish_event clauses.
  # Ensures we have a deterministic name when only :type is provided.
  defp infer_name_from_type(event_type, source) when is_atom(event_type) and is_atom(source) do
    build_name(source, event_type)
  end
  defp infer_name_from_type(event_type, _source) when is_atom(event_type), do: build_name(:unknown, event_type)
  defp infer_name_from_type(_other, _source), do: "system.unknown.event"

  defp do_enqueue(%Thunderline.Event{} = ev, start) do
    pipeline = pipeline_for(ev)
    {table, priority} = table_and_priority(pipeline, ev.priority)
    try do
      Thunderflow.MnesiaProducer.enqueue_event(table, ev, pipeline_type: pipeline, priority: priority)
      :telemetry.execute([:thunderline, :event, :enqueue], %{count: 1}, %{pipeline: pipeline, name: ev.name, priority: priority})
      telemetry_publish(start, ev, :ok, pipeline)
      {:ok, ev}
    rescue
      error ->
        Logger.warning("MnesiaProducer unavailable (#{pipeline}) fallback PubSub: #{inspect(error)}")
        PubSub.broadcast(@pubsub, "events:" <> to_string(ev.type || :unknown), ev)
        telemetry_publish(start, ev, :ok, :fallback_pubsub)
        {:ok, ev}
    end
  end

  defp telemetry_publish(start, ev, status, pipeline) do
    :telemetry.execute([
      :thunderline, :event, :publish
    ], %{duration: System.monotonic_time() - start}, %{status: status, name: ev.name, pipeline: pipeline})
  end

  defp pipeline_for(%Thunderline.Event{} = ev) do
    cond do
      match?(%{meta: %{pipeline: p}} when p in [:realtime, :cross_domain, :general], ev) -> ev.meta.pipeline
      is_binary(ev.name) and String.starts_with?(ev.name, "ai.") -> :realtime
      is_binary(ev.name) and String.starts_with?(ev.name, "grid.") -> :realtime
      ev.target_domain && ev.target_domain != "broadcast" -> :cross_domain
      ev.priority == :high -> :realtime
      true -> :general
    end
  end

  defp table_and_priority(pipeline, priority) do
    case pipeline do
      :general -> {Thunderflow.MnesiaProducer, priority}
      :cross_domain -> {Thunderflow.CrossDomainEvents, priority}
      :realtime -> {Thunderflow.RealTimeEvents, priority}
      _ -> {Thunderflow.MnesiaProducer, priority || :normal}
    end
  end

  # Event validation and transformation

  @doc "Validate event structure before emission (legacy – prefer EventValidator)."
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

  # Map-form (legacy) publish variants – construct canonical event then delegate
  @spec publish_event(map()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def publish_event(%{type: event_type, data: data} = event) when is_atom(event_type) do
    source = map_source_domain(Map.get(event, :source_domain) || Map.get(event, :source) || "unknown")
    name = Map.get(event, :name) || infer_name_from_type(event_type, source)
    attrs = [name: name, type: event_type, payload: Map.put(data, :source, source), source: source]
    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      publish_event(ev)
    end
  end
  def publish_event(%{type: event_type, payload: payload} = event) when is_atom(event_type) and is_map(payload) do
    source = map_source_domain(Map.get(event, :source_domain) || Map.get(event, :source) || "unknown")
    name = Map.get(event, :name) || infer_name_from_type(event_type, source)
    attrs = [name: name, type: event_type, payload: payload, source: source]
    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      publish_event(ev)
    end
  end
  def publish_event(event) when is_map(event) do
    Logger.warning("Unsupported legacy event map: #{inspect(event)}")
    {:error, :unsupported_event_map}
  end
end
