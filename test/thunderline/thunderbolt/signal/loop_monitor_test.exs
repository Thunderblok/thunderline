defmodule Thunderline.Thunderbolt.Signal.LoopMonitorTest do
  @moduledoc """
  Tests for HC-40 LoopMonitor - criticality feedback loop monitor.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Signal.LoopMonitor

  describe "pure functions" do
    test "plv/1 returns 1.0 for identical phases" do
      phases = [0.5, 0.5, 0.5, 0.5]
      assert LoopMonitor.plv(phases) == 1.0
    end

    test "plv/1 returns ~0 for uniformly distributed phases" do
      # Phases spread evenly around the circle
      phases = [0.0, 0.25, 0.5, 0.75]
      assert LoopMonitor.plv(phases) < 0.1
    end

    test "plv/1 returns 0.0 for empty list" do
      assert LoopMonitor.plv([]) == 0.0
    end

    test "permutation_entropy/1 returns 0.0 for constant series" do
      series = [1.0, 1.0, 1.0, 1.0, 1.0]
      assert LoopMonitor.permutation_entropy(series) == 0.0
    end

    test "permutation_entropy/1 returns high value for random series" do
      # Pseudorandom sequence should have high entropy
      series = [1, 4, 2, 8, 5, 7, 3, 6, 9, 0]
      entropy = LoopMonitor.permutation_entropy(series)
      assert entropy > 0.5
    end

    test "permutation_entropy/1 returns 0.0 for short series" do
      assert LoopMonitor.permutation_entropy([1, 2]) == 0.0
    end

    test "lambda_hat/1 returns 0.0 for all-quiescent states" do
      states = [0, 0, 0, 0, 0]
      assert LoopMonitor.lambda_hat(states) == 0.0
    end

    test "lambda_hat/1 returns 1.0 for all-active states" do
      states = [1, 1, 1, 1, 1]
      assert LoopMonitor.lambda_hat(states) == 1.0
    end

    test "lambda_hat/1 returns correct fraction" do
      # 2/5 active
      states = [0, 1, 0, 1, 0]
      assert LoopMonitor.lambda_hat(states) == 0.4
    end

    test "lambda_from_rule/1 computes correct λ̂ for rule 110" do
      # Rule 110: 01101110 in binary = 7 ones out of 8
      lambda = LoopMonitor.lambda_from_rule(110)
      # 110 = 0b01101110, count of 1s = 6
      assert lambda == 0.75
    end

    test "lambda_from_rule/1 for rule 0 returns 0.0" do
      assert LoopMonitor.lambda_from_rule(0) == 0.0
    end

    test "lambda_from_rule/1 for rule 255 returns 1.0" do
      assert LoopMonitor.lambda_from_rule(255) == 1.0
    end

    test "lyapunov_local/1 returns 0.0 for empty trajectories" do
      assert LoopMonitor.lyapunov_local([]) == 0.0
    end

    test "lyapunov_local/1 returns negative for stable trajectories" do
      # Identical trajectories = no divergence
      trajectories = [[1, 0, 1], [1, 0, 1], [1, 0, 1]]
      lyap = LoopMonitor.lyapunov_local(trajectories)
      assert lyap < 0
    end

    test "lyapunov_local/1 returns positive for diverging trajectories" do
      # Diverging trajectories
      trajectories = [[0, 0, 0], [0, 0, 1], [0, 1, 1], [1, 1, 1]]
      lyap = LoopMonitor.lyapunov_local(trajectories)
      assert lyap > 0
    end

    test "classify_zone/4 returns :ordered for low λ̂" do
      assert LoopMonitor.classify_zone(0.1, 0.5, 0.25, 0.35) == :ordered
    end

    test "classify_zone/4 returns :critical for λ̂ in target range" do
      assert LoopMonitor.classify_zone(0.3, 0.5, 0.25, 0.35) == :critical
    end

    test "classify_zone/4 returns :chaotic for high λ̂" do
      assert LoopMonitor.classify_zone(0.5, 0.5, 0.25, 0.35) == :chaotic
    end

    test "criticality_score/3 returns 1.0 at target midpoint" do
      score = LoopMonitor.criticality_score(0.3, 0.25, 0.35)
      assert score > 0.9
    end

    test "criticality_score/3 returns low value far from target" do
      score = LoopMonitor.criticality_score(0.9, 0.25, 0.35)
      assert score < 0.1
    end
  end

  describe "GenServer operations" do
    setup do
      {:ok, pid} = LoopMonitor.start_link(name: nil)
      {:ok, server: pid}
    end

    test "records phases and computes metrics", %{server: pid} do
      # Record some phases
      for phase <- [0.1, 0.15, 0.12, 0.11, 0.13] do
        LoopMonitor.record_phase(pid, phase)
      end

      # Record some states
      for _ <- 1..5 do
        LoopMonitor.record_state(pid, [1, 0, 1, 0, 1])
      end

      metrics = LoopMonitor.compute_and_emit(pid)

      assert is_float(metrics.plv)
      assert is_float(metrics.lambda_hat)
      assert is_float(metrics.criticality_score)
      assert metrics.zone in [:ordered, :critical, :chaotic]
    end

    test "recommended_perturbation returns float", %{server: pid} do
      # Record some data first
      LoopMonitor.record_state(pid, [0, 0, 0, 0, 0])
      LoopMonitor.compute_and_emit(pid)

      perturb = LoopMonitor.recommended_perturbation(pid)
      assert is_float(perturb)
      assert perturb >= 0.0
    end

    test "get_metrics returns default when no data", %{server: pid} do
      metrics = LoopMonitor.get_metrics(pid)

      assert is_float(metrics.plv)
      assert is_float(metrics.lambda_hat)
    end
  end

  describe "telemetry" do
    setup do
      {:ok, pid} = LoopMonitor.start_link(name: nil)
      {:ok, server: pid}
    end

    test "emits criticality telemetry on compute_and_emit", %{server: pid} do
      test_pid = self()

      :telemetry.attach(
        "test-criticality",
        [:thunderline, :bolt, :ca, :criticality],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      # Add some data
      LoopMonitor.record_state(pid, [1, 0, 1, 0])
      LoopMonitor.compute_and_emit(pid)

      assert_receive {:telemetry, measurements, metadata}, 1000

      assert is_float(measurements.plv)
      assert is_float(measurements.lambda_hat)
      assert metadata.zone in [:ordered, :critical, :chaotic]

      :telemetry.detach("test-criticality")
    end
  end
end
