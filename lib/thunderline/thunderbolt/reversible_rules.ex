defmodule Thunderline.Thunderbolt.ReversibleRules do
  @moduledoc """
  Reversible cellular automata rules using Toffoli and Feynman gates.

  Implements bijective transition functions for Thunderbits, enabling:
  - Perfect undo/redo in CA evolution
  - Entropy-preserving state transitions
  - Audit trail via inverse computation

  ## HC-89: Reversible CA Rules

  Standard CA rules are irreversible (many states map to same output).
  Reversible rules maintain bijection: every output has exactly one input.
  This enables "running the tape backward" for debugging and rollback.

  ## Gate Primitives

  - **Feynman (CNOT)**: `target ← target ⊕ control`
  - **Toffoli (CCNOT)**: `target ← target ⊕ (c1 ∧ c2)`
  - **Fredkin (CSWAP)**: Swap targets if control is active

  ## Usage

      # Check if a rule is reversible
      ReversibleRules.reversible?(&my_rule/1)

      # Apply reversible rule
      {new_state, inverse_op} = ReversibleRules.apply_rule(:feynman, [center, neighbor])

      # Undo the rule
      original = ReversibleRules.apply_inverse(inverse_op, new_state)

  ## References

  - HC_QUANTUM_SUBSTRATE_SPEC.md §4 Reversible Logic Substrate
  - Toffoli, T. "Reversible Computing" (1980)
  - Margolus partitioning for 2nd-order reversible CA
  """

  alias Thunderline.Thunderbolt.TernaryState

  # ═══════════════════════════════════════════════════════════════════════════
  # Types
  # ═══════════════════════════════════════════════════════════════════════════

  @type ternary :: TernaryState.ternary()
  @type rule_name :: :feynman | :toffoli | :fredkin | :margolus | :second_order
  @type inverse_op :: {rule_name(), [ternary()]}

  # ═══════════════════════════════════════════════════════════════════════════
  # Reversibility Checking
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if a ternary CA rule function is reversible (bijective).

  Tests all possible input combinations to verify unique outputs.

  ## Examples

      iex> reversible?(fn {a, _, _} -> a end)  # projection - NOT reversible
      false

      iex> reversible?(&TernaryState.feynman/2)  # CNOT - reversible
      true
  """
  @spec reversible?((tuple() -> ternary())) :: boolean()
  def reversible?(rule_fn) when is_function(rule_fn, 1) do
    # Generate all 3^3 = 27 possible ternary triplets
    inputs =
      for a <- [:neg, :zero, :pos],
          b <- [:neg, :zero, :pos],
          c <- [:neg, :zero, :pos] do
        {a, b, c}
      end

    outputs = Enum.map(inputs, &rule_fn.(&1))

    # Bijective iff all outputs are unique
    length(Enum.uniq(outputs)) == length(inputs)
  end

  def reversible?(rule_fn) when is_function(rule_fn, 2) do
    # For 2-arity rules (control, target)
    inputs =
      for a <- [:neg, :zero, :pos],
          b <- [:neg, :zero, :pos] do
        {a, b}
      end

    outputs = Enum.map(inputs, fn {a, b} -> {a, rule_fn.(a, b)} end)

    length(Enum.uniq(outputs)) == length(inputs)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Reversible Gate Application
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Applies a named reversible gate and returns {result, inverse_op}.

  The inverse_op can be passed to `apply_inverse/2` to undo the operation.

  ## Supported Gates

  - `:feynman` - CNOT gate: `[control, target] → [control, control⊕target]`
  - `:toffoli` - CCNOT gate: `[c1, c2, target] → [c1, c2, target⊕(c1∧c2)]`
  - `:fredkin` - CSWAP gate: `[control, t1, t2] → [control, t2, t1]` if control=:pos

  ## Examples

      iex> {result, inv} = apply_rule(:feynman, [:pos, :zero])
      {[:pos, :pos], {:feynman, [:pos, :pos]}}

      iex> apply_inverse(inv)
      [:pos, :zero]  # original restored
  """
  @spec apply_rule(rule_name(), [ternary()]) :: {[ternary()], inverse_op()}

  def apply_rule(:feynman, [control, target]) do
    new_target = TernaryState.feynman(control, target)
    result = [control, new_target]
    # Feynman is self-inverse
    {result, {:feynman, result}}
  end

  def apply_rule(:toffoli, [c1, c2, target]) do
    {new_c1, new_c2, new_target} = TernaryState.toffoli(c1, c2, target)
    result = [new_c1, new_c2, new_target]
    # Toffoli is self-inverse
    {result, {:toffoli, result}}
  end

  def apply_rule(:fredkin, [control, t1, t2]) do
    {new_control, new_t1, new_t2} = TernaryState.fredkin(control, t1, t2)
    result = [new_control, new_t1, new_t2]
    # Fredkin is self-inverse
    {result, {:fredkin, result}}
  end

  @doc """
  Applies the inverse operation to restore original state.

  For Toffoli, Feynman, and Fredkin gates, they are their own inverses
  (involutions), so applying twice returns to original.

  ## Examples

      iex> {result, inv} = apply_rule(:feynman, [:pos, :neg])
      iex> apply_inverse(inv)
      [:pos, :neg]
  """
  @spec apply_inverse(inverse_op()) :: [ternary()]
  def apply_inverse({:feynman, [control, target]}) do
    # Feynman is self-inverse
    new_target = TernaryState.feynman(control, target)
    [control, new_target]
  end

  def apply_inverse({:toffoli, [c1, c2, target]}) do
    # Toffoli is self-inverse
    {_, _, new_target} = TernaryState.toffoli(c1, c2, target)
    [c1, c2, new_target]
  end

  def apply_inverse({:fredkin, [control, t1, t2]}) do
    # Fredkin is self-inverse
    {_, new_t1, new_t2} = TernaryState.fredkin(control, t1, t2)
    [control, new_t1, new_t2]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Second-Order Reversible CA
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Applies a second-order reversible CA rule.

  Second-order rules use both current and previous state:
  `s(t+1) = f(neighbors(t)) - s(t-1)`

  This makes ANY rule reversible by storing one timestep of history.

  ## Parameters

  - `current` - Current cell state
  - `previous` - Previous cell state (t-1)
  - `neighbor_sum` - Sum/function of neighbor states

  ## Examples

      iex> second_order_step(:zero, :pos, :pos)
      {:zero, :zero}  # new_current = neighbor_sum - previous = 1 - 1 = 0
  """
  @spec second_order_step(ternary(), ternary(), ternary()) :: {ternary(), ternary()}
  def second_order_step(current, previous, neighbor_contribution) do
    # New state = f(neighbors) - previous (mod 3 balanced)
    f_val = TernaryState.to_balanced(neighbor_contribution)
    prev_val = TernaryState.to_balanced(previous)

    # Balanced ternary subtraction
    diff = Integer.mod(f_val - prev_val + 1, 3) - 1
    new_state = TernaryState.from_balanced(diff)

    # Current becomes new previous
    {new_state, current}
  end

  @doc """
  Reverses a second-order CA step.

  Given current and "previous" (which was current before step),
  recover the original previous state.

  ## Examples

      iex> {new, old_curr} = second_order_step(:zero, :pos, :pos)
      iex> reverse_second_order(new, old_curr, :pos)
      :pos  # recovered original previous
  """
  @spec reverse_second_order(ternary(), ternary(), ternary()) :: ternary()
  def reverse_second_order(current, _next_previous, neighbor_contribution) do
    # previous = f(neighbors) - current
    f_val = TernaryState.to_balanced(neighbor_contribution)
    curr_val = TernaryState.to_balanced(current)

    diff = Integer.mod(f_val - curr_val + 1, 3) - 1
    TernaryState.from_balanced(diff)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Margolus Partitioning
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Applies Margolus partitioning for reversible 2D CA.

  Alternates between even and odd grid partitions, applying
  block rules that are reversible within each 2×2 block.

  ## Parameters

  - `block` - 4-element list `[tl, tr, bl, br]` (top-left, top-right, etc.)
  - `phase` - `:even` or `:odd` partition phase

  Returns `{new_block, inverse_info}`.
  """
  @spec margolus_block([ternary()], :even | :odd) :: {[ternary()], map()}
  def margolus_block([tl, tr, bl, br], phase) do
    # Simple rotation rule (reversible)
    rotated =
      case phase do
        :even -> [br, tl, tr, bl]  # Rotate clockwise
        :odd -> [tr, bl, br, tl]  # Rotate counter-clockwise
      end

    inverse_info = %{
      phase: phase,
      original: [tl, tr, bl, br]
    }

    {rotated, inverse_info}
  end

  @doc """
  Reverses a Margolus block transformation.
  """
  @spec reverse_margolus([ternary()], :even | :odd) :: [ternary()]
  def reverse_margolus([a, b, c, d], phase) do
    case phase do
      :even -> [b, c, d, a]  # Counter-clockwise undoes clockwise
      :odd -> [d, a, b, c]  # Clockwise undoes counter-clockwise
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Rule Composition
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Composes multiple reversible rules into a single transformation.

  Returns a function that applies all rules in sequence and
  can be inverted by applying inverses in reverse order.

  ## Examples

      iex> composed = compose([:feynman, :toffoli])
      iex> {result, inverses} = composed.([:pos, :neg, :zero])
      iex> Enum.reduce(inverses, result, &apply_inverse/1)
      [:pos, :neg, :zero]
  """
  @spec compose([rule_name()]) :: ([ternary()] -> {[ternary()], [inverse_op()]})
  def compose(rules) when is_list(rules) do
    fn initial_state ->
      {final_state, inverses} =
        Enum.reduce(rules, {initial_state, []}, fn rule, {state, inv_acc} ->
          {new_state, inverse} = apply_rule(rule, state)
          {new_state, [inverse | inv_acc]}
        end)

      # Inverses are in reverse order (for proper undo sequence)
      {final_state, inverses}
    end
  end

  @doc """
  Applies a sequence of inverse operations to restore original state.
  """
  @spec apply_inverses([inverse_op()], [ternary()]) :: [ternary()]
  def apply_inverses(inverses, state) do
    Enum.reduce(inverses, state, fn inverse, _current ->
      apply_inverse(inverse)
    end)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Entropy Tracking
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Computes the "logical entropy" of a rule application.

  For reversible rules, entropy change is always 0.
  For irreversible rules, entropy increases (information loss).

  Returns `{entropy_before, entropy_after, delta}`.
  """
  @spec entropy_delta([ternary()], rule_name()) :: {float(), float(), float()}
  def entropy_delta(state, rule_name) do
    entropy_before = state_entropy(state)

    {new_state, _inverse} = apply_rule(rule_name, state)
    entropy_after = state_entropy(new_state)

    {entropy_before, entropy_after, entropy_after - entropy_before}
  end

  @doc """
  Computes Shannon entropy of a ternary state vector.
  """
  @spec state_entropy([ternary()]) :: float()
  def state_entropy(states) when is_list(states) do
    freqs = Enum.frequencies(states)
    total = length(states)

    freqs
    |> Map.values()
    |> Enum.map(fn count ->
      p = count / total
      if p > 0, do: -p * :math.log2(p), else: 0.0
    end)
    |> Enum.sum()
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Thunderbit Integration
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Applies a reversible rule to a Thunderbit and its neighbors.

  Returns `{new_center_state, inverse_op, audit_entry}`.

  The audit_entry can be stored for rollback/replay.
  """
  @spec apply_to_neighborhood(ternary(), [ternary()], rule_name(), keyword()) ::
          {ternary(), inverse_op(), map()}
  def apply_to_neighborhood(center, neighbors, rule_name, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)
    bit_id = Keyword.get(opts, :bit_id, nil)

    # Compute neighbor contribution (majority vote or sum)
    neighbor_contrib = TernaryState.weighted_vote(neighbors)

    # Build rule input based on rule type
    {input, new_center, inverse} =
      case rule_name do
        :feynman ->
          input = [neighbor_contrib, center]
          {result, inv} = apply_rule(:feynman, input)
          [_ctrl, new_target] = result
          {input, new_target, inv}

        :second_order ->
          # Requires previous state - use :zero as default
          previous = Keyword.get(opts, :previous_state, :zero)
          {new_state, _new_prev} = second_order_step(center, previous, neighbor_contrib)
          inv = {:second_order, [center, previous, neighbor_contrib]}
          {[center, previous], new_state, inv}

        _ ->
          # Default: Feynman gate
          input = [neighbor_contrib, center]
          {result, inv} = apply_rule(:feynman, input)
          [_ctrl, new_target] = result
          {input, new_target, inv}
      end

    audit_entry = %{
      bit_id: bit_id,
      tick: tick,
      rule: rule_name,
      input: input,
      output: new_center,
      inverse: inverse,
      timestamp: DateTime.utc_now()
    }

    {new_center, inverse, audit_entry}
  end

  @doc """
  Rolls back a Thunderbit state using an audit entry.
  """
  @spec rollback(map()) :: ternary()
  def rollback(%{inverse: inverse}) do
    result = apply_inverse(inverse)

    case result do
      [_ctrl, target] -> target
      [_c1, _c2, target] -> target
      other -> List.last(other)
    end
  end
end
