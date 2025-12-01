defmodule Thunderline.Thunderbolt.Sparse.GridTest do
  @moduledoc """
  Tests for Finch-inspired sparse grid implementation.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Sparse.Grid

  describe "new/2" do
    test "creates grid with correct shape" do
      grid = Grid.new({10, 10, 10})
      assert grid.shape == {10, 10, 10}
    end

    test "starts with zero non-zero entries" do
      grid = Grid.new({5, 5, 5})
      assert grid.nnz == 0
    end

    test "respects format option" do
      hash_grid = Grid.new({5, 5, 5}, format: :hash)
      coo_grid = Grid.new({5, 5, 5}, format: :coo)

      assert hash_grid.format == :hash
      assert coo_grid.format == :coo
    end

    test "respects channels option" do
      grid = Grid.new({5, 5, 5}, channels: 32)
      assert grid.channels == 32
    end
  end

  describe "put/3 and get/2" do
    test "stores and retrieves values (hash format)" do
      grid = Grid.new({10, 10, 10}, format: :hash)
      value = List.duplicate(1.0, 16)

      updated = Grid.put(grid, {5, 5, 5}, value)
      retrieved = Grid.get(updated, {5, 5, 5})

      assert retrieved == value
    end

    test "stores and retrieves values (COO format)" do
      grid = Grid.new({10, 10, 10}, format: :coo)
      value = List.duplicate(0.5, 16)

      updated = Grid.put(grid, {3, 4, 5}, value)
      retrieved = Grid.get(updated, {3, 4, 5})

      assert retrieved == value
    end

    test "returns default for missing coordinates" do
      grid = Grid.new({10, 10, 10})
      default = Grid.get(grid, {7, 7, 7})

      assert default == List.duplicate(0.0, 16)
    end

    test "increments nnz on new entries" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid = Grid.put(grid, {1, 1, 1}, value)
      assert grid.nnz == 1

      grid = Grid.put(grid, {2, 2, 2}, value)
      assert grid.nnz == 2
    end

    test "doesn't increment nnz on update" do
      grid = Grid.new({10, 10, 10})
      value1 = List.duplicate(1.0, 16)
      value2 = List.duplicate(2.0, 16)

      grid = Grid.put(grid, {1, 1, 1}, value1)
      grid = Grid.put(grid, {1, 1, 1}, value2)

      assert grid.nnz == 1
      assert Grid.get(grid, {1, 1, 1}) == value2
    end
  end

  describe "delete/2" do
    test "removes entry" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid = Grid.put(grid, {5, 5, 5}, value)
      assert grid.nnz == 1

      grid = Grid.delete(grid, {5, 5, 5})
      assert grid.nnz == 0
      assert Grid.get(grid, {5, 5, 5}) == grid.default
    end

    test "is idempotent" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid = Grid.put(grid, {5, 5, 5}, value)
      grid = Grid.delete(grid, {5, 5, 5})
      # Delete again
      grid = Grid.delete(grid, {5, 5, 5})

      assert grid.nnz == 0
    end
  end

  describe "each_active/2" do
    test "iterates over all active cells" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid =
        grid
        |> Grid.put({1, 1, 1}, value)
        |> Grid.put({2, 2, 2}, value)
        |> Grid.put({3, 3, 3}, value)

      visited = Agent.start_link(fn -> [] end) |> elem(1)

      Grid.each_active(grid, fn coord, _value ->
        Agent.update(visited, fn list -> [coord | list] end)
      end)

      coords = Agent.get(visited, & &1)
      assert length(coords) == 3
      assert {1, 1, 1} in coords
      assert {2, 2, 2} in coords
      assert {3, 3, 3} in coords

      Agent.stop(visited)
    end
  end

  describe "map_active/2" do
    test "transforms all active cells" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid =
        grid
        |> Grid.put({1, 1, 1}, value)
        |> Grid.put({2, 2, 2}, value)

      doubled =
        Grid.map_active(grid, fn _coord, v ->
          Enum.map(v, &(&1 * 2))
        end)

      assert Grid.get(doubled, {1, 1, 1}) == List.duplicate(2.0, 16)
      assert Grid.get(doubled, {2, 2, 2}) == List.duplicate(2.0, 16)
    end
  end

  describe "filter_active/2" do
    test "removes cells not matching predicate" do
      grid = Grid.new({10, 10, 10})

      grid =
        grid
        # First channel = 1
        |> Grid.put({1, 1, 1}, [1.0] ++ List.duplicate(0.0, 15))
        # First channel = 2
        |> Grid.put({2, 2, 2}, [2.0] ++ List.duplicate(0.0, 15))
        # First channel = 3
        |> Grid.put({3, 3, 3}, [3.0] ++ List.duplicate(0.0, 15))

      filtered =
        Grid.filter_active(grid, fn _coord, value ->
          hd(value) >= 2.0
        end)

      assert filtered.nnz == 2
      # Filtered out
      assert Grid.get(filtered, {1, 1, 1}) == filtered.default
      assert hd(Grid.get(filtered, {2, 2, 2})) == 2.0
      assert hd(Grid.get(filtered, {3, 3, 3})) == 3.0
    end
  end

  describe "neighbors/2" do
    test "returns 26 neighbors in interior" do
      grid = Grid.new({10, 10, 10})
      neighbors = Grid.neighbors(grid, {5, 5, 5})

      # 3x3x3 - 1 = 26 neighbors
      assert length(neighbors) == 26
    end

    test "returns fewer neighbors at boundary" do
      grid = Grid.new({10, 10, 10})
      neighbors = Grid.neighbors(grid, {0, 0, 0})

      # Corner: 2x2x2 - 1 = 7 neighbors
      assert length(neighbors) == 7
    end
  end

  describe "format conversion" do
    test "to_hash preserves data" do
      grid = Grid.new({10, 10, 10}, format: :coo)
      value = List.duplicate(1.5, 16)

      grid = Grid.put(grid, {5, 5, 5}, value)
      hash_grid = Grid.to_hash(grid)

      assert hash_grid.format == :hash
      assert Grid.get(hash_grid, {5, 5, 5}) == value
    end

    test "to_coo preserves data" do
      grid = Grid.new({10, 10, 10}, format: :hash)
      value = List.duplicate(2.5, 16)

      grid = Grid.put(grid, {3, 3, 3}, value)
      coo_grid = Grid.to_coo(grid)

      assert coo_grid.format == :coo
      assert Grid.get(coo_grid, {3, 3, 3}) == value
    end
  end

  describe "sparsity/1" do
    test "returns 1.0 for empty grid" do
      grid = Grid.new({10, 10, 10})
      assert Grid.sparsity(grid) == 1.0
    end

    test "decreases as cells are added" do
      # 1000 cells total
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid = Grid.put(grid, {0, 0, 0}, value)

      # 999/1000 empty = 0.999 sparsity
      assert_in_delta Grid.sparsity(grid), 0.999, 0.001
    end
  end

  describe "count_active/1" do
    test "returns nnz" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid =
        grid
        |> Grid.put({1, 1, 1}, value)
        |> Grid.put({2, 2, 2}, value)

      assert Grid.count_active(grid) == 2
    end
  end

  describe "bounding_box/1" do
    test "returns nil for empty grid" do
      grid = Grid.new({10, 10, 10})
      assert Grid.bounding_box(grid) == nil
    end

    test "returns tight bounds" do
      grid = Grid.new({10, 10, 10})
      value = List.duplicate(1.0, 16)

      grid =
        grid
        |> Grid.put({2, 3, 4}, value)
        |> Grid.put({5, 6, 7}, value)

      {{min_x, min_y, min_z}, {max_x, max_y, max_z}} = Grid.bounding_box(grid)

      assert {min_x, min_y, min_z} == {2, 3, 4}
      assert {max_x, max_y, max_z} == {5, 6, 7}
    end
  end
end
