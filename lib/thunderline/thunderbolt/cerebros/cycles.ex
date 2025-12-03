defmodule Thunderline.Thunderbolt.Cerebros.Cycles do
  @moduledoc """
  Cycle detection for CA state sequences.

  Implements Floyd's tortoise-and-hare algorithm and Brent's improvement
  for detecting cycles in potentially infinite CA evolution traces.

  ## HC-Δ-15: Cerebros CA Proposal Requirement

  From the original Cerebros proposal:
  > "find_cycles(sequence) → cycle list"

  ## QuAK Integration

  From the QuAK paper analysis:
  > "Everything reduces to two primitives: Inclusion checking and Top-value computation"

  Cycle detection is fundamental to both: cycles determine the ultimate
  periodic behavior that dominates limit computations.

  For quantitative automata:
  - Cycles determine the LimInf and LimSup values
  - Cycle averages determine LimSupAvg (critical for Cerebros)
  - Top value computation requires finding optimal reachable cycles

  ## Usage

      # Detect cycles in a CA trace
      {:ok, cycle} = Cycles.find_cycles(state_sequence)

      # Get cycle statistics for value function computation
      stats = Cycles.cycle_stats(cycle, weight_fn)

      # Use Brent's algorithm for step-by-step detection
      {:ok, cycle} = Cycles.find_cycles_brent(initial_state, &next_state/1)

  ## Performance

  - Floyd's algorithm: O(μ + λ) time, O(1) space
  - Brent's algorithm: O(μ + λ) time, O(1) space (faster constant factor)
  - Sequence-based: O(n) time, O(n) space for n states

  Where μ = prefix length, λ = cycle length.
  """

  @type state :: term()
  @type cycle :: %{
          prefix_length: non_neg_integer(),
          cycle_start: non_neg_integer(),
          cycle_length: pos_integer(),
          cycle_states: [state()]
        }

  @type weight_fn :: (state() -> float())

  # ═══════════════════════════════════════════════════════════════
  # Primary API: Find Cycles in Sequences
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Find cycles in a sequence of states.

  Uses indexed lookup for O(n) detection on pre-computed sequences.

  ## Parameters

  - `sequence` - List of states to analyze

  ## Returns

  - `{:ok, cycle}` - A cycle was detected
  - `:no_cycle` - No repetition found in the sequence

  ## Examples

      iex> Cycles.find_cycles([1, 2, 3, 2, 3, 2, 3])
      {:ok, %{prefix_length: 1, cycle_start: 1, cycle_length: 2, cycle_states: [2, 3]}}

      iex> Cycles.find_cycles([1, 2, 3, 4, 5])
      :no_cycle
  """
  @spec find_cycles([state()]) :: {:ok, cycle()} | :no_cycle
  def find_cycles([]), do: :no_cycle
  def find_cycles([_]), do: :no_cycle

  def find_cycles(sequence) when is_list(sequence) do
    # Build state -> indices map
    indexed =
      sequence
      |> Enum.with_index()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # Find first repeated state
    repeated =
      indexed
      |> Enum.filter(fn {_state, indices} -> length(indices) > 1 end)
      |> Enum.sort_by(fn {_state, [first_idx | _]} -> first_idx end)

    case repeated do
      [] ->
        :no_cycle

      [{_state, [first_idx | [second_idx | _]]} | _] ->
        cycle_length = second_idx - first_idx
        cycle_states = Enum.slice(sequence, first_idx, cycle_length)

        {:ok,
         %{
           prefix_length: first_idx,
           cycle_start: first_idx,
           cycle_length: cycle_length,
           cycle_states: cycle_states
         }}
    end
  end

  @doc """
  Find all cycles in a sequence.

  Returns all detected cycles ordered by first occurrence.
  """
  @spec find_all_cycles([state()]) :: [cycle()]
  def find_all_cycles(sequence) when is_list(sequence) do
    indexed =
      sequence
      |> Enum.with_index()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    indexed
    |> Enum.filter(fn {_state, indices} -> length(indices) > 1 end)
    |> Enum.map(fn {_state, [first_idx | [second_idx | _]]} ->
      cycle_length = second_idx - first_idx

      %{
        prefix_length: first_idx,
        cycle_start: first_idx,
        cycle_length: cycle_length,
        cycle_states: Enum.slice(sequence, first_idx, cycle_length)
      }
    end)
    |> Enum.sort_by(& &1.prefix_length)
  end

  # ═══════════════════════════════════════════════════════════════
  # Brent's Algorithm: For Iterative State Generation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Find cycles using Brent's algorithm.

  More efficient than Floyd's for iterative state generation.
  Good when you have a `next_fn` that computes the next state.

  ## Parameters

  - `initial` - Starting state
  - `next_fn` - Function to compute next state: `state -> state`
  - `opts` - Options:
    - `:max_iter` - Maximum iterations (default: 10_000)

  ## Returns

  - `{:ok, cycle}` - A cycle was detected
  - `:no_cycle` - No cycle found within iteration limit

  ## Example

      # Detect cycle in CA evolution
      initial_grid = CA.Grid.random(100, 100)
      next_fn = fn grid -> CA.Stepper.next(grid, :game_of_life_3d) end

      {:ok, cycle} = Cycles.find_cycles_brent(initial_grid, next_fn)
  """
  @spec find_cycles_brent(state(), (state() -> state()), keyword()) ::
          {:ok, cycle()} | :no_cycle
  def find_cycles_brent(initial, next_fn, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iter, 10_000)

    # Brent's algorithm: Phase 1 - Find cycle length (lambda)
    case find_cycle_length(initial, next_fn.(initial), next_fn, 1, 1, max_iter) do
      {:found, lambda, _hare} ->
        # Phase 2: Find cycle start (mu)
        mu = find_cycle_start(initial, lambda, next_fn)

        # Extract cycle states
        cycle_start_state = advance(initial, next_fn, mu)
        cycle_states = extract_cycle_states(cycle_start_state, next_fn, lambda)

        {:ok,
         %{
           prefix_length: mu,
           cycle_start: mu,
           cycle_length: lambda,
           cycle_states: cycle_states
         }}

      :not_found ->
        :no_cycle
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Floyd's Algorithm: Classic Tortoise and Hare
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Find cycles using Floyd's tortoise-and-hare algorithm.

  Classic algorithm with guaranteed O(1) space complexity.

  ## Parameters

  - `initial` - Starting state
  - `next_fn` - Function to compute next state
  - `opts` - Options:
    - `:max_iter` - Maximum iterations (default: 10_000)
  """
  @spec find_cycles_floyd(state(), (state() -> state()), keyword()) ::
          {:ok, cycle()} | :no_cycle
  def find_cycles_floyd(initial, next_fn, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iter, 10_000)

    # Phase 1: Find meeting point
    case floyd_find_meeting(initial, initial, next_fn, max_iter) do
      {:found, meeting} ->
        # Phase 2: Find cycle start (mu)
        mu = floyd_find_start(initial, meeting, next_fn)

        # Phase 3: Find cycle length (lambda)
        lambda = floyd_find_length(meeting, next_fn)

        # Extract cycle states
        cycle_start_state = advance(initial, next_fn, mu)
        cycle_states = extract_cycle_states(cycle_start_state, next_fn, lambda)

        {:ok,
         %{
           prefix_length: mu,
           cycle_start: mu,
           cycle_length: lambda,
           cycle_states: cycle_states
         }}

      :not_found ->
        :no_cycle
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Cycle Statistics for Value Functions
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute statistics for a detected cycle.

  These statistics are used by TAE value functions to compute
  LimInf, LimSup, and LimSupAvg values.

  ## Parameters

  - `cycle` - Detected cycle from find_cycles
  - `weight_fn` - Function mapping state to weight (default: constant 1.0)

  ## Returns

  Map with cycle statistics suitable for value computation.
  """
  @spec cycle_stats(cycle(), weight_fn()) :: map()
  def cycle_stats(cycle, weight_fn \\ fn _ -> 1.0 end) do
    weights = Enum.map(cycle.cycle_states, weight_fn)

    %{
      cycle_length: cycle.cycle_length,
      prefix_length: cycle.prefix_length,
      cycle_sum: Enum.sum(weights),
      cycle_avg: safe_mean(weights),
      cycle_min: Enum.min(weights, fn -> 0.0 end),
      cycle_max: Enum.max(weights, fn -> 0.0 end),
      weights: weights
    }
  end

  @doc """
  Check if a sequence is ultimately periodic.
  """
  @spec ultimately_periodic?([state()]) :: boolean()
  def ultimately_periodic?(sequence) do
    case find_cycles(sequence) do
      {:ok, _} -> true
      :no_cycle -> false
    end
  end

  @doc """
  Compute the eventual value for a cycle with given value function.

  For limit functions, the cycle's contribution dominates.
  """
  @spec eventual_value(cycle(), weight_fn(), atom()) :: float()
  def eventual_value(cycle, weight_fn, value_type \\ :lim_sup_avg) do
    stats = cycle_stats(cycle, weight_fn)

    case value_type do
      :lim_inf -> stats.cycle_min
      :lim_sup -> stats.cycle_max
      :lim_inf_avg -> stats.cycle_avg
      :lim_sup_avg -> stats.cycle_avg
      :sum -> :infinity
      _ -> stats.cycle_avg
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Private: Brent's Algorithm Implementation
  # ═══════════════════════════════════════════════════════════════

  defp find_cycle_length(_tortoise, _hare, _next_fn, _power, _lambda, 0) do
    :not_found
  end

  defp find_cycle_length(tortoise, hare, next_fn, power, lambda, remaining) do
    cond do
      tortoise == hare ->
        {:found, lambda, hare}

      power == lambda ->
        # Increase power, reset lambda, move tortoise to hare
        find_cycle_length(hare, next_fn.(hare), next_fn, power * 2, 1, remaining - 1)

      true ->
        find_cycle_length(tortoise, next_fn.(hare), next_fn, power, lambda + 1, remaining - 1)
    end
  end

  defp find_cycle_start(initial, lambda, next_fn) do
    tortoise = initial
    hare = advance(initial, next_fn, lambda)
    find_mu(tortoise, hare, next_fn, 0)
  end

  defp find_mu(tortoise, hare, _next_fn, mu) when tortoise == hare, do: mu

  defp find_mu(tortoise, hare, next_fn, mu) do
    find_mu(next_fn.(tortoise), next_fn.(hare), next_fn, mu + 1)
  end

  # ═══════════════════════════════════════════════════════════════
  # Private: Floyd's Algorithm Implementation
  # ═══════════════════════════════════════════════════════════════

  defp floyd_find_meeting(_tortoise, _hare, _next_fn, 0), do: :not_found

  defp floyd_find_meeting(tortoise, hare, next_fn, remaining) do
    new_tortoise = next_fn.(tortoise)
    new_hare = next_fn.(next_fn.(hare))

    cond do
      new_tortoise == new_hare -> {:found, new_tortoise}
      true -> floyd_find_meeting(new_tortoise, new_hare, next_fn, remaining - 1)
    end
  end

  defp floyd_find_start(tortoise, hare, next_fn) do
    if tortoise == hare do
      0
    else
      1 + floyd_find_start(next_fn.(tortoise), next_fn.(hare), next_fn)
    end
  end

  defp floyd_find_length(meeting, next_fn) do
    count_until_return(next_fn.(meeting), meeting, next_fn, 1)
  end

  defp count_until_return(current, target, _next_fn, count) when current == target, do: count

  defp count_until_return(current, target, next_fn, count) do
    count_until_return(next_fn.(current), target, next_fn, count + 1)
  end

  # ═══════════════════════════════════════════════════════════════
  # Private: Shared Helpers
  # ═══════════════════════════════════════════════════════════════

  defp advance(state, _next_fn, 0), do: state
  defp advance(state, next_fn, n), do: advance(next_fn.(state), next_fn, n - 1)

  defp extract_cycle_states(start_state, next_fn, length) do
    do_extract(start_state, next_fn, length, [])
  end

  defp do_extract(_state, _next_fn, 0, acc), do: Enum.reverse(acc)

  defp do_extract(state, next_fn, remaining, acc) do
    do_extract(next_fn.(state), next_fn, remaining - 1, [state | acc])
  end

  defp safe_mean([]), do: 0.0
  defp safe_mean(list), do: Enum.sum(list) / length(list)
end
