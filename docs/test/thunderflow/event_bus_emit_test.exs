defmodule Thunderflow.EventBusEmitTest do
  use ExUnit.Case, async: true

  alias Thunderline.{Event, EventBus}

  test "publish_event returns {:ok, %Event{}}" do
    {:ok, ev} =
      Event.new(
        name: "system.flow.test",
        source: :flow,
        payload: %{ok: true}
      )

    assert {:ok, published} = EventBus.publish_event(ev)
    assert published.name == "system.flow.test"
    assert published.source == :flow
    assert published.payload == %{ok: true}
  end

  test "publish_event rejects unsupported payloads" do
    assert {:error, {:unsupported_event, %{}}} = EventBus.publish_event(%{})
  end

  test "publish_event! raises on invalid event" do
    bad_event = %Event{name: "badprefix.x", source: :flow, payload: %{}}

    assert_raise ArgumentError, ~r/Invalid event/, fn -> EventBus.publish_event!(bad_event) end
  end
end
