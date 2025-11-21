defmodule Thunderline.Thunderbolt.TAK.IntegrationTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.TAK

  @moduletag :integration

  describe "Phase 3 Grid↔Tensor Integration" do
    test "full pipeline: Grid → Tensor → GPU evolve → Grid → Deltas" do
      # Create initial grid with a simple pattern (glider seed)
      grid = %TAK.Grid{
        size: {10, 10},
        cells: %{
          {1, 0} => 1,
          {2, 1} => 1,
          {0, 2} => 1,
          {1, 2} => 1,
          {2, 2} => 1
        },
        generation: 0
      }

      # Conway's Game of Life rules: B3/S23
      born = [3]
      survive = [2, 3]

      # Step 1: Convert to tensor
      tensor = TAK.Grid.to_tensor(grid)
      assert Nx.shape(tensor) == {10, 10}
      assert Nx.type(tensor) == {:u, 8}

      # Step 2: Evolve on GPU
      evolved_tensor = TAK.GPUStepper.evolve(tensor, born, survive)
      assert Nx.shape(evolved_tensor) == {10, 10}

      # Step 3: Convert back to Grid
      new_grid = TAK.Grid.from_tensor(grid, evolved_tensor)
      assert new_grid.size == grid.size

      # Step 4: Compute deltas
      deltas = TAK.Grid.compute_deltas(grid, new_grid)
      
      # Should have some changes (glider evolves)
      assert length(deltas) > 0
      
      # All deltas should have proper structure
      for delta <- deltas do
        assert Map.has_key?(delta, :coord)
        assert Map.has_key?(delta, :old)
        assert Map.has_key?(delta, :new)
        assert delta.old in [0, 1]
        assert delta.new in [0, 1]
        assert delta.old != delta.new
      end
    end

    test "empty grid stays empty" do
      grid = TAK.Grid.new({5, 5})
      
      tensor = TAK.Grid.to_tensor(grid)
      evolved = TAK.GPUStepper.evolve(tensor, [3], [2, 3])
      new_grid = TAK.Grid.from_tensor(grid, evolved)
      
      deltas = TAK.Grid.compute_deltas(grid, new_grid)
      assert deltas == []
    end

    test "stable pattern (block) remains stable" do
      # Block is stable in Conway's Game of Life
      grid = %TAK.Grid{
        size: {5, 5},
        cells: %{
          {1, 1} => 1,
          {2, 1} => 1,
          {1, 2} => 1,
          {2, 2} => 1
        }
      }
      
      tensor = TAK.Grid.to_tensor(grid)
      evolved = TAK.GPUStepper.evolve(tensor, [3], [2, 3])
      new_grid = TAK.Grid.from_tensor(grid, evolved)
      
      deltas = TAK.Grid.compute_deltas(grid, new_grid)
      assert deltas == []
    end

    test "blinker oscillates correctly" do
      # Vertical blinker
      grid = %TAK.Grid{
        size: {5, 5},
        cells: %{
          {2, 1} => 1,
          {2, 2} => 1,
          {2, 3} => 1
        }
      }
      
      tensor = TAK.Grid.to_tensor(grid)
      evolved = TAK.GPUStepper.evolve(tensor, [3], [2, 3])
      new_grid = TAK.Grid.from_tensor(grid, evolved)
      
      # Should become horizontal
      expected_cells = %{
        {1, 2} => 1,
        {2, 2} => 1,
        {3, 2} => 1
      }
      
      assert new_grid.cells == expected_cells
      
      deltas = TAK.Grid.compute_deltas(grid, new_grid)
      # 6 changes: 3 cells die, 3 cells born
      assert length(deltas) == 4  # Actually 4 because center stays
    end

    test "3D grid evolution" do
      # Simple 3D pattern
      grid = %TAK.Grid{
        size: {5, 5, 5},
        cells: %{
          {2, 2, 2} => 1,
          {2, 2, 3} => 1,
          {2, 3, 2} => 1
        }
      }
      
      tensor = TAK.Grid.to_tensor(grid)
      assert Nx.shape(tensor) == {5, 5, 5}
      
      # 3D rules (example)
      evolved = TAK.GPUStepper.evolve(tensor, [5, 6, 7], [4, 5, 6])
      new_grid = TAK.Grid.from_tensor(grid, evolved)
      
      assert new_grid.size == {5, 5, 5}
      
      deltas = TAK.Grid.compute_deltas(grid, new_grid)
      # Should have changes in 3D space
      assert is_list(deltas)
    end

    test "large grid performance sanity check" do
      # Ensure large grids don't crash
      grid = TAK.Grid.new({100, 100})
      
      tensor = TAK.Grid.to_tensor(grid)
      assert Nx.shape(tensor) == {100, 100}
      
      evolved = TAK.GPUStepper.evolve(tensor, [3], [2, 3])
      new_grid = TAK.Grid.from_tensor(grid, evolved)
      
      assert new_grid.size == {100, 100}
    end
  end

  describe "Delta emission for Thundervine" do
    test "deltas have correct format for event emission" do
      grid1 = %TAK.Grid{
        size: {3, 3},
        cells: %{{1, 1} => 1}
      }
      
      grid2 = %TAK.Grid{
        size: {3, 3},
        cells: %{{0, 0} => 1, {2, 2} => 1}
      }
      
      deltas = TAK.Grid.compute_deltas(grid1, grid2)
      
      # Verify format matches what Thundervine.TAKEventRecorder expects
      for delta <- deltas do
        assert is_tuple(delta.coord)
        assert is_integer(delta.old)
        assert is_integer(delta.new)
      end
    end
  end
end
