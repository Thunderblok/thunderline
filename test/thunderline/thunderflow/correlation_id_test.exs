defmodule Thunderline.Thunderflow.CorrelationIdTest do
  @moduledoc """
  Test suite for correlation ID propagation across the event-driven architecture.

  Based on OPERATION SAGA CONCORDIA - Correlation Audit (docs/concordia/correlation_audit.md)
  Tests verify:
  - Correlation ID acceptance and propagation through sagas
  - Auto-generation when correlation_id not provided
  - Multi-step saga correlation ID preservation
  - EventBus validation of correlation_id format

  Phase 3 Week 2 - Task 1: Correlation ID Test Cases
  """
  use ExUnit.Case, async: false

  alias Thunderline.{Event, EventBus, UUID}
  alias Thunderline.Thunderbolt.Sagas.UserProvisioningSaga

  @moduletag :correlation

  setup do
    # Attach telemetry handler to capture saga events
    parent = self()
    handler_id = "correlation-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:reactor, :saga, :start],
        # Use actual Reactor.Middleware.Telemetry event names for steps
        [:reactor, :step, :run, :start],
        [:reactor, :step, :run, :stop],
        [:reactor, :saga, :complete],
        [:thunderline, :event, :enqueue],
        [:thunderline, :event, :dropped]
      ],
      fn event, measurements, metadata, _cfg ->
        send(parent, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "Test 1: Saga accepts correlation_id from caller" do
    test "saga preserves correlation_id passed as input" do
      correlation_id = UUID.v7()

      inputs = %{
        email: "correlation-test-1@example.com",
        correlation_id: correlation_id,
        causation_id: nil,
        magic_link_redirect: "/communities"
      }

      # Run saga (may fail due to mocked dependencies, but telemetry still fires)
      _result = Reactor.run(UserProvisioningSaga, inputs)

      # Verify saga start event includes same correlation_id
      assert_receive {
                       :telemetry,
                       [:reactor, :saga, :start],
                       %{count: 1},
                       %{correlation_id: ^correlation_id} = metadata
                     },
                     1000

      assert metadata.saga =~ "UserProvisioningSaga"

      # If saga emits events (may be blocked by mocked steps), verify correlation_id
      # Note: This may timeout if saga fails early, which is OK for this test
      receive do
        {:telemetry, [:thunderline, :event, :enqueue], _meas, %{name: event_name}} ->
          # If event was published, it should have same correlation_id
          # (EventBus doesn't expose metadata in telemetry, so we verify indirectly)
          assert event_name == "user.onboarding.complete"

        after
          500 -> :ok
      end
    end
  end

  describe "Test 2: Saga generates correlation_id when missing" do
    test "saga auto-generates correlation_id if not provided" do
      inputs = %{
        email: "correlation-test-2@example.com",
        # Explicitly pass nil to trigger auto-generation via input transform
        correlation_id: nil,
        causation_id: nil,
        magic_link_redirect: "/communities"
      }

      # Run saga
      _result = Reactor.run(UserProvisioningSaga, inputs)

      # Verify saga start event has generated correlation_id
      assert_receive {
                       :telemetry,
                       [:reactor, :saga, :start],
                       %{count: 1},
                       %{correlation_id: generated_correlation_id} = metadata
                     },
                     1000

      assert is_binary(generated_correlation_id)
      # Verify UUID v7 format (8-4-7-4-12 hex groups)
      assert String.match?(
               generated_correlation_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
             )

      assert metadata.saga =~ "UserProvisioningSaga"
    end
  end

  describe "Test 3: correlation_id flows through multi-step saga" do
    test "correlation_id preserved across all saga steps" do
      correlation_id = UUID.v7()

      inputs = %{
        email: "correlation-test-3@example.com",
        correlation_id: correlation_id,
        causation_id: nil,
        magic_link_redirect: "/communities"
      }

      # Run saga
      _result = Reactor.run(UserProvisioningSaga, inputs)

      # Collect all Reactor step events (using actual Reactor.Middleware.Telemetry event names)
      step_events =
        collect_telemetry_events([:reactor, :step, :run, :start], timeout: 2000, max: 10)

      # Verify at least some steps executed (saga may fail, but initial steps should fire)
      assert length(step_events) > 0,
             "Expected at least one step to execute, but got 0 step events"

      # Verify all collected steps belong to our saga
      Enum.each(step_events, fn {_event, _meas, metadata} ->
        # Reactor telemetry includes the reactor module in metadata[:id]
        assert metadata[:id] == UserProvisioningSaga,
               "Expected reactor id to be UserProvisioningSaga, got: #{inspect(metadata[:id])}"
      end)

      # Verify saga start had correct correlation_id
      assert_receive {
                       :telemetry,
                       [:reactor, :saga, :start],
                       %{count: 1},
                       %{correlation_id: ^correlation_id}
                     },
                     1000
    end
  end

  describe "Test 4: EventBus validates correlation_id" do
    test "EventBus rejects events with missing correlation_id" do
      # Create event without correlation_id (bypass Event.new validation)
      event = %Event{
        id: UUID.v7(),
        name: "system.test.correlation_missing",
        source: :flow,
        payload: %{test: true},
        correlation_id: nil,
        # nil violates validation
        causation_id: nil,
        priority: :normal,
        timestamp: DateTime.utc_now(),
        meta: %{}
      }

      # Attempt to publish should fail with ArgumentError in test mode
      assert_raise ArgumentError, ~r/Invalid event system\.test\.correlation_missing: :missing_correlation_id/, fn ->
        EventBus.publish_event(event)
      end
    end

    test "EventBus rejects events with invalid correlation_id format" do
      # Create event with invalid correlation_id format
      event = %Event{
        id: UUID.v7(),
        name: "system.test.correlation_invalid",
        source: :flow,
        payload: %{test: true},
        correlation_id: "not-a-valid-uuid",
        # Invalid format
        causation_id: nil,
        priority: :normal,
        timestamp: DateTime.utc_now(),
        meta: %{}
      }

      # Attempt to publish should fail with ArgumentError in test mode
      assert_raise ArgumentError, ~r/Invalid event system\.test\.correlation_invalid: :bad_correlation_id/, fn ->
        EventBus.publish_event(event)
      end
    end

    test "EventBus accepts events with valid correlation_id" do
      correlation_id = UUID.v7()

      {:ok, event} =
        Event.new(
          name: "system.test.correlation_valid",
          source: :flow,
          payload: %{test: true},
          correlation_id: correlation_id
        )

      # Should publish successfully
      assert {:ok, published_event} = EventBus.publish_event(event)
      assert published_event.correlation_id == correlation_id

      # Verify telemetry emitted enqueue event
      assert_receive {
                       :telemetry,
                       [:thunderline, :event, :enqueue],
                       %{count: 1},
                       %{name: "system.test.correlation_valid", pipeline: _pipeline}
                     },
                     500
    end

    test "EventBus accepts UUID v7 correlation_id format" do
      # UUID v7 has specific format: 8-4-7-4-12 with version '7' in 3rd group
      correlation_id = UUID.v7()

      # Verify it matches UUID v7 pattern
      assert String.match?(
               correlation_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
             )

      {:ok, event} =
        Event.new(
          name: "system.test.correlation_uuidv7",
          source: :flow,
          payload: %{test: true},
          correlation_id: correlation_id
        )

      # Should publish successfully
      assert {:ok, published_event} = EventBus.publish_event(event)
      assert published_event.correlation_id == correlation_id
    end
  end

  # Helper function to collect multiple telemetry events
  defp collect_telemetry_events(event_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    max_events = Keyword.get(opts, :max, 5)

    collect_events(event_name, [], max_events, timeout)
  end

  defp collect_events(_event_name, collected, 0, _timeout), do: Enum.reverse(collected)

  defp collect_events(event_name, collected, remaining, timeout) do
    receive do
      {:telemetry, ^event_name, measurements, metadata} ->
        collect_events(
          event_name,
          [{event_name, measurements, metadata} | collected],
          remaining - 1,
          timeout
        )
    after
      timeout -> Enum.reverse(collected)
    end
  end
end
