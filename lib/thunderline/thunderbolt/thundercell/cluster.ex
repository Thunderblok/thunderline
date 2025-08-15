defmodule Thunderline.Thunderbolt.ThunderCell.Cluster do
  @moduledoc """
  Individual CA cluster managing a 3D cellular automata space with
  massive concurrent processing. Each cell is a separate Elixir process
  for maximum concurrency and fault isolation.
  """

  use GenServer

  # 100ms = 10 generations/second
  @default_evolution_interval 100

  defstruct [
    :cluster_id,
    # {X, Y, Z} grid dimensions
    :dimensions,
    # Current CA rules for evolution
    :ca_rules,
    # Map of {X,Y,Z} -> CellPid
    :cell_processes,
    # Current generation number
    :generation,
    # Timer for automatic evolution
    :evolution_timer,
    # Milliseconds between generations
    :evolution_interval,
    # Performance statistics
    :stats,
    # Evolution paused flag
    paused: false
  ]

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(cluster_config) do
    cluster_id = Map.get(cluster_config, :cluster_id)
    GenServer.start_link(__MODULE__, cluster_config, name: cluster_id)
  end

  def evolve_generation(cluster_id) do
    GenServer.call(cluster_id, :evolve_generation)
  end

  def get_cluster_stats(cluster_id) do
    GenServer.call(cluster_id, :get_cluster_stats)
  end

  def get_cell_state(cluster_id, x, y, z) do
    GenServer.call(cluster_id, {:get_cell_state, x, y, z})
  end

  def set_ca_rules(cluster_id, new_rules) do
    GenServer.call(cluster_id, {:set_ca_rules, new_rules})
  end

  def pause_evolution(cluster_id) do
    GenServer.call(cluster_id, :pause_evolution)
  end

  def resume_evolution(cluster_id) do
    GenServer.call(cluster_id, :resume_evolution)
  end

  # ====================================================================
  # GenServer callbacks
  # ====================================================================

  @impl true
  def init(cluster_config) do
    Process.flag(:trap_exit, true)

    cluster_id = Map.get(cluster_config, :cluster_id)
    dimensions = Map.get(cluster_config, :dimensions, {10, 10, 10})
    ca_rules = Map.get(cluster_config, :ca_rules, default_ca_rules())
    evolution_interval = Map.get(cluster_config, :evolution_interval, @default_evolution_interval)

    # Initialize all cell processes for the 3D grid
    cell_processes = initialize_cell_grid(dimensions, ca_rules)

    # Start evolution timer
    evolution_timer = Process.send_after(self(), :evolve_generation, evolution_interval)

    state = %__MODULE__{
      cluster_id: cluster_id,
      dimensions: dimensions,
      ca_rules: ca_rules,
      cell_processes: cell_processes,
      generation: 0,
      evolution_timer: evolution_timer,
      evolution_interval: evolution_interval,
      stats: initialize_stats()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:evolve_generation, _from, state) do
    {new_state, generation_time} = perform_evolution(state)
    stats = update_stats(new_state.stats, generation_time)
    updated_state = %{new_state | stats: stats}
    {:reply, {:ok, updated_state.generation}, updated_state}
  end

  def handle_call(:get_cluster_stats, _from, state) do
    cluster_stats = %{
      cluster_id: state.cluster_id,
      dimensions: state.dimensions,
      generation: state.generation,
      paused: state.paused,
      cell_count: map_size(state.cell_processes),
      performance: state.stats
    }

    {:reply, {:ok, cluster_stats}, state}
  end

  def handle_call({:get_cell_state, x, y, z}, _from, state) do
    case Map.get(state.cell_processes, {x, y, z}) do
      nil ->
        {:reply, {:error, :cell_not_found}, state}

      cell_pid ->
        case Thunderline.Thunderbolt.ThunderCell.CACell.get_state(cell_pid) do
          {:ok, cell_state} ->
            {:reply, {:ok, cell_state}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:set_ca_rules, new_rules}, _from, state) do
    # Distribute new CA rules to all cells
    Enum.each(state.cell_processes, fn {_coord, cell_pid} ->
      Thunderline.Thunderbolt.ThunderCell.CACell.set_rules(cell_pid, new_rules)
    end)

    {:reply, :ok, %{state | ca_rules: new_rules}}
  end

  def handle_call(:pause_evolution, _from, state) do
    case state.evolution_timer do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    {:reply, :ok, %{state | paused: true, evolution_timer: nil}}
  end

  def handle_call(:resume_evolution, _from, state) do
    case state.paused do
      true ->
        timer = Process.send_after(self(), :evolve_generation, state.evolution_interval)
        {:reply, :ok, %{state | paused: false, evolution_timer: timer}}

      false ->
        {:reply, {:error, :not_paused}, state}
    end
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:evolve_generation, state) do
    case state.paused do
      true ->
        {:noreply, state}

      false ->
        {new_state, generation_time} = perform_evolution(state)
        stats = update_stats(new_state.stats, generation_time)

        # Schedule next evolution
        timer = Process.send_after(self(), :evolve_generation, state.evolution_interval)

        updated_state = %{new_state | evolution_timer: timer, stats: stats}
        {:noreply, updated_state}
    end
  end

  def handle_info({:EXIT, cell_pid, _reason}, state) do
    # Handle cell process crash - restart the cell
    case find_cell_coordinate(cell_pid, state.cell_processes) do
      {:ok, coord} ->
        new_cell_pid = restart_cell(coord, state.ca_rules)
        new_cell_processes = Map.put(state.cell_processes, coord, new_cell_pid)
        {:noreply, %{state | cell_processes: new_cell_processes}}

      :not_found ->
        {:noreply, state}
    end
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean shutdown of all cell processes
    Enum.each(state.cell_processes, fn {_coord, cell_pid} ->
      Thunderline.Thunderbolt.ThunderCell.CACell.stop(cell_pid)
    end)

    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # ====================================================================
  # Internal functions
  # ====================================================================

  defp initialize_cell_grid({x, y, z}, ca_rules) do
    for xi <- 0..(x - 1), yi <- 0..(y - 1), zi <- 0..(z - 1), into: %{} do
      coord = {xi, yi, zi}
      cell_pid = start_cell_process(coord, ca_rules)
      {coord, cell_pid}
    end
  end

  defp start_cell_process(coord, ca_rules) do
    {:ok, cell_pid} = Thunderline.Thunderbolt.ThunderCell.CACell.start_link(coord, ca_rules)
    Process.link(cell_pid)
    cell_pid
  end

  defp restart_cell(coord, ca_rules) do
    start_cell_process(coord, ca_rules)
  end

  defp perform_evolution(state) do
    start_time = System.monotonic_time(:millisecond)

    # Phase 1: All cells calculate their next state based on neighbors
    Enum.each(state.cell_processes, fn {coord, cell_pid} ->
      neighbors = get_neighbor_states(coord, state)
      Thunderline.Thunderbolt.ThunderCell.CACell.prepare_evolution(cell_pid, neighbors)
    end)

    # Phase 2: All cells simultaneously transition to their new state
    Enum.each(state.cell_processes, fn {_coord, cell_pid} ->
      Thunderline.Thunderbolt.ThunderCell.CACell.commit_evolution(cell_pid)
    end)

    end_time = System.monotonic_time(:millisecond)
    generation_time = end_time - start_time

    new_generation = state.generation + 1
    {%{state | generation: new_generation}, generation_time}
  end

  defp get_neighbor_states({x, y, z}, state) do
    neighbor_coords = get_3d_neighbors(x, y, z, state.dimensions)

    Enum.map(neighbor_coords, fn coord ->
      case Map.get(state.cell_processes, coord) do
        # Out of bounds cells are considered dead
        nil ->
          :dead

        cell_pid ->
          case Thunderline.Thunderbolt.ThunderCell.CACell.get_state(cell_pid) do
            {:ok, cell_state} -> cell_state
            _ -> :dead
          end
      end
    end)
  end

  defp get_3d_neighbors(x, y, z, {max_x, max_y, max_z}) do
    for xi <- (x - 1)..(x + 1),
        yi <- (y - 1)..(y + 1),
        zi <- (z - 1)..(z + 1),
        # Exclude self
        {xi, yi, zi} != {x, y, z},
        xi >= 0 and xi < max_x,
        yi >= 0 and yi < max_y,
        zi >= 0 and zi < max_z do
      {xi, yi, zi}
    end
  end

  defp find_cell_coordinate(cell_pid, cell_processes) do
    case Enum.find(cell_processes, fn {_coord, pid} -> pid == cell_pid end) do
      {coord, ^cell_pid} -> {:ok, coord}
      nil -> :not_found
    end
  end

  defp default_ca_rules do
    %{
      name: "Conway's Game of Life 3D",
      # Neighbors needed for birth
      birth_neighbors: [5, 6, 7],
      # Neighbors needed for survival
      survival_neighbors: [4, 5, 6],
      # 26-neighbor Moore neighborhood
      neighbor_type: :moore_3d
    }
  end

  defp initialize_stats do
    %{
      total_generations: 0,
      avg_generation_time: 0.0,
      min_generation_time: :infinity,
      max_generation_time: 0,
      last_generation_time: 0
    }
  end

  defp update_stats(stats, generation_time) do
    total_gens = stats.total_generations + 1
    current_avg = stats.avg_generation_time
    new_avg = (current_avg * (total_gens - 1) + generation_time) / total_gens

    %{
      stats
      | total_generations: total_gens,
        avg_generation_time: new_avg,
        min_generation_time: min(stats.min_generation_time, generation_time),
        max_generation_time: max(stats.max_generation_time, generation_time),
        last_generation_time: generation_time
    }
  end
end
