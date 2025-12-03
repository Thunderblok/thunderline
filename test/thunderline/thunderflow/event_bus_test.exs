defmodule Thunderline.Thunderflow.EventBusTest do
  @moduledoc """
  Tests for the unified EventBus.publish_event/1 helper.

  HC-01 requirement: Validates that:
  - publish_event/1 validates event structure
  - publish_event/1 emits telemetry spans
  - publish_event/1 returns {:ok, event} | {:error, reason}
  - publish_event!/1 raises on invalid events
  """
  use ExUnit.Case, async: true

  alias Thunderline.Event
  alias Thunderline.EventBus
  alias Thunderline.Thunderflow.EventBus, as: FlowEventBus

  describe "publish_event/1 with valid event" do
    test "returns {:ok, event} for valid Event struct" do
      {:ok, event} =
        Event.new(
          name: "system.test.published",
          source: :flow,
          payload: %{test: true},
          priority: :normal
        )

      # Without a running MnesiaProducer, it should fallback to PubSub
      result = EventBus.publish_event(event)

      assert {:ok, %Event{}} = result
    end

    test "preserves event fields through publish" do
      {:ok, event} =
        Event.new(
          name: "system.test.preserved",
          source: :bolt,
          payload: %{value: 42},
          priority: :high
        )

      {:ok, published} = EventBus.publish_event(event)

      assert published.name == "system.test.preserved"
      assert published.source == :bolt
      assert published.payload == %{value: 42}
      assert published.priority == :high
    end

    test "FlowEventBus is the canonical implementation" do
      {:ok, event} =
        Event.new(
          name: "system.test.flow",
          source: :flow,
          payload: %{}
        )

      # Both should work identically
      result1 = EventBus.publish_event(event)
      result2 = FlowEventBus.publish_event(event)

      assert {:ok, _} = result1
      assert {:ok, _} = result2
    end
  end

  describe "publish_event/1 with invalid input" do
    test "returns {:error, :event_creation_failed} for non-Event struct map" do
      # Maps are attempted to be converted via Event.new/1 for backwards compatibility
      result = EventBus.publish_event(%{not: "an event"})
      assert {:error, {:event_creation_failed, _reasons}} = result
    end

    test "returns {:error, :event_creation_failed} for incomplete map" do
      # Missing required :source field causes Event.new/1 to fail validation
      result = EventBus.publish_event(%{name: "test", payload: %{}})
      assert {:error, {:event_creation_failed, _reasons}} = result
    end

    test "returns {:error, :unsupported_event} for nil" do
      result = EventBus.publish_event(nil)
      assert {:error, {:unsupported_event, nil}} = result
    end
  end

  describe "publish_event!/1" do
    test "returns event for valid input" do
      {:ok, event} =
        Event.new(
          name: "system.test.bang",
          source: :flow,
          payload: %{}
        )

      result = EventBus.publish_event!(event)
      assert %Event{name: "system.test.bang"} = result
    end

    test "raises for invalid input" do
      assert_raise RuntimeError, ~r/invalid_event/, fn ->
        EventBus.publish_event!(%{not: "an event"})
      end
    end
  end

  describe "Event.new/1 validation" do
    test "requires name with at least 2 segments" do
      assert {:error, errors} = Event.new(name: "single", source: :flow, payload: %{})
      assert Enum.any?(errors, fn err -> match?({:invalid_format, _}, err) end)
    end

    test "requires valid source domain" do
      assert {:error, errors} = Event.new(name: "system.test", source: "not_atom", payload: %{})
      assert Enum.any?(errors, fn err -> match?({:invalid, :source}, err) end)
    end

    test "requires payload to be a map" do
      assert {:error, errors} = Event.new(name: "system.test", source: :flow, payload: "string")
      assert Enum.any?(errors, fn err -> match?({:invalid, :payload}, err) end)
    end

    test "generates correlation_id if not provided" do
      {:ok, event} = Event.new(name: "system.test.corr", source: :flow, payload: %{})
      assert is_binary(event.correlation_id)
      assert String.length(event.correlation_id) > 10
    end

    test "uses provided correlation_id" do
      corr_id = "test-correlation-id-12345"

      {:ok, event} =
        Event.new(
          name: "system.test.corr",
          source: :flow,
          payload: %{},
          correlation_id: corr_id
        )

      assert event.correlation_id == corr_id
    end
  end
end
