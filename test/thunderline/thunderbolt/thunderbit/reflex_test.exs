defmodule Thunderline.Thunderbolt.Thunderbit.ReflexTest do
  @moduledoc """
  Tests for Thunderbit Reflexive Intelligence Layer (HC-Ω-1).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Thunderbit
  alias Thunderline.Thunderbolt.Thunderbit.Reflex

  describe "compute_local_metrics/2" do
    test "returns default metrics for isolated bit" do
      bit = create_test_bit()
      metrics = Reflex.compute_local_metrics(bit, [])

      assert metrics.neighbor_count == 0
      assert metrics.plv == 0.5
      assert metrics.entropy == 0.5
      assert metrics.lambda_hat == bit.lambda_sensitivity
    end

    test "computes PLV from neighbor phases" do
      bit = create_test_bit(%{phi_phase: 0.0})

      # Neighbors with same phase = high PLV
      coherent_neighbors = [
        %{coord: {1, 0, 0}, phi_phase: 0.0, sigma_flow: 0.5, lambda_sensitivity: 0.3, trust_score: 0.8},
        %{coord: {0, 1, 0}, phi_phase: 0.1, sigma_flow: 0.5, lambda_sensitivity: 0.3, trust_score: 0.8}
      ]

      metrics = Reflex.compute_local_metrics(bit, coherent_neighbors)

      assert metrics.plv > 0.9
      assert metrics.neighbor_count == 2
    end

    test "computes entropy from flow variance" do
      bit = create_test_bit(%{sigma_flow: 0.5})

      # Neighbors with varied flow = high entropy
      varied_neighbors = [
        %{coord: {1, 0, 0}, phi_phase: 0.0, sigma_flow: 0.1, lambda_sensitivity: 0.3, trust_score: 0.8},
        %{coord: {0, 1, 0}, phi_phase: 0.0, sigma_flow: 0.9, lambda_sensitivity: 0.3, trust_score: 0.8}
      ]

      metrics = Reflex.compute_local_metrics(bit, varied_neighbors)

      assert metrics.entropy > 0.3
      assert metrics.neighbor_count == 2
    end

    test "computes lambda_hat as neighborhood average" do
      bit = create_test_bit(%{lambda_sensitivity: 0.3})

      neighbors = [
        %{coord: {1, 0, 0}, phi_phase: 0.0, sigma_flow: 0.5, lambda_sensitivity: 0.5, trust_score: 0.8},
        %{coord: {0, 1, 0}, phi_phase: 0.0, sigma_flow: 0.5, lambda_sensitivity: 0.7, trust_score: 0.8}
      ]

      metrics = Reflex.compute_local_metrics(bit, neighbors)

      # Average of 0.3, 0.5, 0.7 = 0.5
      assert_in_delta metrics.lambda_hat, 0.5, 0.01
    end
  end

  describe "apply_rule/4" do
    test "applies decay rule for isolated bit" do
      bit = create_test_bit(%{sigma_flow: 0.8})
      gate_logits = Nx.tensor([1.0] ++ List.duplicate(0.0, 15))
      policy = %{decay_rate: 0.9}

      {state, flow, phase, lambda} = Reflex.apply_rule(bit, [], gate_logits, policy)

      assert flow < bit.sigma_flow
      assert_in_delta flow, 0.72, 0.01  # 0.8 * 0.9
    end

    test "applies override freeze rule" do
      bit = create_test_bit(%{sigma_flow: 0.8, phi_phase: 1.5})
      policy = %{override_rules: %{rule: :freeze}}

      {_state, flow, phase, _lambda} = Reflex.apply_rule(bit, [], nil, policy)

      assert flow == bit.sigma_flow
      assert phase == bit.phi_phase
    end

    test "applies override collapse rule" do
      bit = create_test_bit(%{sigma_flow: 0.8})
      policy = %{override_rules: %{rule: :collapse}}

      {state, flow, _phase, lambda} = Reflex.apply_rule(bit, [], nil, policy)

      assert state == :collapsed
      assert flow == 0.0
      assert lambda == 1.0
    end

    test "applies override activate rule" do
      bit = create_test_bit(%{sigma_flow: 0.2, phi_phase: 0.5})
      policy = %{override_rules: %{rule: :activate}}

      {state, flow, phase, lambda} = Reflex.apply_rule(bit, [], nil, policy)

      assert state == :active
      assert flow == 1.0
      assert phase == 0.5  # preserved
      assert lambda == 0.0
    end
  end

  describe "evaluate_reflexes/3" do
    test "fires stability reflex on low sigma_flow" do
      bit = create_test_bit(%{sigma_flow: 0.1, trust_score: 0.5})
      metrics = %{plv: 0.3, entropy: 0.5, lambda_hat: 0.3, neighbor_count: 2}
      policy = %{stability_threshold: 0.3, propagation_enabled: false}

      {updated_bit, events} = Reflex.evaluate_reflexes(bit, metrics, policy)

      assert length(events) > 0
      stability_event = Enum.find(events, &(&1.type == :stability))
      assert stability_event != nil
      assert stability_event.trigger == :low_stability
    end

    test "fires chaos reflex on high lambda_hat" do
      bit = create_test_bit()
      metrics = %{plv: 0.3, entropy: 0.8, lambda_hat: 0.9, neighbor_count: 2}
      policy = %{chaos_threshold: 0.8, propagation_enabled: false}

      {updated_bit, events} = Reflex.evaluate_reflexes(bit, metrics, policy)

      chaos_event = Enum.find(events, &(&1.type == :chaos))
      assert chaos_event != nil
      assert chaos_event.trigger == :chaos_spike
      assert chaos_event.data.action == :quarantine
    end

    test "fires trust reflex when stable and coherent" do
      bit = create_test_bit(%{sigma_flow: 0.7, trust_score: 0.5})
      metrics = %{plv: 0.8, entropy: 0.3, lambda_hat: 0.3, neighbor_count: 4}
      policy = %{stability_threshold: 0.3, plv_threshold: 0.6, trust_boost: 0.1, propagation_enabled: false}

      {updated_bit, events} = Reflex.evaluate_reflexes(bit, metrics, policy)

      trust_event = Enum.find(events, &(&1.type == :trust))
      assert trust_event != nil
      assert trust_event.trigger == :trust_boost
    end

    test "returns unchanged bit when no reflexes fire" do
      bit = create_test_bit(%{sigma_flow: 0.5, trust_score: 0.5})
      metrics = %{plv: 0.5, entropy: 0.5, lambda_hat: 0.3, neighbor_count: 2}
      policy = %{stability_threshold: 0.3, chaos_threshold: 0.8, plv_threshold: 0.9, propagation_enabled: false}

      {updated_bit, events} = Reflex.evaluate_reflexes(bit, metrics, policy)

      assert events == []
    end
  end

  describe "check_propagation/2" do
    test "propagates chaos spikes to neighbors" do
      bit = create_test_bit()
      # Add neighborhood manually since struct might not have it
      bit = Map.put(bit, :neighborhood, [{1, 0, 0}, {0, 1, 0}, {0, 0, 1}])

      event = %{type: :chaos_spike, bit_id: bit.id, coord: bit.coord, trigger: :chaos_spike, data: %{}}

      result = Reflex.check_propagation(bit, event)

      assert match?({:propagate, _}, result)
      {:propagate, targets} = result
      assert length(targets) == 3
    end

    test "propagates stability warnings" do
      bit = create_test_bit()
      bit = Map.put(bit, :neighborhood, [{1, 0, 0}])

      event = %{type: :stability, bit_id: bit.id, coord: bit.coord, trigger: :low_stability, data: %{}}

      result = Reflex.check_propagation(bit, event)

      assert match?({:propagate, _}, result)
    end

    test "does not propagate trust events" do
      bit = create_test_bit()
      event = %{type: :trust, bit_id: bit.id, coord: bit.coord, trigger: :trust_boost, data: %{}}

      result = Reflex.check_propagation(bit, event)

      assert result == :no_propagate
    end
  end

  describe "step/5" do
    @tag :skip  # Requires DiffLogic.Gates module
    test "performs complete reflex step" do
      bit = create_test_bit()

      neighbors = [
        %{coord: {1, 0, 0}, phi_phase: 0.1, sigma_flow: 0.6, lambda_sensitivity: 0.3, trust_score: 0.8}
      ]

      gate_logits = Nx.tensor(List.duplicate(0.1, 16))
      policy = %{propagation_enabled: false}

      {:ok, updated_bit, events} = Reflex.step(bit, neighbors, gate_logits, policy, 1)

      assert updated_bit.id == bit.id
      assert is_list(events)
    end
  end

  describe "batch_step/4" do
    @tag :skip  # Requires DiffLogic.Gates module
    test "updates multiple bits in parallel" do
      bits_map = %{
        {0, 0, 0} => create_test_bit(%{coord: {0, 0, 0}}),
        {1, 0, 0} => create_test_bit(%{coord: {1, 0, 0}}),
        {0, 1, 0} => create_test_bit(%{coord: {0, 1, 0}})
      }

      # Set neighborhoods
      bits_map =
        bits_map
        |> Map.update!({0, 0, 0}, &Map.put(&1, :neighborhood, [{1, 0, 0}, {0, 1, 0}]))
        |> Map.update!({1, 0, 0}, &Map.put(&1, :neighborhood, [{0, 0, 0}]))
        |> Map.update!({0, 1, 0}, &Map.put(&1, :neighborhood, [{0, 0, 0}]))

      gate_logits = Nx.tensor(List.duplicate(0.1, 16))
      policy = %{propagation_enabled: false}

      {updated_bits, all_events} = Reflex.batch_step(bits_map, gate_logits, policy, 1)

      assert map_size(updated_bits) == 3
      assert is_list(all_events)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Test Helpers
  # ═══════════════════════════════════════════════════════════════

  defp create_test_bit(overrides \\ %{}) do
    defaults = %{
      id: "test_bit_#{System.unique_integer([:positive])}",
      coord: {0, 0, 0},
      state: :active,
      rule_id: 0,
      phi_phase: 0.0,
      sigma_flow: 0.5,
      lambda_sensitivity: 0.3,
      trust_score: 0.8,
      presence_vector: %{},
      neighborhood: []
    }

    struct_data = Map.merge(defaults, overrides)

    # Create a map that mimics Thunderbit struct
    struct_data
  end
end
