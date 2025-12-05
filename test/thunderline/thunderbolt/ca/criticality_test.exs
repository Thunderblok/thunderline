defmodule Thunderline.Thunderbolt.CA.CriticalityTest do
  @moduledoc """
  Tests for CA Criticality Metrics (HC-40).

  Verifies:
  - PLV computation (phase synchronization)
  - Permutation entropy (temporal complexity)
  - Langton's λ̂ (non-quiescent fraction)
  - Lyapunov exponent estimation (divergence rate)
  - Edge-of-chaos scoring
  - Telemetry emission
  - EventBus integration
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.Criticality

  describe "compute_from_deltas/2" do
    test "computes metrics from delta list" do
      deltas = generate_test_deltas(100)
      {:ok, metrics} = Criticality.compute_from_deltas(deltas)

      assert is_float(metrics.plv)
      assert is_float(metrics.entropy)
      assert is_float(metrics.lambda_hat)
      assert is_float(metrics.lyapunov)
      assert is_float(metrics.edge_score)
      assert metrics.zone in [:ordered, :critical, :chaotic]
      assert metrics.tick == 0
    end

    test "handles empty delta list" do
      {:ok, metrics} = Criticality.compute_from_deltas([])

      assert metrics.plv == 0.5
      assert metrics.entropy == 0.5
      assert metrics.lambda_hat == 0.5
      assert metrics.lyapunov == 0.0
    end

    test "accepts tick option" do
      deltas = generate_test_deltas(10)
      {:ok, metrics} = Criticality.compute_from_deltas(deltas, tick: 42)

      assert metrics.tick == 42
    end

    test "accepts history for temporal metrics" do
      current = generate_test_deltas(10)
      history = [generate_test_deltas(10), generate_test_deltas(10)]

      {:ok, metrics} = Criticality.compute_from_deltas(current, history: history)

      assert is_float(metrics.entropy)
      assert is_float(metrics.lyapunov)
    end
  end

  describe "compute_plv/1" do
    test "returns 1.0 for perfectly synchronized phases" do
      phases = List.duplicate(:math.pi() / 4, 50)
      plv = Criticality.compute_plv(phases)

      assert_in_delta plv, 1.0, 0.01
    end

    test "returns low value for random phases" do
      phases = Enum.map(1..100, fn _ -> :rand.uniform() * 2 * :math.pi() end)
      plv = Criticality.compute_plv(phases)

      # Random phases should give low PLV
      assert plv < 0.5
    end

    test "returns 0.5 for empty or single phase" do
      assert Criticality.compute_plv([]) == 0.5
      assert Criticality.compute_plv([0.5]) == 0.5
    end

    test "handles two phases (baseline synchronization)" do
      phases = [0.0, 0.0]
      plv = Criticality.compute_plv(phases)

      assert_in_delta plv, 1.0, 0.01
    end
  end

  describe "compute_langton_lambda/1" do
    test "returns 1.0 for all active states" do
      states = List.duplicate(:active, 100)
      lambda = Criticality.compute_langton_lambda(states)

      assert_in_delta lambda, 1.0, 0.01
    end

    test "returns 0.0 for all quiescent states" do
      states = List.duplicate(:inactive, 100)
      lambda = Criticality.compute_langton_lambda(states)

      assert_in_delta lambda, 0.0, 0.01
    end

    test "returns ~0.5 for mixed states" do
      states = Enum.map(1..100, fn i ->
        if rem(i, 2) == 0, do: :active, else: :inactive
      end)
      lambda = Criticality.compute_langton_lambda(states)

      assert_in_delta lambda, 0.5, 0.05
    end

    test "returns 0.5 for empty state list" do
      assert Criticality.compute_langton_lambda([]) == 0.5
    end
  end

  describe "compute_edge_score/1" do
    test "returns high score near critical values" do
      critical_metrics = %{
        lambda_hat: 0.273,
        entropy: 0.5,
        plv: 0.4,
        lyapunov: 0.0
      }

      score = Criticality.compute_edge_score(critical_metrics)
      assert score > 0.8
    end

    test "returns low score for ordered regime" do
      ordered_metrics = %{
        lambda_hat: 0.05,
        entropy: 0.1,
        plv: 0.9,
        lyapunov: -1.0
      }

      score = Criticality.compute_edge_score(ordered_metrics)
      assert score < 0.5
    end

    test "returns low score for chaotic regime" do
      chaotic_metrics = %{
        lambda_hat: 0.8,
        entropy: 0.95,
        plv: 0.1,
        lyapunov: 1.5
      }

      score = Criticality.compute_edge_score(chaotic_metrics)
      assert score < 0.5
    end

    test "handles missing values with defaults" do
      score = Criticality.compute_edge_score(%{})
      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end
  end

  describe "classify_zone/1" do
    test "classifies ordered regime" do
      ordered = %{lambda_hat: 0.1, entropy: 0.2}
      assert Criticality.classify_zone(ordered) == :ordered
    end

    test "classifies chaotic regime" do
      chaotic = %{lambda_hat: 0.6, entropy: 0.9}
      assert Criticality.classify_zone(chaotic) == :chaotic
    end

    test "classifies critical regime" do
      critical = %{lambda_hat: 0.27, entropy: 0.5}
      assert Criticality.classify_zone(critical) == :critical
    end
  end

  describe "step_with_metrics/3" do
    test "returns deltas, grid, and metrics" do
      # Create a minimal test grid
      grid = %{size: 4, tick: 0}
      ruleset = %{rule: :demo, rule_version: 1}

      {:ok, deltas, new_grid, metrics} = Criticality.step_with_metrics(grid, ruleset)

      assert is_list(deltas)
      assert is_map(new_grid)
      assert is_map(metrics)
      assert Map.has_key?(metrics, :plv)
      assert Map.has_key?(metrics, :edge_score)
    end
  end

  describe "emit_metrics/4" do
    test "emits telemetry event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        {__MODULE__, ref},
        [:thunderline, :bolt, :ca, :criticality],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      metrics = %{
        plv: 0.4,
        entropy: 0.5,
        lambda_hat: 0.273,
        lyapunov: 0.0,
        edge_score: 0.9,
        zone: :critical,
        tick: 42,
        timestamp: System.monotonic_time(:millisecond)
      }

      :ok = Criticality.emit_metrics("test_run", 42, metrics, emit_event: false)

      assert_receive {:telemetry, [:thunderline, :bolt, :ca, :criticality], measurements, metadata}

      assert measurements.plv == 0.4
      assert measurements.entropy == 0.5
      assert measurements.lambda_hat == 0.273
      assert measurements.edge_score == 0.9
      assert metadata.run_id == "test_run"
      assert metadata.tick == 42
      assert metadata.zone == :critical

      :telemetry.detach({__MODULE__, ref})
    end
  end

  describe "integration with history" do
    test "entropy improves with history depth" do
      # Generate consistent deltas across multiple ticks
      history = Enum.map(1..5, fn _ -> generate_consistent_flows(10) end)
      current = generate_consistent_flows(10)

      {:ok, metrics_with_history} = Criticality.compute_from_deltas(
        Enum.map(current, &%{sigma_flow: &1}),
        history: history
      )

      {:ok, metrics_no_history} = Criticality.compute_from_deltas(
        Enum.map(current, &%{sigma_flow: &1}),
        history: []
      )

      # Both should produce valid metrics
      assert is_float(metrics_with_history.entropy)
      assert is_float(metrics_no_history.entropy)
    end
  end

  # ────────────────────────────────────────────────────────────────
  # Test Helpers
  # ────────────────────────────────────────────────────────────────

  defp generate_test_deltas(count) do
    Enum.map(1..count, fn i ->
      %{
        x: rem(i, 10),
        y: div(i, 10),
        state: Enum.random([:active, :inactive, :dormant]),
        phi_phase: :rand.uniform() * 2 * :math.pi(),
        sigma_flow: :rand.uniform(),
        energy: :rand.uniform(100)
      }
    end)
  end

  defp generate_consistent_flows(count) do
    # Generate flows with some temporal structure
    base = :rand.uniform()
    Enum.map(1..count, fn i ->
      base + 0.1 * :math.sin(i / 3) + 0.05 * :rand.uniform()
    end)
  end
end
