defmodule Thunderline.Thunderflow.EventValidatorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventValidator

  test "valid reserved prefix passes" do
    {:ok, ev} = Event.new(%{name: "system.test.ok", source: :flow, payload: %{}})
    assert :ok == EventValidator.validate(ev)
  end

  test "bad prefix fails during construction" do
    assert {:error, [forbidden_category: {:flow, "badprefix.x"}]} =
             Event.new(%{name: "badprefix.x", source: :flow, payload: %{}})
  end
end
