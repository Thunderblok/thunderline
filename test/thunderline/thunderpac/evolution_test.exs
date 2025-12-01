defmodule Thunderline.Thunderpac.EvolutionTest do
  @moduledoc """
  Tests for Thunderpac Evolution System (HC-Ω-2).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderpac.Evolution

  describe "list_profiles/0" do
    test "returns all evolution profiles" do
      profiles = Evolution.list_profiles()

      assert Map.has_key?(profiles, :explorer)
      assert Map.has_key?(profiles, :exploiter)
      assert Map.has_key?(profiles, :balanced)
      assert Map.has_key?(profiles, :resilient)
      assert Map.has_key?(profiles, :aggressive)
    end

    test "each profile has required keys" do
      profiles = Evolution.list_profiles()

      for {_name, config} <- profiles do
        assert Map.has_key?(config, :description)
        assert Map.has_key?(config, :fitness_weights)
        assert Map.has_key?(config, :trait_modifiers)
      end
    end

    test "fitness weights sum to 1.0" do
      profiles = Evolution.list_profiles()

      for {name, config} <- profiles do
        weights = config.fitness_weights
        total = weights.stability + weights.coherence + weights.adaptability + weights.efficiency
        assert_in_delta total, 1.0, 0.01, "Profile #{name} weights don't sum to 1.0"
      end
    end
  end

  describe "get_profile/1" do
    test "returns profile config for valid profile" do
      {:ok, config} = Evolution.get_profile(:balanced)

      assert config.trait_modifiers.lambda_target == 0.273  # Langton's λc
    end

    test "returns error for invalid profile" do
      assert {:error, :not_found} = Evolution.get_profile(:nonexistent)
    end
  end

  describe "compute_fitness/3" do
    test "computes fitness with balanced profile" do
      metrics = %{
        plv: 0.4,
        entropy: 0.5,
        lambda_hat: 0.273,
        lyapunov: 0.0
      }

      pac = %{
        intent_queue: [],
        memory_state: %{},
        session_count: 5
      }

      {:ok, profile_config} = Evolution.get_profile(:balanced)

      result = Evolution.compute_fitness(metrics, pac, profile_config)

      assert result.total > 0.0
      assert result.total <= 1.0
      assert Map.has_key?(result.components, :stability)
      assert Map.has_key?(result.components, :coherence)
      assert Map.has_key?(result.components, :adaptability)
      assert Map.has_key?(result.components, :efficiency)
    end

    test "high entropy reduces stability fitness" do
      {:ok, profile} = Evolution.get_profile(:balanced)

      low_entropy_metrics = %{plv: 0.5, entropy: 0.1, lambda_hat: 0.3, lyapunov: 0.0}
      high_entropy_metrics = %{plv: 0.5, entropy: 0.9, lambda_hat: 0.3, lyapunov: 0.0}
      pac = %{intent_queue: [], memory_state: %{}, session_count: 1}

      low_result = Evolution.compute_fitness(low_entropy_metrics, pac, profile)
      high_result = Evolution.compute_fitness(high_entropy_metrics, pac, profile)

      assert low_result.components.stability > high_result.components.stability
    end

    test "lambda_hat near target increases adaptability" do
      {:ok, profile} = Evolution.get_profile(:balanced)
      target = profile.trait_modifiers.lambda_target  # 0.273

      optimal_metrics = %{plv: 0.5, entropy: 0.5, lambda_hat: target, lyapunov: 0.0}
      far_metrics = %{plv: 0.5, entropy: 0.5, lambda_hat: 0.9, lyapunov: 0.0}
      pac = %{intent_queue: [], memory_state: %{}, session_count: 1}

      optimal_result = Evolution.compute_fitness(optimal_metrics, pac, profile)
      far_result = Evolution.compute_fitness(far_metrics, pac, profile)

      assert optimal_result.components.adaptability > far_result.components.adaptability
    end

    test "large intent queue reduces efficiency" do
      {:ok, profile} = Evolution.get_profile(:balanced)
      metrics = %{plv: 0.5, entropy: 0.5, lambda_hat: 0.3, lyapunov: 0.0}

      small_queue_pac = %{intent_queue: [], memory_state: %{}, session_count: 1}
      large_queue_pac = %{intent_queue: List.duplicate(%{}, 20), memory_state: %{}, session_count: 1}

      small_result = Evolution.compute_fitness(metrics, small_queue_pac, profile)
      large_result = Evolution.compute_fitness(metrics, large_queue_pac, profile)

      assert small_result.components.efficiency > large_result.components.efficiency
    end

    test "explorer profile favors high adaptability" do
      metrics = %{plv: 0.3, entropy: 0.7, lambda_hat: 0.5, lyapunov: 0.1}
      pac = %{intent_queue: [], memory_state: %{}, session_count: 1}

      {:ok, explorer} = Evolution.get_profile(:explorer)
      {:ok, exploiter} = Evolution.get_profile(:exploiter)

      explorer_result = Evolution.compute_fitness(metrics, pac, explorer)
      exploiter_result = Evolution.compute_fitness(metrics, pac, exploiter)

      # Explorer should handle high entropy better
      assert explorer_result.total >= exploiter_result.total * 0.8
    end
  end

  describe "apply_evolution/2" do
    test "updates trait_vector from evolved traits" do
      pac = %{
        id: "test_pac",
        trait_vector: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.3, 0.5, 0.4, 0.5],
        persona: %{}
      }

      evolved_traits = %{
        aggression: 0.7,
        curiosity: 0.8,
        caution: 0.3,
        persistence: 0.6,
        adaptability: 0.9,
        sociability: 0.4,
        lambda_sensitivity: 0.273,
        entropy_tolerance: 0.5,
        phase_coherence: 0.4,
        flow_stability: 0.6
      }

      {:ok, evolved_pac} = Evolution.apply_evolution(pac, evolved_traits)

      assert evolved_pac.trait_vector == [0.7, 0.8, 0.3, 0.6, 0.9, 0.4, 0.273, 0.5, 0.4, 0.6]
      assert evolved_pac.persona["evolved"] == true
      assert evolved_pac.persona["evolution_traits"] == evolved_traits
    end
  end

  describe "GenServer operations" do
    setup do
      # Start Evolution GenServer for tests
      {:ok, pid} = Evolution.start_link(name: :"Evolution_#{System.unique_integer([:positive])}")
      Process.register(pid, Thunderline.Thunderpac.Evolution)
      on_exit(fn -> Process.unregister(Thunderline.Thunderpac.Evolution) end)
      {:ok, pid: pid}
    end

    test "starts evolution session", %{pid: _pid} do
      pac_id = "test_pac_#{System.unique_integer([:positive])}"

      {:ok, session_id} = Evolution.start_session(pac_id, profile: :explorer)

      assert String.starts_with?(session_id, "evo_#{pac_id}")
    end

    test "starts session with custom profile", %{pid: _pid} do
      pac_id = "test_pac_#{System.unique_integer([:positive])}"

      {:ok, _session_id} = Evolution.start_session(pac_id, profile: :aggressive)

      # Session should be created (verifiable via best_params)
      result = Evolution.best_params(pac_id)
      assert match?({:error, :no_evolution_yet}, result)
    end

    test "performs evolution step", %{pid: _pid} do
      pac = %{
        id: "test_pac_step_#{System.unique_integer([:positive])}",
        trait_vector: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.3, 0.5, 0.4, 0.5],
        persona: %{},
        intent_queue: [],
        memory_state: %{},
        session_count: 1
      }

      metrics = %{
        plv: 0.4,
        entropy: 0.5,
        lambda_hat: 0.273,
        lyapunov: 0.0
      }

      {:ok, evolved_pac, fitness} = Evolution.step(pac, metrics)

      assert is_map(evolved_pac)
      assert evolved_pac.persona["evolved"] == true
      assert fitness.total > 0.0
      assert Map.has_key?(fitness, :components)
    end

    test "gets best params after evolution", %{pid: _pid} do
      pac = %{
        id: "test_pac_best_#{System.unique_integer([:positive])}",
        trait_vector: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.3, 0.5, 0.4, 0.5],
        persona: %{},
        intent_queue: [],
        memory_state: %{},
        session_count: 1
      }

      metrics = %{plv: 0.4, entropy: 0.5, lambda_hat: 0.273, lyapunov: 0.0}

      # Run a few steps
      for _ <- 1..3 do
        Evolution.step(pac, metrics)
      end

      {:ok, best} = Evolution.best_params(pac.id)

      assert is_map(best)
      # Should have trait keys
      assert Map.has_key?(best, :aggression) or Map.has_key?(best, :lambda_sensitivity)
    end

    test "gets lineage after evolution", %{pid: _pid} do
      pac = %{
        id: "test_pac_lineage_#{System.unique_integer([:positive])}",
        trait_vector: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.3, 0.5, 0.4, 0.5],
        persona: %{},
        intent_queue: [],
        memory_state: %{},
        session_count: 1
      }

      metrics = %{plv: 0.4, entropy: 0.5, lambda_hat: 0.273, lyapunov: 0.0}

      # Run evolution
      Evolution.step(pac, metrics)

      {:ok, lineage} = Evolution.get_lineage(pac.id)

      assert is_list(lineage)
      assert length(lineage) >= 1

      [entry | _] = lineage
      assert Map.has_key?(entry, :generation)
      assert Map.has_key?(entry, :fitness)
      assert Map.has_key?(entry, :traits)
    end

    test "switches profile", %{pid: _pid} do
      pac_id = "test_pac_switch_#{System.unique_integer([:positive])}"

      {:ok, _} = Evolution.start_session(pac_id, profile: :balanced)
      :ok = Evolution.switch_profile(pac_id, :explorer)

      # Profile switch should succeed without error
    end

    test "spawns child from parent", %{pid: _pid} do
      parent_pac = %{
        id: "parent_pac_#{System.unique_integer([:positive])}",
        trait_vector: [0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.273, 0.5, 0.4, 0.6],
        persona: %{},
        intent_queue: [],
        memory_state: %{},
        session_count: 5
      }

      metrics = %{plv: 0.4, entropy: 0.5, lambda_hat: 0.273, lyapunov: 0.0}

      # Run parent evolution first
      {:ok, _, _} = Evolution.step(parent_pac, metrics)

      # Spawn child
      {:ok, child_pac} = Evolution.spawn_child(parent_pac.id, mutation_rate: 0.1)

      assert child_pac.persona["lineage"]["parent_id"] == parent_pac.id
      assert is_list(child_pac.trait_vector)
      assert length(child_pac.trait_vector) == 10
    end
  end

  describe "edge cases" do
    test "handles empty trait vector" do
      pac = %{
        id: "empty_traits",
        trait_vector: [],
        persona: %{},
        intent_queue: [],
        memory_state: %{},
        session_count: 1
      }

      evolved_traits = %{aggression: 0.5}

      {:ok, evolved_pac} = Evolution.apply_evolution(pac, evolved_traits)

      assert is_list(evolved_pac.trait_vector)
    end

    test "handles missing metrics" do
      {:ok, profile} = Evolution.get_profile(:balanced)

      metrics = %{}  # Empty metrics
      pac = %{intent_queue: [], memory_state: %{}, session_count: 1}

      result = Evolution.compute_fitness(metrics, pac, profile)

      assert result.total >= 0.0
      assert result.total <= 1.0
    end
  end
end
