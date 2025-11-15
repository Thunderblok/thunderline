defmodule Thunderline.Thunderflow.IntrinsicRewardTest do
  @moduledoc """
  Unit tests for the IGPO intrinsic reward computation module.

  Tests cover:
  - Feature flag gating
  - Heuristic reward computation
  - Edge cases (empty laps, nil values, extreme values)
  - Normalization behavior
  - Error handling
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderflow.IntrinsicReward
  alias Thunderline.Feature

  setup do
    # Ensure feature is enabled for tests (can override per test)
    Feature.override(:reward_signal, true)

    on_exit(fn ->
      Feature.clear_override(:reward_signal)
    end)

    :ok
  end

  describe "compute_reward/3 with feature disabled" do
    setup do
      Feature.override(:reward_signal, false)
      :ok
    end

    test "returns 0.0 when feature flag is disabled" do
      laps = [
        %{
          char_entropy: 0.8,
          lexical_diversity: 0.7,
          repetition_ratio: 0.2,
          cosine_to_prev: nil
        }
      ]

      assert IntrinsicReward.compute_reward(laps, %{}) == 0.0
    end

    test "returns 0.0 for multiple laps when disabled" do
      laps = [
        %{char_entropy: 0.8, lexical_diversity: 0.7, repetition_ratio: 0.2, cosine_to_prev: nil},
        %{char_entropy: 0.7, lexical_diversity: 0.6, repetition_ratio: 0.3, cosine_to_prev: 0.4}
      ]

      assert IntrinsicReward.compute_reward(laps, %{}) == 0.0
    end
  end

  describe "compute_reward/3 with feature enabled" do
    test "returns 0.0 for empty lap list" do
      assert IntrinsicReward.compute_reward([], %{}) == 0.0
    end

    test "computes non-zero reward for single lap with high entropy" do
      laps = [
        %{
          char_entropy: 0.9,
          lexical_diversity: 0.8,
          repetition_ratio: 0.1,
          cosine_to_prev: nil
        }
      ]

      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward > 0.0
      assert reward <= 1.0
    end

    test "computes reward for single lap with moderate metrics" do
      laps = [
        %{
          char_entropy: 0.5,
          lexical_diversity: 0.5,
          repetition_ratio: 0.5,
          cosine_to_prev: nil
        }
      ]

      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward > 0.0
      assert reward <= 1.0
      # Moderate metrics should yield moderate reward
      assert reward >= 0.3 and reward <= 0.7
    end

    test "computes reward for single lap with low metrics (high repetition)" do
      laps = [
        %{
          char_entropy: 0.2,
          lexical_diversity: 0.2,
          repetition_ratio: 0.9,
          cosine_to_prev: nil
        }
      ]

      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward >= 0.0
      assert reward < 0.5
      # High repetition should lower reward
    end

    test "averages reward across multiple laps" do
      laps = [
        # First lap: high entropy, no cosine
        %{
          char_entropy: 0.9,
          lexical_diversity: 0.8,
          repetition_ratio: 0.1,
          cosine_to_prev: nil
        },
        # Second lap: moderate, some similarity to prev
        %{
          char_entropy: 0.6,
          lexical_diversity: 0.6,
          repetition_ratio: 0.3,
          cosine_to_prev: 0.5
        },
        # Third lap: lower entropy, more similarity
        %{
          char_entropy: 0.4,
          lexical_diversity: 0.5,
          repetition_ratio: 0.4,
          cosine_to_prev: 0.7
        }
      ]

      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward > 0.0
      assert reward <= 1.0

      # Should be somewhere between first and third lap rewards
      first_lap_reward = compute_single_lap_reward(Enum.at(laps, 0))
      third_lap_reward = compute_single_lap_reward(Enum.at(laps, 2))
      assert reward >= min(first_lap_reward, third_lap_reward)
      assert reward <= max(first_lap_reward, third_lap_reward)
    end

    test "handles nil cosine_to_prev for first lap" do
      laps = [
        %{
          char_entropy: 0.7,
          lexical_diversity: 0.6,
          repetition_ratio: 0.3,
          cosine_to_prev: nil
        }
      ]

      # Should not crash, cosine component should be 0.0
      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward > 0.0
    end

    test "handles nil entropy gracefully" do
      laps = [
        %{
          char_entropy: nil,
          lexical_diversity: 0.7,
          repetition_ratio: 0.2,
          cosine_to_prev: nil
        }
      ]

      # Should not crash, entropy component should be 0.0
      reward = IntrinsicReward.compute_reward(laps, %{})
      assert is_float(reward)
      assert reward >= 0.0
    end

    test "handles all nil metrics" do
      laps = [
        %{
          char_entropy: nil,
          lexical_diversity: nil,
          repetition_ratio: nil,
          cosine_to_prev: nil
        }
      ]

      # Should return 0.0 for all nil metrics
      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward == 0.0
    end

    test "handles out-of-range values (clamps to [0,1])" do
      laps = [
        %{
          char_entropy: 1.5,
          # >1.0 - should clamp to 1.0
          lexical_diversity: -0.2,
          # <0.0 - should clamp to 0.0
          repetition_ratio: 0.5,
          cosine_to_prev: nil
        }
      ]

      # Should not crash, normalization should clamp
      reward = IntrinsicReward.compute_reward(laps, %{})
      assert reward > 0.0
      assert reward <= 1.0
    end
  end

  describe "reward formula weights" do
    test "entropy contributes 30% to reward" do
      # High entropy, low everything else
      high_entropy_lap = %{
        char_entropy: 1.0,
        lexical_diversity: 0.0,
        repetition_ratio: 0.0,
        cosine_to_prev: nil
      }

      reward = IntrinsicReward.compute_reward([high_entropy_lap], %{})
      # Should be approximately 0.3 (30% weight for entropy)
      assert_in_delta(reward, 0.3, 0.05)
    end

    test "lexical diversity contributes 30% to reward" do
      # High diversity, low everything else
      high_diversity_lap = %{
        char_entropy: 0.0,
        lexical_diversity: 1.0,
        repetition_ratio: 0.0,
        cosine_to_prev: nil
      }

      reward = IntrinsicReward.compute_reward([high_diversity_lap], %{})
      # Should be approximately 0.3 (30% weight for diversity)
      assert_in_delta(reward, 0.3, 0.05)
    end

    test "repetition contributes 20% to reward (inverted)" do
      # Low repetition (high novelty), low everything else
      low_repetition_lap = %{
        char_entropy: 0.0,
        lexical_diversity: 0.0,
        repetition_ratio: 0.0,
        # No repetition
        cosine_to_prev: nil
      }

      reward = IntrinsicReward.compute_reward([low_repetition_lap], %{})
      # Should be approximately 0.2 (20% weight for 1-repetition)
      assert_in_delta(reward, 0.2, 0.05)
    end

    test "cosine similarity contributes 20% to reward (inverted)" do
      # Low similarity (high novelty), low everything else
      low_cosine_lap = %{
        char_entropy: 0.0,
        lexical_diversity: 0.0,
        repetition_ratio: 0.0,
        cosine_to_prev: 0.0
        # No similarity to previous
      }

      reward = IntrinsicReward.compute_reward([low_cosine_lap], %{})
      # Should be approximately 0.2 (20% weight for 1-cosine)
      assert_in_delta(reward, 0.2, 0.05)
    end

    test "perfect lap achieves reward close to 1.0" do
      # All metrics optimal (high entropy, diversity, low repetition, low cosine)
      perfect_lap = %{
        char_entropy: 1.0,
        lexical_diversity: 1.0,
        repetition_ratio: 0.0,
        cosine_to_prev: 0.0
      }

      reward = IntrinsicReward.compute_reward([perfect_lap], %{})
      # Should be close to 1.0 (sum of all weights)
      assert_in_delta(reward, 1.0, 0.05)
    end
  end

  describe "error handling" do
    test "handles malformed lap data gracefully" do
      # Lap missing required fields - should rescue and return 0.0
      malformed_laps = [%{some_field: "value"}]

      # Should not crash
      reward = IntrinsicReward.compute_reward(malformed_laps, %{})
      assert reward == 0.0
    end
  end

  ## Helper Functions

  # Computes reward for a single lap using the same formula
  defp compute_single_lap_reward(lap) do
    entropy = normalize_metric(lap.char_entropy, 0.0, 1.0)
    diversity = normalize_metric(lap.lexical_diversity, 0.0, 1.0)
    repetition = normalize_metric(lap.repetition_ratio, 0.0, 1.0)
    cosine = normalize_metric(lap.cosine_to_prev, 0.0, 1.0)

    repetition_score = 1.0 - repetition
    novelty_score = 1.0 - cosine

    0.3 * entropy + 0.3 * diversity + 0.2 * repetition_score + 0.2 * novelty_score
  end

  defp normalize_metric(nil, _min, _max), do: 0.0

  defp normalize_metric(value, min, max) when is_number(value) do
    cond do
      value < min -> 0.0
      value > max -> 1.0
      max == min -> 0.0
      true -> (value - min) / (max - min)
    end
  end
end
