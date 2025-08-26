defmodule Thunderflow.EventBusEmitTest do
  use ExUnit.Case, async: true

  alias Thunderline.{Event, EventBus}

  test "emit returns {:ok, %Event{}} and preserves core fields" do
    {:ok, ev} = EventBus.emit(:ping, %{ok: true, domain: "thunderflow"})
    assert %Event{} = ev
    assert ev.type == :ping
    assert ev.source in [:flow, :unknown] # domain mapping may normalize
  end

  test "emit_batch constructs canonical events" do
    {:ok, events} = EventBus.emit_batch([{:alpha, %{domain: "thunderflow"}}, {:beta, %{domain: "thunderflow"}}])
    assert length(events) == 2
    assert Enum.all?(events, &match?(%Event{}, &1))
  end
end
