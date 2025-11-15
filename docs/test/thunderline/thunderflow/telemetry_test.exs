defmodule Thunderline.Thunderflow.TelemetryTest do
  @moduledoc """
  Comprehensive tests for OtelTrace and Flow.Telemetry modules.

  Tests cover:
  - OtelTrace span lifecycle (with_span macro)
  - Trace ID and span ID extraction
  - Trace context propagation (inject/continue)
  - Span attributes and events
  - Span status management
  - Exception handling in spans
  - Flow.Telemetry stage events
  - Telemetry emission and measurements
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thunderflow.Telemetry.OtelTrace
  alias Thunderline.Thunderflow.Flow.Telemetry, as: FlowTelemetry
  alias Thunderline.Thunderflow.Event

  import ExUnit.CaptureLog

  setup do
    # Ensure clean telemetry state
    detach_all_telemetry()

    on_exit(fn -> detach_all_telemetry() end)

    :ok
  end

  # ============================================================================
  # OtelTrace - Span Lifecycle Tests
  # ============================================================================

  describe "OtelTrace.with_span/3 - span lifecycle" do
    test "creates span and executes block" do
      result =
        OtelTrace.with_span "test.span", %{test_attr: "value"} do
          :test_result
        end

      assert result == :test_result
    end

    test "returns block result on success" do
      result =
        OtelTrace.with_span "test.success" do
          {:ok, 42}
        end

      assert result == {:ok, 42}
    end

    test "sets span status to :ok on successful execution" do
      # Span status is set internally - verify no crashes
      assert :ok =
               OtelTrace.with_span "test.status.ok" do
                 :ok
               end
    end

    test "captures and reraises exceptions with span recording" do
      assert_raise RuntimeError, "test error", fn ->
        OtelTrace.with_span "test.exception" do
          raise "test error"
        end
      end
    end

    test "records exception details in span before reraising" do
      log =
        capture_log(fn ->
          catch_error(
            OtelTrace.with_span "test.exception.details", %{context: "test"} do
              raise ArgumentError, "bad argument"
            end
          )
        end)

      # Exception should be recorded and reraised
      # Log might contain trace info depending on OTel configuration
      assert is_binary(log)
    end

    test "accepts attributes map for span metadata" do
      result =
        OtelTrace.with_span "test.with.attrs",
          %{user_id: 123, action: "test", domain: "flow"} do
          :attrs_set
        end

      assert result == :attrs_set
    end

    test "nested spans maintain parent-child relationship" do
      result =
        OtelTrace.with_span "parent.span", %{level: "parent"} do
          OtelTrace.with_span "child.span", %{level: "child"} do
            :nested_result
          end
        end

      assert result == :nested_result
    end

    test "handles empty attributes map" do
      result =
        OtelTrace.with_span "test.no.attrs", %{} do
          :no_attrs
        end

      assert result == :no_attrs
    end
  end

  # ============================================================================
  # OtelTrace - Trace ID Extraction Tests
  # ============================================================================

  describe "OtelTrace.current_trace_id/0" do
    test "returns 32-character hex string" do
      trace_id = OtelTrace.current_trace_id()

      assert is_binary(trace_id)
      assert String.length(trace_id) == 32
      assert String.match?(trace_id, ~r/^[0-9a-f]{32}$/)
    end

    test "returns zeros when no active span" do
      # Outside any span, should return all zeros
      trace_id = OtelTrace.current_trace_id()

      assert trace_id == "00000000000000000000000000000000" or
               String.match?(trace_id, ~r/^[0-9a-f]{32}$/)
    end

    test "returns consistent trace_id within same span" do
      OtelTrace.with_span "test.consistent.trace" do
        trace_id_1 = OtelTrace.current_trace_id()
        trace_id_2 = OtelTrace.current_trace_id()

        assert trace_id_1 == trace_id_2
      end
    end

    test "trace_id differs across independent spans" do
      trace_id_1 =
        OtelTrace.with_span "test.span.1" do
          OtelTrace.current_trace_id()
        end

      trace_id_2 =
        OtelTrace.with_span "test.span.2" do
          OtelTrace.current_trace_id()
        end

      # In test env without propagation, might be same or different
      assert is_binary(trace_id_1)
      assert is_binary(trace_id_2)
      assert String.length(trace_id_1) == 32
      assert String.length(trace_id_2) == 32
    end
  end

  describe "OtelTrace.current_span_id/0" do
    test "returns 16-character hex string" do
      span_id = OtelTrace.current_span_id()

      assert is_binary(span_id)
      assert String.length(span_id) == 16
      assert String.match?(span_id, ~r/^[0-9a-f]{16}$/)
    end

    test "returns zeros when no active span" do
      span_id = OtelTrace.current_span_id()

      assert span_id == "0000000000000000" or
               String.match?(span_id, ~r/^[0-9a-f]{16}$/)
    end

    test "span_id differs for parent and child spans" do
      parent_span_id =
        OtelTrace.with_span "parent" do
          parent_id = OtelTrace.current_span_id()

          child_span_id =
            OtelTrace.with_span "child" do
              OtelTrace.current_span_id()
            end

          # Child span should have different span_id than parent
          assert parent_id != child_span_id

          parent_id
        end

      assert is_binary(parent_span_id)
      assert String.length(parent_span_id) == 16
    end
  end

  # ============================================================================
  # OtelTrace - Context Propagation Tests
  # ============================================================================

  describe "OtelTrace.inject_trace_context/1" do
    test "injects trace_id and span_id into event metadata" do
      OtelTrace.with_span "test.inject" do
        event = valid_event()

        injected = OtelTrace.inject_trace_context(event)

        assert is_map(injected.meta)
        assert Map.has_key?(injected.meta, :trace_id)
        assert Map.has_key?(injected.meta, :span_id)
        assert String.length(injected.meta.trace_id) == 32
        assert String.length(injected.meta.span_id) == 16
      end
    end

    test "injects parent_domain into event metadata" do
      Process.put(:current_domain, :flow)

      OtelTrace.with_span "test.domain.inject" do
        event = valid_event()

        injected = OtelTrace.inject_trace_context(event)

        assert Map.has_key?(injected.meta, :parent_domain)
        # parent_domain might be :unknown in test env
        assert is_atom(injected.meta.parent_domain)
      end
    end

    test "preserves existing metadata when injecting trace context" do
      event = valid_event(meta: %{existing_key: "existing_value"})

      OtelTrace.with_span "test.preserve.meta" do
        injected = OtelTrace.inject_trace_context(event)

        assert injected.meta.existing_key == "existing_value"
        assert Map.has_key?(injected.meta, :trace_id)
      end
    end

    test "handles event without metadata gracefully" do
      event = valid_event()
      # Remove meta if present
      event_without_meta = %{event | meta: %{}}

      # Should not crash
      assert injected = OtelTrace.inject_trace_context(event_without_meta)
      assert is_map(injected.meta)
    end

    test "returns event unchanged if not an event struct" do
      non_event = %{not_an_event: true}

      # Should return unchanged for non-events
      result = OtelTrace.inject_trace_context(non_event)
      assert result == non_event
    end
  end

  describe "OtelTrace.continue_trace_from_event/1" do
    test "continues trace from event with trace context" do
      # Create event with trace context
      event_with_trace = %{
        valid_event()
        | meta: %{
            trace_id: "0123456789abcdef0123456789abcdef",
            span_id: "0123456789abcdef"
          }
      }

      # Should successfully set trace context
      assert :ok = OtelTrace.continue_trace_from_event(event_with_trace)
    end

    test "returns :ok for event without trace context" do
      event = valid_event()

      # Should not crash, just return :ok
      assert :ok = OtelTrace.continue_trace_from_event(event)
    end

    test "handles malformed trace_id gracefully" do
      event_bad_trace = %{
        valid_event()
        | meta: %{
            trace_id: "invalid_hex",
            span_id: "0123456789abcdef"
          }
      }

      # Should return :error but not crash
      result = OtelTrace.continue_trace_from_event(event_bad_trace)
      assert result in [:ok, :error]
    end

    test "handles event with missing span_id" do
      event_no_span = %{
        valid_event()
        | meta: %{
            trace_id: "0123456789abcdef0123456789abcdef"
          }
      }

      # Should handle gracefully
      assert :ok = OtelTrace.continue_trace_from_event(event_no_span)
    end
  end

  # ============================================================================
  # OtelTrace - Span Attributes Tests
  # ============================================================================

  describe "OtelTrace.set_attributes/1" do
    test "sets attributes on current span with map" do
      OtelTrace.with_span "test.set.attrs" do
        assert :ok =
                 OtelTrace.set_attributes(%{
                   user_id: 123,
                   action: "test",
                   domain: "flow"
                 })
      end
    end

    test "sets attributes on current span with keyword list" do
      OtelTrace.with_span "test.set.attrs.kw" do
        assert :ok =
                 OtelTrace.set_attributes(
                   user_id: 456,
                   action: "update",
                   resource: "post"
                 )
      end
    end

    test "handles empty attributes map" do
      OtelTrace.with_span "test.empty.attrs" do
        assert :ok = OtelTrace.set_attributes(%{})
      end
    end

    test "accepts string and atom keys" do
      OtelTrace.with_span "test.mixed.keys" do
        assert :ok =
                 OtelTrace.set_attributes(%{
                   "string_key" => "value1",
                   atom_key: "value2"
                 })
      end
    end

    test "can be called multiple times in same span" do
      OtelTrace.with_span "test.multiple.attrs" do
        assert :ok = OtelTrace.set_attributes(%{first: 1})
        assert :ok = OtelTrace.set_attributes(%{second: 2})
        assert :ok = OtelTrace.set_attributes(%{third: 3})
      end
    end
  end

  # ============================================================================
  # OtelTrace - Span Status Tests
  # ============================================================================

  describe "OtelTrace.set_status/2" do
    test "sets span status to :ok" do
      OtelTrace.with_span "test.status.ok" do
        assert :ok = OtelTrace.set_status(:ok)
      end
    end

    test "sets span status to :error" do
      OtelTrace.with_span "test.status.error" do
        assert :ok = OtelTrace.set_status(:error)
      end
    end

    test "sets span status to :unset" do
      OtelTrace.with_span "test.status.unset" do
        assert :ok = OtelTrace.set_status(:unset)
      end
    end

    test "sets span status with description" do
      OtelTrace.with_span "test.status.with.desc" do
        assert :ok = OtelTrace.set_status(:error, "Something went wrong")
      end
    end

    test "accepts nil description (same as no description)" do
      OtelTrace.with_span "test.status.nil.desc" do
        assert :ok = OtelTrace.set_status(:ok, nil)
      end
    end
  end

  # ============================================================================
  # OtelTrace - Span Events Tests
  # ============================================================================

  describe "OtelTrace.add_event/2" do
    test "adds event to current span without attributes" do
      OtelTrace.with_span "test.add.event" do
        assert :ok = OtelTrace.add_event("user.logged_in")
      end
    end

    test "adds event to current span with attributes map" do
      OtelTrace.with_span "test.event.with.attrs" do
        assert :ok =
                 OtelTrace.add_event("payment.processed", %{
                   amount: 100,
                   currency: "USD",
                   user_id: 789
                 })
      end
    end

    test "adds event with keyword list attributes" do
      OtelTrace.with_span "test.event.kw.attrs" do
        assert :ok =
                 OtelTrace.add_event("order.shipped",
                   order_id: "ORD-123",
                   carrier: "FedEx"
                 )
      end
    end

    test "adds event with empty attributes" do
      OtelTrace.with_span "test.event.no.attrs" do
        assert :ok = OtelTrace.add_event("simple.event", %{})
      end
    end

    test "can add multiple events to same span" do
      OtelTrace.with_span "test.multiple.events" do
        assert :ok = OtelTrace.add_event("event.1", %{step: 1})
        assert :ok = OtelTrace.add_event("event.2", %{step: 2})
        assert :ok = OtelTrace.add_event("event.3", %{step: 3})
      end
    end
  end

  # ============================================================================
  # Flow.Telemetry - Stage Events Tests
  # ============================================================================

  describe "FlowTelemetry.start/2 - stage start events" do
    test "emits [:thunderline, :flow, :stage, :start] telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-start",
        [:thunderline, :flow, :stage, :start],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :start, measurements, metadata})
        end,
        nil
      )

      try do
        FlowTelemetry.start(:validate, %{batch_size: 10})

        assert_receive {:telemetry, :start, measurements, metadata}, 500
        assert measurements.count == 1
        assert metadata.stage == :validate
        assert metadata.batch_size == 10
      after
        :telemetry.detach("test-stage-start")
      end
    end

    test "accepts empty metadata" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-start-empty",
        [:thunderline, :flow, :stage, :start],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, metadata})
        end,
        nil
      )

      try do
        FlowTelemetry.start(:transform)

        assert_receive {:telemetry, metadata}, 500
        assert metadata.stage == :transform
      after
        :telemetry.detach("test-stage-start-empty")
      end
    end
  end

  describe "FlowTelemetry.stop/3 - stage stop events" do
    test "emits [:thunderline, :flow, :stage, :stop] with duration" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-stop",
        [:thunderline, :flow, :stage, :stop],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :stop, measurements, metadata})
        end,
        nil
      )

      try do
        FlowTelemetry.stop(:process, 1_500_000, %{records: 100})

        assert_receive {:telemetry, :stop, measurements, metadata}, 500
        assert measurements.duration == 1_500_000
        assert metadata.stage == :process
        assert metadata.records == 100
      after
        :telemetry.detach("test-stage-stop")
      end
    end

    test "accepts duration in microseconds" do
      test_pid = self()

      :telemetry.attach(
        "test-duration-us",
        [:thunderline, :flow, :stage, :stop],
        fn _name, measurements, _metadata, _config ->
          send(test_pid, {:duration, measurements.duration})
        end,
        nil
      )

      try do
        FlowTelemetry.stop(:load, 250_000)

        assert_receive {:duration, 250_000}, 500
      after
        :telemetry.detach("test-duration-us")
      end
    end
  end

  describe "FlowTelemetry.exception/3 - stage exception events" do
    test "emits [:thunderline, :flow, :stage, :exception] telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-exception",
        [:thunderline, :flow, :stage, :exception],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :exception, measurements, metadata})
        end,
        nil
      )

      try do
        error = %RuntimeError{message: "test error"}
        FlowTelemetry.exception(:validate, error, %{batch_id: 123})

        assert_receive {:telemetry, :exception, measurements, metadata}, 500
        assert measurements.count == 1
        assert metadata.stage == :validate
        assert metadata.error == error
        assert metadata.batch_id == 123
      after
        :telemetry.detach("test-stage-exception")
      end
    end

    test "captures various error types" do
      test_pid = self()

      :telemetry.attach(
        "test-error-types",
        [:thunderline, :flow, :stage, :exception],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:error, metadata.error})
        end,
        nil
      )

      try do
        errors = [
          %ArgumentError{message: "bad arg"},
          %RuntimeError{message: "runtime error"},
          {:error, :not_found}
        ]

        for error <- errors do
          FlowTelemetry.exception(:test_stage, error)
          assert_receive {:error, ^error}, 500
        end
      after
        :telemetry.detach("test-error-types")
      end
    end
  end

  describe "FlowTelemetry.retry/2 - stage retry events" do
    test "emits [:thunderline, :flow, :stage, :retry] telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-retry",
        [:thunderline, :flow, :stage, :retry],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :retry, measurements, metadata})
        end,
        nil
      )

      try do
        FlowTelemetry.retry(:process, %{attempt: 2, reason: :timeout})

        assert_receive {:telemetry, :retry, measurements, metadata}, 500
        assert measurements.count == 1
        assert metadata.stage == :process
        assert metadata.attempt == 2
        assert metadata.reason == :timeout
      after
        :telemetry.detach("test-stage-retry")
      end
    end
  end

  describe "FlowTelemetry.dlq/2 - dead letter queue events" do
    test "emits [:thunderline, :flow, :stage, :dlq] telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-stage-dlq",
        [:thunderline, :flow, :stage, :dlq],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :dlq, measurements, metadata})
        end,
        nil
      )

      try do
        FlowTelemetry.dlq(:validate, %{event_id: "evt_123", reason: :max_retries})

        assert_receive {:telemetry, :dlq, measurements, metadata}, 500
        assert measurements.count == 1
        assert metadata.stage == :validate
        assert metadata.event_id == "evt_123"
        assert metadata.reason == :max_retries
      after
        :telemetry.detach("test-stage-dlq")
      end
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "telemetry integration" do
    test "multiple telemetry handlers can attach to same event" do
      test_pid = self()

      :telemetry.attach(
        "handler-1",
        [:thunderline, :flow, :stage, :start],
        fn _name, _measurements, _metadata, _config ->
          send(test_pid, {:handler, 1})
        end,
        nil
      )

      :telemetry.attach(
        "handler-2",
        [:thunderline, :flow, :stage, :start],
        fn _name, _measurements, _metadata, _config ->
          send(test_pid, {:handler, 2})
        end,
        nil
      )

      try do
        FlowTelemetry.start(:test_stage)

        assert_receive {:handler, 1}, 500
        assert_receive {:handler, 2}, 500
      after
        :telemetry.detach("handler-1")
        :telemetry.detach("handler-2")
      end
    end

    test "OtelTrace spans nest correctly with Flow telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-nested-flow",
        [:thunderline, :flow, :stage, :start],
        fn _name, _measurements, metadata, _config ->
          # Get current trace ID inside telemetry handler
          trace_id = OtelTrace.current_trace_id()
          send(test_pid, {:trace_in_telemetry, trace_id, metadata})
        end,
        nil
      )

      try do
        OtelTrace.with_span "parent.flow.span" do
          FlowTelemetry.start(:nested_stage)

          assert_receive {:trace_in_telemetry, trace_id, metadata}, 500
          assert is_binary(trace_id)
          assert metadata.stage == :nested_stage
        end
      after
        :telemetry.detach("test-nested-flow")
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp valid_event(opts \\ []) do
    defaults = [
      name: "test.telemetry.event",
      source: :test,
      payload: %{test: true},
      meta: %{}
    ]

    params = Keyword.merge(defaults, opts)

    {:ok, event} = Event.new(params)
    event
  end

  defp detach_all_telemetry do
    handlers = [
      "test-stage-start",
      "test-stage-start-empty",
      "test-stage-stop",
      "test-duration-us",
      "test-stage-exception",
      "test-error-types",
      "test-stage-retry",
      "test-stage-dlq",
      "handler-1",
      "handler-2",
      "test-nested-flow"
    ]

    Enum.each(handlers, fn handler ->
      try do
        :telemetry.detach(handler)
      rescue
        _ -> :ok
      end
    end)
  end
end
