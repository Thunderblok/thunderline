defmodule Thunderline.Thunderbolt.TAE.ValueFunction do
  @moduledoc """
  Quantitative value functions for Tree Automata Evaluation (TAE).

  Implements the complete set of value functions from the QuAK paper,
  mapping infinite runs to quantitative values.

  ## HC-Δ-17: QuAK Value Functions

  From the QuAK research:
  > "val: Σω → ℝ ∪ {∞}"

  The value of an infinite run is determined by the limit behavior
  of the weights along that run. Different value functions capture
  different aspects of the run's behavior.

  ## Value Functions Implemented

  | Function   | Formula                           | Use Case                |
  |------------|-----------------------------------|-------------------------|
  | Inf        | inf{wᵢ}                           | Worst-case guarantee    |
  | Sup        | sup{wᵢ}                           | Best achievable         |
  | LimInf     | lim inf wᵢ                        | Long-term lower bound   |
  | LimSup     | lim sup wᵢ                        | Long-term upper bound   |
  | LimInfAvg  | lim inf (Σwᵢ/n)                   | Sustained average min   |
  | LimSupAvg  | lim sup (Σwᵢ/n)                   | **Cerebros primary**    |
  | Sum        | Σwᵢ (may be ∞)                    | Total accumulated       |
  | Discount   | Σ λⁱwᵢ                            | RL-style discounting    |

  ## Thunderline Mapping

  - `wᵢ` = Thunderbit energy or criticality at step i
  - `run` = CA evolution trace
  - `value` = PAC reward or fitness metric

  ## Usage

      # Compute value for a weight sequence
      weights = [0.5, 0.8, 0.6, 0.7, 0.6, 0.7, ...]
      ValueFunction.lim_sup_avg(weights)

      # With cycle information (more efficient)
      cycle = Cycles.find_cycles(states)
      ValueFunction.from_cycle(cycle, :lim_sup_avg, weight_fn)
  """

  alias Thunderline.Thunderbolt.Cerebros.Cycles

  @type weights :: [float()] | Stream.t()
  @type value_type ::
          :inf
          | :sup
          | :lim_inf
          | :lim_sup
          | :lim_inf_avg
          | :lim_sup_avg
          | :sum
          | :discount

  # ═══════════════════════════════════════════════════════════════
  # Primary API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute a value function for a sequence of weights.

  ## Parameters

  - `weights` - Sequence of numeric weights
  - `type` - Value function type
  - `opts` - Options:
    - `:discount_factor` - λ for discount function (default: 0.99)
    - `:window_size` - For approximate streaming (default: 1000)

  ## Examples

      iex> ValueFunction.compute([1, 2, 3, 2, 3, 2, 3], :lim_sup_avg)
      2.5  # Cycle average

      iex> ValueFunction.compute([0.5, 0.8, 0.3], :sup)
      0.8
  """
  @spec compute(weights(), value_type(), keyword()) :: float() | :infinity | :neg_infinity
  def compute(weights, type, opts \\ [])

  def compute(weights, :inf, _opts), do: inf(weights)
  def compute(weights, :sup, _opts), do: sup(weights)
  def compute(weights, :lim_inf, opts), do: lim_inf(weights, opts)
  def compute(weights, :lim_sup, opts), do: lim_sup(weights, opts)
  def compute(weights, :lim_inf_avg, opts), do: lim_inf_avg(weights, opts)
  def compute(weights, :lim_sup_avg, opts), do: lim_sup_avg(weights, opts)
  def compute(weights, :sum, _opts), do: sum(weights)
  def compute(weights, :discount, opts), do: discount(weights, opts)

  @doc """
  Compute value from a detected cycle.

  More efficient than computing from raw weights when a cycle
  is known, since the cycle determines the limit behavior.
  """
  @spec from_cycle(Cycles.cycle(), value_type(), (term() -> float())) :: float()
  def from_cycle(cycle, type, weight_fn \\ fn _ -> 1.0 end) do
    stats = Cycles.cycle_stats(cycle, weight_fn)

    case type do
      :inf -> stats.cycle_min
      :sup -> stats.cycle_max
      :lim_inf -> stats.cycle_min
      :lim_sup -> stats.cycle_max
      :lim_inf_avg -> stats.cycle_avg
      :lim_sup_avg -> stats.cycle_avg
      :sum -> :infinity
      :discount -> stats.cycle_sum / (1 - 0.99)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Individual Value Functions
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Infimum: The minimum weight in the sequence.

  val(ρ) = inf{wᵢ : i ∈ ℕ}

  For infinite sequences with cycles, equals the cycle minimum.
  """
  @spec inf(weights()) :: float()
  def inf([]), do: :infinity
  def inf(weights), do: Enum.min(weights)

  @doc """
  Supremum: The maximum weight in the sequence.

  val(ρ) = sup{wᵢ : i ∈ ℕ}
  """
  @spec sup(weights()) :: float()
  def sup([]), do: :neg_infinity
  def sup(weights), do: Enum.max(weights)

  @doc """
  Limit Inferior: The greatest lower bound of tail subsequences.

  val(ρ) = lim inf wᵢ = lim_{n→∞} inf{wᵢ : i ≥ n}

  For ultimately periodic sequences, equals the minimum in the cycle.
  """
  @spec lim_inf(weights(), keyword()) :: float()
  def lim_inf([], _opts), do: :infinity

  def lim_inf(weights, opts) do
    window = Keyword.get(opts, :window_size, 1000)
    weights_list = Enum.take(weights, window)

    # For finite approximation, take minimum of latter portion
    tail_size = div(length(weights_list), 2)
    tail = Enum.take(weights_list, -tail_size)

    case tail do
      [] -> inf(weights_list)
      _ -> Enum.min(tail)
    end
  end

  @doc """
  Limit Superior: The least upper bound of tail subsequences.

  val(ρ) = lim sup wᵢ = lim_{n→∞} sup{wᵢ : i ≥ n}

  For ultimately periodic sequences, equals the maximum in the cycle.
  """
  @spec lim_sup(weights(), keyword()) :: float()
  def lim_sup([], _opts), do: :neg_infinity

  def lim_sup(weights, opts) do
    window = Keyword.get(opts, :window_size, 1000)
    weights_list = Enum.take(weights, window)

    tail_size = div(length(weights_list), 2)
    tail = Enum.take(weights_list, -tail_size)

    case tail do
      [] -> sup(weights_list)
      _ -> Enum.max(tail)
    end
  end

  @doc """
  Limit Inferior Average: Lower bound on long-run average.

  val(ρ) = lim inf_{n→∞} (1/n) Σᵢ₌₀ⁿ⁻¹ wᵢ

  For ultimately periodic sequences, equals the cycle average.
  """
  @spec lim_inf_avg(weights(), keyword()) :: float()
  def lim_inf_avg([], _opts), do: 0.0

  def lim_inf_avg(weights, opts) do
    window = Keyword.get(opts, :window_size, 1000)
    weights_list = Enum.take(weights, window)

    # Compute running averages and take minimum of latter portion
    running_avgs = compute_running_averages(weights_list)
    tail_size = div(length(running_avgs), 2)
    tail = Enum.take(running_avgs, -tail_size)

    case tail do
      [] -> Enum.sum(weights_list) / max(1, length(weights_list))
      _ -> Enum.min(tail)
    end
  end

  @doc """
  Limit Superior Average: Upper bound on long-run average.

  val(ρ) = lim sup_{n→∞} (1/n) Σᵢ₌₀ⁿ⁻¹ wᵢ

  **PRIMARY VALUE FUNCTION FOR CEREBROS**

  For ultimately periodic sequences, equals the cycle average.
  This is what determines the "fitness" of a CA evolution path.
  """
  @spec lim_sup_avg(weights(), keyword()) :: float()
  def lim_sup_avg([], _opts), do: 0.0

  def lim_sup_avg(weights, opts) do
    window = Keyword.get(opts, :window_size, 1000)
    weights_list = Enum.take(weights, window)

    running_avgs = compute_running_averages(weights_list)
    tail_size = div(length(running_avgs), 2)
    tail = Enum.take(running_avgs, -tail_size)

    case tail do
      [] -> Enum.sum(weights_list) / max(1, length(weights_list))
      _ -> Enum.max(tail)
    end
  end

  @doc """
  Sum: Total accumulated weight.

  val(ρ) = Σᵢ₌₀^∞ wᵢ

  May be infinite for non-converging sequences.
  """
  @spec sum(weights()) :: float() | :infinity
  def sum([]), do: 0.0

  def sum(weights) do
    # For finite sequences, just sum
    # For infinite, would need convergence check
    Enum.sum(weights)
  end

  @doc """
  Discounted Sum: RL-style discounted value.

  val(ρ) = Σᵢ₌₀^∞ λⁱ wᵢ

  where λ ∈ (0, 1) is the discount factor.

  Converges for any bounded weight sequence.
  """
  @spec discount(weights(), keyword()) :: float()
  def discount([], _opts), do: 0.0

  def discount(weights, opts) do
    lambda = Keyword.get(opts, :discount_factor, 0.99)

    weights
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {w, i}, acc ->
      acc + w * :math.pow(lambda, i)
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Streaming / Incremental Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Create a streaming value function accumulator.

  Useful for computing values incrementally as weights arrive.
  """
  @spec new_accumulator(value_type(), keyword()) :: map()
  def new_accumulator(type, opts \\ []) do
    %{
      type: type,
      count: 0,
      sum: 0.0,
      min: :infinity,
      max: :neg_infinity,
      running_avgs: [],
      discount_factor: Keyword.get(opts, :discount_factor, 0.99),
      discounted_sum: 0.0
    }
  end

  @doc """
  Add a weight to the accumulator.
  """
  @spec accumulate(map(), float()) :: map()
  def accumulate(acc, weight) do
    new_count = acc.count + 1
    new_sum = acc.sum + weight
    new_avg = new_sum / new_count

    %{
      acc
      | count: new_count,
        sum: new_sum,
        min: safe_min(acc.min, weight),
        max: safe_max(acc.max, weight),
        running_avgs: [new_avg | Enum.take(acc.running_avgs, 999)],
        discounted_sum: acc.discounted_sum + weight * :math.pow(acc.discount_factor, acc.count)
    }
  end

  @doc """
  Get current value from accumulator.
  """
  @spec current_value(map()) :: float()
  def current_value(%{type: :inf, min: min}), do: normalize_infinity(min)
  def current_value(%{type: :sup, max: max}), do: normalize_infinity(max)

  def current_value(%{type: :lim_inf, running_avgs: avgs}) do
    tail = Enum.take(avgs, div(length(avgs), 2))
    case tail do
      [] -> 0.0
      _ -> Enum.min(tail)
    end
  end

  def current_value(%{type: :lim_sup, running_avgs: avgs}) do
    tail = Enum.take(avgs, div(length(avgs), 2))
    case tail do
      [] -> 0.0
      _ -> Enum.max(tail)
    end
  end

  def current_value(%{type: :lim_inf_avg, running_avgs: avgs}) do
    tail = Enum.take(avgs, div(length(avgs), 2))
    case tail do
      [] -> 0.0
      _ -> Enum.min(tail)
    end
  end

  def current_value(%{type: :lim_sup_avg, running_avgs: avgs}) do
    tail = Enum.take(avgs, div(length(avgs), 2))
    case tail do
      [] -> 0.0
      _ -> Enum.max(tail)
    end
  end

  def current_value(%{type: :sum, sum: sum}), do: sum
  def current_value(%{type: :discount, discounted_sum: ds}), do: ds

  # ═══════════════════════════════════════════════════════════════
  # Comparison Operations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compare two weight sequences using a value function.

  Returns :gt, :lt, or :eq.
  """
  @spec compare(weights(), weights(), value_type(), keyword()) :: :gt | :lt | :eq
  def compare(weights1, weights2, type, opts \\ []) do
    v1 = compute(weights1, type, opts)
    v2 = compute(weights2, type, opts)

    cond do
      v1 > v2 -> :gt
      v1 < v2 -> :lt
      true -> :eq
    end
  end

  @doc """
  Select the better sequence according to a value function.
  """
  @spec select_best([weights()], value_type(), keyword()) :: {weights(), float()}
  def select_best(sequences, type, opts \\ []) do
    maximize? = type in [:sup, :lim_sup, :lim_sup_avg, :sum, :discount]

    sequences
    |> Enum.map(fn seq -> {seq, compute(seq, type, opts)} end)
    |> Enum.max_by(fn {_seq, val} ->
      if maximize?, do: val, else: -val
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════

  defp compute_running_averages(weights) do
    weights
    |> Enum.scan({0, 0.0}, fn w, {count, sum} ->
      {count + 1, sum + w}
    end)
    |> Enum.map(fn {count, sum} -> sum / count end)
  end

  defp normalize_infinity(:infinity), do: 0.0
  defp normalize_infinity(:neg_infinity), do: 0.0
  defp normalize_infinity(val), do: val

  defp safe_min(:infinity, b), do: b
  defp safe_min(a, :infinity), do: a
  defp safe_min(a, b), do: Kernel.min(a, b)

  defp safe_max(:neg_infinity, b), do: b
  defp safe_max(a, :neg_infinity), do: a
  defp safe_max(a, b), do: Kernel.max(a, b)
end
