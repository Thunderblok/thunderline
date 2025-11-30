defmodule Thunderline.Thunderbolt.Cerebros.LoopMonitorTest do
  @moduledoc """
  Tests for LoopMonitor criticality metrics (HC-40).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Cerebros.LoopMonitor

  describe "start_link/1" do
    test "starts with required options" do
      {:ok, pid} = LoopMonitor.start_link(run_id: "test_run_#{:rand.uniform(10000)}")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "observe/3 and get_metrics/1" do
    test "returns empty metrics before observations" do
      {:ok, pid} = LoopMonitor.start_link(run_id: "observe_test_#{:rand.uniform(10000)}")

      {:ok, metrics} = LoopMonitor.get_metrics(pid)
      assert metrics.plv == 0.5
      assert metrics.entropy == 0.5
      assert metrics.tick == 0

      GenServer.stop(pid)
    end

    test "updates metrics after observations" do
      {:ok, pid} = LoopMonitor.start_link(run_id: "metrics_test_#{:rand.uniform(10000)}")

      # Generate some voxel states
      voxel_states =
        for x <- 0..7, y <- 0..7 do
          %{
            coord: {x, y, 0},
            sigma_flow: :rand.uniform(),
            phi_phase: :rand.uniform() * 2 * :math.pi(),
            state: Enum.random([:active, :dormant, :inactive])
          }
        end

      # Observe multiple ticks
      for tick <- 1..10 do
        # Add some variation to states each tick
        varied_states =
          Enum.map(voxel_states, fn s ->
            %{s | sigma_flow: max(0.0, min(1.0, s.sigma_flow + (:rand.uniform() - 0.5) * 0.1))}
          end)

        LoopMonitor.observe(pid, tick, varied_states)
      end

      # Allow time for async processing
      Process.sleep(10)

      {:ok, metrics} = LoopMonitor.get_metrics(pid)
      assert metrics.tick == 10
      assert is_float(metrics.plv)
      assert is_float(metrics.entropy)
      assert is_float(metrics.lambda_hat)

      GenServer.stop(pid)
    end
  end

  describe "compute_plv/1" do
    test "returns 0.5 for empty input" do
      assert LoopMonitor.compute_plv([]) == 0.5
    end

    test "returns 1.0 for perfectly synchronized phases" do
      # All phases identical
      phases = [[0.0, 0.0, 0.0, 0.0]]
      plv = LoopMonitor.compute_plv(phases)
      assert_in_delta plv, 1.0, 0.01
    end

    test "returns low value for random phases" do
      # Random phases should have low PLV
      random_phases = [
        for(_ <- 1..100, do: :rand.uniform() * 2 * :math.pi())
      ]

      plv = LoopMonitor.compute_plv(random_phases)
      # Random phases should give PLV around 0.1-0.3
      assert plv < 0.5
    end

    test "returns high value for partially synchronized phases" do
      # Phases clustered around 0 with some spread
      clustered_phases = [
        for(_ <- 1..100, do: (:rand.uniform() - 0.5) * 0.5)
      ]

      plv = LoopMonitor.compute_plv(clustered_phases)
      # Clustered phases should give high PLV
      assert plv > 0.5
    end
  end

  describe "compute_permutation_entropy/1" do
    test "returns 0.5 for short series" do
      assert LoopMonitor.compute_permutation_entropy([1.0, 2.0]) == 0.5
    end

    test "returns low entropy for ordered series" do
      # Monotonic series - only one ordinal pattern
      ordered = Enum.to_list(1..20) |> Enum.map(&(&1 * 1.0))
      entropy = LoopMonitor.compute_permutation_entropy(ordered)
      assert entropy < 0.3
    end

    test "returns high entropy for noisy series" do
      # Random series - many ordinal patterns
      noisy = for(_ <- 1..50, do: :rand.uniform())
      entropy = LoopMonitor.compute_permutation_entropy(noisy)
      assert entropy > 0.7
    end
  end

  describe "compute_langton_lambda/1" do
    test "returns 0.5 for empty input" do
      assert LoopMonitor.compute_langton_lambda([]) == 0.5
    end

    test "returns 0 when all inactive" do
      states = [[:inactive, :inactive, :dormant, :dormant]]
      lambda = LoopMonitor.compute_langton_lambda(states)
      assert lambda == 0.0
    end

    test "returns 1.0 when all active" do
      states = [[:active, :active, :chaotic, :stable]]
      lambda = LoopMonitor.compute_langton_lambda(states)
      assert lambda == 1.0
    end

    test "returns proportion for mixed states" do
      # 50% active, 50% inactive
      states = [[:active, :active, :inactive, :inactive]]
      lambda = LoopMonitor.compute_langton_lambda(states)
      assert_in_delta lambda, 0.5, 0.01
    end
  end

  describe "estimate_lyapunov/1" do
    test "returns 0 for short series" do
      assert LoopMonitor.estimate_lyapunov([1.0, 2.0, 3.0]) == 0.0
    end

    test "returns negative for converging series" do
      # Exponentially decaying series - should have negative Lyapunov
      converging =
        for i <- 1..20 do
          :math.exp(-i * 0.1) + :rand.uniform() * 0.01
        end

      lyapunov = LoopMonitor.estimate_lyapunov(converging)
      # Should be negative or near zero
      assert lyapunov <= 0.5
    end

    test "returns near-zero for stable oscillation" do
      # Sine wave - stable, neither chaotic nor converging
      stable =
        for i <- 1..50 do
          :math.sin(i * 0.2)
        end

      lyapunov = LoopMonitor.estimate_lyapunov(stable)
      # Should be near zero
      assert abs(lyapunov) < 1.0
    end
  end

  describe "reset/1" do
    test "clears history and resets tick" do
      {:ok, pid} = LoopMonitor.start_link(run_id: "reset_test_#{:rand.uniform(10000)}")

      # Add some observations
      states = [%{coord: {0, 0, 0}, sigma_flow: 0.5, phi_phase: 0.0, state: :active}]

      for tick <- 1..5 do
        LoopMonitor.observe(pid, tick, states)
      end

      Process.sleep(10)

      {:ok, before} = LoopMonitor.get_metrics(pid)
      assert before.tick == 5

      # Reset
      :ok = LoopMonitor.reset(pid)

      {:ok, after_reset} = LoopMonitor.get_metrics(pid)
      assert after_reset.tick == 0

      GenServer.stop(pid)
    end
  end
end
