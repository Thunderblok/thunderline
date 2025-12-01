defmodule Thunderline.Thunderbolt.CA.NeighborhoodTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.Neighborhood

  describe "compute/4 with Von Neumann neighborhood" do
    test "returns 6 face neighbors for interior cell" do
      neighbors = Neighborhood.compute({5, 5, 5}, {10, 10, 10}, :von_neumann)

      assert length(neighbors) == 6
      assert {4, 5, 5} in neighbors
      assert {6, 5, 5} in neighbors
      assert {5, 4, 5} in neighbors
      assert {5, 6, 5} in neighbors
      assert {5, 5, 4} in neighbors
      assert {5, 5, 6} in neighbors
    end

    test "clips neighbors at boundary with :clip" do
      neighbors = Neighborhood.compute({0, 0, 0}, {10, 10, 10}, :von_neumann, :clip)

      # Only 3 neighbors (positive direction)
      assert length(neighbors) == 3
      assert {1, 0, 0} in neighbors
      assert {0, 1, 0} in neighbors
      assert {0, 0, 1} in neighbors
    end

    test "wraps neighbors with :periodic" do
      neighbors = Neighborhood.compute({0, 0, 0}, {10, 10, 10}, :von_neumann, :periodic)

      assert length(neighbors) == 6
      # wrapped from -1
      assert {9, 0, 0} in neighbors
      assert {1, 0, 0} in neighbors
      # wrapped from -1
      assert {0, 9, 0} in neighbors
      assert {0, 1, 0} in neighbors
      # wrapped from -1
      assert {0, 0, 9} in neighbors
      assert {0, 0, 1} in neighbors
    end
  end

  describe "compute/4 with Moore neighborhood" do
    test "returns 26 neighbors for interior cell" do
      neighbors = Neighborhood.compute({5, 5, 5}, {10, 10, 10}, :moore)

      assert length(neighbors) == 26
      # Check corners
      assert {4, 4, 4} in neighbors
      assert {6, 6, 6} in neighbors
      # Check faces
      assert {4, 5, 5} in neighbors
      # Check edges
      assert {4, 4, 5} in neighbors
    end

    test "clips neighbors at corner" do
      neighbors = Neighborhood.compute({0, 0, 0}, {10, 10, 10}, :moore, :clip)

      # Corner cell has 7 neighbors (only positive octant + edges)
      assert length(neighbors) == 7
    end
  end

  describe "compute/4 with extended neighborhoods" do
    test "von_neumann with radius 2 includes all cells within Manhattan distance 2" do
      neighbors = Neighborhood.compute({5, 5, 5}, {10, 10, 10}, {:von_neumann, 2})

      # Should include cells at distance 1 and 2
      # distance 2
      assert {5, 5, 3} in neighbors
      # distance 2
      assert {4, 5, 4} in neighbors
      # distance 1
      assert {5, 5, 4} in neighbors
    end

    test "moore with radius 2 returns 124 neighbors" do
      neighbors = Neighborhood.compute({5, 5, 5}, {10, 10, 10}, {:moore, 2})

      # 5^3 - 1 = 124
      assert length(neighbors) == 124
    end
  end

  describe "neighbor_count/1" do
    test "returns correct counts for standard neighborhoods" do
      assert Neighborhood.neighbor_count(:von_neumann) == 6
      assert Neighborhood.neighbor_count(:moore) == 26
    end

    test "returns correct counts for extended neighborhoods" do
      assert Neighborhood.neighbor_count({:moore, 1}) == 26
      assert Neighborhood.neighbor_count({:moore, 2}) == 124
      # (2*2+1)^3 - 1 = 5^3 - 1 = 124
    end
  end

  describe "neighbors?/3" do
    test "correctly identifies von_neumann neighbors" do
      assert Neighborhood.neighbors?({5, 5, 5}, {5, 5, 6}, :von_neumann)
      assert Neighborhood.neighbors?({5, 5, 5}, {4, 5, 5}, :von_neumann)
      # diagonal
      refute Neighborhood.neighbors?({5, 5, 5}, {4, 4, 5}, :von_neumann)
      # same cell
      refute Neighborhood.neighbors?({5, 5, 5}, {5, 5, 5}, :von_neumann)
    end

    test "correctly identifies moore neighbors" do
      assert Neighborhood.neighbors?({5, 5, 5}, {5, 5, 6}, :moore)
      # corner
      assert Neighborhood.neighbors?({5, 5, 5}, {4, 4, 4}, :moore)
      # too far
      refute Neighborhood.neighbors?({5, 5, 5}, {3, 5, 5}, :moore)
      # same cell
      refute Neighborhood.neighbors?({5, 5, 5}, {5, 5, 5}, :moore)
    end
  end

  describe "distance functions" do
    test "manhattan_distance/2" do
      assert Neighborhood.manhattan_distance({0, 0, 0}, {1, 2, 3}) == 6
      assert Neighborhood.manhattan_distance({5, 5, 5}, {5, 5, 5}) == 0
    end

    test "chebyshev_distance/2" do
      assert Neighborhood.chebyshev_distance({0, 0, 0}, {1, 2, 3}) == 3
      assert Neighborhood.chebyshev_distance({5, 5, 5}, {5, 5, 5}) == 0
    end

    test "euclidean_distance/2" do
      assert_in_delta Neighborhood.euclidean_distance({0, 0, 0}, {3, 4, 0}), 5.0, 0.001
    end
  end

  describe "generate_von_neumann_offsets/1" do
    test "generates correct number of offsets" do
      offsets_r1 = Neighborhood.generate_von_neumann_offsets(1)
      offsets_r2 = Neighborhood.generate_von_neumann_offsets(2)

      assert length(offsets_r1) == 6
      # r=2: octahedron in 3D
      assert length(offsets_r2) == 18
    end
  end

  describe "generate_moore_offsets/1" do
    test "generates correct number of offsets" do
      offsets_r1 = Neighborhood.generate_moore_offsets(1)
      offsets_r2 = Neighborhood.generate_moore_offsets(2)

      assert length(offsets_r1) == 26
      assert length(offsets_r2) == 124
    end
  end

  describe "boundary conditions" do
    test "apply_boundary with :reflect" do
      bounds = {10, 10, 10}

      # Inside bounds - unchanged
      assert Neighborhood.apply_boundary({5, 5, 5}, bounds, :reflect) == {5, 5, 5}

      # Negative coords - reflected
      assert Neighborhood.apply_boundary({-1, 5, 5}, bounds, :reflect) == {1, 5, 5}

      # Beyond upper bound - reflected
      assert Neighborhood.apply_boundary({10, 5, 5}, bounds, :reflect) == {8, 5, 5}
    end
  end
end
