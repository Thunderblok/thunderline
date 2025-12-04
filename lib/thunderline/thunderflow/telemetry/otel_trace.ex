defmodule Thunderline.Thunderflow.Telemetry.OtelTrace do
  @moduledoc """
  OpenTelemetry trace helpers for cross-domain instrumentation.

  Provides standardized span creation and context propagation across all
  Thunderline domains to enable the T-72h telemetry heartbeat requirement.

  ## Usage

      # Start a span with automatic trace context propagation
      OtelTrace.with_span "gate.receive", %{event_id: event.id} do
        # Your code here
      end

      # Get current trace ID for correlation
      trace_id = OtelTrace.current_trace_id()

      # Inject trace context into event metadata
      event = OtelTrace.inject_trace_context(event)

  ## Telemetry Events

  All spans emit standard OpenTelemetry events visible in Grafana:
  - [:thunderline, :trace, :span, :start]
  - [:thunderline, :trace, :span, :stop]
  - [:thunderline, :trace, :span, :exception]
  """

  require OpenTelemetry.Tracer
  require OpenTelemetry.Span
  require Logger

  @doc """
  Execute code within an OpenTelemetry span.

  Automatically handles span lifecycle (start, set_status, end) and exception capture.
  """
  defmacro with_span(span_name, attrs \\ quote(do: %{}), do: block) do
    quote do
      require OpenTelemetry.Tracer

      OpenTelemetry.Tracer.with_span unquote(span_name),
                                     %{attributes: Map.to_list(unquote(attrs))} do
        span_ctx = OpenTelemetry.Tracer.current_span_ctx()

        try do
          result = unquote(block)
          OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(:ok))
          result
        rescue
          error ->
            OpenTelemetry.Span.record_exception(span_ctx, error, __STACKTRACE__)

            OpenTelemetry.Span.set_status(
              span_ctx,
              OpenTelemetry.status(:error, Exception.message(error))
            )

            reraise error, __STACKTRACE__
        end
      end
    end
  end

  @doc """
  Get the current OpenTelemetry trace ID as a hex string.

  Returns `"00000000000000000000000000000000"` if no active span.
  """
  def current_trace_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        "00000000000000000000000000000000"

      span_ctx ->
        trace_id = OpenTelemetry.Span.trace_id(span_ctx)

        if trace_id == 0 do
          "00000000000000000000000000000000"
        else
          trace_id
          |> Integer.to_string(16)
          |> String.pad_leading(32, "0")
          |> String.downcase()
        end
    end
  end

  @doc """
  Get the current OpenTelemetry span ID as a hex string.

  Returns `"0000000000000000"` if no active span.
  """
  def current_span_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        "0000000000000000"

      span_ctx ->
        span_id = OpenTelemetry.Span.span_id(span_ctx)

        if span_id == 0 do
          "0000000000000000"
        else
          span_id
          |> Integer.to_string(16)
          |> String.pad_leading(16, "0")
          |> String.downcase()
        end
    end
  end

  @doc """
  Inject trace context into event metadata for cross-domain propagation.

  Adds `trace_id` and `span_id` to event metadata so downstream domains
  can continue the trace.
  """
  def inject_trace_context(%{meta: meta} = event) do
    trace_context = %{
      trace_id: current_trace_id(),
      span_id: current_span_id(),
      parent_domain: infer_domain_from_span()
    }

    %{event | meta: Map.merge(meta, trace_context)}
  end

  def inject_trace_context(event) do
    event
  end

  @doc """
  Extract trace context from event metadata and set as current span parent.

  Enables trace continuation across domain boundaries.
  Uses W3C traceparent format via OpenTelemetry propagator.
  """
  def continue_trace_from_event(%{meta: %{trace_id: trace_id, span_id: span_id}} = _event)
      when is_binary(trace_id) and is_binary(span_id) do
    # Build W3C traceparent header: version-traceid-spanid-flags
    # Format: 00-{32 hex trace_id}-{16 hex span_id}-{2 hex flags}
    # Pad trace_id to 32 chars, span_id to 16 chars
    padded_trace_id = String.pad_leading(trace_id, 32, "0")
    padded_span_id = String.pad_leading(span_id, 16, "0")
    traceparent = "00-#{padded_trace_id}-#{padded_span_id}-01"

    # Use the W3C trace context propagator to extract and set the context
    # extract/1 uses the default propagator and default carrier functions
    carrier = %{"traceparent" => traceparent}

    # Get the current propagator and use extract/4
    propagator = :opentelemetry.get_text_map_extractor()

    ctx =
      :otel_propagator_text_map.extract(
        propagator,
        carrier,
        fn c -> Map.keys(c) end,
        fn key, c -> Map.get(c, key) end
      )

    OpenTelemetry.Ctx.attach(ctx)
    :ok
  rescue
    _ ->
      Logger.debug("Failed to parse trace context from event")
      :error
  end

  def continue_trace_from_event(_event), do: :ok

  @doc """
  Add domain-specific attributes to the current span.

  Useful for annotating spans with domain-specific context like actor_id,
  resource_type, operation, etc.
  """
  def set_attributes(attrs) when is_map(attrs) or is_list(attrs) do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    attrs_list = if is_map(attrs), do: Map.to_list(attrs), else: attrs
    OpenTelemetry.Span.set_attributes(span_ctx, attrs_list)
    :ok
  end

  @doc """
  Set span status and optional description.

  Status can be :ok, :error, or :unset.
  """
  def set_status(status, description \\ nil)

  def set_status(status, nil) when status in [:ok, :error, :unset] do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(status))
    :ok
  end

  def set_status(status, description) when status in [:ok, :error, :unset] do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(status, description))
    :ok
  end

  @doc """
  Add an event to the current span with optional attributes.

  Events are timestamped and appear in trace visualizations.
  """
  def add_event(name, attrs \\ %{}) do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    attrs_list = if is_map(attrs), do: Map.to_list(attrs), else: attrs
    # OpenTelemetry.Span.add_event requires span context
    OpenTelemetry.Span.add_event(span_ctx, name, attrs_list)
    :ok
  end

  # Private helpers

  defp infer_domain_from_span do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        :unknown

      _span_ctx ->
        # Try to infer domain from span name
        # Span names follow pattern: "domain.operation"
        case Process.get(:current_domain) do
          nil -> :unknown
          domain when is_atom(domain) -> domain
          domain -> String.to_atom("#{domain}")
        end
    end
  rescue
    _ -> :unknown
  end
end
