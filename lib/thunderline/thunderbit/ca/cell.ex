# SPDX-FileCopyrightText: 2025 Thunderline Contributors
# SPDX-License-Identifier: MIT

defmodule Thunderline.Thunderbit.CA.Cell do
  @moduledoc """
  HC-Δ-9: Cellular Automata Cell Struct

  A CA.Cell is a unit of the activation lattice. It holds:
  - Spatial coordinate in the 3D lattice
  - Activation dynamics (activation, excitation, inhibition, error)
  - Energy budget for metabolic constraints
  - Cell kind for specialized behavior
  - Links to Thundercells (grounding data) and Thunderbits (semantic particles)

  ## Cell Kinds

  - `:standard` - Normal processing cell
  - `:border` - Edge cells with boundary behavior
  - `:hub` - High-connectivity routing cells
  - `:sink` - Energy absorption / termination cells

  ## Activation Dynamics

  Cells follow a continuous activation model:
  - `activation` ∈ [0.0, 1.0] - current activity level
  - `excitation` - incoming positive signals from neighbors
  - `inhibition` - incoming negative/dampening signals
  - `error_potential` - error signal for learning/adaptation

  ## Energy Model

  Cells have an energy budget that constrains activity:
  - Activation consumes energy
  - Energy regenerates over time
  - Zero energy prevents activation
  """

  @type coord :: {integer(), integer(), integer()}

  @type cell_kind :: :standard | :border | :hub | :sink

  @type t :: %__MODULE__{
          coord: coord(),
          activation: float(),
          excitation: float(),
          inhibition: float(),
          error_potential: float(),
          energy: float(),
          cell_kind: cell_kind(),
          thundercell_ids: [String.t()],
          thunderbit_ids: [String.t()],
          last_updated_at: DateTime.t() | nil
        }

  defstruct coord: {0, 0, 0},
            activation: 0.0,
            excitation: 0.0,
            inhibition: 0.0,
            error_potential: 0.0,
            energy: 1.0,
            cell_kind: :standard,
            thundercell_ids: [],
            thunderbit_ids: [],
            last_updated_at: nil

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new CA.Cell at the given coordinate.

  ## Options

  - `:activation` - Initial activation level (default: 0.0)
  - `:energy` - Initial energy budget (default: 1.0)
  - `:cell_kind` - Cell type (default: :standard)
  - `:thundercell_ids` - Initial grounding cells (default: [])
  - `:thunderbit_ids` - Initial semantic particles (default: [])

  ## Examples

      iex> cell = CA.Cell.new({5, 10, 2})
      iex> cell.coord
      {5, 10, 2}

      iex> cell = CA.Cell.new({0, 0, 0}, cell_kind: :hub, energy: 2.0)
      iex> cell.cell_kind
      :hub
  """
  @spec new(coord(), keyword()) :: t()
  def new(coord, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      coord: coord,
      activation: Keyword.get(opts, :activation, 0.0),
      excitation: Keyword.get(opts, :excitation, 0.0),
      inhibition: Keyword.get(opts, :inhibition, 0.0),
      error_potential: Keyword.get(opts, :error_potential, 0.0),
      energy: Keyword.get(opts, :energy, 1.0),
      cell_kind: Keyword.get(opts, :cell_kind, :standard),
      thundercell_ids: Keyword.get(opts, :thundercell_ids, []),
      thunderbit_ids: Keyword.get(opts, :thunderbit_ids, []),
      last_updated_at: now
    }
  end

  # ============================================================================
  # Activation Dynamics
  # ============================================================================

  @doc """
  Computes the net input signal: excitation - inhibition.
  """
  @spec net_input(t()) :: float()
  def net_input(%__MODULE__{excitation: exc, inhibition: inh}) do
    exc - inh
  end

  @doc """
  Computes the new activation based on net input and energy constraints.

  Uses a sigmoid-like transfer with energy gating:
  - If energy <= 0, activation decays toward 0
  - Otherwise, activation = sigmoid(net_input) * energy_factor
  """
  @spec compute_activation(t(), keyword()) :: float()
  def compute_activation(%__MODULE__{} = cell, opts \\ []) do
    gain = Keyword.get(opts, :gain, 1.0)
    decay = Keyword.get(opts, :decay, 0.1)

    if cell.energy <= 0.0 do
      # No energy - decay activation
      max(0.0, cell.activation - decay)
    else
      net = net_input(cell)
      # Sigmoid transfer function
      raw = 1.0 / (1.0 + :math.exp(-gain * net))
      # Energy gating - reduce activation if energy is low
      energy_factor = min(1.0, cell.energy)
      # Blend with current activation for smooth transitions
      blended = cell.activation * (1.0 - decay) + raw * decay * energy_factor
      clamp(blended, 0.0, 1.0)
    end
  end

  @doc """
  Applies activation update, consuming energy proportional to activation.

  Returns the updated cell with new activation and reduced energy.
  """
  @spec step_activation(t(), keyword()) :: t()
  def step_activation(%__MODULE__{} = cell, opts \\ []) do
    new_activation = compute_activation(cell, opts)
    energy_cost = Keyword.get(opts, :energy_cost, 0.01)

    # Energy consumption proportional to activation
    consumed = new_activation * energy_cost
    new_energy = max(0.0, cell.energy - consumed)

    %{cell | activation: new_activation, energy: new_energy, last_updated_at: DateTime.utc_now()}
  end

  @doc """
  Regenerates cell energy up to a maximum.
  """
  @spec regenerate_energy(t(), float(), float()) :: t()
  def regenerate_energy(%__MODULE__{} = cell, amount, max_energy \\ 1.0) do
    new_energy = min(max_energy, cell.energy + amount)
    %{cell | energy: new_energy}
  end

  @doc """
  Resets excitation and inhibition to zero (for next timestep).
  """
  @spec clear_signals(t()) :: t()
  def clear_signals(%__MODULE__{} = cell) do
    %{cell | excitation: 0.0, inhibition: 0.0}
  end

  @doc """
  Adds excitation signal from a neighbor.
  """
  @spec add_excitation(t(), float()) :: t()
  def add_excitation(%__MODULE__{} = cell, amount) when is_float(amount) do
    %{cell | excitation: cell.excitation + amount}
  end

  @doc """
  Adds inhibition signal from a neighbor.
  """
  @spec add_inhibition(t(), float()) :: t()
  def add_inhibition(%__MODULE__{} = cell, amount) when is_float(amount) do
    %{cell | inhibition: cell.inhibition + amount}
  end

  @doc """
  Adds error potential for learning signals.
  """
  @spec add_error(t(), float()) :: t()
  def add_error(%__MODULE__{} = cell, amount) when is_float(amount) do
    %{cell | error_potential: cell.error_potential + amount}
  end

  @doc """
  Clears error potential after learning step.
  """
  @spec clear_error(t()) :: t()
  def clear_error(%__MODULE__{} = cell) do
    %{cell | error_potential: 0.0}
  end

  # ============================================================================
  # Thundercell Association (Grounding)
  # ============================================================================

  @doc """
  Adds a Thundercell ID to this cell's grounding set.
  """
  @spec add_thundercell(t(), String.t()) :: t()
  def add_thundercell(%__MODULE__{} = cell, thundercell_id) when is_binary(thundercell_id) do
    if thundercell_id in cell.thundercell_ids do
      cell
    else
      %{cell | thundercell_ids: [thundercell_id | cell.thundercell_ids]}
    end
  end

  @doc """
  Removes a Thundercell ID from this cell's grounding set.
  """
  @spec remove_thundercell(t(), String.t()) :: t()
  def remove_thundercell(%__MODULE__{} = cell, thundercell_id) when is_binary(thundercell_id) do
    %{cell | thundercell_ids: List.delete(cell.thundercell_ids, thundercell_id)}
  end

  @doc """
  Checks if cell is grounded to a specific Thundercell.
  """
  @spec grounded_to?(t(), String.t()) :: boolean()
  def grounded_to?(%__MODULE__{} = cell, thundercell_id) do
    thundercell_id in cell.thundercell_ids
  end

  # ============================================================================
  # Thunderbit Association (Semantic Particles)
  # ============================================================================

  @doc """
  Adds a Thunderbit ID to this cell's particle set.
  """
  @spec add_thunderbit(t(), String.t()) :: t()
  def add_thunderbit(%__MODULE__{} = cell, thunderbit_id) when is_binary(thunderbit_id) do
    if thunderbit_id in cell.thunderbit_ids do
      cell
    else
      %{cell | thunderbit_ids: [thunderbit_id | cell.thunderbit_ids]}
    end
  end

  @doc """
  Removes a Thunderbit ID from this cell's particle set.
  """
  @spec remove_thunderbit(t(), String.t()) :: t()
  def remove_thunderbit(%__MODULE__{} = cell, thunderbit_id) when is_binary(thunderbit_id) do
    %{cell | thunderbit_ids: List.delete(cell.thunderbit_ids, thunderbit_id)}
  end

  @doc """
  Checks if a Thunderbit is present in this cell.
  """
  @spec has_thunderbit?(t(), String.t()) :: boolean()
  def has_thunderbit?(%__MODULE__{} = cell, thunderbit_id) do
    thunderbit_id in cell.thunderbit_ids
  end

  @doc """
  Returns the count of Thunderbits in this cell.
  """
  @spec thunderbit_count(t()) :: non_neg_integer()
  def thunderbit_count(%__MODULE__{thunderbit_ids: ids}), do: length(ids)

  # ============================================================================
  # Cell Kind Behavior
  # ============================================================================

  @doc """
  Returns true if this is a boundary cell.
  """
  @spec border?(t()) :: boolean()
  def border?(%__MODULE__{cell_kind: :border}), do: true
  def border?(_), do: false

  @doc """
  Returns true if this is a hub cell (high connectivity).
  """
  @spec hub?(t()) :: boolean()
  def hub?(%__MODULE__{cell_kind: :hub}), do: true
  def hub?(_), do: false

  @doc """
  Returns true if this is a sink cell (energy absorption).
  """
  @spec sink?(t()) :: boolean()
  def sink?(%__MODULE__{cell_kind: :sink}), do: true
  def sink?(_), do: false

  @doc """
  Returns the connectivity multiplier for this cell kind.

  - Hub cells have 2x connectivity
  - Border cells have 0.5x connectivity
  - Standard and sink have 1x
  """
  @spec connectivity_factor(t()) :: float()
  def connectivity_factor(%__MODULE__{cell_kind: :hub}), do: 2.0
  def connectivity_factor(%__MODULE__{cell_kind: :border}), do: 0.5
  def connectivity_factor(_), do: 1.0

  # ============================================================================
  # Serialization
  # ============================================================================

  @doc """
  Converts the cell to a serializable map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cell) do
    %{
      coord: Tuple.to_list(cell.coord),
      activation: cell.activation,
      excitation: cell.excitation,
      inhibition: cell.inhibition,
      error_potential: cell.error_potential,
      energy: cell.energy,
      cell_kind: cell.cell_kind,
      thundercell_ids: cell.thundercell_ids,
      thunderbit_ids: cell.thunderbit_ids,
      last_updated_at: cell.last_updated_at && DateTime.to_iso8601(cell.last_updated_at)
    }
  end

  @doc """
  Reconstructs a cell from a serialized map.
  """
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    coord =
      case data["coord"] || data[:coord] do
        [x, y, z] -> {x, y, z}
        {_, _, _} = c -> c
        _ -> {0, 0, 0}
      end

    last_updated =
      case data["last_updated_at"] || data[:last_updated_at] do
        nil -> nil
        %DateTime{} = dt -> dt
        str when is_binary(str) -> parse_datetime(str)
        _ -> nil
      end

    %__MODULE__{
      coord: coord,
      activation: get_float(data, "activation", :activation, 0.0),
      excitation: get_float(data, "excitation", :excitation, 0.0),
      inhibition: get_float(data, "inhibition", :inhibition, 0.0),
      error_potential: get_float(data, "error_potential", :error_potential, 0.0),
      energy: get_float(data, "energy", :energy, 1.0),
      cell_kind: get_atom(data, "cell_kind", :cell_kind, :standard),
      thundercell_ids: data["thundercell_ids"] || data[:thundercell_ids] || [],
      thunderbit_ids: data["thunderbit_ids"] || data[:thunderbit_ids] || [],
      last_updated_at: last_updated
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  defp get_float(data, str_key, atom_key, default) do
    case data[str_key] || data[atom_key] do
      nil -> default
      val when is_float(val) -> val
      val when is_integer(val) -> val / 1
      _ -> default
    end
  end

  defp get_atom(data, str_key, atom_key, default) do
    case data[str_key] || data[atom_key] do
      nil -> default
      val when is_atom(val) -> val
      val when is_binary(val) -> String.to_existing_atom(val)
      _ -> default
    end
  rescue
    ArgumentError -> default
  end

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
