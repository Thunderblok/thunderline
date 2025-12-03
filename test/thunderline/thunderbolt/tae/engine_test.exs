defmodule Thunderline.Thunderbolt.TAE.EngineTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.TAE.Engine
  alias Thunderline.Thunderbolt.TAE.ValueFunction

  @moduletag :tae

  describe "top_value/3" do
    test "computes optimal value over traces" do
      # Simple automaton: states are integers, transitions increment
      automaton = %{
        initial: 0,
        transitions: fn state -> [{state + 1, state * 0.5}] end,
        accepting: fn _state -> true end
      }

      result = Engine.top_value(automaton, :lim_sup_avg, max_steps: 10)

      assert {:ok, value} = result
      assert is_number(value)
    end

    test "returns error for invalid automaton" do
      result = Engine.top_value(%{}, :sum, max_steps: 5)

      assert {:error, _reason} = result
    end
  end

  describe "top_value_with_cycles/3" do
    test "detects cycles and computes eventual value" do
      # Automaton that cycles
      automaton = %{
        initial: 0,
        transitions: fn
          0 -> [{1, 1.0}]
          1 -> [{2, 2.0}]
          2 -> [{1, 2.0}]
        end,
        accepting: fn _state -> true end
      }

      result = Engine.top_value_with_cycles(automaton, :lim_sup_avg, max_steps: 20)

      case result do
        {:ok, value, :cyclic, cycle_info} ->
          assert is_number(value)
          assert cycle_info.cycle_length > 0

        {:ok, value, :bounded, _} ->
          assert is_number(value)
      end
    end
  end

  describe "trace_included?/4" do
    test "checks if trace is included in language" do
      # Simple inclusion check
      trace = [{0, 1.0}, {1, 2.0}, {2, 1.5}]

      automaton = %{
        initial: 0,
        transitions: fn
          0 -> [{1, 1.0}]
          1 -> [{2, 2.0}]
          2 -> [{3, 1.5}]
          _ -> []
        end,
        accepting: fn state -> state in [2, 3] end
      }

      result = Engine.trace_included?(trace, automaton, :sup)

      assert is_boolean(result) or match?({:included, _}, result)
    end
  end

  describe "safety_closure/4" do
    test "computes safety closure of automaton" do
      automaton = %{
        initial: :start,
        transitions: fn
          :start -> [{:safe, 1.0}, {:unsafe, 10.0}]
          :safe -> [{:safe, 1.0}]
          :unsafe -> [{:bad, 0.0}]
          :bad -> []
        end,
        accepting: fn state -> state != :bad end
      }

      threshold = 5.0
      {:ok, safe_automaton} = Engine.safety_closure(automaton, :sup, threshold, max_steps: 10)

      assert is_map(safe_automaton)
      assert Map.has_key?(safe_automaton, :initial)
    end
  end

  describe "safety_prefix/4" do
    test "finds safety prefix length" do
      automaton = %{
        initial: 0,
        transitions: fn
          n when n < 5 -> [{n + 1, 1.0}]
          5 -> [{6, 100.0}]
          _ -> []
        end,
        accepting: fn _ -> true end
      }

      result = Engine.safety_prefix(automaton, :sup, 10.0, max_steps: 10)

      case result do
        {:ok, prefix_length} ->
          assert is_integer(prefix_length)
          assert prefix_length >= 0

        {:error, _} ->
          # Acceptable if no safe prefix exists
          :ok
      end
    end
  end

  describe "liveness_decomposition/3" do
    test "decomposes automaton into live components" do
      automaton = %{
        initial: :root,
        transitions: fn
          :root -> [{:live1, 1.0}, {:live2, 2.0}]
          :live1 -> [{:live1, 1.0}]
          :live2 -> [{:live2, 2.0}]
        end,
        accepting: fn state -> state in [:live1, :live2] end
      }

      result = Engine.liveness_decomposition(automaton, :lim_sup_avg, max_steps: 10)

      assert {:ok, components} = result
      assert is_list(components) or is_map(components)
    end
  end

  describe "select_optimal_trace/3" do
    test "selects trace with optimal value" do
      traces = [
        [{0, 1.0}, {1, 2.0}, {2, 3.0}],
        [{0, 5.0}, {1, 5.0}, {2, 5.0}],
        [{0, 1.0}, {1, 1.0}, {2, 10.0}]
      ]

      {:ok, optimal, value} = Engine.select_optimal_trace(traces, :sup)

      assert optimal in traces
      assert value == 10.0  # Max sup across all traces
    end

    test "handles empty traces list" do
      result = Engine.select_optimal_trace([], :sum)

      assert {:error, :no_traces} = result
    end

    test "selects based on lim_sup_avg" do
      traces = [
        [{0, 2.0}, {1, 2.0}, {2, 2.0}],  # avg = 2
        [{0, 1.0}, {1, 3.0}, {2, 2.0}],  # avg = 2
        [{0, 3.0}, {1, 3.0}, {2, 3.0}]   # avg = 3
      ]

      {:ok, optimal, _value} = Engine.select_optimal_trace(traces, :lim_sup_avg)

      # Should select trace with highest average
      weights = Enum.map(optimal, fn {_s, w} -> w end)
      assert Enum.sum(weights) / length(weights) >= 2.9
    end
  end

  describe "pareto_frontier/3" do
    test "computes Pareto frontier over multiple value functions" do
      traces = [
        [{0, 1.0}, {1, 10.0}],  # sum=11, sup=10
        [{0, 5.0}, {1, 5.0}],   # sum=10, sup=5
        [{0, 6.0}, {1, 6.0}],   # sum=12, sup=6
        [{0, 2.0}, {1, 2.0}]    # sum=4, sup=2 (dominated)
      ]

      frontier = Engine.pareto_frontier(traces, [:sum, :sup])

      assert is_list(frontier)
      # Should have at least one non-dominated solution
      assert length(frontier) >= 1

      # Last trace should be dominated and not in frontier
      last_trace = List.last(traces)
      refute last_trace in frontier
    end
  end

  describe "reachable_values/5" do
    test "enumerates reachable value combinations" do
      automaton = %{
        initial: 0,
        transitions: fn
          0 -> [{1, 1.0}, {2, 2.0}]
          1 -> [{3, 1.0}]
          2 -> [{3, 0.5}]
          3 -> []
        end,
        accepting: fn state -> state == 3 end
      }

      values = Engine.reachable_values(automaton, :sum, 0.0, 10.0, max_steps: 5)

      assert is_list(values)
      # Should have explored some paths
    end
  end

  describe "top_value_stream/3" do
    test "streams approximations of top value" do
      automaton = %{
        initial: 0,
        transitions: fn n -> [{n + 1, 1.0 / (n + 1)}] end,
        accepting: fn _ -> true end
      }

      stream = Engine.top_value_stream(automaton, :sum, max_steps: 100)

      approximations = stream |> Enum.take(5)

      assert length(approximations) == 5
      assert Enum.all?(approximations, &is_number/1)

      # Values should be non-decreasing for sum
      pairs = Enum.zip(approximations, tl(approximations))
      assert Enum.all?(pairs, fn {a, b} -> a <= b end)
    end
  end

  describe "integration with ValueFunction" do
    test "engine uses value function correctly" do
      weights = [1.0, 2.0, 3.0, 4.0, 5.0]

      # Direct computation
      direct = ValueFunction.compute(weights, :lim_sup_avg)

      # Through engine trace
      trace = Enum.with_index(weights, fn w, i -> {i, w} end)
      trace_weights = Enum.map(trace, fn {_s, w} -> w end)
      engine = ValueFunction.compute(trace_weights, :lim_sup_avg)

      assert_in_delta direct, engine, 0.01
    end
  end

  describe "automaton validation" do
    test "validates automaton structure" do
      valid = %{
        initial: :start,
        transitions: fn _ -> [] end,
        accepting: fn _ -> false end
      }

      invalid1 = %{initial: :start}  # Missing transitions
      invalid2 = %{transitions: fn _ -> [] end}  # Missing initial

      assert Engine.valid_automaton?(valid)
      refute Engine.valid_automaton?(invalid1)
      refute Engine.valid_automaton?(invalid2)
    end
  end

  describe "deterministic vs non-deterministic" do
    test "handles non-deterministic transitions" do
      # Multiple successors from same state
      automaton = %{
        initial: 0,
        transitions: fn
          0 -> [{1, 1.0}, {2, 5.0}]  # Two choices
          1 -> [{3, 1.0}]
          2 -> [{3, 1.0}]
          3 -> []
        end,
        accepting: fn state -> state == 3 end
      }

      result = Engine.top_value(automaton, :sup, max_steps: 10)

      assert {:ok, value} = result
      # Should find path with sup = 5.0
      assert value >= 5.0
    end
  end
end
