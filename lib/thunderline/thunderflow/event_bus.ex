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
  alias Phoenix.PubSub
  alias Thunderline.Thunderflow.EventValidator

  @pubsub Thunderline.PubSub
  @telemetry_drop [:thunderline, :event, :dropped]

  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def publish_event(%Thunderline.Event{} = ev) do
    start = System.monotonic_time()

    case EventValidator.validate(ev) do
      :ok -> do_publish(ev, start)
      {:error, reason} -> on_invalid(ev, reason, start)
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

  defp on_invalid(ev, reason, start) do
    :telemetry.execute(@telemetry_drop, %{count: 1}, %{reason: reason, name: ev.name})
    telemetry_publish(start, ev, :error, :invalid)
    {:error, reason}
  end

  # --- Legacy helpers removed (blackhole) ---------------------------------
  defp extract_domain(payload), do: Map.get(payload, :domain)

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

  # build_event removed – explicit construction required upstream.

  # Shared batch construction returning {correlation_id, events, built_count}
  # Batch build removed – callers must publish individually.

  # batch_table_and_priority removed.

  # Compatibility helper for legacy map-form publish_event clauses.
  # Ensures we have a deterministic name when only :type is provided.
  # infer_name_from_type removed.

  defp do_publish(%Thunderline.Event{} = ev, start) do
    pipeline = pipeline_for(ev)
    {table, priority} = table_and_priority(pipeline, ev.priority)

    try do
      Thunderflow.MnesiaProducer.enqueue_event(table, ev,
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
      :general -> {Thunderflow.MnesiaProducer, priority}
      :cross_domain -> {Thunderflow.CrossDomainEvents, priority}
      :realtime -> {Thunderflow.RealTimeEvents, priority}
      _ -> {Thunderflow.MnesiaProducer, priority || :normal}
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
