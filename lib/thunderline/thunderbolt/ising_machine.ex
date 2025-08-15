defmodule Thunderline.Thunderbolt.IsingMachine do
  @moduledoc """
  Thunderline Ising Machine - BEAM-native spin glass optimizer.

  A high-performance, fault-tolerant Ising machine implementation built on
  Elixir/BEAM with Nx/EXLA acceleration. Designed for combinatorial optimization,
  parameter tuning, and integration with the Thunderline ecosystem.

  ## Features

  - **Multiple Optimization Kernels**:
    - Metropolis-Hastings (Glauber dynamics)
    - Simulated annealing with various schedules
    - Parallel tempering (replica exchange)
    - Mean-field approximations (planned)

  - **Topology Support**:
    - 2D/3D regular grids with periodic/open boundaries
    - General graphs (Max-Cut, TSP, graph coloring)
    - Custom lattice structures

  - **BEAM-Native Concurrency**:
    - Fault-tolerant tile-based distribution
    - Process-per-replica for parallel tempering
    - Distributed computation across BEAM clusters

  - **High Performance**:
    - Nx/EXLA kernels for vectorized updates
    - GPU/TPU acceleration support
    - Checkerboard parallelization
    - Minimal memory allocations

  ## Quick Start

      # Simple 2D grid optimization
      {:ok, result} = ThunderIsing.quick_solve(128, 128)

      # Max-Cut problem
      edges = [{0, 1, 1.0}, {1, 2, 2.0}, {2, 0, 1.5}]
      {:ok, cut_result} = ThunderIsing.solve_max_cut(edges, 3)

      # Parallel tempering for difficult problems
      {:ok, result} = ThunderIsing.solve_with_parallel_tempering(
        [height: 64, width: 64],
        temperatures: [2.0, 1.5, 1.0, 0.7, 0.5, 0.3, 0.2, 0.1]
      )

  ## Integration with Thunderline.Thunderbolt

  ThunderIsing can be used within Thunderline.Thunderbolt for:
  - Parameter optimization (coupling selection, field tuning)
  - Segmentation with smoothness constraints
  - Scheduling and resource allocation
  - Neural network training with spin-based regularization

  ## Architecture

  The implementation follows the Thunderline control plane pattern:
  - Elixir processes orchestrate optimization
  - Nx/EXLA kernels handle compute-intensive operations
  - GenServer supervision provides fault tolerance
  - Event-driven coordination enables distributed scaling

  ## Energy Model

  The Ising Hamiltonian is:

      E(s) = -∑(i<j) J_ij s_i s_j - ∑i h_i s_i

  Where:
  - `s_i ∈ {-1, +1}` are spin variables
  - `J_ij` are coupling strengths between spins
  - `h_i` are external magnetic fields
  - The goal is to find spin configurations minimizing E(s)
  """

  # Re-export main API functions for convenience
  defdelegate quick_solve(height, width, opts \\ []), to: __MODULE__.API
  defdelegate solve_grid(opts), to: __MODULE__.API
  defdelegate solve_max_cut(edges, num_vertices, opts \\ []), to: __MODULE__.API
  defdelegate solve_with_parallel_tempering(lattice_or_opts, opts \\ []), to: __MODULE__.API
  defdelegate solve_distributed(lattice, opts \\ []), to: __MODULE__.API

  alias __MODULE__.{Lattice, Kernel, Anneal, Temper, Scheduler, API}

  @doc """
  Creates a 2D grid lattice for Ising optimization.

  ## Examples

      # Uniform coupling grid
      lattice = ThunderIsing.grid_2d(100, 100)

      # Anisotropic couplings
      lattice = ThunderIsing.grid_2d(100, 100, coupling: {:anisotropic, {1.0, 0.5}})
  """
  defdelegate grid_2d(height, width, opts \\ []), to: Lattice

  @doc """
  Creates a general graph lattice from edge list.

  ## Examples

      # From edge list
      edges = [{0, 1, 1.0}, {1, 2, 0.5}, {2, 0, 2.0}]
      lattice = ThunderIsing.graph_from_edges(edges, 3)
  """
  def graph_from_edges(edges, num_vertices, opts \\ []) do
    Lattice.graph(num_vertices, edges, opts)
  end

  @doc """
  Starts a simulated annealing process.

  Returns `{:ok, pid}` where pid can be used with Anneal module functions.
  """
  defdelegate start_annealing(opts), to: Anneal, as: :start_link

  @doc """
  Starts parallel tempering optimization.

  Returns `{:ok, pid}` for the parallel tempering coordinator.
  """
  defdelegate start_parallel_tempering(opts), to: Temper, as: :start_link

  @doc """
  Starts distributed optimization across multiple tiles.

  Returns `{:ok, pid}` for the distributed scheduler.
  """
  defdelegate start_distributed(opts), to: Scheduler, as: :start_link

  @doc """
  Generates random spin configuration for testing.
  """
  def random_spins(height, width, opts \\ []) do
    Kernel.random_spins(height, width, opts)
  end

  @doc """
  Computes energy of a spin configuration.
  """
  def compute_energy(spins, lattice, field \\ 0.0) do
    case lattice.topology do
      :grid_2d ->
        field_tensor =
          if is_number(field) do
            Nx.broadcast(field, Nx.shape(spins))
          else
            field
          end

        Kernel.total_energy_grid(spins, lattice.coupling_matrix, field_tensor)

      :graph ->
        {rows, cols, weights} = lattice.edges

        field_tensor =
          if is_number(field) do
            Nx.broadcast(field, Nx.shape(spins))
          else
            field
          end

        # Would need to implement graph energy computation
        Nx.tensor(0.0)
    end
  end

  @doc """
  Computes magnetization (average spin) of configuration.
  """
  defdelegate magnetization(spins), to: Kernel

  @doc """
  Creates temperature schedule for annealing.

  ## Examples

      # Exponential cooling
      schedule = ThunderIsing.temperature_schedule(:exponential, 2.0, 0.01, 1000)

      # Linear cooling
      schedule = ThunderIsing.temperature_schedule(:linear, 2.0, 0.01, 1000)
  """
  def temperature_schedule(type, t_start, t_end, num_steps) do
    case type do
      :exponential ->
        factor = :math.pow(t_end / t_start, 1.0 / num_steps)
        {:exp, factor}

      :linear ->
        rate = (t_start - t_end) / num_steps
        {:linear, rate}

      :power ->
        # T(k) = t_start / (1 + k)^alpha
        alpha = :math.log(t_start / t_end) / :math.log(num_steps)
        {:power, t_start, alpha}
    end
  end

  @doc """
  Validates that EXLA is properly configured for acceleration.

  Returns information about available backends and performance characteristics.
  """
  def check_acceleration() do
    try do
      # Test basic Nx operation
      test_tensor = Nx.tensor([[1, 2], [3, 4]])
      result = Nx.add(test_tensor, 1)

      # Check EXLA availability
      exla_available = Code.ensure_loaded?(EXLA)

      # Get backend info
      backend_info = %{
        default_backend: Nx.default_backend(),
        exla_available: exla_available,
        basic_ops_working: Nx.shape(result) == {2, 2}
      }

      # Test kernel compilation if EXLA is available
      if exla_available do
        compiled_test =
          try do
            compiled_fn = Nx.Defn.compile(&Nx.add(&1, 1), [test_tensor])
            compiled_result = compiled_fn.(test_tensor)
            Nx.equal(compiled_result, result) |> Nx.all() |> Nx.to_number() == 1
          rescue
            _ -> false
          end

        Map.put(backend_info, :kernel_compilation, compiled_test)
      else
        backend_info
      end
    rescue
      error ->
        %{error: inspect(error), basic_ops_working: false}
    end
  end

  @doc """
  Returns performance benchmarks for the current system.

  Useful for sizing problems and setting appropriate timeouts.
  """
  def benchmark(opts \\ []) do
    size = Keyword.get(opts, :size, 64)
    steps = Keyword.get(opts, :steps, 1000)

    start_time = System.monotonic_time(:microsecond)

    # Run a quick optimization
    result = quick_solve(size, size, max_steps: steps, t0: 1.0, t_min: 0.1)

    end_time = System.monotonic_time(:microsecond)
    runtime_us = end_time - start_time

    case result do
      {:ok, optimization_result} ->
        spins_per_second = size * size * optimization_result.steps / (runtime_us / 1_000_000)

        %{
          grid_size: {size, size},
          steps_completed: optimization_result.steps,
          total_runtime_us: runtime_us,
          spins_per_second: round(spins_per_second),
          final_energy: optimization_result.energy,
          backend_info: check_acceleration()
        }

      {:error, reason} ->
        %{error: reason, backend_info: check_acceleration()}
    end
  end
end
