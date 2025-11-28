defmodule Thunderline.Thunderbolt.CA.Neighborhood do
  @moduledoc """
  3D neighborhood computation for cellular automata.

  Provides various neighborhood types for the CA lattice:
  - Von Neumann (6-connected: face neighbors)
  - Moore (26-connected: all adjacent cells)
  - Extended neighborhoods with configurable radius

  ## Boundary Conditions

  Supports multiple boundary handling strategies:
  - `:clip` - Neighbors outside bounds are excluded
  - `:periodic` - Wraps around (toroidal topology)
  - `:reflect` - Mirrors at boundaries

  ## Reference

  See `docs/HC_ARCHITECTURE_SYNTHESIS.md` Section 1 for lattice architecture.
  """

  @type coord :: {integer(), integer(), integer()}
  @type bounds :: coord()
  @type neighborhood_type :: :von_neumann | :moore | {:von_neumann, pos_integer()} | {:moore, pos_integer()}
  @type boundary_condition :: :clip | :periodic | :reflect

  # ═══════════════════════════════════════════════════════════════
  # Standard Neighborhood Offsets
  # ═══════════════════════════════════════════════════════════════

  # Von Neumann: 6 face neighbors (Manhattan distance = 1)
  @von_neumann_offsets [
    {-1, 0, 0},
    {1, 0, 0},
    {0, -1, 0},
    {0, 1, 0},
    {0, 0, -1},
    {0, 0, 1}
  ]

  # Moore: 26 neighbors (all adjacent, including corners)
  @moore_offsets (for dx <- -1..1,
                      dy <- -1..1,
                      dz <- -1..1,
                      {dx, dy, dz} != {0, 0, 0},
                      do: {dx, dy, dz})

  # ═══════════════════════════════════════════════════════════════
  # Core Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes the neighborhood coordinates for a given cell position.

  ## Parameters

  - `coord` - The {x, y, z} position of the cell
  - `bounds` - The {max_x, max_y, max_z} grid dimensions
  - `neighborhood_type` - Type of neighborhood (`:von_neumann`, `:moore`, or with radius)
  - `boundary_condition` - How to handle edges (default: `:clip`)

  ## Examples

      iex> Neighborhood.compute({5, 5, 5}, {10, 10, 10}, :von_neumann)
      [{4, 5, 5}, {6, 5, 5}, {5, 4, 5}, {5, 6, 5}, {5, 5, 4}, {5, 5, 6}]

      iex> Neighborhood.compute({0, 0, 0}, {10, 10, 10}, :von_neumann, :periodic)
      [{9, 0, 0}, {1, 0, 0}, {0, 9, 0}, {0, 1, 0}, {0, 0, 9}, {0, 0, 1}]

      iex> Neighborhood.compute({5, 5, 5}, {10, 10, 10}, {:moore, 2})
      # Returns all 124 neighbors within radius 2 (5^3 - 1)
  """
  @spec compute(coord(), bounds(), neighborhood_type(), boundary_condition()) :: [coord()]
  def compute(coord, bounds, neighborhood_type, boundary_condition \\ :clip)

  def compute(coord, bounds, :von_neumann, bc) do
    compute_with_offsets(coord, bounds, @von_neumann_offsets, bc)
  end

  def compute(coord, bounds, :moore, bc) do
    compute_with_offsets(coord, bounds, @moore_offsets, bc)
  end

  def compute(coord, bounds, {:von_neumann, radius}, bc) when is_integer(radius) and radius > 0 do
    offsets = generate_von_neumann_offsets(radius)
    compute_with_offsets(coord, bounds, offsets, bc)
  end

  def compute(coord, bounds, {:moore, radius}, bc) when is_integer(radius) and radius > 0 do
    offsets = generate_moore_offsets(radius)
    compute_with_offsets(coord, bounds, offsets, bc)
  end

  @doc """
  Computes neighborhood using custom offsets.

  Useful when you need a specific neighborhood shape not covered by standard types.
  """
  @spec compute_with_offsets(coord(), bounds(), [coord()], boundary_condition()) :: [coord()]
  def compute_with_offsets({x, y, z}, bounds, offsets, boundary_condition) do
    offsets
    |> Enum.map(fn {dx, dy, dz} -> {x + dx, y + dy, z + dz} end)
    |> Enum.map(&apply_boundary(&1, bounds, boundary_condition))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # ═══════════════════════════════════════════════════════════════
  # Offset Generation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Generates Von Neumann neighborhood offsets for a given radius.

  Von Neumann neighborhood includes all cells within Manhattan distance r.
  Size = (2r^3 + 2r + 3r^2)/3 for radius r (excluding center).
  """
  @spec generate_von_neumann_offsets(pos_integer()) :: [coord()]
  def generate_von_neumann_offsets(radius) do
    for dx <- -radius..radius,
        dy <- -radius..radius,
        dz <- -radius..radius,
        abs(dx) + abs(dy) + abs(dz) <= radius,
        {dx, dy, dz} != {0, 0, 0},
        do: {dx, dy, dz}
  end

  @doc """
  Generates Moore neighborhood offsets for a given radius.

  Moore neighborhood includes all cells within Chebyshev distance r.
  Size = (2r + 1)^3 - 1 for radius r (excluding center).
  """
  @spec generate_moore_offsets(pos_integer()) :: [coord()]
  def generate_moore_offsets(radius) do
    for dx <- -radius..radius,
        dy <- -radius..radius,
        dz <- -radius..radius,
        {dx, dy, dz} != {0, 0, 0},
        do: {dx, dy, dz}
  end

  # ═══════════════════════════════════════════════════════════════
  # Boundary Conditions
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Applies boundary condition to a coordinate.

  Returns `nil` for clipped out-of-bounds coordinates.
  """
  @spec apply_boundary(coord(), bounds(), boundary_condition()) :: coord() | nil
  def apply_boundary({x, y, z}, {bx, by, bz}, :clip) do
    if x >= 0 and x < bx and y >= 0 and y < by and z >= 0 and z < bz do
      {x, y, z}
    else
      nil
    end
  end

  def apply_boundary({x, y, z}, {bx, by, bz}, :periodic) do
    {Integer.mod(x, bx), Integer.mod(y, by), Integer.mod(z, bz)}
  end

  def apply_boundary({x, y, z}, {bx, by, bz}, :reflect) do
    {reflect_coord(x, bx), reflect_coord(y, by), reflect_coord(z, bz)}
  end

  defp reflect_coord(c, _bound) when c < 0, do: -c
  defp reflect_coord(c, bound) when c >= bound, do: 2 * bound - c - 2
  defp reflect_coord(c, _bound), do: c

  # ═══════════════════════════════════════════════════════════════
  # Utility Functions
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns the count of neighbors for a given neighborhood type.

  Useful for validating neighborhood computations.
  """
  @spec neighbor_count(neighborhood_type()) :: pos_integer()
  def neighbor_count(:von_neumann), do: 6
  def neighbor_count(:moore), do: 26
  def neighbor_count({:von_neumann, r}), do: length(generate_von_neumann_offsets(r))
  def neighbor_count({:moore, r}), do: (2 * r + 1) ** 3 - 1

  @doc """
  Returns the standard offsets for a neighborhood type.
  """
  @spec offsets(neighborhood_type()) :: [coord()]
  def offsets(:von_neumann), do: @von_neumann_offsets
  def offsets(:moore), do: @moore_offsets
  def offsets({:von_neumann, r}), do: generate_von_neumann_offsets(r)
  def offsets({:moore, r}), do: generate_moore_offsets(r)

  @doc """
  Checks if two coordinates are neighbors under a given neighborhood type.
  """
  @spec neighbors?(coord(), coord(), neighborhood_type()) :: boolean()
  def neighbors?({x1, y1, z1}, {x2, y2, z2}, :von_neumann) do
    abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2) == 1
  end

  def neighbors?({x1, y1, z1}, {x2, y2, z2}, :moore) do
    dx = abs(x1 - x2)
    dy = abs(y1 - y2)
    dz = abs(z1 - z2)
    max(dx, max(dy, dz)) == 1 and {dx, dy, dz} != {0, 0, 0}
  end

  def neighbors?({x1, y1, z1}, {x2, y2, z2}, {:von_neumann, r}) do
    abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2) <= r and {x1, y1, z1} != {x2, y2, z2}
  end

  def neighbors?({x1, y1, z1}, {x2, y2, z2}, {:moore, r}) do
    dx = abs(x1 - x2)
    dy = abs(y1 - y2)
    dz = abs(z1 - z2)
    max(dx, max(dy, dz)) <= r and {dx, dy, dz} != {0, 0, 0}
  end

  @doc """
  Computes the Manhattan distance between two coordinates.
  """
  @spec manhattan_distance(coord(), coord()) :: non_neg_integer()
  def manhattan_distance({x1, y1, z1}, {x2, y2, z2}) do
    abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2)
  end

  @doc """
  Computes the Chebyshev (chessboard) distance between two coordinates.
  """
  @spec chebyshev_distance(coord(), coord()) :: non_neg_integer()
  def chebyshev_distance({x1, y1, z1}, {x2, y2, z2}) do
    max(abs(x1 - x2), max(abs(y1 - y2), abs(z1 - z2)))
  end

  @doc """
  Computes the Euclidean distance between two coordinates.
  """
  @spec euclidean_distance(coord(), coord()) :: float()
  def euclidean_distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x1 - x2
    dy = y1 - y2
    dz = z1 - z2
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
end
