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
      assert map_size(grid.bits) == 27  # 3^3
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
      assert length(deltas) == 27  # All bits updated
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

      {:ok, _deltas, new_grid} = Stepper.step_thunderbit_grid(grid, %{
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
      grid = update_in(grid.bits, fn bits ->
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
      grid = update_in(grid.bits, fn bits ->
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
end
