defmodule Thunderline.Thunderbolt.Cerebros.CyclesTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Cerebros.Cycles

  @moduletag :cerebros

  describe "find_cycles/1" do
    test "detects simple cycle" do
      sequence = [1, 2, 3, 2, 3, 2, 3]
      {:ok, cycle} = Cycles.find_cycles(sequence)

      assert cycle.prefix_length == 1
      assert cycle.cycle_length == 2
      assert cycle.cycle_states == [2, 3]
    end

    test "returns :no_cycle for non-repeating sequence" do
      sequence = [1, 2, 3, 4, 5]
      assert :no_cycle = Cycles.find_cycles(sequence)
    end

    test "handles empty sequence" do
      assert :no_cycle = Cycles.find_cycles([])
    end

    test "handles single element" do
      assert :no_cycle = Cycles.find_cycles([1])
    end

    test "detects cycle at start" do
      sequence = [1, 2, 1, 2, 1, 2]
      {:ok, cycle} = Cycles.find_cycles(sequence)

      assert cycle.prefix_length == 0
      assert cycle.cycle_length == 2
    end

    test "works with complex states" do
      sequence = [%{a: 1}, %{a: 2}, %{a: 1}, %{a: 2}]
      {:ok, cycle} = Cycles.find_cycles(sequence)

      assert cycle.cycle_length == 2
    end
  end

  describe "find_all_cycles/1" do
    test "finds multiple cycles" do
      sequence = [1, 2, 3, 2, 3, 4, 5, 4, 5]
      cycles = Cycles.find_all_cycles(sequence)

      assert length(cycles) >= 1
    end

    test "returns empty list for non-repeating" do
      assert [] = Cycles.find_all_cycles([1, 2, 3, 4, 5])
    end
  end

  describe "find_cycles_brent/2" do
    test "detects cycle with next function" do
      # Create a simple cyclic function
      # 0 -> 1 -> 2 -> 3 -> 1 -> 2 -> 3 -> ...
      next_fn = fn
        0 -> 1
        1 -> 2
        2 -> 3
        3 -> 1
      end

      {:ok, cycle} = Cycles.find_cycles_brent(0, next_fn, max_iter: 100)

      assert cycle.prefix_length == 1
      assert cycle.cycle_length == 3
      assert cycle.cycle_states == [1, 2, 3]
    end

    test "returns :no_cycle when max iterations exceeded" do
      # Function that never cycles (within limit)
      next_fn = fn n -> n + 1 end
      assert :no_cycle = Cycles.find_cycles_brent(0, next_fn, max_iter: 10)
    end
  end

  describe "find_cycles_floyd/2" do
    test "detects cycle with Floyd's algorithm" do
      next_fn = fn
        0 -> 1
        1 -> 2
        2 -> 1
      end

      {:ok, cycle} = Cycles.find_cycles_floyd(0, next_fn, max_iter: 100)

      assert cycle.prefix_length == 1
      assert cycle.cycle_length == 2
    end
  end

  describe "cycle_stats/2" do
    test "computes statistics for cycle" do
      cycle = %{
        prefix_length: 1,
        cycle_start: 1,
        cycle_length: 3,
        cycle_states: [:a, :b, :c]
      }

      weight_fn = fn
        :a -> 1.0
        :b -> 2.0
        :c -> 3.0
      end

      stats = Cycles.cycle_stats(cycle, weight_fn)

      assert stats.cycle_length == 3
      assert stats.cycle_sum == 6.0
      assert stats.cycle_avg == 2.0
      assert stats.cycle_min == 1.0
      assert stats.cycle_max == 3.0
    end

    test "uses default weight function" do
      cycle = %{
        prefix_length: 0,
        cycle_start: 0,
        cycle_length: 2,
        cycle_states: [:x, :y]
      }

      stats = Cycles.cycle_stats(cycle)

      assert stats.cycle_sum == 2.0
      assert stats.cycle_avg == 1.0
    end
  end

  describe "ultimately_periodic?/1" do
    test "returns true for periodic sequence" do
      assert Cycles.ultimately_periodic?([1, 2, 3, 2, 3])
    end

    test "returns false for non-periodic sequence" do
      refute Cycles.ultimately_periodic?([1, 2, 3, 4, 5])
    end
  end

  describe "eventual_value/3" do
    test "computes eventual value for lim_sup_avg" do
      cycle = %{
        prefix_length: 1,
        cycle_start: 1,
        cycle_length: 2,
        cycle_states: [:a, :b]
      }

      weight_fn = fn
        :a -> 1.0
        :b -> 3.0
      end

      value = Cycles.eventual_value(cycle, weight_fn, :lim_sup_avg)
      assert value == 2.0
    end

    test "computes eventual value for lim_inf" do
      cycle = %{
        prefix_length: 0,
        cycle_start: 0,
        cycle_length: 3,
        cycle_states: [:x, :y, :z]
      }

      weight_fn = fn
        :x -> 0.5
        :y -> 1.5
        :z -> 1.0
      end

      value = Cycles.eventual_value(cycle, weight_fn, :lim_inf)
      assert value == 0.5
    end
  end
end
