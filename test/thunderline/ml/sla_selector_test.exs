defmodule Thunderline.ML.SLASelectorTest do
  use ExUnit.Case, async: true

  alias Thunderline.ML.SLASelector

  describe "init/2" do
    test "initializes with uniform probabilities" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Each action should have probability 1/3
      assert map_size(sla.probabilities) == 3
      assert_in_delta sla.probabilities[:model_a], 0.333333, 0.001
      assert_in_delta sla.probabilities[:model_b], 0.333333, 0.001
      assert_in_delta sla.probabilities[:model_c], 0.333333, 0.001

      # Sum should be 1.0
      total = sla.probabilities |> Map.values() |> Enum.sum()
      assert_in_delta total, 1.0, 1.0e-10
    end

    test "accepts custom learning rates" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions, alpha: 0.2, v: 0.1)

      assert sla.alpha == 0.2
      assert sla.v == 0.1
    end

    test "validates alpha is in (0, 1]" do
      actions = [:model_a, :model_b]

      assert_raise ArgumentError, ~r/alpha must be in \(0, 1\]/, fn ->
        SLASelector.init(actions, alpha: 0.0)
      end

      assert_raise ArgumentError, ~r/alpha must be in \(0, 1\]/, fn ->
        SLASelector.init(actions, alpha: 1.5)
      end
    end

    test "validates v is in (0, 1]" do
      actions = [:model_a, :model_b]

      assert_raise ArgumentError, ~r/v must be in \(0, 1\]/, fn ->
        SLASelector.init(actions, v: -0.1)
      end

      assert_raise ArgumentError, ~r/v must be in \(0, 1\]/, fn ->
        SLASelector.init(actions, v: 2.0)
      end
    end

    test "initializes all struct fields" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      assert sla.actions == actions
      assert sla.iteration == 0
      assert sla.reward_history == []
      assert sla.last_distance == nil
      assert sla.best_action == nil
    end
  end

  describe "choose_action/2" do
    test "greedy strategy chooses action with max probability" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Manually set unequal probabilities
      sla = %{sla | probabilities: %{model_a: 0.1, model_b: 0.7, model_c: 0.2}}

      {updated_sla, action} = SLASelector.choose_action(sla, strategy: :greedy)

      assert action == :model_b  # Has highest probability (0.7)
      assert updated_sla.iteration == 1
    end

    test "sample strategy respects probability distribution (statistical)" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Set skewed probabilities
      sla = %{sla | probabilities: %{model_a: 0.8, model_b: 0.15, model_c: 0.05}}

      # Sample 1000 times and check distribution
      samples =
        Enum.map(1..1000, fn _ ->
          {_sla, action} = SLASelector.choose_action(sla, strategy: :sample)
          action
        end)

      freq_a = Enum.count(samples, &(&1 == :model_a))
      freq_b = Enum.count(samples, &(&1 == :model_b))
      freq_c = Enum.count(samples, &(&1 == :model_c))

      # Should approximately match probabilities (allow 10% margin)
      assert freq_a > 700  # ~80% of 1000
      assert freq_b > 100  # ~15% of 1000
      assert freq_c > 20   # ~5% of 1000
    end

    test "defaults to sample strategy" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      # Without strategy option, should default to :sample
      {updated_sla, action} = SLASelector.choose_action(sla)

      assert action in actions
      assert updated_sla.iteration == 1
    end

    test "validates unknown strategy" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      assert_raise ArgumentError, ~r/Unknown strategy/, fn ->
        SLASelector.choose_action(sla, strategy: :unknown)
      end
    end

    test "increments iteration counter" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      {sla, _} = SLASelector.choose_action(sla)
      assert sla.iteration == 1

      {sla, _} = SLASelector.choose_action(sla)
      assert sla.iteration == 2

      {sla, _} = SLASelector.choose_action(sla)
      assert sla.iteration == 3
    end
  end

  describe "update/3 reward path (distance improved)" do
    test "reward increases chosen action probability" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, alpha: 0.1)

      # All start at ~0.333
      initial_prob = sla.probabilities[:model_a]

      # Reward model_a
      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)

      # model_a probability should increase
      assert sla.probabilities[:model_a] > initial_prob
    end

    test "reward decreases other action probabilities" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, alpha: 0.1)

      initial_prob_b = sla.probabilities[:model_b]
      initial_prob_c = sla.probabilities[:model_c]

      # Reward model_a
      sla = SLASelector.update(sla, :model_a, 1)

      # Others should decrease
      assert sla.probabilities[:model_b] < initial_prob_b
      assert sla.probabilities[:model_c] < initial_prob_c
    end

    test "reward update preserves probability sum = 1.0" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Apply multiple rewards
      sla = SLASelector.update(sla, :model_a, 1)
      assert_probability_sum(sla)

      sla = SLASelector.update(sla, :model_a, 1)
      assert_probability_sum(sla)

      sla = SLASelector.update(sla, :model_b, 1)
      assert_probability_sum(sla)
    end

    test "repeated rewards converge probability to 1.0" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, alpha: 0.1)

      # Reward model_a 50 times
      sla =
        Enum.reduce(1..50, sla, fn _, acc ->
          SLASelector.update(acc, :model_a, 1)
        end)

      # model_a should dominate
      assert sla.probabilities[:model_a] > 0.9
      assert sla.probabilities[:model_b] < 0.1
      assert sla.probabilities[:model_c] < 0.1
      assert_probability_sum(sla)
    end
  end

  describe "update/3 penalty path (distance worsened)" do
    test "penalty decreases chosen action probability" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, v: 0.05)

      initial_prob = sla.probabilities[:model_a]

      # Penalize model_a
      sla = SLASelector.update(sla, :model_a, 0, distance: 1.5)

      # model_a probability should decrease
      assert sla.probabilities[:model_a] < initial_prob
    end

    test "penalty increases other action probabilities" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, v: 0.05)

      initial_prob_b = sla.probabilities[:model_b]
      initial_prob_c = sla.probabilities[:model_c]

      # Penalize model_a
      sla = SLASelector.update(sla, :model_a, 0)

      # Others should increase
      assert sla.probabilities[:model_b] > initial_prob_b
      assert sla.probabilities[:model_c] > initial_prob_c
    end

    test "penalty update preserves probability sum = 1.0" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Apply multiple penalties
      sla = SLASelector.update(sla, :model_a, 0)
      assert_probability_sum(sla)

      sla = SLASelector.update(sla, :model_a, 0)
      assert_probability_sum(sla)

      sla = SLASelector.update(sla, :model_b, 0)
      assert_probability_sum(sla)
    end

    test "repeated penalties converge probability to 0.0" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, v: 0.05)

      # Penalize model_a 50 times
      sla =
        Enum.reduce(1..50, sla, fn _, acc ->
          SLASelector.update(acc, :model_a, 0)
        end)

      # model_a should be very low
      assert sla.probabilities[:model_a] < 0.1
      # Others should be higher (shared uniformly)
      assert sla.probabilities[:model_b] > 0.4
      assert sla.probabilities[:model_c] > 0.4
      assert_probability_sum(sla)
    end
  end

  describe "update/3 metadata tracking" do
    test "updates reward history" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      assert sla.reward_history == []

      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)

      assert length(sla.reward_history) == 1
      {action, reward, distance, _timestamp} = hd(sla.reward_history)
      assert action == :model_a
      assert reward == 1
      assert distance == 0.5
    end

    test "limits reward history to 100 entries" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      # Add 150 updates
      sla =
        Enum.reduce(1..150, sla, fn i, acc ->
          SLASelector.update(acc, :model_a, rem(i, 2), distance: i * 0.1)
        end)

      # Should only keep last 100
      assert length(sla.reward_history) == 100
    end

    test "updates last_distance" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      sla = SLASelector.update(sla, :model_a, 1, distance: 0.42)
      assert sla.last_distance == 0.42

      sla = SLASelector.update(sla, :model_b, 0, distance: 0.88)
      assert sla.last_distance == 0.88
    end

    test "updates best_action" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Reward model_b heavily
      sla = SLASelector.update(sla, :model_b, 1)
      sla = SLASelector.update(sla, :model_b, 1)
      sla = SLASelector.update(sla, :model_b, 1)

      assert sla.best_action == :model_b
    end

    test "validates action is known" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      assert_raise ArgumentError, ~r/unknown action/, fn ->
        SLASelector.update(sla, :unknown_model, 1)
      end
    end
  end

  describe "probabilities/1" do
    test "returns current probability distribution" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      probs = SLASelector.probabilities(sla)

      assert probs == sla.probabilities
      assert map_size(probs) == 2
    end
  end

  describe "converged?/2" do
    test "returns false for uniform distribution" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      refute SLASelector.converged?(sla)
    end

    test "returns true when max probability exceeds threshold" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      # Manually set high probability
      sla = %{sla | probabilities: %{model_a: 0.9, model_b: 0.05, model_c: 0.05}}

      assert SLASelector.converged?(sla)  # Default threshold 0.85
    end

    test "respects custom threshold" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      sla = %{sla | probabilities: %{model_a: 0.8, model_b: 0.1, model_c: 0.1}}

      refute SLASelector.converged?(sla, threshold: 0.85)  # 0.8 < 0.85
      assert SLASelector.converged?(sla, threshold: 0.75)  # 0.8 > 0.75
    end
  end

  describe "state/1" do
    test "returns complete introspection" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)
      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)

      state = SLASelector.state(sla)

      assert state.probabilities == sla.probabilities
      assert state.iteration == 0  # update no longer increments iteration
      assert state.best_action == :model_a
      assert state.best_probability > 0.33
      assert state.convergence >= 0.0 and state.convergence <= 1.0
      assert state.entropy >= 0.0
      assert state.last_distance == 0.5
    end

    test "entropy is maximum for uniform distribution" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions)

      state = SLASelector.state(sla)

      # log2(3) ≈ 1.585
      assert_in_delta state.entropy, 1.585, 0.01
      assert_in_delta state.max_entropy, 1.585, 0.01
      # Convergence should be near 0 (max entropy = uniform)
      assert_in_delta state.convergence, 0.0, 0.05
    end

    test "entropy decreases as distribution converges" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, alpha: 0.2)

      initial_state = SLASelector.state(sla)

      # Apply multiple rewards to model_a
      sla =
        Enum.reduce(1..20, sla, fn _, acc ->
          SLASelector.update(acc, :model_a, 1)
        end)

      converged_state = SLASelector.state(sla)

      # Entropy should decrease
      assert converged_state.entropy < initial_state.entropy
      # Convergence metric should increase
      assert converged_state.convergence > initial_state.convergence
    end
  end

  describe "snapshot/1 and from_snapshot/1" do
    test "round-trip preserves key state" do
      actions = [:model_a, :model_b, :model_c]
      sla = SLASelector.init(actions, alpha: 0.15, v: 0.08)

      # Evolve the SLA
      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)
      sla = SLASelector.update(sla, :model_a, 1, distance: 0.4)
      sla = SLASelector.update(sla, :model_b, 0, distance: 0.6)

      # Take snapshot
      snapshot = SLASelector.snapshot(sla)

      # Restore from snapshot
      restored = SLASelector.from_snapshot(snapshot)

      # Compare key fields
      assert restored.actions == sla.actions
      assert restored.probabilities == sla.probabilities
      assert restored.alpha == sla.alpha
      assert restored.v == sla.v
      assert restored.best_action == sla.best_action
      assert restored.last_distance == sla.last_distance
      # Note: iteration NOT preserved in snapshot (design choice)
    end

    test "snapshot excludes reward_history" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)
      sla = SLASelector.update(sla, :model_b, 1, distance: 0.3)

      snapshot = SLASelector.snapshot(sla)

      # reward_history should NOT be in snapshot
      refute Map.has_key?(snapshot, :reward_history)
    end

    test "from_snapshot resets reward_history" do
      actions = [:model_a, :model_b]
      sla = SLASelector.init(actions)

      sla = SLASelector.update(sla, :model_a, 1, distance: 0.5)
      snapshot = SLASelector.snapshot(sla)

      restored = SLASelector.from_snapshot(snapshot)

      # Restored SLA should have empty history
      assert restored.reward_history == []
    end
  end

  describe "integration scenario" do
    test "realistic learning scenario with alternating rewards/penalties" do
      actions = [:model_k1, :model_k2, :model_k3]
      sla = SLASelector.init(actions, alpha: 0.1, v: 0.05)

      # Simulate: model_k2 is best, but we explore initially
      scenario = [
        {:model_k1, 0, 1.5},  # Try k1, bad (penalty)
        {:model_k3, 0, 1.8},  # Try k3, bad (penalty)
        {:model_k2, 1, 0.3},  # Try k2, good! (reward)
        {:model_k2, 1, 0.25}, # k2 again, good! (reward)
        {:model_k1, 0, 1.6},  # Try k1 again, still bad
        {:model_k2, 1, 0.22}, # k2 again, good!
        {:model_k2, 1, 0.20}, # k2 again, good!
        {:model_k2, 1, 0.18}  # k2 again, good!
      ]

      sla =
        Enum.reduce(scenario, sla, fn {action, reward, distance}, acc ->
          SLASelector.update(acc, action, reward, distance: distance)
        end)

      # After this scenario, model_k2 should dominate
      assert sla.probabilities[:model_k2] > sla.probabilities[:model_k1]
      assert sla.probabilities[:model_k2] > sla.probabilities[:model_k3]

      state = SLASelector.state(sla)
      assert state.best_action == :model_k2

      # Should be converging (but not fully converged with only 8 updates)
      assert state.convergence > 0.1
    end
  end

  # Helper: Assert probability distribution sums to 1.0
  defp assert_probability_sum(sla) do
    total = sla.probabilities |> Map.values() |> Enum.sum()
    assert_in_delta total, 1.0, 1.0e-9,
      "Probability sum = #{total}, expected 1.0. Probabilities: #{inspect(sla.probabilities)}"
  end
end
