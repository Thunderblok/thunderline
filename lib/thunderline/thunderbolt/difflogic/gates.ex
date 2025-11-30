defmodule Thunderline.Thunderbolt.DiffLogic.Gates do
  @moduledoc """
  Differentiable Logic Gate Networks for Thunderbit CA.

  Based on: "Deep Differentiable Logic Gate Networks" (arXiv:2210.08277, NeurIPS 2022)

  Implements 16 binary logic gates as differentiable operations using real-valued logics
  and continuously parameterized relaxations. This allows training discrete logic networks
  with gradient descent while achieving fast inference speeds.

  ## The 16 Binary Logic Gates

  | ID | Name   | Formula           | Description                    |
  |----|--------|-------------------|--------------------------------|
  | 0  | FALSE  | 0                 | Always false                   |
  | 1  | AND    | a ∧ b             | Both inputs true               |
  | 2  | A>B    | a ∧ ¬b            | A and not B (inhibition)       |
  | 3  | A      | a                 | Pass-through A                 |
  | 4  | B>A    | ¬a ∧ b            | B and not A (inhibition)       |
  | 5  | B      | b                 | Pass-through B                 |
  | 6  | XOR    | a ⊕ b             | Exclusive or                   |
  | 7  | OR     | a ∨ b             | Either input true              |
  | 8  | NOR    | ¬(a ∨ b)          | Neither input true             |
  | 9  | XNOR   | ¬(a ⊕ b)          | Equivalence                    |
  | 10 | NOT_B  | ¬b                | Negate B                       |
  | 11 | A>=B   | a ∨ ¬b            | A implies B (implication)      |
  | 12 | NOT_A  | ¬a                | Negate A                       |
  | 13 | B>=A   | ¬a ∨ b            | B implies A (implication)      |
  | 14 | NAND   | ¬(a ∧ b)          | Not both                       |
  | 15 | TRUE   | 1                 | Always true                    |

  ## Real-Valued Logic

  For differentiable training, we use real-valued logic in [0, 1]:
  - AND(a, b) = a * b
  - OR(a, b) = a + b - a * b  (probabilistic)
  - NOT(a) = 1 - a
  - XOR(a, b) = a + b - 2 * a * b

  ## Reference

  Petersen et al., "Deep Differentiable Logic Gate Networks", NeurIPS 2022
  """

  import Nx.Defn

  @gate_count 16

  # ═══════════════════════════════════════════════════════════════
  # GATE DEFINITIONS (Real-Valued Logic)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply a specific gate by index using real-valued logic.

  Inputs `a` and `b` should be in [0, 1] for proper behavior.
  """
  defn apply_gate(a, b, gate_id) do
    cond do
      gate_id == 0 -> gate_false(a, b)
      gate_id == 1 -> gate_and(a, b)
      gate_id == 2 -> gate_a_inhibit_b(a, b)
      gate_id == 3 -> gate_a(a, b)
      gate_id == 4 -> gate_b_inhibit_a(a, b)
      gate_id == 5 -> gate_b(a, b)
      gate_id == 6 -> gate_xor(a, b)
      gate_id == 7 -> gate_or(a, b)
      gate_id == 8 -> gate_nor(a, b)
      gate_id == 9 -> gate_xnor(a, b)
      gate_id == 10 -> gate_not_b(a, b)
      gate_id == 11 -> gate_a_implies_b(a, b)
      gate_id == 12 -> gate_not_a(a, b)
      gate_id == 13 -> gate_b_implies_a(a, b)
      gate_id == 14 -> gate_nand(a, b)
      true -> gate_true(a, b)
    end
  end

  # Individual gate implementations
  defnp gate_false(_a, _b), do: Nx.tensor(0.0)
  defnp gate_and(a, b), do: Nx.multiply(a, b)
  defnp gate_a_inhibit_b(a, b), do: Nx.multiply(a, Nx.subtract(1.0, b))
  defnp gate_a(a, _b), do: a
  defnp gate_b_inhibit_a(a, b), do: Nx.multiply(Nx.subtract(1.0, a), b)
  defnp gate_b(_a, b), do: b
  defnp gate_xor(a, b), do: Nx.subtract(Nx.add(a, b), Nx.multiply(2.0, Nx.multiply(a, b)))
  defnp gate_or(a, b), do: Nx.subtract(Nx.add(a, b), Nx.multiply(a, b))
  defnp gate_nor(a, b), do: Nx.subtract(1.0, gate_or(a, b))
  defnp gate_xnor(a, b), do: Nx.subtract(1.0, gate_xor(a, b))
  defnp gate_not_b(_a, b), do: Nx.subtract(1.0, b)
  defnp gate_a_implies_b(a, b), do: gate_or(Nx.subtract(1.0, a), b)
  defnp gate_not_a(a, _b), do: Nx.subtract(1.0, a)
  defnp gate_b_implies_a(a, b), do: gate_or(a, Nx.subtract(1.0, b))
  defnp gate_nand(a, b), do: Nx.subtract(1.0, gate_and(a, b))
  defnp gate_true(_a, _b), do: Nx.tensor(1.0)

  # ═══════════════════════════════════════════════════════════════
  # SOFT GATE SELECTION (Differentiable)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply a soft weighted combination of all gates.

  The `weights` tensor has shape {16} and represents the probability distribution
  over gates. This allows gradient-based learning of gate selection.

  ## Example

      # Learned weights (softmax over logits)
      weights = Nx.tensor([0.1, 0.5, 0.1, ...])  # 16 values summing to 1
      result = soft_gate(a, b, weights)
  """
  defn soft_gate(a, b, weights) do
    # Compute all 16 gate outputs
    outputs = Nx.stack([
      gate_false(a, b),
      gate_and(a, b),
      gate_a_inhibit_b(a, b),
      gate_a(a, b),
      gate_b_inhibit_a(a, b),
      gate_b(a, b),
      gate_xor(a, b),
      gate_or(a, b),
      gate_nor(a, b),
      gate_xnor(a, b),
      gate_not_b(a, b),
      gate_a_implies_b(a, b),
      gate_not_a(a, b),
      gate_b_implies_a(a, b),
      gate_nand(a, b),
      gate_true(a, b)
    ])

    # Weighted sum of outputs
    Nx.dot(outputs, weights)
  end

  @doc """
  Convert gate logits to probabilities via softmax.
  """
  defn gate_softmax(logits) do
    max_val = Nx.reduce_max(logits)
    shifted = Nx.subtract(logits, max_val)
    exp_vals = Nx.exp(shifted)
    Nx.divide(exp_vals, Nx.sum(exp_vals))
  end

  @doc """
  Straight-through estimator for discrete gate selection during training.

  Forward: select argmax gate (discrete)
  Backward: use soft gradients

  This is the key technique from the DiffLogic paper.
  """
  defn straight_through_gate(a, b, logits) do
    # Soft probabilities for gradient flow
    probs = gate_softmax(logits)
    soft_output = soft_gate(a, b, probs)

    # Hard selection for forward pass
    gate_idx = Nx.argmax(logits)
    hard_output = apply_gate(a, b, gate_idx)

    # Straight-through: use hard for forward, soft gradient for backward
    # This is achieved by: hard - stop_gradient(soft) + soft
    Nx.add(
      Nx.subtract(hard_output, Nx.Defn.Kernel.stop_grad(soft_output)),
      soft_output
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # GATE NETWORK LAYER
  # ═══════════════════════════════════════════════════════════════

  @doc """
  A layer of parallel logic gates.

  Takes 2*n inputs and produces n outputs, where each output is computed
  by a learned gate operating on a pair of inputs.

  ## Parameters

  - `{a_inputs, b_inputs}` - Tuple of tensors, each of shape {n} or {batch, n}
  - `gate_logits` - Tensor of shape {n, 16} - logits for each gate's selection

  ## Returns

  Tensor of shape {batch, n} or {n}
  """
  def gate_layer({a_inputs, b_inputs}, gate_logits) do
    # Use vectorized soft_gate operation
    # a_inputs: {n} or {batch, n}
    # b_inputs: {n} or {batch, n}
    # gate_logits: {n, 16}
    
    n = elem(Nx.shape(gate_logits), 0)
    
    case Nx.rank(a_inputs) do
      1 ->
        # Single sample: iterate through gates
        0..(n - 1)
        |> Enum.map(fn i ->
          a = Nx.slice(a_inputs, [i], [1]) |> Nx.squeeze()
          b = Nx.slice(b_inputs, [i], [1]) |> Nx.squeeze()
          logits = Nx.slice(gate_logits, [i, 0], [1, 16]) |> Nx.squeeze()
          compute_straight_through_gate(a, b, logits)
        end)
        |> Nx.stack()

      2 ->
        # Batched: process each gate for full batch
        {batch_size, _} = Nx.shape(a_inputs)
        
        0..(n - 1)
        |> Enum.map(fn i ->
          a = Nx.slice(a_inputs, [0, i], [batch_size, 1]) |> Nx.squeeze(axes: [1])
          b = Nx.slice(b_inputs, [0, i], [batch_size, 1]) |> Nx.squeeze(axes: [1])
          logits = Nx.slice(gate_logits, [i, 0], [1, 16]) |> Nx.squeeze()
          
          # Vectorized soft gate for batch
          vectorized_soft_gate_batch(a, b, logits)
        end)
        |> Nx.stack(axis: 1)
    end
  end

  # Helper: straight-through gate outside defn for iteration
  defp compute_straight_through_gate(a, b, logits) do
    Nx.Defn.jit(&straight_through_gate/3).(a, b, logits)
  end

  # Vectorized soft gate for batched inputs (called from non-defn context)
  defp vectorized_soft_gate_batch(a, b, logits) do
    # a, b: {batch_size}
    # logits: {16}
    probs = Nx.Defn.jit(&gate_softmax/1).(logits)
    
    # Compute all 16 gate outputs for entire batch
    gate_outputs = compute_all_gates_batch(a, b)
    
    # Weighted sum: {batch, 16} @ {16} -> {batch}
    Nx.dot(gate_outputs, probs)
  end

  # Compute all 16 gate outputs for batched a, b
  defp compute_all_gates_batch(a, b) do
    # a, b: {batch_size}
    # Returns: {batch_size, 16}
    
    g0 = Nx.broadcast(0.0, Nx.shape(a))           # FALSE
    g1 = Nx.multiply(a, b)                         # AND
    g2 = Nx.multiply(a, Nx.subtract(1, b))         # A > B
    g3 = a                                         # A
    g4 = Nx.multiply(Nx.subtract(1, a), b)         # B > A
    g5 = b                                         # B
    g6 = Nx.abs(Nx.subtract(a, b))                 # XOR
    g7 = Nx.max(a, b)                              # OR
    g8 = Nx.subtract(1, g7)                        # NOR
    g9 = Nx.subtract(1, g6)                        # XNOR
    g10 = Nx.subtract(1, b)                        # NOT B
    g11 = Nx.max(a, Nx.subtract(1, b))             # A >= B
    g12 = Nx.subtract(1, a)                        # NOT A
    g13 = Nx.max(Nx.subtract(1, a), b)             # B >= A
    g14 = Nx.subtract(1, g1)                       # NAND
    g15 = Nx.broadcast(1.0, Nx.shape(a))           # TRUE
    
    Nx.stack([g0, g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12, g13, g14, g15], axis: 1)
  end


  # ═══════════════════════════════════════════════════════════════
  # INITIALIZATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Initialize gate logits for a layer.

  ## Options

  - `:n_gates` - Number of gates in the layer
  - `:init` - Initialization strategy (:uniform, :and_bias, :or_bias)
  - `:seed` - Random seed
  """
  def initialize_gate_logits(opts \\ []) do
    n_gates = Keyword.get(opts, :n_gates, 32)
    init = Keyword.get(opts, :init, :uniform)
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))

    key = Nx.Random.key(seed)

    case init do
      :uniform ->
        # Uniform random initialization
        {logits, _key} = Nx.Random.uniform(key, shape: {n_gates, @gate_count})
        logits

      :and_bias ->
        # Bias toward AND gates (index 1)
        {noise, _key} = Nx.Random.normal(key, 0.0, 0.1, shape: {n_gates, @gate_count})
        bias = Nx.broadcast(Nx.tensor(0.0), {n_gates, @gate_count})
        and_bias = Nx.put_slice(bias, [0, 1], Nx.broadcast(1.0, {n_gates, 1}))
        Nx.add(and_bias, noise)

      :or_bias ->
        # Bias toward OR gates (index 7)
        {noise, _key} = Nx.Random.normal(key, 0.0, 0.1, shape: {n_gates, @gate_count})
        bias = Nx.broadcast(Nx.tensor(0.0), {n_gates, @gate_count})
        or_bias = Nx.put_slice(bias, [0, 7], Nx.broadcast(1.0, {n_gates, 1}))
        Nx.add(or_bias, noise)

      :xor_bias ->
        # Bias toward XOR gates (index 6) - useful for parity-like problems
        {noise, _key} = Nx.Random.normal(key, 0.0, 0.1, shape: {n_gates, @gate_count})
        bias = Nx.broadcast(Nx.tensor(0.0), {n_gates, @gate_count})
        xor_bias = Nx.put_slice(bias, [0, 6], Nx.broadcast(1.0, {n_gates, 1}))
        Nx.add(xor_bias, noise)
    end
  end

  @doc """
  Discretize gate logits to get the selected gate indices.

  Used for fast inference after training.
  """
  def discretize(gate_logits) do
    gate_logits
    |> Nx.argmax(axis: 1)
    |> Nx.to_list()
  end

  @doc """
  Get gate name from index.
  """
  def gate_name(0), do: :false
  def gate_name(1), do: :and
  def gate_name(2), do: :a_inhibit_b
  def gate_name(3), do: :a
  def gate_name(4), do: :b_inhibit_a
  def gate_name(5), do: :b
  def gate_name(6), do: :xor
  def gate_name(7), do: :or
  def gate_name(8), do: :nor
  def gate_name(9), do: :xnor
  def gate_name(10), do: :not_b
  def gate_name(11), do: :a_implies_b
  def gate_name(12), do: :not_a
  def gate_name(13), do: :b_implies_a
  def gate_name(14), do: :nand
  def gate_name(15), do: :true
  def gate_name(_), do: :unknown
end
