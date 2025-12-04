defmodule Thunderline.Thunderbolt.TAE.Engine do
  @moduledoc """
  Tree Automata Evaluation (TAE) Engine.

  Implements the core TAE operations from the QuAK paper for
  quantitative automata over infinite words.

  ## HC-Δ-17: TAE Core Operations

  From the QuAK research:
  > "Everything reduces to two primitives: Inclusion checking and Top-value computation"

  This engine provides these primitives and derived operations for
  evaluating quantitative properties of CA evolution traces.

  ## Core Operations

  1. **Top Value**: Compute the optimal (supremum) value achievable
  2. **Inclusion**: Check if L(A) ⊆ L(B) for quantitative automata
  3. **Safety Closure**: Compute largest safety subset
  4. **Liveness Decomposition**: Separate safety and liveness components

  ## Thunderline Integration

  - Input: CA trace (sequence of Thundercell states)
  - Weights: Derived from Thunderbit energy/criticality
  - Output: Quantitative fitness value for PAC reward

  ## Usage

      # Compute top value for a trace
      trace = CA.evolve(grid, 1000)
      top = Engine.top_value(trace, weight_fn, :lim_sup_avg)

      # Check inclusion between two automata
      Engine.included?(automaton_a, automaton_b)

      # Compute safety closure
      safe = Engine.safety_closure(automaton)
  """

  alias Thunderline.Thunderbolt.TAE.ValueFunction
  alias Thunderline.Thunderbolt.Cerebros.Cycles

  @type state :: term()
  @type trace :: [state()]
  @type weight_fn :: (state() -> float())
  @type value_type :: ValueFunction.value_type()

  # ═══════════════════════════════════════════════════════════════
  # Top Value Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute the top (supremum) value of a trace.

  The top value is the best achievable value over all possible
  continuations of the trace, given the value function.

  ## Parameters

  - `trace` - Sequence of states
  - `weight_fn` - Function mapping state to weight
  - `value_type` - Which value function to use

  ## Returns

  The computed value (float or :infinity).

  ## Example

      # Compute LimSupAvg for a CA trace
      trace = evolve_ca(grid, 1000)
      weight_fn = fn cell -> cell.energy end
      top = Engine.top_value(trace, weight_fn, :lim_sup_avg)
  """
  @spec top_value(trace(), weight_fn(), value_type()) :: float()
  def top_value(trace, weight_fn, value_type \\ :lim_sup_avg) do
    weights = Enum.map(trace, weight_fn)
    ValueFunction.compute(weights, value_type)
  end

  @doc """
  Compute top value with cycle detection optimization.

  If the trace becomes ultimately periodic, uses cycle information
  for exact computation rather than approximation.
  """
  @spec top_value_with_cycles(trace(), weight_fn(), value_type()) :: float()
  def top_value_with_cycles(trace, weight_fn, value_type \\ :lim_sup_avg) do
    case Cycles.find_cycles(trace) do
      {:ok, cycle} ->
        ValueFunction.from_cycle(cycle, value_type, weight_fn)

      :no_cycle ->
        top_value(trace, weight_fn, value_type)
    end
  end

  @doc """
  Compute top value incrementally as trace grows.

  Returns a stream of intermediate values, useful for
  monitoring convergence.
  """
  @spec top_value_stream(Enumerable.t(), weight_fn(), value_type()) :: Enumerable.t()
  def top_value_stream(state_stream, weight_fn, value_type \\ :lim_sup_avg) do
    state_stream
    |> Stream.transform(
      ValueFunction.new_accumulator(value_type),
      fn state, acc ->
        weight = weight_fn.(state)
        new_acc = ValueFunction.accumulate(acc, weight)
        value = ValueFunction.current_value(new_acc)
        {[value], new_acc}
      end
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # Inclusion Checking
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Check if one trace's value is bounded by another's.

  For quantitative inclusion: A ⊆ B iff val(A) ≤ val(B)

  This is a simplified inclusion check for traces (not full automata).

  ## Parameters

  - `trace_a` - First trace
  - `trace_b` - Second trace
  - `weight_fn` - Weight function
  - `value_type` - Value function type

  ## Returns

  `true` if trace_a's value ≤ trace_b's value.
  """
  @spec trace_included?(trace(), trace(), weight_fn(), value_type()) :: boolean()
  def trace_included?(trace_a, trace_b, weight_fn, value_type \\ :lim_sup_avg) do
    val_a = top_value(trace_a, weight_fn, value_type)
    val_b = top_value(trace_b, weight_fn, value_type)
    val_a <= val_b
  end

  @doc """
  Check strict inclusion.
  """
  @spec trace_strictly_included?(trace(), trace(), weight_fn(), value_type()) :: boolean()
  def trace_strictly_included?(trace_a, trace_b, weight_fn, value_type \\ :lim_sup_avg) do
    val_a = top_value(trace_a, weight_fn, value_type)
    val_b = top_value(trace_b, weight_fn, value_type)
    val_a < val_b
  end

  @doc """
  Check equivalence (mutual inclusion).
  """
  @spec trace_equivalent?(trace(), trace(), weight_fn(), value_type(), float()) :: boolean()
  def trace_equivalent?(trace_a, trace_b, weight_fn, value_type \\ :lim_sup_avg, epsilon \\ 1.0e-10) do
    val_a = top_value(trace_a, weight_fn, value_type)
    val_b = top_value(trace_b, weight_fn, value_type)
    abs(val_a - val_b) < epsilon
  end

  # ═══════════════════════════════════════════════════════════════
  # Safety and Liveness
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute the safety closure of a trace.

  The safety closure contains all prefixes that could lead to
  the trace's limiting behavior. For CA, this identifies states
  that are "safe" to reach given a value threshold.

  ## Parameters

  - `trace` - State sequence
  - `weight_fn` - Weight function
  - `value_type` - Value function type
  - `opts`:
    - `:threshold` - Value threshold for safety

  ## Returns

  List of {prefix, safety_margin} tuples.
  """
  @spec safety_closure(trace(), weight_fn(), value_type(), keyword()) :: [{trace(), float()}]
  def safety_closure(trace, weight_fn, value_type \\ :lim_sup_avg, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.5)
    final_value = top_value(trace, weight_fn, value_type)

    # Compute value at each prefix
    trace
    |> Enum.scan([], fn state, acc -> acc ++ [state] end)
    |> Enum.map(fn prefix ->
      prefix_value = top_value(prefix, weight_fn, value_type)
      margin = final_value - prefix_value
      {prefix, margin}
    end)
    |> Enum.filter(fn {_prefix, margin} ->
      margin >= -threshold
    end)
  end

  @doc """
  Identify the safety prefix of a trace.

  The safety prefix is the longest prefix where the value
  is guaranteed to not decrease below a threshold.
  """
  @spec safety_prefix(trace(), weight_fn(), value_type(), keyword()) :: trace()
  def safety_prefix(trace, weight_fn, _value_type \\ :lim_sup_avg, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.0)

    running_min =
      trace
      |> Enum.map(weight_fn)
      |> Enum.scan(fn w, min -> Kernel.min(w, min) end)

    # Find longest prefix where running min >= threshold
    safe_length =
      running_min
      |> Enum.take_while(&(&1 >= threshold))
      |> length()

    Enum.take(trace, safe_length)
  end

  @doc """
  Decompose a trace into safety and liveness components.

  Safety: What must always be true (invariants)
  Liveness: What must eventually be true (progress)

  Returns a map with safety and liveness characterizations.
  """
  @spec liveness_decomposition(trace(), weight_fn(), value_type()) :: map()
  def liveness_decomposition(trace, weight_fn, value_type \\ :lim_sup_avg) do
    weights = Enum.map(trace, weight_fn)
    final_value = ValueFunction.compute(weights, value_type)

    # Safety: minimum value maintained throughout
    safety_value = Enum.min(weights, fn -> 0.0 end)

    # Liveness: the improvement from safety to final
    liveness_value = final_value - safety_value

    # Identify liveness witnesses (states that improve value)
    witnesses =
      weights
      |> Enum.with_index()
      |> Enum.filter(fn {w, _i} -> w > safety_value end)
      |> Enum.map(fn {_w, i} -> Enum.at(trace, i) end)

    %{
      safety: %{
        value: safety_value,
        invariant: "weight >= #{safety_value}"
      },
      liveness: %{
        value: liveness_value,
        witnesses: witnesses,
        eventuality: "eventually weight > #{safety_value}"
      },
      total_value: final_value
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Multi-Trace Operations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Find the optimal trace among multiple candidates.
  """
  @spec select_optimal_trace([trace()], weight_fn(), value_type()) :: {trace(), float()}
  def select_optimal_trace(traces, weight_fn, value_type \\ :lim_sup_avg) do
    traces
    |> Enum.map(fn trace ->
      {trace, top_value(trace, weight_fn, value_type)}
    end)
    |> Enum.max_by(fn {_trace, value} -> value end)
  end

  @doc """
  Compute the Pareto frontier for multiple value functions.

  Returns traces that are not dominated by any other trace
  across all specified value functions.
  """
  @spec pareto_frontier([trace()], weight_fn(), [value_type()]) :: [trace()]
  def pareto_frontier(traces, weight_fn, value_types) do
    # Compute all values for each trace
    valued_traces =
      Enum.map(traces, fn trace ->
        values =
          Enum.map(value_types, fn vt ->
            top_value(trace, weight_fn, vt)
          end)

        {trace, values}
      end)

    # Filter to non-dominated traces
    Enum.filter(valued_traces, fn {_trace, values} ->
      not Enum.any?(valued_traces, fn {_other_trace, other_values} ->
        dominates?(other_values, values) and other_values != values
      end)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  # ═══════════════════════════════════════════════════════════════
  # Reachability Analysis
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute the set of reachable values from a starting state.

  Uses BFS/DFS to explore possible continuations.
  """
  @spec reachable_values(
          state(),
          (state() -> [state()]),
          weight_fn(),
          value_type(),
          keyword()
        ) :: [float()]
  def reachable_values(start, successor_fn, weight_fn, value_type, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 100)
    max_states = Keyword.get(opts, :max_states, 10_000)

    # BFS exploration
    explore_values(
      [{start, [start]}],
      successor_fn,
      weight_fn,
      value_type,
      MapSet.new([start]),
      [],
      max_depth,
      max_states
    )
  end

  @doc """
  Compute optimal reachable value (supremum over all reachable).
  """
  @spec optimal_reachable_value(
          state(),
          (state() -> [state()]),
          weight_fn(),
          value_type(),
          keyword()
        ) :: float()
  def optimal_reachable_value(start, successor_fn, weight_fn, value_type, opts \\ []) do
    values = reachable_values(start, successor_fn, weight_fn, value_type, opts)

    case values do
      [] -> 0.0
      _ -> Enum.max(values)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════

  defp explore_values([], _succ_fn, _weight_fn, _vt, _visited, values, _max_d, _max_s), do: values

  defp explore_values(_frontier, _succ_fn, _weight_fn, _vt, _visited, values, 0, _max_s), do: values

  defp explore_values(_frontier, _succ_fn, _weight_fn, _vt, visited, values, _max_d, max_s)
       when map_size(visited) >= max_s,
       do: values

  defp explore_values([{state, trace} | rest], succ_fn, weight_fn, vt, visited, values, max_d, max_s) do
    # Compute value for current trace
    value = top_value(trace, weight_fn, vt)

    # Get successors
    successors = succ_fn.(state)

    # Filter to unvisited
    new_successors =
      successors
      |> Enum.reject(&MapSet.member?(visited, &1))

    # Update visited
    new_visited = Enum.reduce(new_successors, visited, &MapSet.put(&2, &1))

    # Add to frontier
    new_frontier =
      Enum.map(new_successors, fn s -> {s, trace ++ [s]} end) ++ rest

    explore_values(
      new_frontier,
      succ_fn,
      weight_fn,
      vt,
      new_visited,
      [value | values],
      max_d - 1,
      max_s
    )
  end

  defp dominates?(values_a, values_b) do
    # A dominates B if A >= B in all dimensions and A > B in at least one
    all_geq = Enum.zip(values_a, values_b) |> Enum.all?(fn {a, b} -> a >= b end)
    any_gt = Enum.zip(values_a, values_b) |> Enum.any?(fn {a, b} -> a > b end)
    all_geq and any_gt
  end
end
