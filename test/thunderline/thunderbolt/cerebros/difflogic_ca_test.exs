defmodule Thunderline.Thunderbolt.Cerebros.DiffLogicCATest do
  @moduledoc """
  Tests for DiffLogic-controlled self-optimizing CA (HC-38).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Cerebros.DiffLogicCA

  describe "start_link/1" do
    test "starts with minimal options" do
      run_id = "test_difflogic_#{:rand.uniform(10000)}"
      {:ok, pid} = DiffLogicCA.start_link(run_id: run_id)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom bounds" do
      run_id = "bounds_test_#{:rand.uniform(10000)}"

      {:ok, pid} =
        DiffLogicCA.start_link(
          run_id: run_id,
          bounds: {8, 8, 4}
        )

      {:ok, status} = DiffLogicCA.status(pid)
      assert status.bounds == {8, 8, 4}
      GenServer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns status with idle state initially" do
      run_id = "status_test_#{:rand.uniform(10000)}"
      {:ok, pid} = DiffLogicCA.start_link(run_id: run_id)

      {:ok, status} = DiffLogicCA.status(pid)
      assert status.run_id == run_id
      assert status.status == :idle
      assert status.tick == 0
      assert is_map(status.current_params)

      GenServer.stop(pid)
    end
  end

  describe "build_difflogic_ruleset/1" do
    test "builds ruleset with default params" do
      params = %{lambda: 0.5, bias: 0.3}
      ruleset = DiffLogicCA.build_difflogic_ruleset(params)

      assert ruleset.rule_id == :difflogic
      assert ruleset.lambda == 0.5
      assert ruleset.bias == 0.3
      assert ruleset.neighborhood_type == :von_neumann
      assert is_function(ruleset.apply_fn, 5)
    end

    test "initializes gate logits when not provided" do
      params = %{gate_temp: 1.5}
      ruleset = DiffLogicCA.build_difflogic_ruleset(params)

      assert ruleset.gate_temp == 1.5
      assert is_struct(ruleset.gate_logits, Nx.Tensor)
    end
  end

  describe "run/3" do
    test "runs CA for specified ticks" do
      run_id = "run_test_#{:rand.uniform(10000)}"

      {:ok, pid} =
        DiffLogicCA.start_link(
          run_id: run_id,
          bounds: {4, 4, 2}
        )

      params = %{lambda: 0.5, bias: 0.3}
      assert :ok = DiffLogicCA.run(pid, params, ticks: 10, emit_events: false)

      {:ok, status} = DiffLogicCA.status(pid)
      assert status.tick == 10
      assert status.status == :running

      GenServer.stop(pid)
    end
  end

  describe "step/1" do
    test "returns error when grid not initialized" do
      run_id = "step_err_test_#{:rand.uniform(10000)}"
      {:ok, pid} = DiffLogicCA.start_link(run_id: run_id)

      {:error, :grid_not_initialized} = DiffLogicCA.step(pid)

      GenServer.stop(pid)
    end

    test "returns deltas after grid initialized" do
      run_id = "step_test_#{:rand.uniform(10000)}"

      {:ok, pid} =
        DiffLogicCA.start_link(
          run_id: run_id,
          bounds: {4, 4, 2}
        )

      # Initialize by running 1 tick
      params = %{lambda: 0.5, bias: 0.3}
      :ok = DiffLogicCA.run(pid, params, ticks: 1, emit_events: false)

      # Now step should work
      {:ok, deltas} = DiffLogicCA.step(pid)
      assert is_list(deltas)
      assert length(deltas) > 0

      GenServer.stop(pid)
    end
  end

  describe "get_metrics/1" do
    test "returns metrics after running" do
      run_id = "metrics_test_#{:rand.uniform(10000)}"

      {:ok, pid} =
        DiffLogicCA.start_link(
          run_id: run_id,
          bounds: {4, 4, 2}
        )

      params = %{lambda: 0.5, bias: 0.3}
      :ok = DiffLogicCA.run(pid, params, ticks: 20, emit_events: false)

      {:ok, metrics} = DiffLogicCA.get_metrics(pid)
      assert is_float(metrics.plv)
      assert is_float(metrics.entropy)
      assert is_float(metrics.lambda_hat)
      assert is_float(metrics.lyapunov)

      GenServer.stop(pid)
    end
  end

  describe "apply_difflogic_rule/5" do
    test "applies rule with no neighbors" do
      bit = %{
        state: :active,
        sigma_flow: 0.8,
        phi_phase: 0.0,
        lambda_sensitivity: 0.5
      }

      gate_logits = Nx.broadcast(0.0, {16})

      {state, flow, phase, lambda} =
        DiffLogicCA.apply_difflogic_rule(bit, [], gate_logits, 0.5, 0.3)

      # Decay when isolated
      assert flow < 0.8
      assert is_atom(state)
    end

    test "applies rule with neighbors" do
      bit = %{
        state: :active,
        sigma_flow: 0.5,
        phi_phase: 0.0,
        lambda_sensitivity: 0.5
      }

      neighbors = [
        {{1, 0, 0}, %{sigma_flow: 0.8}},
        {{0, 1, 0}, %{sigma_flow: 0.7}},
        {{0, 0, 1}, %{sigma_flow: 0.6}}
      ]

      gate_logits = Nx.broadcast(0.0, {16})

      {state, flow, phase, lambda} =
        DiffLogicCA.apply_difflogic_rule(bit, neighbors, gate_logits, 0.5, 0.3)

      assert is_atom(state)
      assert flow >= 0.0 and flow <= 1.0
      assert phase >= 0.0
      assert lambda >= 0.0 and lambda <= 1.0
    end
  end
end
