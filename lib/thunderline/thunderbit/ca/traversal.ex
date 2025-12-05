# SPDX-FileCopyrightText: 2025 Thunderline Contributors
# SPDX-License-Identifier: MIT

defmodule Thunderline.Thunderbit.CA.Traversal do
  @moduledoc """
  HC-Δ-9: CA Traversal API for Thunderbit Navigation

  This module provides the navigation layer for Thunderbits traversing
  the cellular automata lattice. It bridges the symbolic layer (Thunderbits)
  with the activation substrate (CA.World).

  ## Core Operations

  - `active_bits/2` - Find all Thunderbits above activation threshold
  - `locate_bit/2` - Get the CA coordinates where a bit resides
  - `inject_bit/4` - Inject a bit into a cell with activation boost
  - `migrate_bit/4` - Move a bit from one cell to another
  - `propagate_bit/3` - Spread a bit to neighboring cells based on activation

  ## Traversal Patterns

  The CA lattice supports several traversal patterns:

  - **Gradient Descent** - Bits move toward higher activation
  - **Random Walk** - Bits diffuse randomly
  - **Targeted** - Bits move toward specific coordinates
  - **Homeostatic** - Bits seek equilibrium states
  """

  alias Thunderline.Thunderbit.CA.{Cell, World}

  @type coord :: {integer(), integer(), integer()}

  # ============================================================================
  # Bit Location Queries
  # ============================================================================

  @doc """
  Finds all cells containing Thunderbits with activation above threshold.

  Returns a list of `{coord, cell, bit_ids}` tuples.

  ## Examples

      iex> active = CA.Traversal.active_bits(world, 0.5)
      iex> length(active)
      42
  """
  @spec active_bits(World.t(), float()) :: [{coord(), Cell.t(), [String.t()]}]
  def active_bits(%World{} = world, threshold \\ 0.1) when is_float(threshold) do
    world.cells
    |> Enum.filter(fn {_coord, cell} ->
      cell.activation > threshold and length(cell.thunderbit_ids) > 0
    end)
    |> Enum.map(fn {coord, cell} ->
      {coord, cell, cell.thunderbit_ids}
    end)
  end

  @doc """
  Finds all cells containing a specific Thunderbit.

  Returns a list of coordinates where the bit is present.
  """
  @spec locate_bit(World.t(), String.t()) :: [coord()]
  def locate_bit(%World{cells: cells}, bit_id) when is_binary(bit_id) do
    cells
    |> Enum.filter(fn {_coord, cell} ->
      bit_id in cell.thunderbit_ids
    end)
    |> Enum.map(fn {coord, _cell} -> coord end)
  end

  @doc """
  Gets the primary location of a bit (highest activation cell containing it).
  """
  @spec primary_location(World.t(), String.t()) :: coord() | nil
  def primary_location(%World{cells: cells}, bit_id) when is_binary(bit_id) do
    cells
    |> Enum.filter(fn {_coord, cell} -> bit_id in cell.thunderbit_ids end)
    |> Enum.max_by(fn {_coord, cell} -> cell.activation end, fn -> nil end)
    |> case do
      nil -> nil
      {coord, _cell} -> coord
    end
  end

  @doc """
  Returns all Thunderbits present in the world.
  """
  @spec all_bits(World.t()) :: [String.t()]
  def all_bits(%World{cells: cells}) do
    cells
    |> Enum.flat_map(fn {_coord, cell} -> cell.thunderbit_ids end)
    |> Enum.uniq()
  end

  @doc """
  Counts occurrences of each bit across all cells.
  """
  @spec bit_distribution(World.t()) :: %{String.t() => non_neg_integer()}
  def bit_distribution(%World{cells: cells}) do
    cells
    |> Enum.flat_map(fn {_coord, cell} -> cell.thunderbit_ids end)
    |> Enum.frequencies()
  end

  # ============================================================================
  # Bit Injection & Removal
  # ============================================================================

  @doc """
  Injects a Thunderbit into a cell at the given coordinate.

  Optionally boosts the cell's activation.

  ## Options

  - `:activation_boost` - Amount to increase activation (default: 0.3)
  - `:energy_cost` - Energy consumed by injection (default: 0.1)

  ## Examples

      iex> {:ok, world} = CA.Traversal.inject_bit(world, {5, 5, 5}, "bit_123")
      iex> CA.Traversal.locate_bit(world, "bit_123")
      [{5, 5, 5}]
  """
  @spec inject_bit(World.t(), coord(), String.t(), keyword()) :: {:ok, World.t()}
  def inject_bit(%World{} = world, coord, bit_id, opts \\ []) when is_binary(bit_id) do
    activation_boost = Keyword.get(opts, :activation_boost, 0.3)
    energy_cost = Keyword.get(opts, :energy_cost, 0.1)

    updated =
      World.update_cell(world, coord, fn cell ->
        new_energy = max(0.0, cell.energy - energy_cost)
        new_activation = min(1.0, cell.activation + activation_boost)

        cell
        |> Cell.add_thunderbit(bit_id)
        |> then(&%{&1 | activation: new_activation, energy: new_energy})
      end)

    {:ok, updated}
  end

  @doc """
  Removes a Thunderbit from a cell.
  """
  @spec remove_bit(World.t(), coord(), String.t()) :: {:ok, World.t()}
  def remove_bit(%World{} = world, coord, bit_id) when is_binary(bit_id) do
    updated =
      World.update_cell(world, coord, fn cell ->
        Cell.remove_thunderbit(cell, bit_id)
      end)

    {:ok, updated}
  end

  @doc """
  Removes a Thunderbit from all cells in the world.
  """
  @spec remove_bit_globally(World.t(), String.t()) :: {:ok, World.t()}
  def remove_bit_globally(%World{cells: cells} = world, bit_id) when is_binary(bit_id) do
    new_cells =
      cells
      |> Enum.map(fn {coord, cell} ->
        {coord, Cell.remove_thunderbit(cell, bit_id)}
      end)
      |> Map.new()

    {:ok, %{world | cells: new_cells}}
  end

  # ============================================================================
  # Bit Migration
  # ============================================================================

  @doc """
  Migrates a Thunderbit from one cell to another.

  The source cell loses the bit, the destination gains it with an activation boost.
  """
  @spec migrate_bit(World.t(), String.t(), coord(), coord()) ::
          {:ok, World.t()} | {:error, term()}
  def migrate_bit(%World{} = world, bit_id, from_coord, to_coord) do
    source_cell = World.get_cell(world, from_coord)

    if bit_id in source_cell.thunderbit_ids do
      world
      |> World.update_cell(from_coord, &Cell.remove_thunderbit(&1, bit_id))
      |> World.update_cell(to_coord, fn cell ->
        cell
        |> Cell.add_thunderbit(bit_id)
        |> then(&%{&1 | activation: min(1.0, &1.activation + 0.2)})
      end)
      |> then(&{:ok, &1})
    else
      {:error, :bit_not_at_source}
    end
  end

  @doc """
  Clones a bit to a destination without removing from source.
  """
  @spec clone_bit(World.t(), String.t(), coord(), coord()) :: {:ok, World.t()}
  def clone_bit(%World{} = world, bit_id, _from_coord, to_coord) do
    inject_bit(world, to_coord, bit_id, activation_boost: 0.1)
  end

  # ============================================================================
  # Propagation Patterns
  # ============================================================================

  @doc """
  Propagates a bit to neighboring cells based on activation gradient.

  Bits spread to neighbors with higher activation than threshold.

  ## Options

  - `:threshold` - Minimum neighbor activation for propagation (default: 0.3)
  - `:max_spread` - Maximum number of neighbors to spread to (default: 3)
  """
  @spec propagate_bit(World.t(), String.t(), coord(), keyword()) :: {:ok, World.t()}
  def propagate_bit(%World{} = world, bit_id, from_coord, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.3)
    max_spread = Keyword.get(opts, :max_spread, 3)

    neighbors = World.neighbors(world, from_coord)

    # Filter neighbors by activation and sort descending
    targets =
      neighbors
      |> Enum.filter(&(&1.activation > threshold))
      |> Enum.sort_by(& &1.activation, :desc)
      |> Enum.take(max_spread)
      |> Enum.map(& &1.coord)

    # Inject bit into each target
    updated =
      Enum.reduce(targets, world, fn coord, w ->
        {:ok, w2} = inject_bit(w, coord, bit_id, activation_boost: 0.1)
        w2
      end)

    {:ok, updated}
  end

  @doc """
  Performs gradient ascent: moves a bit toward higher activation.
  """
  @spec gradient_ascent(World.t(), String.t(), coord()) ::
          {:ok, World.t(), coord()} | {:ok, World.t(), nil}
  def gradient_ascent(%World{} = world, bit_id, from_coord) do
    current_cell = World.get_cell(world, from_coord)
    neighbors = World.neighbors(world, from_coord)

    # Find neighbor with highest activation above current
    best_neighbor =
      neighbors
      |> Enum.filter(&(&1.activation > current_cell.activation))
      |> Enum.max_by(& &1.activation, fn -> nil end)

    case best_neighbor do
      nil ->
        # No better neighbor - stay in place
        {:ok, world, nil}

      target ->
        {:ok, updated} = migrate_bit(world, bit_id, from_coord, target.coord)
        {:ok, updated, target.coord}
    end
  end

  @doc """
  Performs random walk: moves a bit to a random neighbor.
  """
  @spec random_walk(World.t(), String.t(), coord()) :: {:ok, World.t(), coord()}
  def random_walk(%World{} = world, bit_id, from_coord) do
    neighbors = World.neighbors(world, from_coord)

    case neighbors do
      [] ->
        # No neighbors - stay in place
        {:ok, world, from_coord}

      _ ->
        target = Enum.random(neighbors)
        {:ok, updated} = migrate_bit(world, bit_id, from_coord, target.coord)
        {:ok, updated, target.coord}
    end
  end

  # ============================================================================
  # Thundercell Grounding Queries
  # ============================================================================

  @doc """
  Finds all cells grounded to a specific Thundercell.
  """
  @spec cells_grounded_to(World.t(), String.t()) :: [coord()]
  def cells_grounded_to(%World{cells: cells}, thundercell_id) when is_binary(thundercell_id) do
    cells
    |> Enum.filter(fn {_coord, cell} ->
      thundercell_id in cell.thundercell_ids
    end)
    |> Enum.map(fn {coord, _cell} -> coord end)
  end

  @doc """
  Returns all Thundercells referenced in the world.
  """
  @spec all_grounded_thundercells(World.t()) :: [String.t()]
  def all_grounded_thundercells(%World{cells: cells}) do
    cells
    |> Enum.flat_map(fn {_coord, cell} -> cell.thundercell_ids end)
    |> Enum.uniq()
  end

  @doc """
  Finds bits that share grounding with a Thundercell.

  Returns bits present in cells grounded to the given Thundercell.
  """
  @spec bits_grounded_to(World.t(), String.t()) :: [String.t()]
  def bits_grounded_to(%World{cells: cells}, thundercell_id) when is_binary(thundercell_id) do
    cells
    |> Enum.filter(fn {_coord, cell} ->
      thundercell_id in cell.thundercell_ids
    end)
    |> Enum.flat_map(fn {_coord, cell} -> cell.thunderbit_ids end)
    |> Enum.uniq()
  end

  # ============================================================================
  # Activation Analysis
  # ============================================================================

  @doc """
  Computes the activation centroid (center of mass of activation).
  """
  @spec activation_centroid(World.t()) :: coord() | nil
  def activation_centroid(%World{cells: cells}) do
    total_activation =
      cells
      |> Enum.map(fn {_coord, cell} -> cell.activation end)
      |> Enum.sum()

    if total_activation == 0.0 do
      nil
    else
      {weighted_x, weighted_y, weighted_z} =
        Enum.reduce(cells, {0.0, 0.0, 0.0}, fn {{x, y, z}, cell}, {wx, wy, wz} ->
          weight = cell.activation
          {wx + x * weight, wy + y * weight, wz + z * weight}
        end)

      {
        round(weighted_x / total_activation),
        round(weighted_y / total_activation),
        round(weighted_z / total_activation)
      }
    end
  end

  @doc """
  Finds the cell with maximum activation.
  """
  @spec max_activation_cell(World.t()) :: {coord(), Cell.t()} | nil
  def max_activation_cell(%World{cells: cells}) do
    cells
    |> Enum.max_by(fn {_coord, cell} -> cell.activation end, fn -> nil end)
  end

  @doc """
  Returns activation heatmap as a list of `{coord, activation}` tuples.
  """
  @spec activation_heatmap(World.t(), float()) :: [{coord(), float()}]
  def activation_heatmap(%World{cells: cells}, min_threshold \\ 0.0) do
    cells
    |> Enum.filter(fn {_coord, cell} -> cell.activation > min_threshold end)
    |> Enum.map(fn {coord, cell} -> {coord, cell.activation} end)
    |> Enum.sort_by(fn {_coord, act} -> act end, :desc)
  end

  # ============================================================================
  # Distance & Path Utilities
  # ============================================================================

  @doc """
  Computes Manhattan distance between two coordinates.
  """
  @spec manhattan_distance(coord(), coord()) :: non_neg_integer()
  def manhattan_distance({x1, y1, z1}, {x2, y2, z2}) do
    abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2)
  end

  @doc """
  Computes Euclidean distance between two coordinates.
  """
  @spec euclidean_distance(coord(), coord()) :: float()
  def euclidean_distance({x1, y1, z1}, {x2, y2, z2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2) + :math.pow(z1 - z2, 2))
  end

  @doc """
  Finds nearest cell containing a specific bit.
  """
  @spec nearest_bit_location(World.t(), String.t(), coord()) :: coord() | nil
  def nearest_bit_location(%World{} = world, bit_id, from_coord) do
    locations = locate_bit(world, bit_id)

    locations
    |> Enum.min_by(&manhattan_distance(from_coord, &1), fn -> nil end)
  end

  @doc """
  Computes a path toward a target using greedy neighbor selection.

  Returns a list of coordinates from start to target (or as close as possible).
  """
  @spec path_to(World.t(), coord(), coord(), keyword()) :: [coord()]
  def path_to(%World{} = world, start, target, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 100)

    do_path_to(world, [start], target, max_steps)
    |> Enum.reverse()
  end

  defp do_path_to(_world, [current | _] = path, target, _max_steps) when current == target do
    path
  end

  defp do_path_to(_world, path, _target, max_steps) when length(path) >= max_steps do
    path
  end

  defp do_path_to(%World{} = world, [current | _] = path, target, max_steps) do
    neighbors = World.neighbors(world, current)

    # Find neighbor closest to target (not in path)
    visited = MapSet.new(path)

    best =
      neighbors
      |> Enum.reject(&MapSet.member?(visited, &1.coord))
      |> Enum.min_by(&manhattan_distance(&1.coord, target), fn -> nil end)

    case best do
      nil ->
        # Stuck - return current path
        path

      cell ->
        do_path_to(world, [cell.coord | path], target, max_steps)
    end
  end
end
