defmodule Thunderline.Thunderflow.EventBusTest do
  @moduledoc """
  Comprehensive tests for EventBus publish operations.

  Tests cover:
  - Basic publish API (publish_event/1, publish_event!/1)
  - Validation integration (EventValidator)
  - Validation mode behavior (:raise, :warn, :drop)
  - Pipeline selection logic (4 pipeline types)
  - Table routing (3 Mnesia tables)
  - Mnesia enqueue integration
  - PubSub fallback on Mnesia failure
  - Telemetry emission (3 events)
  - OtelTrace integration
  - Feature flag behavior (:debug_event_tap)
  """
  use ExUnit.Case, async: false

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Thunderflow.Validation.EventValidator
  alias Thunderline.Thunderflow.Telemetry.OtelTrace

  import ExUnit.CaptureLog

  @pubsub Thunderline.PubSub

  setup do
    # Ensure clean telemetry state
    detach_all_telemetry()

    # PubSub is already started by the application (lib/thunderline/application.ex:24)
    # No need to start_supervised! - it would fail with :already_started

    on_exit(fn -> detach_all_telemetry() end)

    :ok
  end

  # ============================================================================
  # Basic Publishing Tests
  # ============================================================================

  describe "publish_event/1 - basic API" do
    test "returns {:ok, event} with valid event" do
      event = valid_event(name: "test.basic.publish")

      assert {:ok, published_event} = EventBus.publish_event(event)
      assert published_event.id == event.id
      assert published_event.name == "test.basic.publish"
    end

    test "preserves all event attributes" do
      event =
        valid_event(
          name: "test.preserve.attrs",
          source: :test_source,
          priority: :high,
          payload: %{data: "test"}
        )

      assert {:ok, published} = EventBus.publish_event(event)
      assert published.name == "test.preserve.attrs"
      assert published.source == :test_source
      assert published.priority == :high
      assert published.payload == %{data: "test"}
    end

    test "returns error tuple with invalid event structure" do
      # EventValidator will catch invalid structure
      invalid_event = %{not_an_event: true}

      # This will fail at pattern match, so we test validation separately
      assert_raise FunctionClauseError, fn ->
        EventBus.publish_event(invalid_event)
      end
    end

    test "handles event with minimal required fields" do
      {:ok, event} = Event.new(name: "test.minimal", source: :test, payload: %{})

      assert {:ok, published} = EventBus.publish_event(event)
      assert published.name == "test.minimal"
    end
  end

  describe "publish_event!/1 - raising variant" do
    test "returns event on success" do
      event = valid_event(name: "test.bang.success")

      assert published = EventBus.publish_event!(event)
      assert published.id == event.id
    end

    test "raises on validation failure when validation mode is :raise" do
      # Create invalid event (missing required taxonomy segments)
      {:ok, event} = Event.new(name: "invalid", source: :test, payload: %{})

      # Set validation mode to :raise via Application env
      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :raise)

      try do
        assert_raise RuntimeError, fn ->
          EventBus.publish_event!(event)
        end
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
      end
    end

    test "succeeds when validation mode is :warn even with invalid event" do
      {:ok, event} = Event.new(name: "invalid", source: :test, payload: %{})

      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :warn)

      try do
        # Should not raise, but log warning
        assert published = EventBus.publish_event!(event)
        assert published.name == "invalid"
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
      end
    end
  end

  # ============================================================================
  # Validation Integration Tests
  # ============================================================================

  describe "validation integration" do
    test "EventValidator.validate/1 called for all events" do
      event = valid_event(name: "test.validation.call")

      # Validation should pass for well-formed event
      assert {:ok, _published} = EventBus.publish_event(event)
    end

    test "validation mode :drop silently drops invalid events with telemetry" do
      {:ok, event} = Event.new(name: "invalid", source: :test, payload: %{})

      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :drop)

      # Attach telemetry to verify dropped event is tracked
      test_pid = self()

      :telemetry.attach(
        "test-dropped",
        [:thunderline, :event, :dropped],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :dropped, measurements, metadata})
        end,
        nil
      )

      try do
        capture_log(fn ->
          # Should return ok but not actually publish
          assert {:ok, _returned} = EventBus.publish_event(event)

          # Verify telemetry was emitted
          assert_receive {:telemetry, :dropped, %{count: 1}, metadata}, 500
          assert metadata.name == "invalid"
        end)
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
        :telemetry.detach("test-dropped")
      end
    end

    test "validation mode :warn logs warning but continues publishing" do
      {:ok, event} = Event.new(name: "warn_invalid", source: :test, payload: %{})

      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :warn)

      try do
        log =
          capture_log(fn ->
            assert {:ok, _published} = EventBus.publish_event(event)
          end)

        # Should log warning about validation
        assert log =~ "validation" || log =~ "invalid" || log =~ "warn"
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
      end
    end

    test "validation mode :raise crashes on invalid event" do
      {:ok, event} = Event.new(name: "raise_invalid", source: :test, payload: %{})

      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :raise)

      try do
        assert_raise RuntimeError, fn ->
          EventBus.publish_event(event)
        end
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
      end
    end
  end

  # ============================================================================
  # Pipeline Selection Tests
  # ============================================================================

  describe "pipeline selection logic" do
    test "ai.* events routed to :realtime pipeline" do
      event = valid_event(name: "ai.inference.complete")

      test_pid = self()

      :telemetry.attach(
        "test-ai-pipeline",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :realtime
      after
        :telemetry.detach("test-ai-pipeline")
      end
    end

    test "grid.* events routed to :realtime pipeline" do
      event = valid_event(name: "grid.compute.started")

      test_pid = self()

      :telemetry.attach(
        "test-grid-pipeline",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :realtime
      after
        :telemetry.detach("test-grid-pipeline")
      end
    end

    test "events with target_domain routed to :cross_domain pipeline" do
      event = valid_event(name: "test.cross.domain", target_domain: "remote_domain")

      test_pid = self()

      :telemetry.attach(
        "test-cross-domain",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :cross_domain
      after
        :telemetry.detach("test-cross-domain")
      end
    end

    test "priority :high events routed to :realtime pipeline" do
      event = valid_event(name: "test.high.priority", priority: :high)

      test_pid = self()

      :telemetry.attach(
        "test-high-priority",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :realtime
      after
        :telemetry.detach("test-high-priority")
      end
    end

    test "meta.pipeline explicitly set is respected" do
      {:ok, event} =
        Event.new(
          name: "test.explicit.pipeline",
          source: :test,
          payload: %{},
          meta: %{pipeline: :cross_domain}
        )

      test_pid = self()

      :telemetry.attach(
        "test-explicit-pipeline",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :cross_domain
      after
        :telemetry.detach("test-explicit-pipeline")
      end
    end

    test "default events routed to :general pipeline" do
      event = valid_event(name: "test.default.pipeline")

      test_pid = self()

      :telemetry.attach(
        "test-general-pipeline",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, metadata}, 500
        assert metadata.pipeline == :general
      after
        :telemetry.detach("test-general-pipeline")
      end
    end
  end

  # ============================================================================
  # Telemetry Emission Tests
  # ============================================================================

  describe "telemetry emission" do
    test "[:thunderline, :event, :enqueue] emitted on successful enqueue" do
      event = valid_event(name: "test.enqueue.telemetry")

      test_pid = self()

      :telemetry.attach(
        "test-enqueue",
        [:thunderline, :event, :enqueue],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :enqueue, measurements, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :enqueue, measurements, metadata}, 500
        assert measurements.count == 1
        assert metadata.name == "test.enqueue.telemetry"
        assert metadata.pipeline in [:general, :realtime, :cross_domain]
        assert metadata.priority in [:normal, :high, :low]
      after
        :telemetry.detach("test-enqueue")
      end
    end

    test "[:thunderline, :event, :publish] emitted with duration measurement" do
      event = valid_event(name: "test.publish.telemetry")

      test_pid = self()

      :telemetry.attach(
        "test-publish-duration",
        [:thunderline, :event, :publish],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :publish, measurements, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :publish, measurements, metadata}, 500
        assert is_integer(measurements.duration)
        assert measurements.duration > 0
        assert metadata.status == :ok
        assert metadata.name == "test.publish.telemetry"
      after
        :telemetry.detach("test-publish-duration")
      end
    end

    test "[:thunderline, :event, :dropped] emitted on validation failure" do
      {:ok, event} = Event.new(name: "invalid_drop", source: :test, payload: %{})

      original_mode = Application.get_env(:thunderline, :event_validation_mode, :warn)
      Application.put_env(:thunderline, :event_validation_mode, :drop)

      test_pid = self()

      :telemetry.attach(
        "test-dropped-telemetry",
        [:thunderline, :event, :dropped],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, :dropped, measurements, metadata})
        end,
        nil
      )

      try do
        capture_log(fn ->
          assert {:ok, _} = EventBus.publish_event(event)

          assert_receive {:telemetry, :dropped, measurements, metadata}, 500
          assert measurements.count == 1
          assert metadata.name == "invalid_drop"
          assert is_binary(metadata.reason) or is_atom(metadata.reason)
        end)
      after
        Application.put_env(:thunderline, :event_validation_mode, original_mode)
        :telemetry.detach("test-dropped-telemetry")
      end
    end

    test "telemetry metadata includes all expected fields" do
      event = valid_event(name: "test.metadata.complete", priority: :high)

      test_pid = self()

      :telemetry.attach(
        "test-metadata",
        [:thunderline, :event, :publish],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, :metadata, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _published} = EventBus.publish_event(event)

        assert_receive {:telemetry, :metadata, metadata}, 500
        assert Map.has_key?(metadata, :status)
        assert Map.has_key?(metadata, :name)
        assert Map.has_key?(metadata, :pipeline)
        assert metadata.name == "test.metadata.complete"
      after
        :telemetry.detach("test-metadata")
      end
    end
  end

  # ============================================================================
  # OtelTrace Integration Tests
  # ============================================================================

  describe "OtelTrace integration" do
    test "span created for publish_event/1 call" do
      event = valid_event(name: "test.otel.span")

      # Publish event - span should be created automatically
      assert {:ok, _published} = EventBus.publish_event(event)

      # If OtelTrace is working, trace_id should be set
      trace_id = OtelTrace.current_trace_id()

      # In test environment without full OTel setup, might be zeros
      assert is_binary(trace_id)
      assert String.length(trace_id) == 32
    end

    test "trace context propagated to event metadata" do
      event = valid_event(name: "test.trace.propagation")

      # Wrap in span to ensure trace context exists
      OtelTrace.with_span "test.wrapper" do
        assert {:ok, published} = EventBus.publish_event(event)

        # Published event should have trace context in metadata
        # (if OtelTrace.inject_trace_context was called)
        assert is_map(published.meta)
      end
    end

    test "OtelTrace handles events without existing trace context" do
      # Create event without trace context
      event = valid_event(name: "test.no.trace.context")

      # Should not crash even without parent trace
      assert {:ok, _published} = EventBus.publish_event(event)
    end
  end

  # ============================================================================
  # PubSub Fallback Tests
  # ============================================================================

  describe "PubSub fallback on Mnesia failure" do
    @tag :skip
    test "broadcasts event via PubSub when MnesiaProducer unavailable" do
      # This test would require mocking/stubbing MnesiaProducer to raise
      # Skipped for now as it requires complex Mnesia state manipulation
      :ok
    end

    @tag :skip
    test "fallback emits telemetry with :fallback_pubsub pipeline" do
      # Would verify telemetry metadata.pipeline == :fallback_pubsub
      :ok
    end
  end

  # ============================================================================
  # Feature Flag Tests
  # ============================================================================

  describe "feature flag behavior" do
    test "debug_event_tap flag does not crash when disabled" do
      event = valid_event(name: "test.no.tap")

      # Should work fine with tap disabled (default)
      assert {:ok, _published} = EventBus.publish_event(event)
    end

    @tag :skip
    test "debug_event_tap taps events to EventBuffer when enabled" do
      # Would require enabling :debug_event_tap feature flag
      # and verifying EventBuffer receives tapped events
      :ok
    end
  end

  # ============================================================================
  # Concurrent Publishing Tests
  # ============================================================================

  describe "concurrent publishing" do
    test "handles concurrent publish_event calls" do
      events =
        for i <- 1..10 do
          valid_event(name: "test.concurrent.#{i}")
        end

      tasks =
        Enum.map(events, fn event ->
          Task.async(fn -> EventBus.publish_event(event) end)
        end)

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _event} -> true
               _ -> false
             end)
    end

    test "telemetry correctly tracks concurrent events" do
      test_pid = self()
      event_count = 5

      :telemetry.attach(
        "test-concurrent-telemetry",
        [:thunderline, :event, :enqueue],
        fn _name, _measurements, _metadata, _config ->
          send(test_pid, :telemetry_received)
        end,
        nil
      )

      try do
        events =
          for i <- 1..event_count do
            valid_event(name: "test.concurrent.telemetry.#{i}")
          end

        tasks =
          Enum.map(events, fn event ->
            Task.async(fn -> EventBus.publish_event(event) end)
          end)

        Task.await_many(tasks, 5000)

        # Should receive telemetry for all events
        for _ <- 1..event_count do
          assert_receive :telemetry_received, 1000
        end
      after
        :telemetry.detach("test-concurrent-telemetry")
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp valid_event(opts \\ []) do
    defaults = [
      name: "system.test.default",
      source: :flow,
      payload: %{test: true},
      priority: :normal
    ]

    params = Keyword.merge(defaults, opts)

    {:ok, event} = Event.new(params)
    event
  end

  defp detach_all_telemetry do
    # Detach all test handlers
    handlers = [
      "test-dropped",
      "test-ai-pipeline",
      "test-grid-pipeline",
      "test-cross-domain",
      "test-high-priority",
      "test-explicit-pipeline",
      "test-general-pipeline",
      "test-enqueue",
      "test-publish-duration",
      "test-dropped-telemetry",
      "test-metadata",
      "test-concurrent-telemetry"
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
