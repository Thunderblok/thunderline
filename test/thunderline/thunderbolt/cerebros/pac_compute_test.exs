defmodule Thunderline.Thunderbolt.Cerebros.PACComputeTest do
  @moduledoc """
  Tests for PAC Compute Event Protocol (HC-39).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Cerebros.PACCompute

  describe "request/1" do
    test "creates request event with default config" do
      params = %{
        rule_params: %{lambda: 0.7}
      }

      assert {:ok, event} = PACCompute.request(params)
      assert event.name == "bolt.pac.compute.request"
      assert event.source == :bolt
      assert event.payload.rule_params == %{lambda: 0.7}
      assert event.payload.grid_config == %{bounds: {16, 16, 4}}
      assert is_binary(event.payload.run_id)
    end

    test "creates request event with custom config" do
      params = %{
        run_id: "custom_run",
        rule_params: %{lambda: 0.5, bias: 0.3},
        grid_config: %{bounds: {32, 32, 8}},
        budget: %{max_ticks: 500}
      }

      assert {:ok, event} = PACCompute.request(params)
      assert event.payload.run_id == "custom_run"
      assert event.payload.grid_config == %{bounds: {32, 32, 8}}
      assert event.payload.budget == %{max_ticks: 500}
    end

    test "includes trial_id and correlation_id" do
      params = %{
        run_id: "opt_123",
        trial_id: 5,
        correlation_id: "corr_456",
        rule_params: %{}
      }

      assert {:ok, event} = PACCompute.request(params)
      assert event.payload.trial_id == 5
      assert event.meta.correlation_id == "corr_456"
    end
  end

  describe "response/1" do
    test "creates response event with fitness" do
      params = %{
        run_id: "run_123",
        trial_id: 3,
        status: :ok,
        fitness: 0.85,
        metrics: %{plv: 0.4, entropy: 0.5}
      }

      assert {:ok, event} = PACCompute.response(params)
      assert event.name == "bolt.pac.compute.response"
      assert event.payload.run_id == "run_123"
      assert event.payload.fitness == 0.85
      assert event.payload.metrics == %{plv: 0.4, entropy: 0.5}
    end

    test "includes suggested_params for TPE feedback" do
      params = %{
        run_id: "run_123",
        suggested_params: %{lambda: 0.273, bias: 0.25}
      }

      assert {:ok, event} = PACCompute.response(params)
      assert event.payload.suggested_params == %{lambda: 0.273, bias: 0.25}
    end
  end

  describe "voxel_update/2" do
    test "creates single voxel update event" do
      update = %{
        coord: {5, 10, 2},
        state: :active,
        sigma_flow: 0.75,
        phi_phase: 1.57,
        lambda_sensitivity: 0.3,
        tick: 42
      }

      assert {:ok, event} = PACCompute.voxel_update("run_123", update)
      assert event.name == "bolt.pac.ca.voxel_update"
      assert event.payload.coord == {5, 10, 2}
      assert event.payload.sigma_flow == 0.75
      assert event.payload.tick == 42
    end
  end

  describe "voxel_batch/3" do
    test "creates batch of voxel updates" do
      updates = [
        %{coord: {0, 0, 0}, state: :active, sigma_flow: 0.8},
        %{coord: {1, 0, 0}, state: :dormant, sigma_flow: 0.3},
        %{coord: {0, 1, 0}, state: :inactive, sigma_flow: 0.1}
      ]

      assert {:ok, event} = PACCompute.voxel_batch("run_123", updates, 100)
      assert event.name == "bolt.pac.ca.voxel_batch"
      assert event.payload.count == 3
      assert event.payload.tick == 100
      assert length(event.payload.updates) == 3
    end
  end

  describe "metrics_snapshot/3" do
    test "creates metrics snapshot event" do
      metrics = %{
        plv: 0.42,
        entropy: 0.51,
        lambda_hat: 0.28,
        lyapunov: 0.02
      }

      assert {:ok, event} = PACCompute.metrics_snapshot("run_123", 500, metrics)
      assert event.name == "bolt.pac.metrics.snapshot"
      assert event.payload.plv == 0.42
      assert event.payload.entropy == 0.51
      assert event.payload.lambda_hat == 0.28
      assert is_float(event.payload.edge_of_chaos_score)
    end
  end

  describe "compute_edge_score/1" do
    test "returns high score near critical parameters" do
      # Near edge of chaos: λ̂ ≈ 0.273, entropy ≈ 0.5, PLV ≈ 0.4
      critical_metrics = %{
        plv: 0.4,
        entropy: 0.5,
        lambda_hat: 0.273,
        lyapunov: 0.0
      }

      score = PACCompute.compute_edge_score(critical_metrics)
      assert score > 0.8
    end

    test "returns low score for ordered regime" do
      # Ordered: high PLV, low entropy, low λ̂
      ordered_metrics = %{
        plv: 0.95,
        entropy: 0.1,
        lambda_hat: 0.1,
        lyapunov: -0.5
      }

      score = PACCompute.compute_edge_score(ordered_metrics)
      assert score < 0.5
    end

    test "returns low score for chaotic regime" do
      # Chaotic: low PLV, high entropy, high λ̂
      chaotic_metrics = %{
        plv: 0.1,
        entropy: 0.95,
        lambda_hat: 0.8,
        lyapunov: 0.5
      }

      score = PACCompute.compute_edge_score(chaotic_metrics)
      assert score < 0.5
    end

    test "handles missing metrics with defaults" do
      partial_metrics = %{plv: 0.4}
      score = PACCompute.compute_edge_score(partial_metrics)
      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end
  end
end
