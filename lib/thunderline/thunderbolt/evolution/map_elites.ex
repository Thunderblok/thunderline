defmodule Thunderline.Thunderbolt.Evolution.MapElites do
  @moduledoc """
  MAP-Elites quality-diversity algorithm implementation (HC-Δ-4).

  MAP-Elites (Multi-dimensional Archive of Phenotypic Elites) maintains
  a diverse collection of high-performing solutions across a behavior space.

  ## Algorithm Overview

  1. **Initialize**: Seed archive with random or bootstrapped PACs
  2. **Sample**: Select parent(s) from the archive
  3. **Mutate**: Apply genetic operators to create offspring
  4. **Evaluate**: Run offspring and compute behavior + fitness
  5. **Update**: Try to add offspring to archive
  6. **Repeat**: Continue for N generations

  ## Quality-Diversity Benefits

  - Avoids local optima by maintaining diverse solutions
  - Produces a repertoire of skills/behaviors
  - Enables stepping stones for hard objectives
  - Robust to environmental changes

  ## Usage

      # Configure and run MAP-Elites
      {:ok, config} = MapElites.new(
        population_size: 100,
        generations: 1000,
        resolution: 10
      )

      {:ok, archive} = MapElites.run(config, seed_pacs)

  ## Integration

  Integrates with:
  - `Archive` - Elite storage and management
  - `Mutation` - Genetic operators
  - `BehaviorDescriptor` - Behavior characterization
  - `TraitsEvolutionJob` - Oban-based async evolution
  """

  alias Thunderline.Thunderbolt.Evolution.Archive
  alias Thunderline.Thunderbolt.Evolution.Mutation

  require Logger

  @type config :: %{
          archive_id: String.t(),
          resolution: pos_integer(),
          generations: pos_integer(),
          batch_size: pos_integer(),
          initial_population: pos_integer(),
          mutation_rate: float(),
          crossover_rate: float(),
          selection_strategy: :uniform | :fitness_weighted | :novelty_weighted | :curiosity,
          evaluator: (map() -> {:ok, map()} | {:error, term()}) | nil,
          callbacks: map()
        }

  @type run_result :: %{
          archive: map(),
          stats: map(),
          generations_completed: non_neg_integer(),
          final_coverage: float()
        }

  @default_config %{
    resolution: 10,
    generations: 100,
    batch_size: 20,
    initial_population: 50,
    mutation_rate: 0.15,
    crossover_rate: 0.3,
    selection_strategy: :uniform,
    evaluator: nil,
    callbacks: %{}
  }

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a new MAP-Elites configuration.

  ## Options
  - `:archive_id` - Unique archive identifier (auto-generated if not provided)
  - `:resolution` - Bins per behavior dimension (default: 10)
  - `:generations` - Number of generations to run (default: 100)
  - `:batch_size` - Offspring per generation (default: 20)
  - `:initial_population` - Size of random initial population (default: 50)
  - `:mutation_rate` - Probability of mutation (default: 0.15)
  - `:crossover_rate` - Probability of crossover (default: 0.3)
  - `:selection_strategy` - How to select parents (default: :uniform)
  - `:evaluator` - Function to evaluate PACs (required for `run/2`)
  - `:callbacks` - Optional callbacks for events
  """
  @spec new(keyword()) :: {:ok, config()} | {:error, term()}
  def new(opts \\ []) do
    config =
      @default_config
      |> Map.merge(Map.new(opts))
      |> Map.put_new(:archive_id, Thunderline.UUID.v7())

    {:ok, config}
  end

  @doc """
  Runs the full MAP-Elites algorithm.

  ## Parameters
  - `config` - Configuration from `new/1`
  - `seed_pacs` - Initial PACs to seed the archive (optional)

  ## Returns
  - `{:ok, result}` - Final archive and statistics
  - `{:error, reason}` - If algorithm fails

  ## Callbacks

  The following callbacks can be provided in `config.callbacks`:
  - `:on_generation` - Called after each generation with stats
  - `:on_elite_found` - Called when new elite added
  - `:on_complete` - Called when algorithm finishes
  """
  @spec run(config(), [map()]) :: {:ok, run_result()} | {:error, term()}
  def run(config, seed_pacs \\ []) do
    Logger.info("[MapElites] Starting with #{config.generations} generations")

    with {:ok, archive_config} <- Archive.new(id: config.archive_id, resolution: config.resolution),
         :ok <- initialize_archive(archive_config, seed_pacs, config),
         {:ok, result} <- evolution_loop(archive_config, config, 0) do
      invoke_callback(config, :on_complete, result)
      {:ok, result}
    end
  end

  @doc """
  Runs a single generation of MAP-Elites.

  Useful for incremental evolution or integration with external schedulers.
  """
  @spec run_generation(config(), map(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def run_generation(config, archive_config, generation) do
    with {:ok, elites} <- Archive.elite_descriptors(archive_config),
         {:ok, parents} <- Archive.sample_elites(archive_config, count: config.batch_size, strategy: config.selection_strategy),
         offspring <- generate_offspring(parents, config),
         {:ok, results} <- evaluate_batch(offspring, config),
         :ok <- update_archive(archive_config, results, generation, elites) do
      {:ok, stats} = Archive.coverage(archive_config)

      generation_stats = %{
        generation: generation,
        offspring_count: length(offspring),
        added: count_added(results),
        replaced: count_replaced(results),
        rejected: count_rejected(results),
        coverage: stats.coverage,
        mean_fitness: stats.mean_fitness
      }

      invoke_callback(config, :on_generation, generation_stats)

      {:ok, generation_stats}
    end
  end

  @doc """
  Generates offspring from selected parents using mutation and crossover.
  """
  @spec generate_offspring([map()], config()) :: [map()]
  def generate_offspring(parents, config) do
    if Enum.empty?(parents) do
      # Generate random offspring if no parents
      Enum.map(1..config.batch_size, fn _ ->
        Mutation.random_pac()
      end)
    else
      Enum.map(1..config.batch_size, fn _ ->
        if :rand.uniform() < config.crossover_rate and length(parents) >= 2 do
          # Crossover
          [p1, p2] = Enum.take_random(parents, 2)
          child = Mutation.crossover(extract_pac(p1), extract_pac(p2))
          maybe_mutate(child, config.mutation_rate)
        else
          # Mutation only
          parent = Enum.random(parents)
          Mutation.mutate(extract_pac(parent), rate: config.mutation_rate)
        end
      end)
    end
  end

  @doc """
  Evaluates a batch of PACs using the configured evaluator.
  """
  @spec evaluate_batch([map()], config()) :: {:ok, [map()]} | {:error, term()}
  def evaluate_batch(pacs, config) do
    evaluator = config.evaluator || (&default_evaluator/1)

    results =
      pacs
      |> Task.async_stream(
        fn pac ->
          case evaluator.(pac) do
            {:ok, metrics} -> {:ok, pac, metrics}
            {:error, reason} -> {:error, reason}
          end
        end,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.reduce([], fn
        {:ok, {:ok, pac, metrics}}, acc -> [{pac, metrics} | acc]
        {:ok, {:error, _}}, acc -> acc
        {:exit, _}, acc -> acc
      end)

    {:ok, results}
  end

  @doc """
  Checks if the algorithm should continue running.
  """
  @spec should_continue?(config(), non_neg_integer(), map()) :: boolean()
  def should_continue?(config, generation, stats) do
    generation < config.generations and
      stats.coverage < 0.99 and
      not Map.get(stats, :stalled, false)
  end

  # ═══════════════════════════════════════════════════════════════
  # SELECTION STRATEGIES
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Selects parents using the curiosity strategy.

  Curiosity-driven selection favors elites that:
  1. Have been challenged fewer times (unexplored niches)
  2. Have high fitness improvement potential
  3. Are in sparse regions of behavior space
  """
  @spec select_curious(map(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def select_curious(archive_config, count) do
    with {:ok, elites} <- Archive.all_elites(archive_config) do
      # Score by curiosity (inverse challenge count + region sparsity)
      scored =
        Enum.map(elites, fn elite ->
          challenge_score = 1.0 / max(1, elite.challenge_count)
          freshness = 1.0 / max(1, elite.generation)
          curiosity = challenge_score * 0.7 + freshness * 0.3
          {elite, curiosity}
        end)
        |> Enum.sort_by(fn {_, score} -> score end, :desc)
        |> Enum.take(count)
        |> Enum.map(fn {elite, _} -> elite end)

      {:ok, scored}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp initialize_archive(archive_config, seed_pacs, config) do
    Logger.debug("[MapElites] Initializing archive with #{length(seed_pacs)} seeds")

    # Add seed PACs first
    Enum.each(seed_pacs, fn pac ->
      case config.evaluator do
        nil ->
          metrics = default_evaluator(pac) |> elem(1)
          Archive.add_candidate(archive_config, pac, metrics, generation: 0)

        evaluator ->
          case evaluator.(pac) do
            {:ok, metrics} ->
              Archive.add_candidate(archive_config, pac, metrics, generation: 0)

            {:error, _} ->
              :skip
          end
      end
    end)

    # Generate random initial population if needed
    if length(seed_pacs) < config.initial_population do
      random_count = config.initial_population - length(seed_pacs)

      Enum.each(1..random_count, fn _ ->
        pac = Mutation.random_pac()

        case config.evaluator do
          nil ->
            metrics = default_evaluator(pac) |> elem(1)
            Archive.add_candidate(archive_config, pac, metrics, generation: 0)

          evaluator ->
            case evaluator.(pac) do
              {:ok, metrics} ->
                Archive.add_candidate(archive_config, pac, metrics, generation: 0)

              {:error, _} ->
                :skip
            end
        end
      end)
    end

    :ok
  end

  defp evolution_loop(archive_config, config, generation) do
    if generation >= config.generations do
      finalize_run(archive_config, generation)
    else
      case run_generation(config, archive_config, generation) do
        {:ok, gen_stats} ->
          if should_continue?(config, generation + 1, gen_stats) do
            evolution_loop(archive_config, config, generation + 1)
          else
            finalize_run(archive_config, generation + 1)
          end

        {:error, reason} ->
          Logger.error("[MapElites] Generation #{generation} failed: #{inspect(reason)}")
          finalize_run(archive_config, generation)
      end
    end
  end

  defp finalize_run(archive_config, generations_completed) do
    with {:ok, stats} <- Archive.coverage(archive_config),
         {:ok, archive_data} <- Archive.export(archive_config) do
      result = %{
        archive: archive_data,
        stats: stats,
        generations_completed: generations_completed,
        final_coverage: stats.coverage
      }

      Logger.info(
        "[MapElites] Completed #{generations_completed} generations. " <>
          "Coverage: #{Float.round(stats.coverage * 100, 2)}%, " <>
          "Elites: #{stats.occupied_cells}"
      )

      {:ok, result}
    end
  end

  defp update_archive(archive_config, results, generation, existing_elites) do
    Enum.each(results, fn {pac, metrics} ->
      Archive.add_candidate(
        archive_config,
        pac,
        metrics,
        generation: generation,
        existing_elites: existing_elites
      )
    end)

    :ok
  end

  defp extract_pac(%{pac_snapshot: snapshot}) when is_map(snapshot), do: snapshot
  defp extract_pac(elite) when is_map(elite), do: Map.get(elite, :pac, elite)
  defp extract_pac(other), do: other

  defp maybe_mutate(pac, rate) do
    if :rand.uniform() < rate do
      Mutation.mutate(pac, rate: rate)
    else
      pac
    end
  end

  defp count_added(results) do
    Enum.count(results, fn
      {:added, _} -> true
      _ -> false
    end)
  end

  defp count_replaced(results) do
    Enum.count(results, fn
      {:replaced, _, _} -> true
      _ -> false
    end)
  end

  defp count_rejected(results) do
    Enum.count(results, fn
      {:rejected, _} -> true
      _ -> false
    end)
  end

  defp default_evaluator(_pac) do
    # Default evaluator for testing - assigns random fitness
    # In production, this should run the PAC and compute actual metrics
    {:ok,
     %{
       fitness: :rand.uniform(),
       logic_density: :rand.uniform(),
       memory_reuse: :rand.uniform(),
       action_volatility: :rand.uniform(),
       task_performance: :rand.uniform()
     }}
  end

  defp invoke_callback(config, event, data) do
    case Map.get(config.callbacks, event) do
      nil -> :ok
      callback when is_function(callback, 1) -> callback.(data)
      _ -> :ok
    end
  end
end
