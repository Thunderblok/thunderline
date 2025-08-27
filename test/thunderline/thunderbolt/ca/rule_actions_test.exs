defmodule Thunderline.Thunderbolt.CA.RuleActionsTest do
  use ExUnit.Case, async: true

  test "parse_rule action happy path" do
    changeset = Thunderline.Thunderbolt.CA.RuleActions |> Ash.Changeset.for_action(:parse_rule, %{line: "B3/S23 rate=10Hz"})
    assert {:ok, result} = Ash.run_action(changeset)
    assert result.born == [3]
    assert result.survive == [2,3]
    assert result.rate_hz == 10
  end

  test "parse_rule action error" do
    changeset = Thunderline.Thunderbolt.CA.RuleActions |> Ash.Changeset.for_action(:parse_rule, %{line: "notarule"})
    assert {:error, _} = Ash.run_action(changeset)
  end
end
