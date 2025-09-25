defmodule Thunderline.Thunderflow.EventValidatorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventValidator

  test "valid reserved prefix passes" do
    {:ok, ev} = Event.new(%{name: "system.test.ok", source: :flow, payload: %{}})
    assert :ok == EventValidator.validate(ev)
  end

  test "bad prefix fails and emits telemetry" do
    {:ok, ev} = Event.new(%{name: "badprefix.x", source: :flow, payload: %{}})
    parent = self()
    :telemetry.attach(self(), [:thunderline, :event, :validated], fn _event, _m, meta, _cfg ->
      send(parent, {:validated, meta})
    end, nil)

    assert {:error, :reserved_violation} = EventValidator.validate(ev)
    assert_receive {:validated, %{status: :error, name: "badprefix.x"}}, 100

    :telemetry.detach(self())
  end
end
