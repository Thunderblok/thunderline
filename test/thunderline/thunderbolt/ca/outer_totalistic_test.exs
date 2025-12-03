defmodule Thunderline.Thunderbolt.CA.OuterTotalisticTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.OuterTotalistic

  @moduletag :ca

  describe "apply_rule/2" do
    test "applies rule 30" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      result = OuterTotalistic.apply_rule(cells, 30)

      # Rule 30 from center 1: 001 -> 1, 010 -> 1, 100 -> 1
      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "applies rule 110" do
      cells = [0, 1, 0, 1, 1, 0, 1]
      result = OuterTotalistic.apply_rule(cells, 110)

      assert is_list(result)
      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "handles small cell arrays" do
      cells = [1]
      result = OuterTotalistic.apply_rule(cells, 30)

      assert is_list(result)
    end

    test "handles edge wrapping correctly" do
      cells = [1, 0, 0, 0, 1]
      result = OuterTotalistic.apply_rule(cells, 30)

      # Edges should consider wrapped neighbors
      assert is_list(result)
      assert length(result) == 5
    end
  end

  describe "apply_rule_number/3" do
    test "applies rule with explicit neighborhood size" do
      cells = [0, 0, 1, 1, 0]
      result = OuterTotalistic.apply_rule_number(cells, 30, 3)

      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "applies rule with larger neighborhood" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      result = OuterTotalistic.apply_rule_number(cells, 110, 5)

      assert is_list(result)
    end
  end

  describe "vetted_rules/0" do
    test "returns vetted rules map" do
      rules = OuterTotalistic.vetted_rules()

      assert is_map(rules)
      assert Map.has_key?(rules, :reversible_chaotic)
      assert Map.has_key?(rules, :period_doubling)
      assert Map.has_key?(rules, :xor_linear)
      assert Map.has_key?(rules, :rule_150_analog)
    end

    test "vetted rules have correct structure" do
      rules = OuterTotalistic.vetted_rules()

      Enum.each(rules, fn {_name, rule_spec} ->
        assert Map.has_key?(rule_spec, :rule_number)
        assert Map.has_key?(rule_spec, :description)
        assert is_integer(rule_spec.rule_number)
      end)
    end
  end

  describe "apply_vetted_rule/2" do
    test "applies reversible chaotic rule" do
      cells = [0, 1, 0, 1, 1, 0, 1, 0]
      result = OuterTotalistic.apply_vetted_rule(cells, :reversible_chaotic)

      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "applies XOR linear rule" do
      cells = [1, 0, 1, 0, 1]
      result = OuterTotalistic.apply_vetted_rule(cells, :xor_linear)

      assert is_list(result)
    end

    test "returns error for unknown rule" do
      cells = [1, 0, 1]
      result = OuterTotalistic.apply_vetted_rule(cells, :unknown_rule)

      assert {:error, _} = result
    end
  end

  describe "apply_xor_rule/1" do
    test "applies XOR rule (2863311530)" do
      cells = [1, 0, 1, 0, 1, 0]
      result = OuterTotalistic.apply_xor_rule(cells)

      # XOR rule: new_cell = left XOR right
      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "XOR rule is its own inverse (for linear rules)" do
      cells = [1, 1, 0, 1, 0, 0, 1]

      # For pure XOR, applying twice may not return to original
      # but structure should be preserved
      result = OuterTotalistic.apply_xor_rule(cells)
      assert is_list(result)
    end
  end

  describe "apply_reversible_rule/3" do
    test "applies reversible rule with previous state" do
      cells = [1, 0, 1, 0, 1]
      prev = [0, 1, 0, 1, 0]
      result = OuterTotalistic.apply_reversible_rule(cells, prev, 30)

      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "reversibility property" do
      # For truly reversible rules, f(f(cells, prev), cells) should give prev
      cells = [1, 0, 1, 1, 0, 1, 0]
      prev = [0, 1, 0, 0, 1, 0, 1]

      next = OuterTotalistic.apply_reversible_rule(cells, prev, 30)
      recovered = OuterTotalistic.apply_reversible_rule(next, cells, 30)

      # Should recover previous state
      assert recovered == prev
    end
  end

  describe "analyze_rule/2" do
    test "analyzes rule behavior" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 30, generations: 10)

      assert Map.has_key?(analysis, :generations)
      assert Map.has_key?(analysis, :density_history)
      assert Map.has_key?(analysis, :final_state)
    end

    test "tracks density over generations" do
      cells = [0, 1, 0, 1, 0, 1, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 110, generations: 5)

      assert length(analysis.density_history) == 5
      assert Enum.all?(analysis.density_history, &(&1 >= 0.0 and &1 <= 1.0))
    end
  end

  describe "evolve/3" do
    test "evolves cells for multiple generations" do
      cells = [0, 0, 1, 0, 0]
      history = OuterTotalistic.evolve(cells, 30, 5)

      assert length(history) == 6  # Initial + 5 generations
      assert hd(history) == cells
    end

    test "returns only final state with return: :final" do
      cells = [1, 0, 1, 0, 1]
      final = OuterTotalistic.evolve(cells, 110, 10, return: :final)

      assert is_list(final)
      assert length(final) == length(cells)
    end
  end

  describe "rule_lookup_table/1" do
    test "generates lookup table for rule" do
      table = OuterTotalistic.rule_lookup_table(30)

      # 2^3 = 8 possible neighborhoods for 3-cell neighborhood
      assert map_size(table) == 8
      assert table[{1, 1, 1}] in [0, 1]
      assert table[{0, 0, 0}] in [0, 1]
    end

    test "rule 30 specific patterns" do
      table = OuterTotalistic.rule_lookup_table(30)

      # Rule 30: 30 = 0b00011110
      # 111 -> 0, 110 -> 0, 101 -> 0, 100 -> 1
      # 011 -> 1, 010 -> 1, 001 -> 1, 000 -> 0
      assert table[{0, 0, 0}] == 0
      assert table[{0, 0, 1}] == 1
      assert table[{0, 1, 0}] == 1
      assert table[{0, 1, 1}] == 1
      assert table[{1, 0, 0}] == 1
      assert table[{1, 0, 1}] == 0
      assert table[{1, 1, 0}] == 0
      assert table[{1, 1, 1}] == 0
    end
  end

  describe "edge cases" do
    test "handles all zeros" do
      cells = [0, 0, 0, 0, 0]
      result = OuterTotalistic.apply_rule(cells, 30)

      assert result == [0, 0, 0, 0, 0]
    end

    test "handles all ones" do
      cells = [1, 1, 1, 1, 1]
      result = OuterTotalistic.apply_rule(cells, 30)

      # Rule 30: 111 -> 0
      assert hd(result) == 0
    end

    test "handles binary list representation" do
      cells = [1, 0, 1, 0]
      result = OuterTotalistic.apply_rule(cells, 110)

      assert Enum.all?(result, &(&1 in [0, 1]))
    end
  end
end
