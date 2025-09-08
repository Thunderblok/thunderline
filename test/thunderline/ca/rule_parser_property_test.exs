defmodule Thunderline.CA.RuleParserPropertyTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.RuleParser

  test "digits are within 0..8 and unique within born/survive sets" do
    for _ <- 1..50 do
      digits = Enum.shuffle(0..8) |> Enum.take(Enum.random(1..5)) |> Enum.join()
      digits2 = Enum.shuffle(0..8) |> Enum.take(Enum.random(1..5)) |> Enum.join()
      line = "B#{digits}/S#{digits2}"
      {:ok, rule} = RuleParser.parse(line)
      assert Enum.all?(rule.born, &(&1 in 0..8))
      assert Enum.all?(rule.survive, &(&1 in 0..8))
      assert length(rule.born) == rule.born |> Enum.uniq() |> length()
      assert length(rule.survive) == rule.survive |> Enum.uniq() |> length()
    end
  end
end
