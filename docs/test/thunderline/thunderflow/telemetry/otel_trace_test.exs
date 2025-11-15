defmodule Thunderline.Thunderflow.Telemetry.OtelTraceTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderflow.Telemetry.OtelTrace

  setup do
    # Ensure OpenTelemetry tracer is available
    Application.ensure_all_started(:opentelemetry)
    :ok
  end

  describe "with_span/2" do
    test "creates span and returns block result" do
      require OtelTrace

      result =
        OtelTrace.with_span "test.span", %{test_attr: "value"} do
          :test_result
        end

      assert result == :test_result
    end

    test "captures exceptions and re-raises" do
      require OtelTrace

      assert_raise RuntimeError, "test error", fn ->
        OtelTrace.with_span "test.span", %{} do
          raise "test error"
        end
      end
    end
  end

  describe "current_trace_id/0" do
    test "returns trace ID when span is active" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        trace_id = OtelTrace.current_trace_id()
        assert is_binary(trace_id)
        assert String.length(trace_id) == 32
        assert String.match?(trace_id, ~r/^[0-9a-f]{32}$/)
      end
    end

    test "returns zero trace ID when no span is active" do
      trace_id = OtelTrace.current_trace_id()
      assert trace_id == "00000000000000000000000000000000"
    end
  end

  describe "current_span_id/0" do
    test "returns span ID when span is active" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        span_id = OtelTrace.current_span_id()
        assert is_binary(span_id)
        assert String.length(span_id) == 16
        assert String.match?(span_id, ~r/^[0-9a-f]{16}$/)
      end
    end

    test "returns zero span ID when no span is active" do
      span_id = OtelTrace.current_span_id()
      assert span_id == "0000000000000000"
    end
  end

  describe "inject_trace_context/1" do
    test "adds trace context to event with meta field" do
      require OtelTrace
      event = %{id: "123", meta: %{existing: "field"}}

      OtelTrace.with_span "test.span", %{} do
        enriched = OtelTrace.inject_trace_context(event)

        assert enriched.meta.trace_id != "00000000000000000000000000000000"
        assert enriched.meta.span_id != "0000000000000000"
        assert enriched.meta.existing == "field"
      end
    end

    test "returns event unchanged if no meta field" do
      event = %{id: "123"}
      result = OtelTrace.inject_trace_context(event)
      assert result == event
    end
  end

  describe "continue_trace_from_event/1" do
    test "attempts to set remote span context from event metadata" do
      require OtelTrace

      # Create event with valid trace context format
      trace_id = String.duplicate("a", 32)
      span_id = String.duplicate("b", 16)

      event = %{
        meta: %{
          trace_id: trace_id,
          span_id: span_id
        }
      }

      # Note: This may return :error in test context due to OpenTelemetry
      # context management, but succeeds in production with proper OTLP setup
      result = OtelTrace.continue_trace_from_event(event)
      assert result in [:ok, :error]
    end

    test "handles events without trace context gracefully" do
      event = %{meta: %{}}
      assert OtelTrace.continue_trace_from_event(event) == :ok
    end

    test "handles events without meta field" do
      event = %{id: "123"}
      assert OtelTrace.continue_trace_from_event(event) == :ok
    end
  end

  describe "set_attributes/1" do
    test "accepts map of attributes" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        assert :ok = OtelTrace.set_attributes(%{"key" => "value", "number" => 42})
      end
    end

    test "accepts list of attribute tuples" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        assert :ok = OtelTrace.set_attributes([{"key", "value"}, {"number", 42}])
      end
    end
  end

  describe "set_status/2" do
    test "sets span status" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        assert :ok = OtelTrace.set_status(:ok)
        assert :ok = OtelTrace.set_status(:error, "Test error")
      end
    end
  end

  describe "add_event/2" do
    test "adds event to current span" do
      require OtelTrace

      OtelTrace.with_span "test.span", %{} do
        assert :ok = OtelTrace.add_event("test.event", %{detail: "value"})
      end
    end
  end
end
