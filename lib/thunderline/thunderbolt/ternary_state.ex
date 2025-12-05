defmodule Thunderline.Thunderbolt.TernaryState do
  @moduledoc """
  Ternary state primitives for QCA-inspired Thunderbit operations.

  Implements balanced ternary arithmetic and logic inspired by Quantum-dot
  Cellular Automata (QCA) where cells can be in three states: -1, 0, +1
  representing negative, neutral, and positive charge configurations.

  ## HC-86: Ternary State Primitives

  This module provides:
  - Type definitions for ternary values
  - Conversion between atom/integer representations
  - Balanced ternary arithmetic (add, mul, neg)
  - Ternary logic operations (and, or, not, xor)
  - Consensus and voting functions for neighborhoods

  ## QCA Background

  In QCA systems, cells use charge configurations rather than voltage levels.
  The three states map naturally to:
  - `:neg` (-1) - Inhibitory / negative policy / reject
  - `:zero` (0) - Neutral / undecided / abstain
  - `:pos` (+1) - Excitatory / positive policy / accept

  ## Usage

      iex> TernaryState.to_balanced(:pos)
      1

      iex> TernaryState.ternary_add(:pos, :neg)
      :zero

      iex> TernaryState.majority([:pos, :pos, :neg])
      :pos

  ## References

  - HC_QUANTUM_SUBSTRATE_SPEC.md §2 Thunderbit Formal Definition v2
  - HC_ARCHITECTURE_SYNTHESIS.md §1.4.1 Ternary State Space
  """

  @typedoc "Ternary state as atom"
  @type ternary :: :neg | :zero | :pos

  @typedoc "Ternary state as balanced integer"
  @type balanced :: -1 | 0 | 1

  @typedoc "Multi-channel state vector"
  @type state_vector :: [float()]

  # ═══════════════════════════════════════════════════════════════════════════
  # Conversions
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Converts a ternary atom to balanced integer representation.

  ## Examples

      iex> TernaryState.to_balanced(:neg)
      -1

      iex> TernaryState.to_balanced(:zero)
      0

      iex> TernaryState.to_balanced(:pos)
      1
  """
  @spec to_balanced(ternary()) :: balanced()
  def to_balanced(:neg), do: -1
  def to_balanced(:zero), do: 0
  def to_balanced(:pos), do: 1

  @doc """
  Converts a balanced integer to ternary atom representation.

  Clamps values outside [-1, 1] to the nearest boundary.

  ## Examples

      iex> TernaryState.from_balanced(-1)
      :neg

      iex> TernaryState.from_balanced(0)
      :zero

      iex> TernaryState.from_balanced(1)
      :pos

      iex> TernaryState.from_balanced(5)
      :pos
  """
  @spec from_balanced(integer()) :: ternary()
  def from_balanced(n) when n < 0, do: :neg
  def from_balanced(0), do: :zero
  def from_balanced(n) when n > 0, do: :pos

  @doc """
  Converts a float (e.g., from ML model) to ternary using thresholds.

  Default thresholds: < -0.33 → :neg, > 0.33 → :pos, else :zero

  ## Options

  - `:neg_threshold` - Threshold for negative (default: -0.33)
  - `:pos_threshold` - Threshold for positive (default: 0.33)

  ## Examples

      iex> TernaryState.from_float(-0.5)
      :neg

      iex> TernaryState.from_float(0.1)
      :zero

      iex> TernaryState.from_float(0.8, neg_threshold: -0.5, pos_threshold: 0.5)
      :pos
  """
  @spec from_float(float(), keyword()) :: ternary()
  def from_float(f, opts \\ []) when is_float(f) do
    neg_thresh = Keyword.get(opts, :neg_threshold, -0.33)
    pos_thresh = Keyword.get(opts, :pos_threshold, 0.33)

    cond do
      f < neg_thresh -> :neg
      f > pos_thresh -> :pos
      true -> :zero
    end
  end

  @doc """
  Converts ternary to float (for ML model inputs).

  ## Examples

      iex> TernaryState.to_float(:neg)
      -1.0

      iex> TernaryState.to_float(:zero)
      0.0
  """
  @spec to_float(ternary()) :: float()
  def to_float(:neg), do: -1.0
  def to_float(:zero), do: 0.0
  def to_float(:pos), do: 1.0

  # ═══════════════════════════════════════════════════════════════════════════
  # Ternary Arithmetic (Balanced Ternary)
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Ternary negation: flips :pos ↔ :neg, :zero stays :zero.

  ## Examples

      iex> TernaryState.ternary_neg(:pos)
      :neg

      iex> TernaryState.ternary_neg(:zero)
      :zero
  """
  @spec ternary_neg(ternary()) :: ternary()
  def ternary_neg(:neg), do: :pos
  def ternary_neg(:zero), do: :zero
  def ternary_neg(:pos), do: :neg

  @doc """
  Ternary addition with carry (mod 3 balanced).

  Returns {result, carry} where carry ∈ {:neg, :zero, :pos}.

  ## Examples

      iex> TernaryState.ternary_add_carry(:pos, :pos)
      {:neg, :pos}  # 1 + 1 = 2 = -1 + 3 → result -1, carry +1

      iex> TernaryState.ternary_add_carry(:pos, :neg)
      {:zero, :zero}  # 1 + (-1) = 0
  """
  @spec ternary_add_carry(ternary(), ternary()) :: {ternary(), ternary()}
  def ternary_add_carry(a, b) do
    sum = to_balanced(a) + to_balanced(b)

    cond do
      sum == -2 -> {:pos, :neg}
      sum == 2 -> {:neg, :pos}
      true -> {from_balanced(sum), :zero}
    end
  end

  @doc """
  Ternary addition (mod 3 balanced, discards carry).

  ## Examples

      iex> TernaryState.ternary_add(:pos, :neg)
      :zero

      iex> TernaryState.ternary_add(:pos, :pos)
      :neg  # wraps around
  """
  @spec ternary_add(ternary(), ternary()) :: ternary()
  def ternary_add(a, b) do
    {result, _carry} = ternary_add_carry(a, b)
    result
  end

  @doc """
  Ternary multiplication.

  ## Truth Table

  | × | neg | zero | pos |
  |---|-----|------|-----|
  | neg | pos | zero | neg |
  | zero | zero | zero | zero |
  | pos | neg | zero | pos |

  ## Examples

      iex> TernaryState.ternary_mul(:neg, :neg)
      :pos

      iex> TernaryState.ternary_mul(:pos, :zero)
      :zero
  """
  @spec ternary_mul(ternary(), ternary()) :: ternary()
  def ternary_mul(:zero, _), do: :zero
  def ternary_mul(_, :zero), do: :zero
  def ternary_mul(:neg, :neg), do: :pos
  def ternary_mul(:pos, :pos), do: :pos
  def ternary_mul(_, _), do: :neg

  # ═══════════════════════════════════════════════════════════════════════════
  # Ternary Logic (Łukasiewicz-style)
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Ternary NOT (strong negation).

  ## Examples

      iex> TernaryState.ternary_not(:pos)
      :neg

      iex> TernaryState.ternary_not(:zero)
      :zero
  """
  @spec ternary_not(ternary()) :: ternary()
  def ternary_not(a), do: ternary_neg(a)

  @doc """
  Ternary AND (min operation in balanced ternary).

  ## Truth Table

  | ∧ | neg | zero | pos |
  |---|-----|------|-----|
  | neg | neg | neg | neg |
  | zero | neg | zero | zero |
  | pos | neg | zero | pos |

  ## Examples

      iex> TernaryState.ternary_and(:pos, :zero)
      :zero

      iex> TernaryState.ternary_and(:pos, :pos)
      :pos
  """
  @spec ternary_and(ternary(), ternary()) :: ternary()
  def ternary_and(a, b) do
    from_balanced(min(to_balanced(a), to_balanced(b)))
  end

  @doc """
  Ternary OR (max operation in balanced ternary).

  ## Truth Table

  | ∨ | neg | zero | pos |
  |---|-----|------|-----|
  | neg | neg | zero | pos |
  | zero | zero | zero | pos |
  | pos | pos | pos | pos |

  ## Examples

      iex> TernaryState.ternary_or(:neg, :zero)
      :zero

      iex> TernaryState.ternary_or(:pos, :neg)
      :pos
  """
  @spec ternary_or(ternary(), ternary()) :: ternary()
  def ternary_or(a, b) do
    from_balanced(max(to_balanced(a), to_balanced(b)))
  end

  @doc """
  Ternary XOR (symmetric difference).

  Returns :pos if exactly one is :pos, :neg if exactly one is :neg,
  :zero otherwise.

  ## Examples

      iex> TernaryState.ternary_xor(:pos, :neg)
      :pos  # both non-zero, opposite signs

      iex> TernaryState.ternary_xor(:pos, :pos)
      :zero  # same, cancel out
  """
  @spec ternary_xor(ternary(), ternary()) :: ternary()
  def ternary_xor(a, a), do: :zero

  def ternary_xor(a, b) do
    sum = to_balanced(a) + to_balanced(b)
    from_balanced(Integer.mod(sum + 1, 3) - 1)
  end

  @doc """
  Ternary implication (Łukasiewicz).

  a → b = min(1, 1 - a + b)

  ## Examples

      iex> TernaryState.ternary_implies(:pos, :neg)
      :neg  # T → F = F

      iex> TernaryState.ternary_implies(:neg, :pos)
      :pos  # F → T = T

      iex> TernaryState.ternary_implies(:zero, :zero)
      :pos  # U → U = T
  """
  @spec ternary_implies(ternary(), ternary()) :: ternary()
  def ternary_implies(a, b) do
    result = min(1, 1 - to_balanced(a) + to_balanced(b))
    from_balanced(result)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Neighborhood / Consensus Operations
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Returns the majority value from a list of ternary states.

  Counts each state and returns the most frequent. Ties break toward :zero.

  ## Examples

      iex> TernaryState.majority([:pos, :pos, :neg])
      :pos

      iex> TernaryState.majority([:pos, :neg])
      :zero  # tie → neutral

      iex> TernaryState.majority([:zero, :zero, :pos])
      :zero
  """
  @spec majority([ternary()]) :: ternary()
  def majority([]), do: :zero

  def majority(states) when is_list(states) do
    freqs = Enum.frequencies(states)
    neg_count = Map.get(freqs, :neg, 0)
    zero_count = Map.get(freqs, :zero, 0)
    pos_count = Map.get(freqs, :pos, 0)

    max_count = max(neg_count, max(zero_count, pos_count))

    cond do
      pos_count == max_count and neg_count == max_count -> :zero
      pos_count == max_count -> :pos
      neg_count == max_count -> :neg
      true -> :zero
    end
  end

  @doc """
  Computes weighted sum and returns ternary based on sign.

  Each state contributes its balanced value. Result is sign of sum.

  ## Examples

      iex> TernaryState.weighted_vote([:pos, :pos, :neg, :zero])
      :pos  # 1 + 1 - 1 + 0 = 1 > 0

      iex> TernaryState.weighted_vote([:neg, :neg, :pos])
      :neg  # -1 - 1 + 1 = -1 < 0
  """
  @spec weighted_vote([ternary()]) :: ternary()
  def weighted_vote([]), do: :zero

  def weighted_vote(states) when is_list(states) do
    sum = states |> Enum.map(&to_balanced/1) |> Enum.sum()
    from_balanced(sum)
  end

  @doc """
  Returns true if all states are the same (consensus reached).

  ## Examples

      iex> TernaryState.consensus?([:pos, :pos, :pos])
      true

      iex> TernaryState.consensus?([:pos, :zero, :pos])
      false
  """
  @spec consensus?([ternary()]) :: boolean()
  def consensus?([]), do: true
  def consensus?([_]), do: true
  def consensus?([h | t]), do: Enum.all?(t, &(&1 == h))

  @doc """
  Returns the "energy" of a ternary configuration (count of non-zero states).

  Lower energy = more stable (more neutral states).

  ## Examples

      iex> TernaryState.energy([:zero, :zero, :zero])
      0

      iex> TernaryState.energy([:pos, :neg, :zero])
      2
  """
  @spec energy([ternary()]) :: non_neg_integer()
  def energy(states) when is_list(states) do
    Enum.count(states, &(&1 != :zero))
  end

  @doc """
  Computes local Ising energy for a center cell with neighbors.

  E = -J * Σ(s_center * s_neighbor) - h * s_center

  Where J is coupling strength and h is external field (bias).

  ## Options

  - `:coupling` - J value (default: 1.0)
  - `:bias` - h value / external field (default: 0.0)

  ## Examples

      iex> TernaryState.ising_energy(:pos, [:pos, :pos], coupling: 1.0)
      -2.0  # aligned neighbors = low energy

      iex> TernaryState.ising_energy(:pos, [:neg, :neg], coupling: 1.0)
      2.0  # anti-aligned = high energy
  """
  @spec ising_energy(ternary(), [ternary()], keyword()) :: float()
  def ising_energy(center, neighbors, opts \\ []) when is_list(neighbors) do
    j = Keyword.get(opts, :coupling, 1.0)
    h = Keyword.get(opts, :bias, 0.0)
    s_c = to_float(center)

    interaction_sum =
      neighbors
      |> Enum.map(&to_float/1)
      |> Enum.map(&(s_c * &1))
      |> Enum.sum()

    -j * interaction_sum - h * s_c
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Reversible Gates (Toffoli/Feynman)
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Feynman gate (CNOT) for ternary: target = (control + target) mod 3.

  Returns new target value. Control is unchanged.

  ## Examples

      iex> TernaryState.feynman(:pos, :zero)
      :pos  # 1 + 0 mod 3 = 1

      iex> TernaryState.feynman(:pos, :pos)
      :neg  # 1 + 1 mod 3 = 2 → -1 in balanced
  """
  @spec feynman(ternary(), ternary()) :: ternary()
  def feynman(control, target) do
    sum = to_balanced(control) + to_balanced(target)
    # Convert sum [0,1,2] or [-2,-1,0,1,2] to balanced [-1,0,1]
    balanced = Integer.mod(sum + 1, 3) - 1
    from_balanced(balanced)
  end

  @doc """
  Toffoli gate for ternary: target flips only if both controls are :pos.

  Returns {control1, control2, new_target}.

  ## Examples

      iex> TernaryState.toffoli(:pos, :pos, :zero)
      {:pos, :pos, :pos}  # both controls pos → target flips

      iex> TernaryState.toffoli(:pos, :neg, :zero)
      {:pos, :neg, :zero}  # not both pos → unchanged
  """
  @spec toffoli(ternary(), ternary(), ternary()) :: {ternary(), ternary(), ternary()}
  def toffoli(:pos, :pos, target), do: {:pos, :pos, ternary_neg(target)}
  def toffoli(c1, c2, target), do: {c1, c2, target}

  @doc """
  Fredkin gate (CSWAP) for ternary: swaps t1 and t2 if control is :pos.

  Returns {control, new_t1, new_t2}.

  ## Examples

      iex> TernaryState.fredkin(:pos, :neg, :zero)
      {:pos, :zero, :neg}  # swapped

      iex> TernaryState.fredkin(:neg, :neg, :zero)
      {:neg, :neg, :zero}  # unchanged
  """
  @spec fredkin(ternary(), ternary(), ternary()) :: {ternary(), ternary(), ternary()}
  def fredkin(:pos, t1, t2), do: {:pos, t2, t1}
  def fredkin(control, t1, t2), do: {control, t1, t2}

  # ═══════════════════════════════════════════════════════════════════════════
  # State Vector Operations (NCA compatibility)
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Converts a ternary state to a one-hot vector [neg, zero, pos].

  ## Examples

      iex> TernaryState.to_one_hot(:neg)
      [1.0, 0.0, 0.0]

      iex> TernaryState.to_one_hot(:pos)
      [0.0, 0.0, 1.0]
  """
  @spec to_one_hot(ternary()) :: [float()]
  def to_one_hot(:neg), do: [1.0, 0.0, 0.0]
  def to_one_hot(:zero), do: [0.0, 1.0, 0.0]
  def to_one_hot(:pos), do: [0.0, 0.0, 1.0]

  @doc """
  Converts a one-hot vector back to ternary (argmax).

  ## Examples

      iex> TernaryState.from_one_hot([0.1, 0.2, 0.7])
      :pos

      iex> TernaryState.from_one_hot([0.8, 0.1, 0.1])
      :neg
  """
  @spec from_one_hot([float()]) :: ternary()
  def from_one_hot([neg, zero, pos]) do
    cond do
      neg >= zero and neg >= pos -> :neg
      pos >= zero -> :pos
      true -> :zero
    end
  end

  @doc """
  Applies softmax-style probability to ternary choice.

  Given logits [neg_logit, zero_logit, pos_logit], samples ternary state.

  ## Options

  - `:temperature` - Softmax temperature (default: 1.0)
  - `:deterministic` - If true, returns argmax (default: false)
  """
  @spec sample([float()], keyword()) :: ternary()
  def sample([neg_logit, zero_logit, pos_logit], opts \\ []) do
    temp = Keyword.get(opts, :temperature, 1.0)
    deterministic = Keyword.get(opts, :deterministic, false)

    # Softmax
    scaled = [neg_logit / temp, zero_logit / temp, pos_logit / temp]
    max_logit = Enum.max(scaled)
    exp_vals = Enum.map(scaled, &:math.exp(&1 - max_logit))
    sum_exp = Enum.sum(exp_vals)
    probs = Enum.map(exp_vals, &(&1 / sum_exp))

    if deterministic do
      from_one_hot(probs)
    else
      # Sample from distribution
      r = :rand.uniform()
      [p_neg, p_zero, _p_pos] = probs

      cond do
        r < p_neg -> :neg
        r < p_neg + p_zero -> :zero
        true -> :pos
      end
    end
  end
end
