defmodule Thunderline.Thunderbolt.CA.RuleActionsTest do
  use ExUnit.Case, async: true

  test "parse_rule action happy path" do
    input =
      Ash.ActionInput.for_action(Thunderline.Thunderbolt.CA.RuleActions, :parse_rule, %{
        line: "B3/S23 rate=10Hz"
      })

    assert {:ok, result} = Ash.run_action(input)
    assert Map.get(result, :born) == [3]
    assert Map.get(result, :survive) == [2, 3]
    assert Map.get(result, :rate_hz) == 10
  end

  test "parse_rule action error" do
    input =
      Ash.ActionInput.for_action(Thunderline.Thunderbolt.CA.RuleActions, :parse_rule, %{
        line: "notarule"
      })

    assert {:error, _} = Ash.run_action(input)
  end
end
