defmodule Thunderline.Thunderbolt.TAK.GridTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.TAK.Grid

  describe "new/1" do
    test "creates 2D grid with correct dimensions" do
      grid = Grid.new({10, 20})
      assert grid.size == {10, 20}
      assert grid.cells == %{}
      assert grid.generation == 0
    end

    test "creates 3D grid with correct dimensions" do
      grid = Grid.new({10, 20, 30})
      assert grid.size == {10, 20, 30}
      assert grid.cells == %{}
      assert grid.generation == 0
    end
  end

  describe "to_tensor/1" do
    test "converts empty 2D grid to tensor" do
      grid = Grid.new({3, 4})
      tensor = Grid.to_tensor(grid)

      assert Nx.shape(tensor) == {4, 3}
      assert Nx.type(tensor) == {:u, 8}
      assert Nx.to_flat_list(tensor) == List.duplicate(0, 12)
    end

    test "converts 2D grid with alive cells to tensor" do
      grid = %Grid{
        size: {3, 3},
        cells: %{
          {1, 1} => 1,  # center
          {0, 0} => 1,  # top-left
          {2, 2} => 1   # bottom-right
        }
      }

      tensor = Grid.to_tensor(grid)
      assert Nx.shape(tensor) == {3, 3}

      # Verify alive cells
      flat = Nx.to_flat_list(tensor)
      expected = [
        1, 0, 0,  # row 0: (0,0) alive
        0, 1, 0,  # row 1: (1,1) alive
        0, 0, 1   # row 2: (2,2) alive
      ]
      assert flat == expected
    end

    test "converts empty 3D grid to tensor" do
      grid = Grid.new({2, 3, 4})
      tensor = Grid.to_tensor(grid)

      assert Nx.shape(tensor) == {2, 3, 4}
      assert Nx.type(tensor) == {:u, 8}
      assert Nx.to_flat_list(tensor) == List.duplicate(0, 24)
    end

    test "converts 3D grid with alive cells to tensor" do
      grid = %Grid{
        size: {2, 2, 2},
        cells: %{
          {0, 0, 0} => 1,  # corner
          {1, 1, 1} => 1   # opposite corner
        }
      }

      tensor = Grid.to_tensor(grid)
      assert Nx.shape(tensor) == {2, 2, 2}

      flat = Nx.to_flat_list(tensor)
      # z=0, y=0: [1, 0]  z=0, y=1: [0, 0]
      # z=1, y=0: [0, 0]  z=1, y=1: [0, 1]
      expected = [1, 0, 0, 0, 0, 0, 0, 1]
      assert flat == expected
    end
  end

  describe "from_tensor/2" do
    test "converts tensor back to 2D grid" do
      original = Grid.new({3, 3})

      # Create tensor with specific pattern
      tensor = Nx.tensor([
        [1, 0, 1],
        [0, 1, 0],
        [1, 0, 1]
      ], type: :u8)

      grid = Grid.from_tensor(original, tensor)

      assert grid.size == {3, 3}
      assert grid.cells == %{
        {0, 0} => 1, {2, 0} => 1,
        {1, 1} => 1,
        {0, 2} => 1, {2, 2} => 1
      }
    end

    test "converts tensor back to 3D grid" do
      original = Grid.new({2, 2, 2})

      # Create tensor with corners alive
      tensor = Nx.tensor([
        [[1, 0], [0, 0]],  # z=0
        [[0, 0], [0, 1]]   # z=1
      ], type: :u8)

      grid = Grid.from_tensor(original, tensor)

      assert grid.size == {2, 2, 2}
      assert grid.cells == %{
        {0, 0, 0} => 1,
        {1, 1, 1} => 1
      }
    end

    test "round-trip preserves grid state for 2D" do
      original = %Grid{
        size: {5, 5},
        cells: %{
          {2, 2} => 1,
          {1, 2} => 1,
          {3, 2} => 1
        }
      }

      tensor = Grid.to_tensor(original)
      recovered = Grid.from_tensor(original, tensor)

      assert recovered.cells == original.cells
      assert recovered.size == original.size
    end

    test "round-trip preserves grid state for 3D" do
      original = %Grid{
        size: {4, 4, 4},
        cells: %{
          {2, 2, 2} => 1,
          {1, 2, 2} => 1,
          {3, 2, 2} => 1
        }
      }

      tensor = Grid.to_tensor(original)
      recovered = Grid.from_tensor(original, tensor)

      assert recovered.cells == original.cells
      assert recovered.size == original.size
    end
  end

  describe "compute_deltas/2" do
    test "detects no changes between identical grids" do
      grid1 = %Grid{size: {3, 3}, cells: %{{1, 1} => 1}}
      grid2 = %Grid{size: {3, 3}, cells: %{{1, 1} => 1}}

      deltas = Grid.compute_deltas(grid1, grid2)
      assert deltas == []
    end

    test "detects cell birth" do
      grid1 = %Grid{size: {3, 3}, cells: %{}}
      grid2 = %Grid{size: {3, 3}, cells: %{{1, 1} => 1, {2, 2} => 1}}

      deltas = Grid.compute_deltas(grid1, grid2)
      assert length(deltas) == 2

      assert %{coord: {1, 1}, old: 0, new: 1} in deltas
      assert %{coord: {2, 2}, old: 0, new: 1} in deltas
    end

    test "detects cell death" do
      grid1 = %Grid{size: {3, 3}, cells: %{{1, 1} => 1, {2, 2} => 1}}
      grid2 = %Grid{size: {3, 3}, cells: %{}}

      deltas = Grid.compute_deltas(grid1, grid2)
      assert length(deltas) == 2

      assert %{coord: {1, 1}, old: 1, new: 0} in deltas
      assert %{coord: {2, 2}, old: 1, new: 0} in deltas
    end

    test "detects mixed changes" do
      grid1 = %Grid{size: {3, 3}, cells: %{{0, 0} => 1, {1, 1} => 1}}
      grid2 = %Grid{size: {3, 3}, cells: %{{1, 1} => 1, {2, 2} => 1}}

      deltas = Grid.compute_deltas(grid1, grid2)
      assert length(deltas) == 2

      # (0,0) died, (2,2) born, (1,1) unchanged
      assert %{coord: {0, 0}, old: 1, new: 0} in deltas
      assert %{coord: {2, 2}, old: 0, new: 1} in deltas
    end
  end

  describe "compute_deltas_from_tensor/2" do
    test "detects changes from tensor evolution" do
      original = %Grid{
        size: {3, 3},
        cells: %{{1, 1} => 1}
      }

      # Evolve to blinker pattern
      evolved_tensor = Nx.tensor([
        [0, 1, 0],
        [0, 1, 0],
        [0, 1, 0]
      ], type: :u8)

      deltas = Grid.compute_deltas_from_tensor(original, evolved_tensor)

      # Center cell stays, top and bottom cells born
      assert length(deltas) == 2
      assert %{coord: {1, 0}, old: 0, new: 1} in deltas
      assert %{coord: {1, 2}, old: 0, new: 1} in deltas
    end
  end

  describe "dimensions/1" do
    test "returns 2D dimensions" do
      grid = Grid.new({10, 20})
      assert Grid.dimensions(grid) == {10, 20}
    end

    test "returns 3D dimensions" do
      grid = Grid.new({10, 20, 30})
      assert Grid.dimensions(grid) == {10, 20, 30}
    end
  end

  describe "generation/1" do
    test "returns current generation" do
      grid = %Grid{generation: 42}
      assert Grid.generation(grid) == 42
    end
  end

  describe "increment_generation/1" do
    test "increments generation counter" do
      grid = Grid.new({3, 3})
      assert Grid.generation(grid) == 0

      grid = Grid.increment_generation(grid)
      assert Grid.generation(grid) == 1

      grid = Grid.increment_generation(grid)
      assert Grid.generation(grid) == 2
    end
  end
end
