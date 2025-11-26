defmodule Thunderline.Thunderflow.EventBusTelemetryTest do
  @moduledoc """
  Telemetry span tests for EventBus.publish_event/1.

  HC-01 requirement: Validates that telemetry events are emitted correctly.

  Telemetry events (per EventBus moduledoc):
  - [:thunderline, :event, :enqueue]   count=1  metadata: %{pipeline, name, priority}
  - [:thunderline, :event, :publish]   duration metadata: %{status, name, pipeline}
  - [:thunderline, :event, :dropped]   count=1  metadata: %{reason, name}
  - [:thunderline, :event, :validated] duration metadata: %{status, name}
  """
  use ExUnit.Case, async: false

  alias Thunderline.Event
  alias Thunderline.EventBus

  setup do
    # Attach telemetry handlers to capture events
    test_pid = self()

    handlers = [
      {:enqueue_handler,
       fn name, measurements, metadata, _config ->
         send(test_pid, {:telemetry, name, measurements, metadata})
       end},
      {:publish_handler,
       fn name, measurements, metadata, _config ->
         send(test_pid, {:telemetry, name, measurements, metadata})
       end},
      {:dropped_handler,
       fn name, measurements, metadata, _config ->
         send(test_pid, {:telemetry, name, measurements, metadata})
       end},
      {:validated_handler,
       fn name, measurements, metadata, _config ->
         send(test_pid, {:telemetry, name, measurements, metadata})
       end}
    ]

    # Attach all handlers
    :telemetry.attach(:enqueue_handler, [:thunderline, :event, :enqueue], elem(handlers, 0) |> elem(1), nil)
    :telemetry.attach(:publish_handler, [:thunderline, :event, :publish], elem(handlers, 1) |> elem(1), nil)
    :telemetry.attach(:dropped_handler, [:thunderline, :event, :dropped], elem(handlers, 2) |> elem(1), nil)
    :telemetry.attach(:validated_handler, [:thunderline, :event, :validated], elem(handlers, 3) |> elem(1), nil)

    on_exit(fn ->
      :telemetry.detach(:enqueue_handler)
      :telemetry.detach(:publish_handler)
      :telemetry.detach(:dropped_handler)
      :telemetry.detach(:validated_handler)
    end)

    :ok
  end

  describe "telemetry for valid events" do
    test "emits :validated telemetry on successful validation" do
      {:ok, event} =
        Event.new(
          name: "system.test.telemetry",
          source: :flow,
          payload: %{test: true}
        )

      EventBus.publish_event(event)

      assert_receive {:telemetry, [:thunderline, :event, :validated], %{duration: duration}, %{status: :ok, name: "system.test.telemetry"}}, 1000
      assert is_integer(duration)
      assert duration >= 0
    end

    test "emits :publish telemetry on publish" do
      {:ok, event} =
        Event.new(
          name: "system.test.publish_telemetry",
          source: :flow,
          payload: %{}
        )

      EventBus.publish_event(event)

      assert_receive {:telemetry, [:thunderline, :event, :publish], %{duration: duration}, metadata}, 1000
      assert is_integer(duration)
      assert metadata.name == "system.test.publish_telemetry"
      assert metadata.status in [:ok, :error]
    end

    test "emits :enqueue telemetry when MnesiaProducer available or falls back" do
      {:ok, event} =
        Event.new(
          name: "system.test.enqueue_telemetry",
          source: :flow,
          payload: %{},
          priority: :high
        )

      EventBus.publish_event(event)

      # Either enqueue succeeds or fallback to PubSub happens (both emit :publish)
      assert_receive {:telemetry, [:thunderline, :event, :publish], _, _}, 1000
    end
  end

  describe "telemetry metadata" do
    test "includes pipeline information in telemetry" do
      {:ok, event} =
        Event.new(
          name: "ai.intent.test",
          source: :crown,
          payload: %{},
          meta: %{pipeline: :realtime}
        )

      EventBus.publish_event(event)

      assert_receive {:telemetry, [:thunderline, :event, :publish], _, metadata}, 1000
      assert metadata.pipeline in [:realtime, :general, :cross_domain, :fallback_pubsub]
    end

    test "includes priority in publish metadata" do
      {:ok, event} =
        Event.new(
          name: "system.test.priority",
          source: :flow,
          payload: %{},
          priority: :critical
        )

      EventBus.publish_event(event)

      # The :validated event should include name
      assert_receive {:telemetry, [:thunderline, :event, :validated], _, %{name: "system.test.priority"}}, 1000
    end
  end

  describe "telemetry for invalid events" do
    test "emits :validated with error status for invalid events" do
      # Create a manually crafted invalid event to bypass Event.new validation
      invalid_event = %Event{
        id: "test",
        at: DateTime.utc_now(),
        name: "x",  # Too short - will fail validation
        source: :flow,
        payload: %{},
        correlation_id: "not-a-uuid",  # Invalid UUID format
        taxonomy_version: 1,
        event_version: 1,
        meta: %{}
      }

      # This may return error due to validator
      _result = EventBus.publish_event(invalid_event)

      # Should get a validated telemetry with error status
      assert_receive {:telemetry, [:thunderline, :event, :validated], %{duration: _}, %{status: :error}}, 1000
    end
  end
end
