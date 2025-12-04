defmodule Thunderline.Thunderbolt.CerebrosFacade.Mini.Scorer do
  @moduledoc """
  Mock scoring model for Cerebros-mini MVP.

  Provides a deterministic scoring function that returns:
  - `score` (float 0-1): Overall health/priority score
  - `label` (atom): Categorical label (:low, :medium, :high, :critical)
  - `next_action` (atom | nil): Suggested action for the Thunderbit

  ## Scoring Algorithm

  The mock scorer combines feature values with simple thresholds:

  1. Base score from energy, salience, health
  2. Penalty for high age (stale bits)
  3. Penalty for deep chains (consolidation needed)
  4. Boost for active status

  ## Labels

  - `:critical` - Score < 0.2 (needs immediate attention)
  - `:low` - Score 0.2-0.4 (can wait)
  - `:medium` - Score 0.4-0.7 (normal)
  - `:high` - Score > 0.7 (priority processing)

  ## Suggested Actions

  - `nil` - No action needed
  - `:boost_energy` - Energy critically low
  - `:consolidate` - Chain depth too high
  - `:activate` - Pending bit ready for activation
  - `:retire` - Stale or unhealthy bit

  ## Usage

      {:ok, feature} = Feature.from_bit(bit)
      {:ok, result} = Scorer.infer(feature)
      # => {:ok, %{score: 0.72, label: :high, next_action: nil}}

  ## Architecture Note

  This is a mock implementation for MVP. The real Cerebros-mini will be:
  - A small Nx/Axon model (MLP or tiny transformer)
  - Loaded via ModelServer
  - Trained on trajectory data from BitChief
  """

  alias Thunderline.Thunderbolt.CerebrosFacade.Mini.Feature

  @type result :: %{
          score: float(),
          label: :low | :medium | :high | :critical,
          next_action: atom() | nil,
          confidence: float()
        }

  # Thresholds for label assignment
  @critical_threshold 0.2
  @low_threshold 0.4
  @medium_threshold 0.7

  # Feature weights (mock model "parameters")
  @weights %{
    energy: 0.30,
    salience: 0.20,
    health: 0.25,
    age_penalty: -0.10,
    chain_penalty: -0.10,
    status_bonus: 0.05
  }

  @doc """
  Performs inference on a Feature struct.

  Returns a scored result with label and suggested action.

  ## Parameters

  - `feature` - A `%Feature{}` struct from `Feature.from_bit/1`

  ## Returns

  - `{:ok, %{score: float, label: atom, next_action: atom | nil, confidence: float}}`
  - `{:error, reason}` if feature is invalid

  ## Example

      {:ok, feature} = Feature.from_bit(bit)
      {:ok, result} = Scorer.infer(feature)
      result.score     # => 0.65
      result.label     # => :medium
      result.next_action  # => nil
  """
  @spec infer(Feature.t()) :: {:ok, result()} | {:error, term()}
  def infer(%Feature{} = feature) do
    # Calculate base score from core features
    base_score = calculate_base_score(feature)

    # Apply penalties and bonuses
    adjusted_score = apply_adjustments(base_score, feature)

    # Clamp to [0, 1]
    final_score = max(0.0, min(1.0, adjusted_score))

    # Determine label
    label = score_to_label(final_score)

    # Determine suggested action
    next_action = suggest_action(feature, final_score, label)

    # Mock confidence (in real model, this comes from softmax or similar)
    confidence = calculate_confidence(final_score, feature)

    result = %{
      score: Float.round(final_score, 4),
      label: label,
      next_action: next_action,
      confidence: Float.round(confidence, 4)
    }

    {:ok, result}
  end

  def infer(_), do: {:error, :invalid_feature}

  @doc """
  Batch inference on multiple features.

  ## Parameters

  - `features` - List of `%Feature{}` structs

  ## Returns

  - `{:ok, [result, ...]}` - List of results in same order
  - `{:error, reason}` if any feature is invalid
  """
  @spec infer_batch([Feature.t()]) :: {:ok, [result()]} | {:error, term()}
  def infer_batch(features) when is_list(features) do
    results =
      Enum.reduce_while(features, [], fn feature, acc ->
        case infer(feature) do
          {:ok, result} -> {:cont, [result | acc]}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case results do
      {:error, _} = error -> error
      results -> {:ok, Enum.reverse(results)}
    end
  end

  @doc """
  Returns model metadata for diagnostics.
  """
  @spec model_info() :: map()
  def model_info do
    %{
      name: "cerebros-mini-mock",
      version: "0.1.0",
      type: :mock,
      input_dim: Feature.dimension(),
      output_labels: [:critical, :low, :medium, :high],
      weights: @weights,
      thresholds: %{
        critical: @critical_threshold,
        low: @low_threshold,
        medium: @medium_threshold
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Private: Score Calculation
  # ---------------------------------------------------------------------------

  defp calculate_base_score(feature) do
    # Weighted sum of core features
    feature.energy * @weights.energy +
      feature.salience * @weights.salience +
      feature.health * @weights.health
  end

  defp apply_adjustments(base_score, feature) do
    # Age penalty: older bits get penalized
    age_factor = feature.age_ticks / 10000.0
    age_penalty = min(age_factor, 1.0) * @weights.age_penalty

    # Chain depth penalty: deep chains need consolidation
    chain_factor = feature.chain_depth / 10.0
    chain_penalty = min(chain_factor, 1.0) * @weights.chain_penalty

    # Status bonus: active bits get slight boost
    status_bonus =
      case feature.status do
        :active -> @weights.status_bonus
        :pending -> @weights.status_bonus * 0.5
        _ -> 0.0
      end

    base_score + age_penalty + chain_penalty + status_bonus
  end

  defp score_to_label(score) do
    cond do
      score < @critical_threshold -> :critical
      score < @low_threshold -> :low
      score < @medium_threshold -> :medium
      true -> :high
    end
  end

  defp suggest_action(feature, score, label) do
    cond do
      # Critical energy - needs boost
      feature.energy < 0.15 ->
        :boost_energy

      # Deep chain - needs consolidation
      feature.chain_depth > 5 ->
        :consolidate

      # Very old and low score - retire
      feature.age_ticks > 5000 and score < 0.3 ->
        :retire

      # Pending with decent health - activate
      feature.status == :pending and feature.health > 0.5 ->
        :activate

      # Critical overall - flag for attention
      label == :critical ->
        :flag_for_review

      # No specific action needed
      true ->
        nil
    end
  end

  defp calculate_confidence(score, feature) do
    # Mock confidence: higher when features are decisive
    # In real model, this would come from prediction entropy

    # Higher confidence when score is far from thresholds
    distance_from_thresholds =
      [@critical_threshold, @low_threshold, @medium_threshold]
      |> Enum.map(&abs(score - &1))
      |> Enum.min()

    # Higher confidence when features are consistent
    feature_variance =
      [feature.energy, feature.salience, feature.health]
      |> variance()

    # Base confidence + distance bonus - variance penalty
    base = 0.6
    distance_bonus = distance_from_thresholds * 0.3
    variance_penalty = feature_variance * 0.2

    max(0.3, min(0.99, base + distance_bonus - variance_penalty))
  end

  defp variance(values) do
    n = length(values)

    if n < 2 do
      0.0
    else
      mean = Enum.sum(values) / n
      sq_diffs = Enum.map(values, fn v -> (v - mean) * (v - mean) end)
      Enum.sum(sq_diffs) / n
    end
  end
end
