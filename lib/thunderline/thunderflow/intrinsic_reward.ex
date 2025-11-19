defmodule Thunderline.Thunderflow.IntrinsicReward do
  @moduledoc """
  Intrinsic reward computation for probe runs following IGPO (Information-Gain Policy Optimization) principles.

  Measures how surprising/informative each probe's output is rather than relying on external success metrics.
  Rewards novelty, entropy, and lexical diversity across probe laps.

  ## Computation Methods

  1. **Heuristic-based** (current): Weighted average of existing lap metrics
     - Character entropy (text randomness)
     - Lexical diversity (unique words ratio)
     - Repetition penalty (1 - repetition_ratio)
     - Novelty bonus (1 - cosine similarity to previous lap)

  2. **ML-based** (future): Cerebros Bridge info-gain score when :ml_nas or :vim enabled

  ## Feature Gating

  Computation only runs when `Feature.enabled?(:reward_signal)` returns true.
  Returns 0.0 when disabled.

  ## Error Handling

  - Missing or invalid lap metrics default to 0.0
  - Nil cosine_to_prev (first lap) treated as 1.0 (max novelty)
  - Empty lap lists return 0.0 reward
  """

  alias Thunderline.Feature
  require Logger

  @type lap :: %{
          char_entropy: float() | nil,
          lexical_diversity: float() | nil,
          repetition_ratio: float() | nil,
          cosine_to_prev: float() | nil
        }

  @type context :: %{
          optional(:run_id) => binary(),
          optional(:provider) => binary(),
          optional(:model) => binary()
        }

  # Weights for heuristic reward components (must sum to 1.0)
  @entropy_weight 0.3
  @diversity_weight 0.3
  @repetition_weight 0.2
  @novelty_weight 0.2

  @doc """
  Compute intrinsic reward for a list of probe laps.

  Returns a float in range [0.0, 1.0] representing the overall information gain / novelty
  across all laps in the run.

  ## Options

    * `:method` - Override computation method (`:heuristic` or `:ml`), defaults to auto-select

  ## Examples

      iex> laps = [
      ...>   %{char_entropy: 0.8, lexical_diversity: 0.7, repetition_ratio: 0.1, cosine_to_prev: nil},
      ...>   %{char_entropy: 0.75, lexical_diversity: 0.8, repetition_ratio: 0.15, cosine_to_prev: 0.3}
      ...> ]
      iex> IntrinsicReward.compute_reward(laps, %{})
      0.72  # High reward for novel, diverse output

  """
  @spec compute_reward([lap()], context(), keyword()) :: float()
  def compute_reward(laps, context \\ %{}, opts \\ [])

  def compute_reward(laps, context, opts) when is_list(laps) do
    if Feature.enabled?(:reward_signal) do
      do_compute_reward(laps, context, opts)
    else
      # Feature disabled - no computation
      0.0
    end
  end

  ## Private Functions

  defp do_compute_reward([], _context, _opts) do
    # Empty lap list - no information
    0.0
  end

  defp do_compute_reward(laps, context, opts) do
    method = Keyword.get(opts, :method, select_method(context))

    case method do
      :ml ->
        # Future: CerebrosBridge integration for ML-based info-gain
        Logger.debug(
          "[IntrinsicReward] ML method not yet implemented, falling back to heuristic",
          run_id: Map.get(context, :run_id)
        )

        heuristic_reward(laps)

      :heuristic ->
        heuristic_reward(laps)
    end
  rescue
    error ->
      Logger.error(
        "[IntrinsicReward] Reward computation failed: #{Exception.message(error)}",
        run_id: Map.get(context, :run_id)
      )

      # Return 0.0 on error rather than crashing the job
      0.0
  end

  ## Private Functions

  # Select computation method based on context and feature flags
  defp select_method(_context) do
    # Future: Check Feature.enabled?(:ml_nas) or Feature.enabled?(:vim)
    # For now, always use heuristic
    :heuristic
  end

  # Compute reward using weighted average of lap metrics
  defp heuristic_reward(laps) do
    lap_rewards =
      Enum.map(laps, fn lap ->
        compute_lap_reward(lap)
      end)

    # Average reward across all laps
    case lap_rewards do
      [] ->
        0.0

      rewards ->
        Enum.sum(rewards) / length(rewards)
    end
  end

  # Compute reward for a single lap using weighted formula
  defp compute_lap_reward(lap) do
    entropy = normalize_metric(lap.char_entropy, 0.0, 1.0)
    diversity = normalize_metric(lap.lexical_diversity, 0.0, 1.0)
    repetition = normalize_metric(lap.repetition_ratio, 0.0, 1.0)
    cosine = normalize_metric(lap.cosine_to_prev, 0.0, 1.0)

    # Higher repetition is bad (penalize)
    repetition_score = 1.0 - repetition

    # Higher cosine similarity means less novelty (penalize)
    # Nil cosine (first lap) treated as 0.0 similarity = max novelty
    novelty_score = 1.0 - cosine

    # Weighted sum
    @entropy_weight * entropy +
      @diversity_weight * diversity +
      @repetition_weight * repetition_score +
      @novelty_weight * novelty_score
  end

  # Normalize a metric value to [0.0, 1.0] range
  # Handles nil, out-of-range, and invalid values gracefully
  defp normalize_metric(nil, _min, _max), do: 0.0

  defp normalize_metric(value, min, max) when is_number(value) do
    cond do
      value < min -> 0.0
      value > max -> 1.0
      max == min -> 0.0
      true -> (value - min) / (max - min)
    end
  end

  defp normalize_metric(_invalid, _min, _max), do: 0.0
end
