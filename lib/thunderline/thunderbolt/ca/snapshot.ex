defmodule Thunderline.Thunderbolt.CA.Snapshot do
  @moduledoc """
  Read-only snapshot of CA lattice state for logging, UI visualization, and feature extraction.

  ## Layer Architecture

  This module is part of the **Thunderbolt Physics Layer**, providing a neutral data structure
  for capturing CA state without modifying the underlying simulation.

  ```
  Thunderline.Thunderbit (cognitive)  ←  agent bits, semantic layer
           ↓
  Thunderbolt.Thunderbit (physics)    ←  CA voxels, routing layer
           ↓
  Thunderbolt.CA.Snapshot             ←  YOU ARE HERE (read-only view)
           ↓
  Thunderbolt.Cerebros.Features       ←  feature extraction for TPE
           ↓
  Thunderbolt.Cerebros.TPEBridge      ←  Bayesian optimization
  ```

  ## Usage

      # Capture snapshot from a cluster
      {:ok, snapshot} = Snapshot.capture(cluster_id)

      # Extract for feature pipeline
      features = Thunderbolt.Cerebros.Features.extract(config, context, snapshot, metrics)

      # Log to TPE
      Thunderbolt.Cerebros.TPEBridge.log_trial(features)

  ## Snapshot Structure

  The snapshot captures:
  - `tick` - Current generation number
  - `dims` - Grid dimensions {x, y, z}
  - `cells` - Map of coord => cell_snapshot
  - `stats` - Cluster performance statistics
  - `timestamp` - When snapshot was taken

  Each cell_snapshot contains:
  - `state` - :alive or :dead
  - `activation` - Normalized activation (1.0 for alive, 0.0 for dead)
  - `error_potential` - State instability measure (based on recent history)
  """

  alias Thunderline.Thunderbolt.ThunderCell.Cluster

  @type coord :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @type cell_snapshot :: %{
          state: :alive | :dead,
          activation: float(),
          error_potential: float(),
          generation: non_neg_integer()
        }

  @type t :: %__MODULE__{
          tick: non_neg_integer(),
          dims: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          cells: %{coord() => cell_snapshot()},
          stats: map(),
          ca_rules: map(),
          cluster_id: atom(),
          timestamp: DateTime.t(),
          alive_count: non_neg_integer(),
          dead_count: non_neg_integer(),
          density: float()
        }

  defstruct [
    :tick,
    :dims,
    :cells,
    :stats,
    :ca_rules,
    :cluster_id,
    :timestamp,
    :alive_count,
    :dead_count,
    :density
  ]

  @doc """
  Capture a snapshot of the current CA cluster state.

  ## Options

  - `:include_cells` - Whether to include per-cell data (default: true)
  - `:sample_ratio` - For large grids, sample this ratio of cells (default: 1.0)

  ## Examples

      {:ok, snapshot} = Snapshot.capture(:my_cluster)
      {:ok, snapshot} = Snapshot.capture(:my_cluster, include_cells: false)
      {:ok, snapshot} = Snapshot.capture(:my_cluster, sample_ratio: 0.1)
  """
  @spec capture(atom(), keyword()) :: {:ok, t()} | {:error, term()}
  def capture(cluster_id, opts \\ []) do
    include_cells = Keyword.get(opts, :include_cells, true)
    sample_ratio = Keyword.get(opts, :sample_ratio, 1.0)

    with {:ok, cluster_stats} <- Cluster.get_cluster_stats(cluster_id) do
      dims = cluster_stats.dimensions

      {cells, alive_count, dead_count} =
        if include_cells do
          capture_cells(cluster_id, dims, sample_ratio)
        else
          {%{}, 0, 0}
        end

      total = alive_count + dead_count
      density = if total > 0, do: alive_count / total, else: 0.0

      snapshot = %__MODULE__{
        tick: cluster_stats.generation,
        dims: dims,
        cells: cells,
        stats: cluster_stats.performance,
        ca_rules: Map.get(cluster_stats, :ca_rules, %{}),
        cluster_id: cluster_id,
        timestamp: DateTime.utc_now(),
        alive_count: alive_count,
        dead_count: dead_count,
        density: density
      }

      {:ok, snapshot}
    end
  end

  @doc """
  Capture snapshot - raising version.
  """
  @spec capture!(atom(), keyword()) :: t()
  def capture!(cluster_id, opts \\ []) do
    case capture(cluster_id, opts) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> raise "Failed to capture snapshot: #{inspect(reason)}"
    end
  end

  @doc """
  Get aggregate statistics from a snapshot for feature extraction.

  Returns a map suitable for feeding into `Cerebros.Features.extract/4`.
  """
  @spec aggregate_stats(t()) :: map()
  def aggregate_stats(%__MODULE__{} = snapshot) do
    cell_activations = Enum.map(snapshot.cells, fn {_coord, cell} -> cell.activation end)
    cell_errors = Enum.map(snapshot.cells, fn {_coord, cell} -> cell.error_potential end)

    %{
      tick: snapshot.tick,
      dims: snapshot.dims,
      density: snapshot.density,
      alive_count: snapshot.alive_count,
      dead_count: snapshot.dead_count,
      total_cells: map_size(snapshot.cells),

      # Activation statistics
      mean_activation: safe_mean(cell_activations),
      std_activation: safe_std(cell_activations),
      min_activation: safe_min(cell_activations),
      max_activation: safe_max(cell_activations),

      # Error potential statistics
      mean_error: safe_mean(cell_errors),
      std_error: safe_std(cell_errors),
      max_error: safe_max(cell_errors),

      # Performance stats from cluster
      avg_generation_time: get_in(snapshot.stats, [:avg_generation_time]) || 0.0,
      last_generation_time: get_in(snapshot.stats, [:last_generation_time]) || 0.0,
      total_generations: get_in(snapshot.stats, [:total_generations]) || 0
    }
  end

  @doc """
  Get spatial distribution statistics (for pattern detection).
  """
  @spec spatial_stats(t()) :: map()
  def spatial_stats(%__MODULE__{} = snapshot) do
    {_dim_x, _dim_y, dim_z} = snapshot.dims

    # Calculate density per layer (z-axis slices)
    layer_densities =
      for z <- 0..(dim_z - 1) do
        layer_cells =
          Enum.filter(snapshot.cells, fn {{_x, _y, cz}, _cell} -> cz == z end)

        alive = Enum.count(layer_cells, fn {_coord, cell} -> cell.state == :alive end)
        total = length(layer_cells)
        if total > 0, do: alive / total, else: 0.0
      end

    # Calculate activity gradient (change in density across layers)
    gradients =
      layer_densities
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    %{
      layer_densities: layer_densities,
      layer_variance: safe_variance(layer_densities),
      gradient_mean: safe_mean(gradients),
      gradient_max: safe_max(gradients),
      is_stratified: safe_variance(layer_densities) > 0.1
    }
  end

  @doc """
  Convert snapshot to a compact map for serialization/logging.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot) do
    %{
      tick: snapshot.tick,
      dims: Tuple.to_list(snapshot.dims),
      density: snapshot.density,
      alive_count: snapshot.alive_count,
      dead_count: snapshot.dead_count,
      cluster_id: snapshot.cluster_id,
      timestamp: DateTime.to_iso8601(snapshot.timestamp),
      stats: snapshot.stats,
      aggregate: aggregate_stats(snapshot)
    }
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp capture_cells(cluster_id, {dim_x, dim_y, dim_z}, sample_ratio) do
    coords =
      for x <- 0..(dim_x - 1),
          y <- 0..(dim_y - 1),
          z <- 0..(dim_z - 1) do
        {x, y, z}
      end

    # Apply sampling if ratio < 1.0
    sampled_coords =
      if sample_ratio < 1.0 do
        sample_count = round(length(coords) * sample_ratio)
        Enum.take_random(coords, sample_count)
      else
        coords
      end

    # Capture each cell state
    results =
      Enum.reduce(sampled_coords, {%{}, 0, 0}, fn coord, {cells_acc, alive_acc, dead_acc} ->
        {x, y, z} = coord

        case Cluster.get_cell_state(cluster_id, x, y, z) do
          {:ok, cell_state} ->
            cell_snapshot = %{
              state: cell_state.current_state,
              activation: if(cell_state.current_state == :alive, do: 1.0, else: 0.0),
              error_potential: calculate_error_potential(cell_state),
              generation: cell_state.generation
            }

            new_alive = if cell_state.current_state == :alive, do: alive_acc + 1, else: alive_acc
            new_dead = if cell_state.current_state == :dead, do: dead_acc + 1, else: dead_acc

            {Map.put(cells_acc, coord, cell_snapshot), new_alive, new_dead}

          {:error, _} ->
            {cells_acc, alive_acc, dead_acc}
        end
      end)

    results
  end

  # Calculate error potential based on state history stability
  defp calculate_error_potential(cell_state) do
    history = Map.get(cell_state, :state_history, [])

    case length(history) do
      0 ->
        0.0

      1 ->
        0.0

      n ->
        # Count state transitions in history
        transitions =
          history
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.count(fn [a, b] -> a != b end)

        # Normalize by possible transitions
        transitions / (n - 1)
    end
  end

  # Safe statistics functions that handle empty lists

  defp safe_mean([]), do: 0.0

  defp safe_mean(list) do
    Enum.sum(list) / length(list)
  end

  defp safe_std([]), do: 0.0
  defp safe_std([_]), do: 0.0

  defp safe_std(list) do
    mean = safe_mean(list)

    variance =
      Enum.reduce(list, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / length(list)

    :math.sqrt(variance)
  end

  defp safe_variance([]), do: 0.0
  defp safe_variance([_]), do: 0.0

  defp safe_variance(list) do
    mean = safe_mean(list)
    Enum.reduce(list, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / length(list)
  end

  defp safe_min([]), do: 0.0
  defp safe_min(list), do: Enum.min(list)

  defp safe_max([]), do: 0.0
  defp safe_max(list), do: Enum.max(list)
end
