defmodule Thunderline.Thunderbolt.ThunderCell.CAEngine do
  @moduledoc """
  High-level CA computation engine that coordinates multiple algorithms
  and optimization strategies for cellular automata processing.
  """

  use GenServer
  require Logger

  defstruct algorithms: [],
            optimization_cache: %{},
            benchmark_history: [],
            engine_stats: %{}

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_available_algorithms do
    GenServer.call(__MODULE__, :get_algorithms)
  end

  def optimize_rules(ca_rules, performance_targets) do
    GenServer.call(__MODULE__, {:optimize_rules, ca_rules, performance_targets})
  end

  def benchmark_performance(cluster_config) do
    GenServer.call(__MODULE__, {:benchmark, cluster_config})
  end

  def get_engine_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # ====================================================================
  # GenServer callbacks
  # ====================================================================

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      algorithms: initialize_algorithms(),
      optimization_cache: %{},
      benchmark_history: [],
      engine_stats: initialize_engine_stats()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_algorithms, _from, state) do
    {:reply, {:ok, state.algorithms}, state}
  end

  def handle_call({:optimize_rules, ca_rules, performance_targets}, _from, state) do
    case optimize_ca_rules(ca_rules, performance_targets, state) do
      {:ok, optimized_rules, new_state} -> {:reply, {:ok, optimized_rules}, new_state}
    end
  end

  def handle_call({:benchmark, cluster_config}, _from, state) do
    case run_benchmark(cluster_config, state) do
      {:ok, benchmark_results, new_state} ->
        {:reply, {:ok, benchmark_results}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      algorithms: length(state.algorithms),
      cached_optimizations: map_size(state.optimization_cache),
      benchmark_runs: length(state.benchmark_history),
      engine_stats: state.engine_stats
    }

    {:reply, {:ok, status}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # ====================================================================
  # Internal functions
  # ====================================================================

  defp initialize_algorithms do
    [
      %{
        name: "Conway's Game of Life 3D",
        birth_neighbors: [5, 6, 7],
        survival_neighbors: [4, 5, 6],
        description: "3D extension of Conway's classic Game of Life",
        complexity: :medium
      },
      %{
        name: "Highlife 3D",
        birth_neighbors: [6, 8],
        survival_neighbors: [5, 6],
        description: "3D Highlife with different birth/survival rules",
        complexity: :medium
      },
      %{
        name: "Seeds 3D",
        birth_neighbors: [4],
        survival_neighbors: [],
        description: "3D Seeds rule - cells die immediately after birth",
        complexity: :low
      },
      %{
        name: "Maze 3D",
        birth_neighbors: [6],
        survival_neighbors: [3, 4, 5, 6, 7, 8],
        description: "3D Maze generation algorithm",
        complexity: :high
      },
      %{
        name: "Custom Thunderline CA",
        birth_neighbors: [6, 7, 8],
        survival_neighbors: [5, 6, 7, 8],
        description: "Optimized CA rules for Thunderline architecture",
        complexity: :medium
      }
    ]
  end

  defp initialize_engine_stats do
    %{
      optimizations_performed: 0,
      benchmarks_run: 0,
      total_clusters_processed: 0,
      avg_optimization_time: 0.0,
      cache_hit_ratio: 0.0
    }
  end

  defp optimize_ca_rules(ca_rules, performance_targets, state) do
    # Check optimization cache first
    cache_key = {ca_rules, performance_targets}

    case Map.get(state.optimization_cache, cache_key) do
      nil ->
        # Perform new optimization
        case perform_optimization(ca_rules, performance_targets) do
          {:ok, optimized_rules} ->
            # Cache the result
            new_cache = Map.put(state.optimization_cache, cache_key, optimized_rules)
            new_stats = update_optimization_stats(state.engine_stats)
            new_state = %{state | optimization_cache: new_cache, engine_stats: new_stats}
            {:ok, optimized_rules, new_state}

          error ->
            error
        end

      cached_result ->
        # Return cached optimization
        {:ok, cached_result, state}
    end
  end

  defp perform_optimization(ca_rules, performance_targets) do
    # Optimization algorithms based on performance targets
    target_generation_time = Map.get(performance_targets, :max_generation_time, 100)
    _target_concurrency = Map.get(performance_targets, :min_concurrency, 1000)

    # Simple optimization: adjust neighbor requirements based on targets
    optimized_rules =
      case target_generation_time < 50 do
        true ->
          # Aggressive optimization for speed
          Map.merge(ca_rules, %{
            # Fewer birth conditions
            birth_neighbors: [6, 7],
            # Fewer survival conditions
            survival_neighbors: [5, 6],
            optimization_level: :high
          })

        false ->
          # Balanced optimization
          Map.put(ca_rules, :optimization_level, :medium)
      end

    {:ok, optimized_rules}
  end

  defp run_benchmark(cluster_config, state) do
    # Create a temporary benchmark cluster
    benchmark_id = generate_benchmark_id()

    # Start benchmark cluster
    case start_benchmark_cluster(Map.put(cluster_config, :cluster_id, benchmark_id)) do
      {:ok, cluster_pid} ->
        # Run benchmark
        benchmark_results = execute_benchmark(benchmark_id, cluster_pid)

        # Clean up benchmark cluster
        stop_benchmark_cluster(benchmark_id)

        # Update benchmark history
        new_history = [benchmark_results | state.benchmark_history]
        # Keep last 50 benchmarks
        trimmed_history = Enum.take(new_history, 50)

        new_stats = update_benchmark_stats(state.engine_stats)
        new_state = %{state | benchmark_history: trimmed_history, engine_stats: new_stats}

        {:ok, benchmark_results, new_state}

      error ->
        error
    end
  end

  defp start_benchmark_cluster(cluster_config) do
    # Start a temporary cluster for benchmarking
    case Thunderline.Thunderbolt.ThunderCell.Cluster.start_link(cluster_config) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  defp stop_benchmark_cluster(benchmark_id) do
    # Stop the benchmark cluster
    case Process.whereis(benchmark_id) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp execute_benchmark(benchmark_id, _cluster_pid) do
    start_time = System.monotonic_time(:millisecond)

    # Run 10 generations and measure performance
    generation_times =
      for _ <- 1..10 do
        gen_start = System.monotonic_time(:millisecond)

        {:ok, generation} =
          Thunderline.Thunderbolt.ThunderCell.Cluster.evolve_generation(benchmark_id)

        gen_end = System.monotonic_time(:millisecond)
        gen_time = gen_end - gen_start
        {generation, gen_time}
      end

    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time

    {:ok, cluster_stats} =
      Thunderline.Thunderbolt.ThunderCell.Cluster.get_cluster_stats(benchmark_id)

    %{
      benchmark_id: benchmark_id,
      total_time: total_time,
      generation_times: generation_times,
      cluster_stats: cluster_stats,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp generate_benchmark_id do
    timestamp = System.monotonic_time(:millisecond)
    random = :rand.uniform(1000)
    String.to_atom("benchmark_#{timestamp}_#{random}")
  end

  defp update_optimization_stats(stats) do
    count = Map.get(stats, :optimizations_performed, 0) + 1
    Map.put(stats, :optimizations_performed, count)
  end

  defp update_benchmark_stats(stats) do
    count = Map.get(stats, :benchmarks_run, 0) + 1
    Map.put(stats, :benchmarks_run, count)
  end
end
