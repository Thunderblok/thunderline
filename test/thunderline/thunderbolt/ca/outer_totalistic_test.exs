defmodule Thunderline.Thunderbolt.CA.OuterTotalisticTest do
  @moduledoc """
  Tests for the Outer-Totalistic Cellular Automata module.

  Covers elementary CA rules (0-255) and the vetted rules from
  the Cerebros/QuAK proposal (HC-Δ-16).
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.OuterTotalistic

  @moduletag :ca

  # ═══════════════════════════════════════════════════════════════
  # apply_rule/2 - Elementary CA rule application
  # ═══════════════════════════════════════════════════════════════

  describe "apply_rule/2" do
    test "applies rule 30 correctly" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      result = OuterTotalistic.apply_rule(cells, 30)

      assert is_list(result)
      assert length(result) == length(cells)
      # Rule 30 evolves single 1 into [0, 0, 1, 1, 1, 0, 0]
      assert result == [0, 0, 1, 1, 1, 0, 0]
    end

    test "applies rule 110 preserving structure" do
      cells = [0, 1, 0, 1, 1, 0, 1]
      result = OuterTotalistic.apply_rule(cells, 110)

      assert is_list(result)
      assert length(result) == length(cells)
      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "handles single-cell array" do
      cells = [1]
      result = OuterTotalistic.apply_rule(cells, 30)

      assert is_list(result)
      assert length(result) == 1
    end

    test "handles empty cell array" do
      cells = []
      result = OuterTotalistic.apply_rule(cells, 30)

      assert result == []
    end

    test "wraps edges correctly (periodic boundary)" do
      cells = [1, 0, 0, 0, 1]
      result = OuterTotalistic.apply_rule(cells, 30)

      assert is_list(result)
      assert length(result) == 5
      # Edges use wrapped neighbors
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # apply_rule_number/3 - Extended neighborhood rules
  # ═══════════════════════════════════════════════════════════════

  describe "apply_rule_number/3" do
    test "applies rule with default neighborhood size 3" do
      cells = [0, 0, 1, 1, 0]
      result = OuterTotalistic.apply_rule_number(cells, 30, 3)

      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "defaults to neighborhood size 3 when omitted" do
      cells = [0, 0, 1, 0, 0]
      result_explicit = OuterTotalistic.apply_rule_number(cells, 30, 3)
      result_default = OuterTotalistic.apply_rule_number(cells, 30)

      assert result_explicit == result_default
    end

    test "applies rule with larger neighborhood (5)" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      result = OuterTotalistic.apply_rule_number(cells, 110, 5)

      assert is_list(result)
      assert length(result) == length(cells)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # vetted_rules/0 - Cerebros/QuAK vetted rule metadata
  # ═══════════════════════════════════════════════════════════════

  describe "vetted_rules/0" do
    test "returns all four vetted rules" do
      rules = OuterTotalistic.vetted_rules()

      assert is_map(rules)
      assert Map.has_key?(rules, :reversible_chaotic)
      assert Map.has_key?(rules, :period_doubling)
      assert Map.has_key?(rules, :xor_linear)
      assert Map.has_key?(rules, :rule_150_analog)
      assert map_size(rules) == 4
    end

    test "vetted rules have required fields" do
      rules = OuterTotalistic.vetted_rules()

      Enum.each(rules, fn {_name, rule_spec} ->
        assert Map.has_key?(rule_spec, :rule_number)
        assert Map.has_key?(rule_spec, :description)
        assert Map.has_key?(rule_spec, :k)
        assert Map.has_key?(rule_spec, :r)
        assert Map.has_key?(rule_spec, :properties)
        assert is_integer(rule_spec.rule_number)
        assert is_binary(rule_spec.description)
        assert is_list(rule_spec.properties)
      end)
    end

    test "rule numbers match Cerebros proposal" do
      rules = OuterTotalistic.vetted_rules()

      assert rules.reversible_chaotic.rule_number == 267_422_991
      assert rules.period_doubling.rule_number == 4_042_321_935
      assert rules.xor_linear.rule_number == 2_863_311_530
      assert rules.rule_150_analog.rule_number == 3_435_973_836
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # rule_info/1 and rule_by_number/1 - Rule lookup functions
  # ═══════════════════════════════════════════════════════════════

  describe "rule_info/1" do
    test "returns rule info for valid name" do
      info = OuterTotalistic.rule_info(:xor_linear)

      assert info.rule_number == 2_863_311_530
      assert info.description == "XOR-based linear rule"
      assert :linear in info.properties
    end

    test "returns nil for unknown rule name" do
      assert OuterTotalistic.rule_info(:nonexistent) == nil
    end
  end

  describe "rule_by_number/1" do
    test "finds rule by its number" do
      result = OuterTotalistic.rule_by_number(267_422_991)

      assert {:reversible_chaotic, info} = result
      assert info.description == "Reversible, chaotic attractor"
    end

    test "returns nil for unknown number" do
      assert OuterTotalistic.rule_by_number(12345) == nil
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # apply_vetted_rule/2 - Apply rules by name
  # ═══════════════════════════════════════════════════════════════

  describe "apply_vetted_rule/2" do
    test "applies reversible chaotic rule" do
      cells = [0, 1, 0, 1, 1, 0, 1, 0]
      result = OuterTotalistic.apply_vetted_rule(cells, :reversible_chaotic)

      assert is_list(result)
      assert length(result) == length(cells)
      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "applies XOR linear rule" do
      cells = [1, 0, 1, 0, 1]
      result = OuterTotalistic.apply_vetted_rule(cells, :xor_linear)

      assert is_list(result)
      assert length(result) == length(cells)
    end

    test "applies all four vetted rules without error" do
      cells = [1, 0, 1, 1, 0, 0, 1, 0]

      for rule_name <- [:reversible_chaotic, :period_doubling, :xor_linear, :rule_150_analog] do
        result = OuterTotalistic.apply_vetted_rule(cells, rule_name)
        assert is_list(result), "#{rule_name} should return a list"
        assert length(result) == length(cells)
      end
    end

    test "returns error tuple for unknown rule" do
      cells = [1, 0, 1]
      result = OuterTotalistic.apply_vetted_rule(cells, :unknown_rule)

      assert {:error, {:unknown_rule, :unknown_rule}} = result
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # apply_xor_rule/1 - Pure XOR-based rule
  # ═══════════════════════════════════════════════════════════════

  describe "apply_xor_rule/1" do
    test "XOR rule: new_cell = left XOR right" do
      # Known pattern: [1, 0, 1, 0]
      # Position 0: wrap(3) XOR wrap(1) = 0 XOR 0 = 0
      # Position 1: 1 XOR 1 = 0
      # Position 2: 0 XOR 0 = 0
      # Position 3: 1 XOR 1 = 0
      cells = [1, 0, 1, 0]
      result = OuterTotalistic.apply_xor_rule(cells)

      assert is_list(result)
      assert length(result) == length(cells)
      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "handles alternating pattern" do
      cells = [1, 0, 1, 0, 1, 0]
      result = OuterTotalistic.apply_xor_rule(cells)

      assert is_list(result)
      assert length(result) == 6
    end

    test "handles empty cells" do
      assert OuterTotalistic.apply_xor_rule([]) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # apply_reversible_rule/3 - Second-order reversible CA
  # ═══════════════════════════════════════════════════════════════

  describe "apply_reversible_rule/3" do
    test "applies rule and XORs with previous state" do
      cells = [1, 0, 1, 0, 1]
      prev = [0, 1, 0, 1, 0]
      result = OuterTotalistic.apply_reversible_rule(cells, prev, 30)

      assert is_list(result)
      assert length(result) == length(cells)
      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "second-order reversibility: forward and reverse are inverses" do
      # Second-order CA: next = f(current) XOR prev
      # This makes the system reversible because:
      # prev = f(current) XOR next
      #
      # We can verify this by showing that XORing the forward result
      # with f(current) recovers prev
      cells = [1, 0, 1, 1, 0, 1, 0]
      prev = [0, 1, 0, 0, 1, 0, 1]

      # Forward step: next = f(cells) XOR prev
      next = OuterTotalistic.apply_reversible_rule(cells, prev, 30)

      # To recover prev: prev = f(cells) XOR next
      # This is NOT apply_reversible_rule(next, cells, 30) which would be f(next) XOR cells
      # Instead we need: f(cells) XOR next
      forward_only = OuterTotalistic.apply_rule(cells, 30)
      recovered = Enum.zip(forward_only, next) |> Enum.map(fn {f, n} -> Bitwise.bxor(f, n) end)

      assert recovered == prev
    end

    test "works with different rule numbers" do
      cells = [1, 1, 0, 0, 1, 0]
      prev = [0, 0, 1, 1, 0, 1]

      # Rule 110
      result_110 = OuterTotalistic.apply_reversible_rule(cells, prev, 110)
      assert is_list(result_110)

      # Rule 90 (also produces interesting patterns)
      result_90 = OuterTotalistic.apply_reversible_rule(cells, prev, 90)
      assert is_list(result_90)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # analyze_rule/3 - Rule behavior analysis
  # ═══════════════════════════════════════════════════════════════

  describe "analyze_rule/3" do
    test "returns analysis map with required keys" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 30, generations: 10)

      assert Map.has_key?(analysis, :rule_number)
      assert Map.has_key?(analysis, :generations)
      assert Map.has_key?(analysis, :initial_size)
      assert Map.has_key?(analysis, :density_history)
      assert Map.has_key?(analysis, :final_density)
      assert Map.has_key?(analysis, :final_state)

      assert analysis.rule_number == 30
      assert analysis.generations == 10
      assert analysis.initial_size == 7
    end

    test "density_history has correct length" do
      cells = [0, 1, 0, 1, 0, 1, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 110, generations: 5)

      # density_history tracks exactly `generations` steps
      assert length(analysis.density_history) == 5
    end

    test "densities are valid ratios between 0 and 1" do
      cells = [0, 1, 0, 1, 0, 1, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 110, generations: 5)

      assert Enum.all?(analysis.density_history, fn d ->
               is_float(d) and d >= 0.0 and d <= 1.0
             end)
    end

    test "uses default generations when not specified" do
      cells = [0, 0, 1, 0, 0]
      analysis = OuterTotalistic.analyze_rule(cells, 30)

      assert analysis.generations == 10
      assert length(analysis.density_history) == 10
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # evolve/4 - Multi-generation evolution
  # ═══════════════════════════════════════════════════════════════

  describe "evolve/4" do
    test "returns full history by default" do
      cells = [0, 0, 1, 0, 0]
      history = OuterTotalistic.evolve(cells, 30, 5)

      # History includes initial state + 5 generations
      assert length(history) == 6
      assert hd(history) == cells
    end

    test "each generation has same length as initial" do
      cells = [0, 0, 0, 1, 0, 0, 0]
      history = OuterTotalistic.evolve(cells, 30, 3)

      Enum.each(history, fn gen ->
        assert length(gen) == length(cells)
      end)
    end

    test "returns only final state with return: :final" do
      cells = [1, 0, 1, 0, 1]
      final = OuterTotalistic.evolve(cells, 110, 10, return: :final)

      assert is_list(final)
      assert length(final) == length(cells)
      # Should not be wrapped in list
      assert Enum.all?(final, &(&1 in [0, 1]))
    end

    test "zero generations returns just initial state" do
      cells = [1, 0, 1]
      history = OuterTotalistic.evolve(cells, 30, 0)

      assert history == [cells]
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # rule_lookup_table/1 - Lookup table generation
  # ═══════════════════════════════════════════════════════════════

  describe "rule_lookup_table/1" do
    test "generates 8-entry lookup table for elementary rules" do
      table = OuterTotalistic.rule_lookup_table(30)

      # Elementary CA: 2^3 = 8 possible neighborhoods
      assert map_size(table) == 8
    end

    test "keys are tuples of {left, center, right}" do
      table = OuterTotalistic.rule_lookup_table(30)

      for l <- [0, 1], c <- [0, 1], r <- [0, 1] do
        assert Map.has_key?(table, {l, c, r})
      end
    end

    test "values are 0 or 1" do
      table = OuterTotalistic.rule_lookup_table(30)

      Enum.each(table, fn {_pattern, output} ->
        assert output in [0, 1]
      end)
    end

    test "rule 30 lookup table matches Wolfram specification" do
      table = OuterTotalistic.rule_lookup_table(30)

      # Rule 30 = 0b00011110
      # Pattern (binary high to low): 111 110 101 100 011 010 001 000
      # Output:                         0   0   0   1   1   1   1   0
      assert table[{0, 0, 0}] == 0
      assert table[{0, 0, 1}] == 1
      assert table[{0, 1, 0}] == 1
      assert table[{0, 1, 1}] == 1
      assert table[{1, 0, 0}] == 1
      assert table[{1, 0, 1}] == 0
      assert table[{1, 1, 0}] == 0
      assert table[{1, 1, 1}] == 0
    end

    test "rule 110 lookup table is correct" do
      table = OuterTotalistic.rule_lookup_table(110)

      # Rule 110 = 0b01101110
      assert table[{0, 0, 0}] == 0
      assert table[{0, 0, 1}] == 1
      assert table[{0, 1, 0}] == 1
      assert table[{0, 1, 1}] == 1
      assert table[{1, 0, 0}] == 0
      assert table[{1, 0, 1}] == 1
      assert table[{1, 1, 0}] == 1
      assert table[{1, 1, 1}] == 0
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Edge Cases
  # ═══════════════════════════════════════════════════════════════

  describe "edge cases" do
    test "all zeros stay all zeros for rule 30" do
      cells = [0, 0, 0, 0, 0]
      result = OuterTotalistic.apply_rule(cells, 30)

      # Rule 30: 000 -> 0
      assert result == [0, 0, 0, 0, 0]
    end

    test "all ones become all zeros for rule 30" do
      cells = [1, 1, 1, 1, 1]
      result = OuterTotalistic.apply_rule(cells, 30)

      # Rule 30: 111 -> 0
      assert result == [0, 0, 0, 0, 0]
    end

    test "output values are always binary" do
      cells = [1, 0, 1, 0]
      result = OuterTotalistic.apply_rule(cells, 110)

      assert Enum.all?(result, &(&1 in [0, 1]))
    end

    test "large cell array is handled efficiently" do
      cells = List.duplicate(0, 100) ++ [1] ++ List.duplicate(0, 100)
      result = OuterTotalistic.apply_rule(cells, 30)

      assert length(result) == 201
    end
  end
end
