defmodule Thunderline.CA.RuleParserTest do
  use ExUnit.Case, async: true
  alias Thunderline.Thunderbolt.CA.RuleParser

  describe "parse/1" do
    test "parses classic Conway rule with extras" do
      {:ok, rule} = RuleParser.parse("B3/S23 rate=15Hz seed=glider zone=A2")
      assert rule.born == [3]
      assert rule.survive == [2, 3]
      assert rule.rate_hz == 15
      assert rule.seed == "glider"
      assert rule.zone == "A2"
    end

    test "defaults rate when absent" do
      {:ok, rule} = RuleParser.parse("B36/S23")
      assert rule.rate_hz == 30
    end

    test "error on malformed" do
      assert {:error, %{message: _}} = RuleParser.parse("bad stuff")
    end
  end
end
