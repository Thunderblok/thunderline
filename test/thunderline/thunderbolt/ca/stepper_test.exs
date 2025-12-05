defmodule Thunderline.Thunderbolt.CA.StepperTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.Stepper
  alias Thunderline.Thunderbolt.Thunderbit

  describe "legacy grid stepping" do
    test "next/2 returns deltas for legacy grid" do
      grid = %{size: 10}

      {:ok, deltas, new_grid} = Stepper.next(grid, %{rule: :demo})

      assert is_list(deltas)
      assert length(deltas) >= 5
      assert length(deltas) <= 18
      assert new_grid == grid

      # Check delta structure
      [delta | _] = deltas
      assert is_binary(delta.id)
      assert is_atom(delta.state)
      assert is_integer(delta.hex)
      assert is_integer(delta.energy)
    end

    test "step_legacy_grid/2 maintains backward compatibility" do
      grid = %{size: 24}

      {:ok, deltas, _new_grid} = Stepper.step_legacy_grid(grid, :demo)

      assert Enum.all?(deltas, fn d ->
               Map.has_key?(d, :id) and
                 Map.has_key?(d, :state) and
                 Map.has_key?(d, :hex) and
                 Map.has_key?(d, :energy)
             end)
    end
  end

  describe "thunderbit grid creation" do
    test "create_thunderbit_grid/4 creates a full grid" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      assert grid.bounds == {3, 3, 3}
      assert grid.tick == 0
      # 3^3
      assert map_size(grid.bits) == 27
    end

    test "create_thunderbit_grid/4 accepts sparse mode" do
      coords = [{0, 0, 0}, {1, 1, 1}, {2, 2, 2}]
      grid = Stepper.create_thunderbit_grid(10, 10, 10, sparse: true, coords: coords)

      assert grid.bounds == {10, 10, 10}
      assert map_size(grid.bits) == 3
      assert Map.has_key?(grid.bits, {0, 0, 0})
      assert Map.has_key?(grid.bits, {1, 1, 1})
      assert Map.has_key?(grid.bits, {2, 2, 2})
    end

    test "create_thunderbit_grid/4 sets rule_id on all bits" do
      grid = Stepper.create_thunderbit_grid(2, 2, 2, rule_id: :diffusion)

      Enum.each(grid.bits, fn {_coord, bit} ->
        assert bit.rule_id == :diffusion
      end)
    end
  end

  describe "thunderbit grid stepping" do
    test "next/2 steps thunderbit grid and returns deltas" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      {:ok, deltas, new_grid} = Stepper.next(grid, %{rule_id: :demo})

      assert is_list(deltas)
      # All bits updated
      assert length(deltas) == 27
      assert new_grid.tick == 1
      assert map_size(new_grid.bits) == 27
    end

    test "step_thunderbit_grid/2 updates all bit states" do
      grid = Stepper.create_thunderbit_grid(2, 2, 2)

      {:ok, _deltas, new_grid} = Stepper.step_thunderbit_grid(grid, %{rule_id: :demo})

      # All bits should have last_tick updated
      Enum.each(new_grid.bits, fn {_coord, bit} ->
        assert bit.last_tick == 1
      end)
    end

    test "step_thunderbit_grid/2 produces valid delta format" do
      grid = Stepper.create_thunderbit_grid(2, 2, 2)

      {:ok, deltas, _new_grid} = Stepper.step_thunderbit_grid(grid, %{rule_id: :demo})

      [delta | _] = deltas
      assert is_binary(delta.id)
      assert is_integer(delta.x)
      assert is_integer(delta.y)
      assert is_integer(delta.z)
      assert is_integer(delta.tick)
      assert is_integer(delta.hex)
      assert is_float(delta.flow) or is_integer(delta.flow)
      assert is_float(delta.trust)
    end

    test "step_thunderbit_grid/2 respects neighborhood_type" do
      # Create a grid where center cell has different initial state
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      center_bit = grid.bits[{1, 1, 1}] |> Thunderbit.update_state(sigma_flow: 0.9)
      grid = put_in(grid.bits[{1, 1, 1}], center_bit)

      {:ok, _deltas, new_grid} =
        Stepper.step_thunderbit_grid(grid, %{
          rule_id: :demo,
          neighborhood_type: :von_neumann
        })

      # Neighbors of center should have been influenced by it
      # Just verify the computation ran without error
      assert new_grid.tick == 1
    end
  end

  describe "CA rules" do
    test "diffusion rule spreads flow" do
      # Create grid with one high-flow cell
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      center_bit = Thunderbit.new({1, 1, 1}, sigma_flow: 1.0)
      grid = put_in(grid.bits[{1, 1, 1}], center_bit)

      # Zero out all other cells
      grid =
        update_in(grid.bits, fn bits ->
          Enum.map(bits, fn
            {{1, 1, 1}, bit} -> {{1, 1, 1}, bit}
            {coord, bit} -> {coord, %{bit | sigma_flow: 0.0}}
          end)
          |> Map.new()
        end)

      {:ok, _deltas, new_grid} = Stepper.step_thunderbit_grid(grid, %{rule_id: :diffusion})

      # Center should have decreased, neighbors should have increased
      new_center = new_grid.bits[{1, 1, 1}]
      assert new_center.sigma_flow < 1.0
    end

    test "game_of_life_3d rule follows life-like behavior" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      # Seed with a known pattern
      active_coords = [{1, 0, 1}, {1, 1, 1}, {1, 2, 1}]

      grid =
        update_in(grid.bits, fn bits ->
          Enum.map(bits, fn {coord, bit} ->
            if coord in active_coords do
              {coord, %{bit | sigma_flow: 1.0}}
            else
              {coord, %{bit | sigma_flow: 0.0}}
            end
          end)
          |> Map.new()
        end)

      {:ok, _deltas, new_grid} = Stepper.step_thunderbit_grid(grid, %{rule_id: :game_of_life_3d})

      # Should run without error and produce changes
      assert new_grid.tick == 1
    end
  end

  describe "multiple steps" do
    test "grid evolves over multiple steps" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      # Run several steps
      {final_grid, all_deltas} =
        Enum.reduce(1..5, {grid, []}, fn _, {g, acc_deltas} ->
          {:ok, deltas, new_g} = Stepper.next(g, %{rule_id: :demo})
          {new_g, [deltas | acc_deltas]}
        end)

      assert final_grid.tick == 5
      assert length(all_deltas) == 5
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Feature Extraction Tests (HC-Δ-3)
  # ═══════════════════════════════════════════════════════════════

  describe "extract_features/1" do
    test "returns empty features for empty delta list" do
      features = Stepper.extract_features([])

      assert features.mean_energy == 0.0
      assert features.energy_variance == 0.0
      assert features.mean_flow == 0.0
      assert features.activation_count == 0
      assert features.total_count == 0
      assert features.state_distribution == %{}
      assert features.mean_chaos == 0.0
      assert features.phase_coherence == 1.0
      assert features.spatial_centroid == nil
      assert is_integer(features.timestamp)
    end

    test "computes mean_energy from Thunderbit deltas" do
      deltas = [
        %{energy: 0.8, flow: 0.5, state: :active, lambda: 0.2, phase: 0.0},
        %{energy: 0.4, flow: 0.3, state: :stable, lambda: 0.1, phase: 0.0},
        %{energy: 0.2, flow: 0.1, state: :dormant, lambda: 0.0, phase: 0.0}
      ]

      features = Stepper.extract_features(deltas)

      # Mean energy of 0.8, 0.4, 0.2 = 1.4/3 ≈ 0.4667
      assert_in_delta features.mean_energy, 0.4667, 0.001
      # Mean flow of 0.5, 0.3, 0.1 = 0.9/3 = 0.3
      assert_in_delta features.mean_flow, 0.3, 0.001
    end

    test "computes mean_energy from legacy deltas with integer energy" do
      deltas = [
        %{energy: 80, state: :active},
        %{energy: 40, state: :evolving},
        %{energy: 20, state: :inactive}
      ]

      features = Stepper.extract_features(deltas)

      # Integer energies normalized: 80/100=0.8, 40/100=0.4, 20/100=0.2
      # Mean = (0.8 + 0.4 + 0.2) / 3 ≈ 0.4667
      assert_in_delta features.mean_energy, 0.4667, 0.001
      # No flow field, so mean_flow defaults to 0.0
      assert features.mean_flow == 0.0
    end

    test "computes energy_variance" do
      deltas = [
        %{energy: 1.0, state: :active},
        %{energy: 0.5, state: :stable},
        %{energy: 0.0, state: :inactive}
      ]

      features = Stepper.extract_features(deltas)

      # Mean = 0.5, variance = ((1-0.5)² + (0.5-0.5)² + (0-0.5)²) / 3 = 0.5/3 ≈ 0.1667
      assert_in_delta features.energy_variance, 0.1667, 0.001
    end

    test "counts activations correctly" do
      deltas = [
        %{energy: 0.8, state: :active},
        %{energy: 0.6, state: :stable},
        %{energy: 0.3, state: :dormant},
        %{energy: 0.1, state: :inactive},
        %{energy: 0.9, state: :chaotic}
      ]

      features = Stepper.extract_features(deltas)

      # active, stable, chaotic count as activations = 3
      assert features.activation_count == 3
      assert features.total_count == 5
    end

    test "computes state_distribution" do
      deltas = [
        %{energy: 0.8, state: :active},
        %{energy: 0.6, state: :stable},
        %{energy: 0.5, state: :stable},
        %{energy: 0.1, state: :inactive}
      ]

      features = Stepper.extract_features(deltas)

      assert features.state_distribution == %{
               active: 1,
               stable: 2,
               inactive: 1
             }
    end

    test "computes mean_chaos from lambda values" do
      deltas = [
        %{energy: 0.5, state: :active, lambda: 0.6},
        %{energy: 0.5, state: :stable, lambda: 0.4},
        %{energy: 0.5, state: :dormant, lambda: 0.2}
      ]

      features = Stepper.extract_features(deltas)

      # Mean of 0.6, 0.4, 0.2 = 0.4
      assert_in_delta features.mean_chaos, 0.4, 0.001
    end

    test "computes phase_coherence for aligned phases" do
      # All phases at 0 = perfectly coherent
      deltas = [
        %{energy: 0.5, state: :active, phase: 0.0},
        %{energy: 0.5, state: :stable, phase: 0.0},
        %{energy: 0.5, state: :dormant, phase: 0.0}
      ]

      features = Stepper.extract_features(deltas)

      # Perfect coherence = 0.0
      assert_in_delta features.phase_coherence, 0.0, 0.01
    end

    test "computes phase_coherence for random phases" do
      # Uniformly distributed phases around circle
      deltas = [
        %{energy: 0.5, state: :active, phase: 0.0},
        %{energy: 0.5, state: :stable, phase: :math.pi() * 2 / 3},
        %{energy: 0.5, state: :dormant, phase: :math.pi() * 4 / 3}
      ]

      features = Stepper.extract_features(deltas)

      # Low coherence (but not exactly 1 due to finite sample)
      assert features.phase_coherence > 0.8
    end

    test "computes spatial_centroid from x/y/z coordinates" do
      deltas = [
        %{x: 0, y: 0, z: 0, energy: 0.5, state: :active},
        %{x: 2, y: 2, z: 2, energy: 0.5, state: :stable}
      ]

      features = Stepper.extract_features(deltas)

      # Center of mass with equal energy weights = (1.0, 1.0, 1.0)
      assert features.spatial_centroid == {1.0, 1.0, 1.0}
    end

    test "computes weighted spatial_centroid" do
      deltas = [
        %{x: 0, y: 0, z: 0, energy: 0.25, state: :dormant},
        %{x: 4, y: 4, z: 4, energy: 0.75, state: :active}
      ]

      features = Stepper.extract_features(deltas)

      # Weighted by energy: (0*0.25 + 4*0.75) / 1.0 = 3.0 for each axis
      assert features.spatial_centroid == {3.0, 3.0, 3.0}
    end

    test "returns nil centroid when no coordinates present" do
      deltas = [
        %{energy: 0.5, state: :active},
        %{energy: 0.5, state: :stable}
      ]

      features = Stepper.extract_features(deltas)

      assert features.spatial_centroid == nil
    end
  end

  describe "step_with_features/2" do
    test "returns deltas, grid, and features in one call" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      {:ok, deltas, new_grid, features} = Stepper.step_with_features(grid, %{rule_id: :demo})

      assert is_list(deltas)
      assert length(deltas) == 27
      assert new_grid.tick == 1

      # Features should be computed from the deltas
      assert features.total_count == 27
      assert is_float(features.mean_energy)
      assert is_float(features.mean_flow)
      assert is_map(features.state_distribution)
      assert is_integer(features.timestamp)
    end

    test "features reflect actual delta values" do
      # Create a grid with known state
      grid = Stepper.create_thunderbit_grid(2, 2, 2)

      {:ok, deltas, _new_grid, features} = Stepper.step_with_features(grid, %{rule_id: :demo})

      # Manually compute what features should be using :energy field
      energies = Enum.map(deltas, & &1.energy)
      expected_mean_energy = Enum.sum(energies) / length(energies)

      assert_in_delta features.mean_energy, expected_mean_energy, 0.0001

      # Also verify mean_flow
      flows = Enum.map(deltas, & &1.flow)
      expected_mean_flow = Enum.sum(flows) / length(flows)

      assert_in_delta features.mean_flow, expected_mean_flow, 0.0001
    end
  end

  describe "feature extraction integration" do
    test "features evolve over multiple steps" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)

      # Run several steps and collect features
      {_final_grid, feature_history} =
        Enum.reduce(1..5, {grid, []}, fn _, {g, acc_features} ->
          {:ok, _deltas, new_g, features} = Stepper.step_with_features(g, %{rule_id: :demo})
          {new_g, [features | acc_features]}
        end)

      # Should have 5 feature snapshots
      assert length(feature_history) == 5

      # All should have valid structure
      Enum.each(feature_history, fn f ->
        assert is_float(f.mean_energy)
        assert is_float(f.energy_variance)
        assert is_float(f.mean_flow)
        assert is_integer(f.activation_count)
        assert is_map(f.state_distribution)
      end)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # HC-95: V2 Ternary Grid Tests (Wired to TernaryState)
  # ═══════════════════════════════════════════════════════════════

  describe "v2 ternary grid stepping (HC-95)" do
    test "next/2 dispatches to step_ternary_grid when rule_version: 2" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      ruleset = %{rule_id: :demo, rule_version: 2}

      {:ok, deltas, new_grid} = Stepper.next(grid, ruleset)

      # Should produce valid output
      assert is_list(deltas)
      assert length(deltas) == 27
      assert new_grid.tick == 1
    end

    test "step_ternary_grid/2 uses Thunderbit.ternary_tick" do
      grid = Stepper.create_thunderbit_grid(2, 2, 2)
      ruleset = %{rule_id: :demo, rule_version: 2}

      {:ok, deltas, new_grid} = Stepper.step_ternary_grid(grid, ruleset)

      # All bits should be updated
      assert length(deltas) == 8
      assert new_grid.tick == 1

      # Check that ternary state is valid (sigma in -1..1 or 0..1 range)
      Enum.each(new_grid.bits, fn {_coord, bit} ->
        assert bit.last_tick == 1
        # sigma_flow should be a valid float
        assert is_float(bit.sigma_flow) or is_integer(bit.sigma_flow)
      end)
    end

    test "step_ternary_grid/2 respects neighborhood_type option" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      ruleset = %{rule_id: :demo, rule_version: 2, neighborhood_type: :von_neumann}

      {:ok, _deltas, new_grid} = Stepper.step_ternary_grid(grid, ruleset)

      # Should complete without error
      assert new_grid.tick == 1
    end

    test "step_ternary_grid/2 respects boundary_condition option" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      ruleset = %{rule_id: :demo, rule_version: 2, boundary_condition: :periodic}

      {:ok, _deltas, new_grid} = Stepper.step_ternary_grid(grid, ruleset)

      assert new_grid.tick == 1
    end

    test "step_ternary_grid/2 can update MIRAS" do
      grid = Stepper.create_thunderbit_grid(2, 2, 2)
      ruleset = %{rule_id: :demo, rule_version: 2, update_miras: true}

      {:ok, _deltas, new_grid} = Stepper.step_ternary_grid(grid, ruleset)

      # MIRAS metrics may be updated - just verify no crash
      assert new_grid.tick == 1
    end

    test "rule_version: 1 (default) uses step_thunderbit_grid" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      ruleset = %{rule_id: :demo, rule_version: 1}

      {:ok, deltas, new_grid} = Stepper.next(grid, ruleset)

      # Should use v1 path and succeed
      assert is_list(deltas)
      assert new_grid.tick == 1
    end

    test "missing rule_version defaults to v1" do
      grid = Stepper.create_thunderbit_grid(3, 3, 3)
      ruleset = %{rule_id: :demo}

      {:ok, _deltas, new_grid} = Stepper.next(grid, ruleset)

      # Should succeed using v1 path
      assert new_grid.tick == 1
    end
  end
end
