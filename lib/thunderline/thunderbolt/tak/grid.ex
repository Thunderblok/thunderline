defmodule Thunderline.Thunderbolt.TAK.Grid do
  @moduledoc """
  TAK Grid - ThunderCell integration layer for GPU-accelerated CA evolution.

  ## Overview

  TAK.Grid bridges ThunderCell's concurrent cell processes with GPU tensor operations:

  1. ThunderCell.Cluster manages 1000+ cell processes (fault-isolated)
  2. Grid converts cell states → Nx tensor
  3. TAK.GPUStepper evolves tensor on GPU
  4. Grid applies changes back to cell processes

  ## Architecture

  ```
  ThunderCell.Cluster (Cell Processes)
       ↓ to_tensor/1
  Nx Tensor (GPU-friendly)
       ↓ TAK.GPUStepper.evolve/3
  Updated Tensor
       ↓ update_from_tensor/2
  ThunderCell.Cluster (Updated Cells)
  ```

  ## Phase 3 Implementation

  This module is Phase 3 of TAK build. Current implementation provides
  basic grid structure compatible with existing Bolt.CA.

  Phase 3 will add:
  - `to_tensor/1` - Convert cell processes → Nx tensor
  - `update_from_tensor/2` - Apply GPU results → cell processes
  - ThunderCell.Cluster integration
  - Fault tolerance for tensor ↔ process sync

  ## Usage

  ```elixir
  # Phase 1: Basic grid creation (Bolt.CA compatible)
  grid = TAK.Grid.new({100, 100})

  # Phase 3: ThunderCell integration
  {:ok, cluster_pid} = ThunderCell.Cluster.start_link(dimensions: {100, 100, 100})
  tensor = TAK.Grid.to_tensor(cluster_pid)
  updated_tensor = TAK.GPUStepper.evolve(tensor, born, survive)
  :ok = TAK.Grid.update_from_tensor(cluster_pid, updated_tensor)
  ```
  """

  @type dimensions ::
          {pos_integer(), pos_integer()} | {pos_integer(), pos_integer(), pos_integer()}
  @type t :: %__MODULE__{
          size: dimensions(),
          cells: map(),
          generation: non_neg_integer(),
          metadata: map()
        }

  defstruct size: {10, 10},
            cells: %{},
            generation: 0,
            metadata: %{}

  @doc """
  Create a new grid with given dimensions.

  Backward compatible with Bolt.CA grid structure.

  ## Examples

      # 2D grid (100x100)
      grid = TAK.Grid.new({100, 100})

      # 3D grid (100x100x100) for ThunderCell
      grid = TAK.Grid.new({100, 100, 100})
  """
  def new(size) when is_tuple(size) do
    %__MODULE__{
      size: size,
      cells: %{},
      generation: 0,
      metadata: %{created_at: DateTime.utc_now()}
    }
  end

  @doc """
  Convert Grid struct to Nx tensor.

  Phase 3 implementation. Returns GPU-friendly tensor representation.
  Supports both 2D and 3D grids.

  ## Examples

      grid = TAK.Grid.new({100, 100})
      tensor = TAK.Grid.to_tensor(grid)
      # => #Nx.Tensor<u8[100][100]>
  """
  def to_tensor(%__MODULE__{size: size, cells: cells}) do
    # Create tensor from grid dimensions
    # cells map: %{{x, y} => 1, {x2, y2} => 1, ...} (only alive cells stored)
    # Convert to full tensor (0 = dead, 1 = alive)

    case size do
      {width, height} ->
        # 2D grid
        data =
          for y <- 0..(height - 1),
              x <- 0..(width - 1) do
            Map.get(cells, {x, y}, 0)
          end

        Nx.tensor(data, type: :u8)
        |> Nx.reshape({height, width})

      {depth, height, width} ->
        # 3D grid
        data =
          for z <- 0..(depth - 1),
              y <- 0..(height - 1),
              x <- 0..(width - 1) do
            Map.get(cells, {x, y, z}, 0)
          end

        Nx.tensor(data, type: :u8)
        |> Nx.reshape({depth, height, width})
    end
  end

  @doc """
  Create new Grid from evolved Nx tensor.

  Phase 3 implementation. Converts tensor back to Grid struct.
  Only stores alive cells (value = 1) for memory efficiency.

  ## Examples

      tensor = TAK.Grid.to_tensor(grid)
      updated_tensor = TAK.GPUStepper.evolve(tensor, born, survive)
      new_grid = TAK.Grid.from_tensor(grid, updated_tensor)
  """
  def from_tensor(%__MODULE__{} = grid, %Nx.Tensor{} = tensor) do
    # Extract alive cells from tensor
    # GPU kernel may add batch/channel dimensions - squeeze them
    squeezed = Nx.squeeze(tensor)
    shape = Nx.shape(squeezed)
    flat_data = Nx.to_flat_list(squeezed)

    cells =
      case shape do
        {_height, width} ->
          # 2D grid
          flat_data
          |> Enum.with_index()
          |> Enum.reduce(%{}, fn {value, idx}, acc ->
            if value == 1 do
              x = rem(idx, width)
              y = div(idx, width)
              Map.put(acc, {x, y}, 1)
            else
              acc
            end
          end)

        {_depth, height, width} ->
          # 3D grid
          flat_data
          |> Enum.with_index()
          |> Enum.reduce(%{}, fn {value, idx}, acc ->
            if value == 1 do
              x = rem(idx, width)
              y = rem(div(idx, width), height)
              z = div(idx, width * height)
              Map.put(acc, {x, y, z}, 1)
            else
              acc
            end
          end)
      end

    %{grid | cells: cells}
  end

  @doc """
  Get grid dimensions.

  ## Examples

      grid = TAK.Grid.new({100, 100, 100})
      TAK.Grid.dimensions(grid)
      # => {100, 100, 100}
  """
  def dimensions(%__MODULE__{size: size}), do: size

  @doc """
  Get current generation count.

  ## Examples

      TAK.Grid.generation(grid)
      # => 42
  """
  def generation(%__MODULE__{generation: gen}), do: gen

  @doc """
  Increment generation counter.

  ## Examples

      grid = TAK.Grid.increment_generation(grid)
  """
  def increment_generation(%__MODULE__{} = grid) do
    %{grid | generation: grid.generation + 1}
  end

  @doc """
  Compute delta changes between two grids.

  Returns list of cells that changed (born or died).
  Used for efficient PubSub broadcasting and Thundervine event emission.

  ## Examples

      deltas = TAK.Grid.compute_deltas(old_grid, new_grid)
      # => [
      #   %{coord: {5, 10}, old: 0, new: 1},  # cell born
      #   %{coord: {8, 12}, old: 1, new: 0}   # cell died
      # ]
  """
  def compute_deltas(%__MODULE__{cells: old_cells}, %__MODULE__{cells: new_cells}) do
    # Find all coordinates that changed
    all_coords =
      MapSet.union(
        MapSet.new(Map.keys(old_cells)),
        MapSet.new(Map.keys(new_cells))
      )

    all_coords
    |> Enum.reduce([], fn coord, acc ->
      old_val = Map.get(old_cells, coord, 0)
      new_val = Map.get(new_cells, coord, 0)

      if old_val != new_val do
        [%{coord: coord, old: old_val, new: new_val} | acc]
      else
        acc
      end
    end)
  end

  @doc """
  Compute delta changes from tensor evolution.

  Compares original grid cells with evolved tensor state.
  Returns minimal set of changed cells for efficient broadcasting.

  ## Examples

      tensor = TAK.Grid.to_tensor(grid)
      evolved = TAK.GPUStepper.evolve(tensor, born, survive)
      deltas = TAK.Grid.compute_deltas_from_tensor(grid, evolved)
  """
  def compute_deltas_from_tensor(%__MODULE__{} = old_grid, %Nx.Tensor{} = new_tensor) do
    new_grid = from_tensor(old_grid, new_tensor)
    compute_deltas(old_grid, new_grid)
  end
end
