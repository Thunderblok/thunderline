defmodule Thunderline.Thunderflow.EventBus do
  @moduledoc """
  ANVIL Phase II simplified EventBus.

  Public surface (P0 hard contract):
    * publish_event(%Thunderline.Event{}) :: {:ok, event} | {:error, reason}
    * publish_event!(%Thunderline.Event{}) :: %Thunderline.Event{} | no_return()

  Semantics:
    * Validator ALWAYS runs first.
    * Invalid in :test (validator mode :raise) -> raise (crash fast)
    * Invalid in other modes -> emit drop telemetry & return {:error, reason}
    * NO silent fallbacks. Callers must branch on {:ok, _} | {:error, _}.

  Telemetry (emitted here):
    * [:thunderline, :event, :enqueue]  count=1  metadata: %{pipeline, name, priority}
    * [:thunderline, :event, :publish]  duration  metadata: %{status, name, pipeline}
    * [:thunderline, :event, :dropped]  count=1  metadata: %{reason, name}

  All former helper/legacy emit/batch/ai convenience functions have been removed. Build
  explicit %Thunderline.Event{} via Thunderline.Event.new/1 upstream.
  """

  require Logger
  require Thunderline.Thunderflow.Telemetry.OtelTrace
  alias Phoenix.PubSub
  alias Thunderline.Thunderflow.EventValidator

  @pubsub Thunderline.PubSub
  @telemetry_drop [:thunderline, :event, :dropped]

  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def publish_event(%Thunderline.Event{} = ev) do
    alias Thunderline.Thunderflow.Telemetry.OtelTrace

    OtelTrace.with_span "flow.publish_event", %{
      event_id: ev.id,
      event_name: ev.name,
      pipeline: ev.meta[:pipeline] || :default
    } do
      Process.put(:current_domain, :flow)

      OtelTrace.set_attributes(%{
        "thunderline.domain" => "flow",
        "thunderline.component" => "event_bus",
        "event.id" => ev.id,
        "event.name" => ev.name,
        "event.type" => to_string(ev.type),
        "event.source" => to_string(ev.source),
        "event.priority" => to_string(ev.priority)
      })

      # Continue trace from upstream domain if trace context present
      OtelTrace.continue_trace_from_event(ev)

      start = System.monotonic_time()

      result =
        case EventValidator.validate(ev) do
          :ok ->
            OtelTrace.add_event("flow.event_validated")
            do_publish(ev, start)

          {:error, reason} ->
            OtelTrace.set_status(:error, "Validation failed: #{inspect(reason)}")
            on_invalid(ev, reason, start)
        end

      case result do
        {:ok, published_ev} ->
          OtelTrace.add_event("flow.event_published", %{
            event_id: published_ev.id,
            published_at: published_ev.meta[:published_at]
          })

        {:error, _reason} ->
          OtelTrace.add_event("flow.event_dropped")
      end

      result
    end
  end

  # Accept maps and convert to Event structs for backwards compatibility
  def publish_event(%{} = attrs) when not is_struct(attrs) do
    case Thunderline.Event.new(attrs) do
      {:ok, event} -> publish_event(event)
      {:error, reason} -> {:error, {:event_creation_failed, reason}}
    end
  end

  def publish_event(other), do: {:error, {:unsupported_event, other}}

  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  def publish_event!(%Thunderline.Event{} = ev) do
    case publish_event(ev) do
      {:ok, ev} -> ev
      {:error, reason} -> raise "invalid_event: #{inspect(reason)}"
    end
  end

  # Accept maps and convert to Event structs for backwards compatibility
  def publish_event!(%{} = attrs) when not is_struct(attrs) do
    case publish_event(attrs) do
      {:ok, ev} -> ev
      {:error, reason} -> raise "invalid_event: #{inspect(reason)}"
    end
  end

  defp on_invalid(ev, reason, start) do
    :telemetry.execute(@telemetry_drop, %{count: 1}, %{reason: reason, name: ev.name})
    telemetry_publish(start, ev, :error, :invalid)
    {:error, reason}
  end

  # NOTE: Legacy helpers removed. The following were previously used for
  # topic-based routing but are now deprecated. Kept commented for reference
  # during migration period - safe to fully delete after 2025-08.
  #
  # defp extract_domain(payload), do: Map.get(payload, :domain)
  # defp determine_pipeline_from_topic(topic), do: ...
  # defp extract_domains_from_topic(topic), do: ...
  # defp generate_correlation_id, do: Thunderline.UUID.v7()
  # defp map_source_domain(domain), do: ...
  # defp build_name(source, type), do: ...

  defp do_publish(%Thunderline.Event{} = ev, start) do
    pipeline = pipeline_for(ev)
    {table, priority} = table_and_priority(pipeline, ev.priority)

    try do
      Thunderline.Thunderflow.MnesiaProducer.enqueue_event(table, ev,
        pipeline_type: pipeline,
        priority: priority
      )

      :telemetry.execute([:thunderline, :event, :enqueue], %{count: 1}, %{
        pipeline: pipeline,
        name: ev.name,
        priority: priority
      })

      telemetry_publish(start, ev, :ok, pipeline)
      maybe_tap(ev, pipeline, :enqueue)
      {:ok, ev}
    rescue
      error ->
        Logger.warning(
          "MnesiaProducer unavailable (#{pipeline}) fallback PubSub: #{inspect(error)}"
        )

        PubSub.broadcast(@pubsub, "events:" <> to_string(ev.type || :unknown), ev)
        telemetry_publish(start, ev, :ok, :fallback_pubsub)
        maybe_tap(ev, pipeline, :fallback_pubsub)
        {:ok, ev}
    end
  end

  defp telemetry_publish(start, ev, status, pipeline) do
    :telemetry.execute(
      [:thunderline, :event, :publish],
      %{duration: System.monotonic_time() - start},
      %{status: status, name: ev.name, pipeline: pipeline}
    )
  end

  defp pipeline_for(%Thunderline.Event{} = ev) do
    cond do
      match?(%{meta: %{pipeline: p}} when p in [:realtime, :cross_domain, :general], ev) ->
        ev.meta.pipeline

      is_binary(ev.name) and String.starts_with?(ev.name, "ai.") ->
        :realtime

      is_binary(ev.name) and String.starts_with?(ev.name, "grid.") ->
        :realtime

      ev.target_domain && ev.target_domain != "broadcast" ->
        :cross_domain

      ev.priority == :high ->
        :realtime

      true ->
        :general
    end
  end

  defp table_and_priority(pipeline, priority) do
    case pipeline do
      :general -> {Thunderline.Thunderflow.MnesiaProducer, priority}
      :cross_domain -> {Thunderline.Thunderflow.CrossDomainEvents, priority}
      :realtime -> {Thunderline.Thunderflow.RealTimeEvents, priority}
      _ -> {Thunderline.Thunderflow.MnesiaProducer, priority || :normal}
    end
  end

  # Lightweight debug fan-out into EventBuffer so the dashboard shows *something*
  # even if downstream pipelines are stalled. Controlled by feature flag :debug_event_tap.
  defp maybe_tap(ev, pipeline, stage) do
    if feature?(:debug_event_tap) do
      safe_put = fn ->
        msg = ev.name || to_string(ev.type || :event)

        Thunderline.Thunderflow.EventBuffer.put(%{
          kind: :tap,
          domain: pipeline,
          message: "#{msg} (#{stage})",
          source: "eventbus"
        })
      end

      try do
        safe_put.()
      rescue
        _ -> :ok
      end
    end
  end

  defp feature?(flag), do: flag in Application.get_env(:thunderline, :features, [])

  # Legacy validation/transform helpers removed (enforced upstream via EventValidator).
end
