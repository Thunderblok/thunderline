defmodule Thunderline.Thunderbolt.TAE.ValueFunctionTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.TAE.ValueFunction

  @moduletag :tae

  describe "compute/3" do
    test "computes inf value" do
      weights = [5.0, 3.0, 8.0, 2.0, 6.0]
      assert ValueFunction.compute(weights, :inf) == 2.0
    end

    test "computes sup value" do
      weights = [5.0, 3.0, 8.0, 2.0, 6.0]
      assert ValueFunction.compute(weights, :sup) == 8.0
    end

    test "computes sum value" do
      weights = [1.0, 2.0, 3.0, 4.0]
      assert ValueFunction.compute(weights, :sum) == 10.0
    end

    test "computes discount value" do
      weights = [1.0, 1.0, 1.0, 1.0]
      # Default discount factor 0.9
      # 1 + 0.9 + 0.81 + 0.729 ≈ 3.439
      result = ValueFunction.compute(weights, :discount, discount_factor: 0.9)
      assert_in_delta result, 3.439, 0.01
    end

    test "handles empty list" do
      assert ValueFunction.compute([], :inf) == :infinity
      assert ValueFunction.compute([], :sup) == :neg_infinity
      assert ValueFunction.compute([], :sum) == 0.0
    end
  end

  describe "inf/1" do
    test "returns minimum weight" do
      assert ValueFunction.inf([10, 5, 15, 3, 8]) == 3
    end

    test "handles single element" do
      assert ValueFunction.inf([42]) == 42
    end

    test "handles negative weights" do
      assert ValueFunction.inf([5, -3, 2]) == -3
    end
  end

  describe "sup/1" do
    test "returns maximum weight" do
      assert ValueFunction.sup([10, 5, 15, 3, 8]) == 15
    end

    test "handles single element" do
      assert ValueFunction.sup([42]) == 42
    end

    test "handles negative weights" do
      assert ValueFunction.sup([-5, -3, -10]) == -3
    end
  end

  describe "lim_inf/2" do
    test "computes limit inferior" do
      # For sequence [1, 5, 1, 5, 1, 5, ...] lim_inf should be 1
      weights = [1, 5, 1, 5, 1, 5]
      result = ValueFunction.lim_inf(weights)

      # Should approach the minimum seen repeatedly
      assert result <= 1.5
    end

    test "with explicit window" do
      weights = [10, 2, 8, 2, 9, 2, 7, 2]
      result = ValueFunction.lim_inf(weights, window: 4)

      assert is_number(result)
    end
  end

  describe "lim_sup/2" do
    test "computes limit superior" do
      weights = [1, 5, 1, 5, 1, 5]
      result = ValueFunction.lim_sup(weights)

      # Should approach the maximum seen repeatedly
      assert result >= 4.5
    end

    test "with explicit window" do
      weights = [1, 10, 1, 10, 1, 10]
      result = ValueFunction.lim_sup(weights, window: 4)

      assert is_number(result)
    end
  end

  describe "lim_inf_avg/2" do
    test "computes limit inferior of running averages" do
      weights = [2.0, 4.0, 2.0, 4.0, 2.0, 4.0]
      result = ValueFunction.lim_inf_avg(weights)

      # Average alternates, lim_inf_avg should be around 3
      assert result >= 2.5 and result <= 3.5
    end
  end

  describe "lim_sup_avg/2 (Cerebros primary)" do
    test "computes limit superior of running averages" do
      weights = [2.0, 4.0, 2.0, 4.0, 2.0, 4.0]
      result = ValueFunction.lim_sup_avg(weights)

      # Average oscillates around 3
      assert result >= 2.5 and result <= 3.5
    end

    test "converges for constant sequence" do
      weights = [5.0, 5.0, 5.0, 5.0, 5.0]
      result = ValueFunction.lim_sup_avg(weights)

      assert_in_delta result, 5.0, 0.1
    end

    test "handles increasing sequence" do
      weights = [1.0, 2.0, 3.0, 4.0, 5.0]
      result = ValueFunction.lim_sup_avg(weights)

      # Running averages: 1, 1.5, 2, 2.5, 3 - sup is 3
      assert result >= 2.5
    end
  end

  describe "sum/1" do
    test "sums all weights" do
      assert ValueFunction.sum([1, 2, 3, 4, 5]) == 15
    end

    test "handles empty list" do
      assert ValueFunction.sum([]) == 0
    end

    test "handles floats" do
      assert_in_delta ValueFunction.sum([1.5, 2.5, 3.0]), 7.0, 0.001
    end
  end

  describe "discount/2" do
    test "applies discount factor" do
      weights = [1.0, 1.0, 1.0]
      # 1 + 0.5 + 0.25 = 1.75
      result = ValueFunction.discount(weights, 0.5)

      assert_in_delta result, 1.75, 0.01
    end

    test "with default discount factor" do
      weights = [1.0, 1.0]
      result = ValueFunction.discount(weights)

      # Default is 0.9, so 1 + 0.9 = 1.9
      assert_in_delta result, 1.9, 0.01
    end

    test "zero discount means only first element" do
      weights = [5.0, 10.0, 15.0]
      result = ValueFunction.discount(weights, 0.0)

      assert result == 5.0
    end
  end

  describe "from_cycle/3" do
    test "computes value from cycle info" do
      cycle = %{
        prefix_length: 1,
        cycle_length: 3,
        cycle_states: [:a, :b, :c]
      }

      weight_fn = fn
        :a -> 1.0
        :b -> 2.0
        :c -> 3.0
      end

      result = ValueFunction.from_cycle(cycle, weight_fn, :lim_sup_avg)
      # Cycle avg = (1 + 2 + 3) / 3 = 2
      assert_in_delta result, 2.0, 0.1
    end

    test "handles inf on cycle" do
      cycle = %{
        prefix_length: 0,
        cycle_length: 2,
        cycle_states: [:x, :y]
      }

      weight_fn = fn
        :x -> 5.0
        :y -> 10.0
      end

      result = ValueFunction.from_cycle(cycle, weight_fn, :inf)
      assert result == 5.0
    end
  end

  describe "streaming accumulator" do
    test "creates and uses accumulator for lim_sup_avg" do
      acc = ValueFunction.new_accumulator(:lim_sup_avg)

      acc = ValueFunction.accumulate(acc, 2.0)
      acc = ValueFunction.accumulate(acc, 4.0)
      acc = ValueFunction.accumulate(acc, 2.0)
      acc = ValueFunction.accumulate(acc, 4.0)

      value = ValueFunction.current_value(acc)
      assert is_number(value)
    end

    test "accumulator for sum" do
      acc = ValueFunction.new_accumulator(:sum)

      acc = acc |> ValueFunction.accumulate(1.0)
      assert ValueFunction.current_value(acc) == 1.0

      acc = acc |> ValueFunction.accumulate(2.0)
      assert ValueFunction.current_value(acc) == 3.0

      acc = acc |> ValueFunction.accumulate(3.0)
      assert ValueFunction.current_value(acc) == 6.0
    end

    test "accumulator for inf" do
      acc = ValueFunction.new_accumulator(:inf)

      acc = acc |> ValueFunction.accumulate(5.0)
      assert ValueFunction.current_value(acc) == 5.0

      acc = acc |> ValueFunction.accumulate(3.0)
      assert ValueFunction.current_value(acc) == 3.0

      acc = acc |> ValueFunction.accumulate(7.0)
      assert ValueFunction.current_value(acc) == 3.0
    end

    test "accumulator for discount" do
      acc = ValueFunction.new_accumulator(:discount, discount_factor: 0.5)

      acc = acc |> ValueFunction.accumulate(1.0)
      assert_in_delta ValueFunction.current_value(acc), 1.0, 0.01

      acc = acc |> ValueFunction.accumulate(1.0)
      assert_in_delta ValueFunction.current_value(acc), 1.5, 0.01

      acc = acc |> ValueFunction.accumulate(1.0)
      assert_in_delta ValueFunction.current_value(acc), 1.75, 0.01
    end
  end

  describe "compare_values/3" do
    test "compares values for optimization" do
      assert ValueFunction.compare_values(5.0, 3.0, :maximize) == :gt
      assert ValueFunction.compare_values(3.0, 5.0, :maximize) == :lt
      assert ValueFunction.compare_values(4.0, 4.0, :maximize) == :eq

      assert ValueFunction.compare_values(3.0, 5.0, :minimize) == :gt
      assert ValueFunction.compare_values(5.0, 3.0, :minimize) == :lt
    end
  end

  describe "value function properties" do
    test "lim_inf <= lim_sup for any sequence" do
      weights = [1.0, 5.0, 2.0, 8.0, 3.0, 7.0]
      lim_inf = ValueFunction.lim_inf(weights)
      lim_sup = ValueFunction.lim_sup(weights)

      assert lim_inf <= lim_sup
    end

    test "inf <= lim_inf_avg <= lim_sup_avg <= sup" do
      weights = [2.0, 5.0, 3.0, 6.0, 1.0, 4.0]

      inf_val = ValueFunction.inf(weights)
      lim_inf_avg = ValueFunction.lim_inf_avg(weights)
      lim_sup_avg = ValueFunction.lim_sup_avg(weights)
      sup_val = ValueFunction.sup(weights)

      # These inequalities should hold for any finite sequence
      assert inf_val <= lim_inf_avg + 0.1
      assert lim_inf_avg <= lim_sup_avg + 0.1
      assert lim_sup_avg <= sup_val + 0.1
    end
  end
end
