# SPDX-FileCopyrightText: 2025 Thunderline Contributors
# SPDX-License-Identifier: MIT

defmodule Thunderline.Thunderbit.CA.World do
  @moduledoc """
  HC-Δ-9: Cellular Automata World (Lattice State)

  The CA.World is the activation lattice that Thunderbits traverse.
  It maintains:
  - 3D grid of CA.Cell structs
  - Global simulation parameters
  - Tick counter for temporal progression
  - Step pipeline for lattice evolution

  ## Step Pipeline (5 Stages)

  Each `step/1` call executes:

  1. **Diffusion** - Spread activation to neighbors
  2. **Decay** - Global activation decay
  3. **Energy Regeneration** - Restore cell energy
  4. **Activation Update** - Compute new activations
  5. **Signal Clear** - Reset excitation/inhibition for next tick

  ## Parameters

  - `diffusion` - Rate of activation spread (default: 0.1)
  - `decay` - Per-tick activation decay (default: 0.05)
  - `neighbor_radius` - Distance for neighbor influence (default: 1)
  - `excitation_gain` - Multiplier for excitatory signals (default: 1.0)
  - `inhibition_gain` - Multiplier for inhibitory signals (default: 0.5)
  - `error_gain` - Multiplier for error signals (default: 0.1)
  - `energy_regen` - Per-tick energy regeneration (default: 0.05)
  - `max_energy` - Maximum cell energy (default: 1.0)
  """

  alias Thunderline.Thunderbit.CA.Cell

  @type coord :: {integer(), integer(), integer()}
  @type dims :: {pos_integer(), pos_integer(), pos_integer()}

  @type params :: %{
          diffusion: float(),
          decay: float(),
          neighbor_radius: pos_integer(),
          excitation_gain: float(),
          inhibition_gain: float(),
          error_gain: float(),
          energy_regen: float(),
          max_energy: float()
        }

  @type t :: %__MODULE__{
          tick: non_neg_integer(),
          dims: dims(),
          cells: %{coord() => Cell.t()},
          params: params(),
          meta: map()
        }

  defstruct tick: 0,
            dims: {10, 10, 10},
            cells: %{},
            params: %{},
            meta: %{}

  @default_params %{
    diffusion: 0.1,
    decay: 0.05,
    neighbor_radius: 1,
    excitation_gain: 1.0,
    inhibition_gain: 0.5,
    error_gain: 0.1,
    energy_regen: 0.05,
    max_energy: 1.0
  }

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new CA.World with the given dimensions.

  ## Options

  - `:params` - Simulation parameters (merged with defaults)
  - `:meta` - Arbitrary metadata
  - `:init_cells` - Whether to initialize all cells (default: true)
  - `:sparse` - If true, don't pre-create cells (default: false)

  ## Examples

      iex> world = CA.World.new({20, 20, 5})
      iex> world.dims
      {20, 20, 5}

      iex> world = CA.World.new({10, 10, 10}, params: %{diffusion: 0.2})
      iex> world.params.diffusion
      0.2
  """
  @spec new(dims(), keyword()) :: t()
  def new(dims, opts \\ []) do
    custom_params = Keyword.get(opts, :params, %{})
    params = Map.merge(@default_params, custom_params)
    sparse = Keyword.get(opts, :sparse, false)
    meta = Keyword.get(opts, :meta, %{})

    cells =
      if sparse do
        %{}
      else
        init_cells(dims)
      end

    %__MODULE__{
      tick: 0,
      dims: dims,
      cells: cells,
      params: params,
      meta: meta
    }
  end

  @doc """
  Creates a sparse world (cells created on demand).
  """
  @spec new_sparse(dims(), keyword()) :: t()
  def new_sparse(dims, opts \\ []) do
    new(dims, Keyword.put(opts, :sparse, true))
  end

  defp init_cells({x_max, y_max, z_max}) do
    for x <- 0..(x_max - 1),
        y <- 0..(y_max - 1),
        z <- 0..(z_max - 1),
        into: %{} do
      coord = {x, y, z}
      cell_kind = classify_cell_kind(coord, {x_max, y_max, z_max})
      {{x, y, z}, Cell.new(coord, cell_kind: cell_kind)}
    end
  end

  defp classify_cell_kind({x, y, z}, {x_max, y_max, z_max}) do
    # Border cells at edges
    cond do
      x == 0 or x == x_max - 1 or y == 0 or y == y_max - 1 or z == 0 or z == z_max - 1 ->
        :border

      # Hub cells at center (roughly)
      x > div(x_max, 3) and x < div(2 * x_max, 3) and
        y > div(y_max, 3) and y < div(2 * y_max, 3) and
          z > div(z_max, 3) and z < div(2 * z_max, 3) ->
        :hub

      true ->
        :standard
    end
  end

  # ============================================================================
  # Cell Access
  # ============================================================================

  @doc """
  Gets a cell at the given coordinate.

  For sparse worlds, returns a default cell if not present.
  """
  @spec get_cell(t(), coord()) :: Cell.t()
  def get_cell(%__MODULE__{cells: cells} = world, coord) do
    case Map.get(cells, coord) do
      nil ->
        # Create on demand for sparse worlds
        cell_kind = classify_cell_kind(coord, world.dims)
        Cell.new(coord, cell_kind: cell_kind)

      cell ->
        cell
    end
  end

  @doc """
  Sets a cell at the given coordinate.
  """
  @spec put_cell(t(), coord(), Cell.t()) :: t()
  def put_cell(%__MODULE__{cells: cells} = world, coord, cell) do
    %{world | cells: Map.put(cells, coord, cell)}
  end

  @doc """
  Updates a cell at the given coordinate using a function.
  """
  @spec update_cell(t(), coord(), (Cell.t() -> Cell.t())) :: t()
  def update_cell(%__MODULE__{} = world, coord, fun) when is_function(fun, 1) do
    cell = get_cell(world, coord)
    updated = fun.(cell)
    put_cell(world, coord, updated)
  end

  @doc """
  Returns all cells as a list.
  """
  @spec list_cells(t()) :: [Cell.t()]
  def list_cells(%__MODULE__{cells: cells}) do
    Map.values(cells)
  end

  @doc """
  Returns cells matching a predicate.
  """
  @spec filter_cells(t(), (Cell.t() -> boolean())) :: [Cell.t()]
  def filter_cells(%__MODULE__{cells: cells}, pred) when is_function(pred, 1) do
    cells
    |> Map.values()
    |> Enum.filter(pred)
  end

  @doc """
  Returns all cells with activation above threshold.
  """
  @spec active_cells(t(), float()) :: [Cell.t()]
  def active_cells(%__MODULE__{} = world, threshold \\ 0.1) do
    filter_cells(world, fn cell -> cell.activation > threshold end)
  end

  # ============================================================================
  # Neighbor Computation
  # ============================================================================

  @doc """
  Returns the neighbor coordinates within the given radius.

  Uses Moore neighborhood (all 26 neighbors in 3D for radius 1).
  """
  @spec neighbor_coords(coord(), pos_integer(), dims()) :: [coord()]
  def neighbor_coords({x, y, z} = _coord, radius, {x_max, y_max, z_max}) do
    for dx <- -radius..radius,
        dy <- -radius..radius,
        dz <- -radius..radius,
        not (dx == 0 and dy == 0 and dz == 0),
        nx = x + dx,
        ny = y + dy,
        nz = z + dz,
        nx >= 0 and nx < x_max,
        ny >= 0 and ny < y_max,
        nz >= 0 and nz < z_max do
      {nx, ny, nz}
    end
  end

  @doc """
  Returns neighbor cells for a given coordinate.
  """
  @spec neighbors(t(), coord()) :: [Cell.t()]
  def neighbors(%__MODULE__{params: params, dims: dims} = world, coord) do
    radius = params.neighbor_radius
    coords = neighbor_coords(coord, radius, dims)
    Enum.map(coords, fn c -> get_cell(world, c) end)
  end

  # ============================================================================
  # Step Pipeline (5 Stages)
  # ============================================================================

  @doc """
  Advances the world by one tick.

  Executes the 5-stage pipeline:
  1. Diffusion
  2. Decay
  3. Energy regeneration
  4. Activation update
  5. Signal clear
  """
  @spec step(t()) :: t()
  def step(%__MODULE__{} = world) do
    world
    |> step_diffusion()
    |> step_decay()
    |> step_energy_regen()
    |> step_activation()
    |> step_clear_signals()
    |> increment_tick()
  end

  @doc """
  Runs multiple steps.
  """
  @spec step_n(t(), pos_integer()) :: t()
  def step_n(%__MODULE__{} = world, n) when is_integer(n) and n > 0 do
    Enum.reduce(1..n, world, fn _, w -> step(w) end)
  end

  # Stage 1: Diffusion - spread activation to neighbors
  defp step_diffusion(%__MODULE__{params: params} = world) do
    diffusion = params.diffusion
    exc_gain = params.excitation_gain
    inh_gain = params.inhibition_gain

    # First pass: compute signals to send
    signals =
      world.cells
      |> Enum.flat_map(fn {coord, cell} ->
        neighbors = neighbor_coords(coord, params.neighbor_radius, world.dims)

        # Active cells send excitation, inhibition based on cell kind
        Enum.map(neighbors, fn neighbor_coord ->
          connectivity = Cell.connectivity_factor(cell)
          signal_strength = cell.activation * diffusion * connectivity

          if Cell.sink?(cell) do
            # Sink cells send inhibition
            {neighbor_coord, :inhibition, signal_strength * inh_gain}
          else
            # Normal cells send excitation
            {neighbor_coord, :excitation, signal_strength * exc_gain}
          end
        end)
      end)

    # Second pass: apply signals
    Enum.reduce(signals, world, fn {coord, signal_type, amount}, w ->
      update_cell(w, coord, fn cell ->
        case signal_type do
          :excitation -> Cell.add_excitation(cell, amount)
          :inhibition -> Cell.add_inhibition(cell, amount)
        end
      end)
    end)
  end

  # Stage 2: Decay - reduce activation globally
  defp step_decay(%__MODULE__{params: params, cells: cells} = world) do
    decay = params.decay

    new_cells =
      cells
      |> Enum.map(fn {coord, cell} ->
        new_activation = max(0.0, cell.activation - decay)
        {coord, %{cell | activation: new_activation}}
      end)
      |> Map.new()

    %{world | cells: new_cells}
  end

  # Stage 3: Energy regeneration
  defp step_energy_regen(%__MODULE__{params: params, cells: cells} = world) do
    regen = params.energy_regen
    max_energy = params.max_energy

    new_cells =
      cells
      |> Enum.map(fn {coord, cell} ->
        {coord, Cell.regenerate_energy(cell, regen, max_energy)}
      end)
      |> Map.new()

    %{world | cells: new_cells}
  end

  # Stage 4: Activation update
  defp step_activation(%__MODULE__{cells: cells} = world) do
    new_cells =
      cells
      |> Enum.map(fn {coord, cell} ->
        {coord, Cell.step_activation(cell)}
      end)
      |> Map.new()

    %{world | cells: new_cells}
  end

  # Stage 5: Clear signals for next tick
  defp step_clear_signals(%__MODULE__{cells: cells} = world) do
    new_cells =
      cells
      |> Enum.map(fn {coord, cell} ->
        {coord, Cell.clear_signals(cell)}
      end)
      |> Map.new()

    %{world | cells: new_cells}
  end

  defp increment_tick(%__MODULE__{tick: tick} = world) do
    %{world | tick: tick + 1}
  end

  # ============================================================================
  # Activation Injection
  # ============================================================================

  @doc """
  Injects activation at a specific coordinate.
  """
  @spec inject_activation(t(), coord(), float()) :: t()
  def inject_activation(%__MODULE__{} = world, coord, amount) when is_float(amount) do
    update_cell(world, coord, fn cell ->
      new_activation = min(1.0, cell.activation + amount)
      %{cell | activation: new_activation, last_updated_at: DateTime.utc_now()}
    end)
  end

  @doc """
  Injects a Thunderbit at a coordinate with activation boost.
  """
  @spec inject_thunderbit(t(), coord(), String.t(), float()) :: t()
  def inject_thunderbit(%__MODULE__{} = world, coord, bit_id, activation_boost \\ 0.5) do
    update_cell(world, coord, fn cell ->
      cell
      |> Cell.add_thunderbit(bit_id)
      |> then(fn c ->
        new_activation = min(1.0, c.activation + activation_boost)
        %{c | activation: new_activation, last_updated_at: DateTime.utc_now()}
      end)
    end)
  end

  @doc """
  Removes a Thunderbit from a coordinate.
  """
  @spec remove_thunderbit(t(), coord(), String.t()) :: t()
  def remove_thunderbit(%__MODULE__{} = world, coord, bit_id) do
    update_cell(world, coord, fn cell ->
      Cell.remove_thunderbit(cell, bit_id)
    end)
  end

  # ============================================================================
  # Thundercell Grounding
  # ============================================================================

  @doc """
  Grounds a Thundercell to a coordinate.
  """
  @spec ground_thundercell(t(), coord(), String.t()) :: t()
  def ground_thundercell(%__MODULE__{} = world, coord, thundercell_id) do
    update_cell(world, coord, fn cell ->
      Cell.add_thundercell(cell, thundercell_id)
    end)
  end

  @doc """
  Removes a Thundercell grounding from a coordinate.
  """
  @spec unground_thundercell(t(), coord(), String.t()) :: t()
  def unground_thundercell(%__MODULE__{} = world, coord, thundercell_id) do
    update_cell(world, coord, fn cell ->
      Cell.remove_thundercell(cell, thundercell_id)
    end)
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Returns statistics about the world state.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{cells: cells, tick: tick, dims: dims}) do
    cell_list = Map.values(cells)
    count = length(cell_list)

    activations = Enum.map(cell_list, & &1.activation)
    energies = Enum.map(cell_list, & &1.energy)

    thunderbit_counts =
      cell_list
      |> Enum.map(&length(&1.thunderbit_ids))
      |> Enum.sum()

    %{
      tick: tick,
      dims: dims,
      cell_count: count,
      total_activation: Enum.sum(activations),
      mean_activation: if(count > 0, do: Enum.sum(activations) / count, else: 0.0),
      max_activation: if(count > 0, do: Enum.max(activations), else: 0.0),
      total_energy: Enum.sum(energies),
      mean_energy: if(count > 0, do: Enum.sum(energies) / count, else: 0.0),
      active_cells: Enum.count(cell_list, &(&1.activation > 0.1)),
      total_thunderbits: thunderbit_counts
    }
  end

  # ============================================================================
  # Serialization
  # ============================================================================

  @doc """
  Converts the world to a serializable map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = world) do
    cells_map =
      world.cells
      |> Enum.map(fn {coord, cell} ->
        {coord_to_string(coord), Cell.to_map(cell)}
      end)
      |> Map.new()

    %{
      tick: world.tick,
      dims: Tuple.to_list(world.dims),
      cells: cells_map,
      params: world.params,
      meta: world.meta
    }
  end

  @doc """
  Reconstructs a world from a serialized map.
  """
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    dims =
      case data["dims"] || data[:dims] do
        [x, y, z] -> {x, y, z}
        {_, _, _} = d -> d
        _ -> {10, 10, 10}
      end

    cells_data = data["cells"] || data[:cells] || %{}

    cells =
      cells_data
      |> Enum.map(fn {coord_str, cell_data} ->
        coord = string_to_coord(coord_str)
        {coord, Cell.from_map(cell_data)}
      end)
      |> Map.new()

    params =
      (data["params"] || data[:params] || %{})
      |> atomize_keys()
      |> then(&Map.merge(@default_params, &1))

    %__MODULE__{
      tick: data["tick"] || data[:tick] || 0,
      dims: dims,
      cells: cells,
      params: params,
      meta: data["meta"] || data[:meta] || %{}
    }
  end

  defp coord_to_string({x, y, z}), do: "#{x},#{y},#{z}"

  defp string_to_coord(str) when is_binary(str) do
    case String.split(str, ",") do
      [x, y, z] -> {String.to_integer(x), String.to_integer(y), String.to_integer(z)}
      _ -> {0, 0, 0}
    end
  end

  defp string_to_coord({x, y, z}), do: {x, y, z}

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> String.to_existing_atom(k)
          true -> k
        end

      {key, v}
    end)
    |> Map.new()
  rescue
    ArgumentError -> map
  end
end
