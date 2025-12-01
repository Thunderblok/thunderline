defmodule Thunderline.Thundercrown.CurriculumRewardsTest do
  @moduledoc """
  Tests for Agent0-style curriculum rewards.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thundercrown.CurriculumRewards

  describe "uncertainty_reward/1" do
    test "maximum at 50% consistency" do
      reward = CurriculumRewards.uncertainty_reward(0.5)
      assert_in_delta reward, 1.0, 0.001
    end

    test "minimum at 0% consistency" do
      reward = CurriculumRewards.uncertainty_reward(0.0)
      assert_in_delta reward, 0.0, 0.001
    end

    test "minimum at 100% consistency" do
      reward = CurriculumRewards.uncertainty_reward(1.0)
      assert_in_delta reward, 0.0, 0.001
    end

    test "symmetric around 0.5" do
      reward_30 = CurriculumRewards.uncertainty_reward(0.3)
      reward_70 = CurriculumRewards.uncertainty_reward(0.7)
      assert_in_delta reward_30, reward_70, 0.001
    end
  end

  describe "compute_consistency/1" do
    test "returns 1.0 for unanimous responses" do
      consistency = CurriculumRewards.compute_consistency([:yes, :yes, :yes, :yes])
      assert_in_delta consistency, 1.0, 0.001
    end

    test "returns 0.5 for evenly split responses" do
      consistency = CurriculumRewards.compute_consistency([:yes, :yes, :no, :no])
      assert_in_delta consistency, 0.5, 0.001
    end

    test "returns 0.75 for 3:1 split" do
      consistency = CurriculumRewards.compute_consistency([:yes, :yes, :yes, :no])
      assert_in_delta consistency, 0.75, 0.001
    end

    test "returns 0.0 for empty list" do
      consistency = CurriculumRewards.compute_consistency([])
      assert_in_delta consistency, 0.0, 0.001
    end

    test "returns 1.0 for single response" do
      consistency = CurriculumRewards.compute_consistency([:answer])
      assert_in_delta consistency, 1.0, 0.001
    end
  end

  describe "tool_use_reward/2" do
    test "returns 0 for no tool calls" do
      reward = CurriculumRewards.tool_use_reward(0)
      assert_in_delta reward, 0.0, 0.001
    end

    test "returns gamma for max tool calls" do
      reward = CurriculumRewards.tool_use_reward(4, gamma: 0.6, cap: 4)
      assert_in_delta reward, 0.6, 0.001
    end

    test "caps at specified maximum" do
      reward_4 = CurriculumRewards.tool_use_reward(4, cap: 4)
      reward_10 = CurriculumRewards.tool_use_reward(10, cap: 4)
      assert_in_delta reward_4, reward_10, 0.001
    end

    test "scales linearly below cap" do
      reward_2 = CurriculumRewards.tool_use_reward(2, gamma: 1.0, cap: 4)
      assert_in_delta reward_2, 0.5, 0.001
    end
  end

  describe "in_frontier_band?/2" do
    test "returns true for 50% success rate" do
      assert CurriculumRewards.in_frontier_band?(0.5)
    end

    test "returns false for 10% success rate (too easy)" do
      refute CurriculumRewards.in_frontier_band?(0.1)
    end

    test "returns false for 90% success rate (too hard)" do
      refute CurriculumRewards.in_frontier_band?(0.9)
    end

    test "custom band works" do
      assert CurriculumRewards.in_frontier_band?(0.2, low: 0.1, high: 0.3)
      refute CurriculumRewards.in_frontier_band?(0.5, low: 0.1, high: 0.3)
    end
  end

  describe "repetition_penalty/3" do
    test "returns 0 for empty history" do
      embedding = [1.0, 0.0, 0.0]
      penalty = CurriculumRewards.repetition_penalty(embedding, [])
      assert_in_delta penalty, 0.0, 0.001
    end

    test "penalizes identical tasks" do
      embedding = [1.0, 0.0, 0.0]
      # Identical
      history = [[1.0, 0.0, 0.0]]
      penalty = CurriculumRewards.repetition_penalty(embedding, history, threshold: 0.9)
      assert penalty > 0.0
    end

    test "no penalty for orthogonal tasks" do
      embedding = [1.0, 0.0, 0.0]
      # Orthogonal
      history = [[0.0, 1.0, 0.0]]
      penalty = CurriculumRewards.repetition_penalty(embedding, history)
      assert_in_delta penalty, 0.0, 0.001
    end

    test "applies decay to older tasks" do
      embedding = [1.0, 0.0, 0.0]
      # Use a slightly different embedding that's still similar (0.95 cosine sim)
      # [1.0, 0.0, 0.0] · [0.95, 0.31, 0.0] ≈ 0.95
      # normalized to unit length
      similar_1 = [0.95, 0.31224989991991996, 0.0]
      similar_2 = [0.95, 0.31224989991991996, 0.0]

      history_1 = [similar_1]
      history_2 = [similar_1, similar_2]

      penalty_1 = CurriculumRewards.repetition_penalty(embedding, history_1, threshold: 0.9)
      penalty_2 = CurriculumRewards.repetition_penalty(embedding, history_2, threshold: 0.9)

      # Second penalty should be higher (adds decayed second match)
      assert penalty_2 > penalty_1
      # But less than double (due to decay of 0.9^1 = 0.9 for second item)
      assert penalty_2 < penalty_1 * 2
    end
  end

  describe "curriculum_reward/2" do
    test "combines all components" do
      metrics = %{
        # Max uncertainty
        consistency_score: 0.5,
        # Half of default cap
        tool_calls: 2
      }

      reward = CurriculumRewards.curriculum_reward(metrics)

      # Should be positive (uncertainty + tool use)
      assert reward > 0.0
    end

    test "respects weight parameters" do
      metrics = %{consistency_score: 0.5, tool_calls: 0}

      reward_alpha_1 = CurriculumRewards.curriculum_reward(metrics, alpha: 1.0)
      reward_alpha_2 = CurriculumRewards.curriculum_reward(metrics, alpha: 2.0)

      # Doubling alpha should double the uncertainty component
      assert_in_delta reward_alpha_2, reward_alpha_1 * 2, 0.001
    end
  end

  describe "ambiguity_scaled_advantage/2" do
    test "scales advantage by consistency" do
      scaled = CurriculumRewards.ambiguity_scaled_advantage(1.0, 0.5)
      assert_in_delta scaled, 0.5, 0.001
    end

    test "zero advantage with zero consistency" do
      scaled = CurriculumRewards.ambiguity_scaled_advantage(1.0, 0.0)
      assert_in_delta scaled, 0.0, 0.001
    end
  end

  describe "dynamic_clip_bound/2" do
    test "higher bound for lower consistency" do
      bound_low = CurriculumRewards.dynamic_clip_bound(0.3)
      bound_high = CurriculumRewards.dynamic_clip_bound(0.9)

      assert bound_low > bound_high
    end

    test "respects base and bonus parameters" do
      bound = CurriculumRewards.dynamic_clip_bound(0.5, eps_base: 0.1, eps_bonus: 0.4)
      # 0.1 + (1 - 0.5) * 0.4 = 0.1 + 0.2 = 0.3
      assert_in_delta bound, 0.3, 0.001
    end
  end

  describe "rank_tasks/2" do
    test "ranks by descending reward" do
      tasks = [
        # High reward
        {:task_a, %{consistency_score: 0.5, tool_calls: 4}},
        # Low reward
        {:task_b, %{consistency_score: 1.0, tool_calls: 0}},
        # Medium reward
        {:task_c, %{consistency_score: 0.6, tool_calls: 2}}
      ]

      ranked = CurriculumRewards.rank_tasks(tasks)

      # Extract task names in order
      task_order = Enum.map(ranked, fn {task, _reward} -> task end)

      # task_a should be first (highest reward)
      assert hd(task_order) == :task_a
    end
  end
end
