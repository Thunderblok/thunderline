defmodule Thunderline.Thunderbolt.Evolution.Archive do
  @moduledoc """
  MAP-Elites Archive management for quality-diversity search (HC-Δ-4).

  The archive maintains a sparse N-dimensional grid where each cell stores
  the best-performing (elite) agent for that behavioral niche.

  ## Archive Operations

  - `new/1` - Create a new archive with configuration
  - `add_candidate/3` - Try to add a candidate to the archive
  - `get_elite/2` - Get elite at specific cell
  - `sample_elites/2` - Random sample of elites for reproduction
  - `coverage/1` - Calculate archive coverage statistics
  - `export/1` - Export archive for analysis

  ## Quality-Diversity Principle

  Unlike traditional optimization that converges to a single best solution,
  MAP-Elites maintains diversity by:

  1. Mapping candidates to behavior space coordinates
  2. Storing only one elite per cell (the best for that niche)
  3. Using the diverse population for exploration

  This produces a collection of high-quality, behaviorally diverse solutions.

  ## Integration

  The archive integrates with:
  - `BehaviorDescriptor` - Maps candidates to grid cells
  - `EliteEntry` - Ash resource for persistence
  - `Mutation` - Generates new candidates from elites
  """

  alias Thunderline.Thunderbolt.Evolution.BehaviorDescriptor
  alias Thunderline.Thunderbolt.Evolution.Resources.EliteEntry

  require Logger

  @type archive_id :: String.t()

  @type config :: %{
          id: archive_id(),
          resolution: pos_integer(),
          dimensions: [BehaviorDescriptor.dimension()],
          description: String.t() | nil
        }

  @type stats :: %{
          total_cells: non_neg_integer(),
          occupied_cells: non_neg_integer(),
          coverage: float(),
          mean_fitness: float(),
          max_fitness: float(),
          min_fitness: float(),
          generation: non_neg_integer()
        }

  @type add_result ::
          {:added, EliteEntry.t()}
          | {:replaced, EliteEntry.t(), float()}
          | {:rejected, :lower_fitness}
          | {:error, term()}

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a new archive configuration.

  ## Options
  - `:resolution` - Bins per dimension (default: 10)
  - `:description` - Optional description

  ## Example

      {:ok, config} = Archive.new(id: "agent-v1", resolution: 10)
  """
  @spec new(keyword()) :: {:ok, config()} | {:error, term()}
  def new(opts \\ []) do
    id = Keyword.get(opts, :id, Thunderline.UUID.v7())
    resolution = Keyword.get(opts, :resolution, BehaviorDescriptor.default_resolution())
    description = Keyword.get(opts, :description)

    config = %{
      id: id,
      resolution: resolution,
      dimensions: BehaviorDescriptor.dimensions(),
      description: description
    }

    {:ok, config}
  end

  @doc """
  Attempts to add a candidate to the archive.

  The candidate is evaluated for its behavioral niche and fitness.
  It will be added if:
  1. The cell is empty, OR
  2. The candidate has higher fitness than the current elite

  ## Parameters
  - `config` - Archive configuration
  - `pac` - The PAC to evaluate
  - `metrics` - Metrics from the PAC run
  - `opts` - Options:
    - `:generation` - Current generation number
    - `:existing_elites` - List for novelty calculation

  ## Returns
  - `{:added, entry}` - New cell occupied
  - `{:replaced, entry, old_fitness}` - Elite was replaced
  - `{:rejected, :lower_fitness}` - Candidate not good enough
  - `{:error, reason}` - Processing error
  """
  @spec add_candidate(config(), map(), map(), keyword()) :: add_result()
  def add_candidate(config, pac, metrics, opts \\ []) do
    generation = Keyword.get(opts, :generation, 0)
    existing_elites = Keyword.get(opts, :existing_elites, [])

    with {:ok, descriptor} <-
           BehaviorDescriptor.extract(pac, metrics, existing_elites: existing_elites),
         coords = BehaviorDescriptor.to_grid_coords(descriptor, resolution: config.resolution),
         cell_key = BehaviorDescriptor.cell_key(coords),
         fitness = Map.get(metrics, :fitness, descriptor.task_performance) do
      # Check if cell exists
      case EliteEntry.get_by_cell(cell_key) do
        {:ok, nil} ->
          # Empty cell - add new elite
          create_elite(config, cell_key, coords, descriptor, fitness, pac, generation, metrics)

        {:ok, existing} ->
          # Occupied cell - try to replace
          challenge_elite(existing, fitness, pac, descriptor, generation, metrics)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the elite at a specific cell.
  """
  @spec get_elite(config(), String.t()) :: {:ok, EliteEntry.t() | nil} | {:error, term()}
  def get_elite(_config, cell_key) do
    EliteEntry.get_by_cell(cell_key)
  end

  @doc """
  Gets all elites in the archive.
  """
  @spec all_elites(config()) :: {:ok, [EliteEntry.t()]} | {:error, term()}
  def all_elites(config) do
    EliteEntry.archive_elites(config.id)
  end

  @doc """
  Samples random elites from the archive for reproduction.

  ## Options
  - `:count` - Number of elites to sample (default: 10)
  - `:strategy` - Sampling strategy (default: :uniform)
    - `:uniform` - Equal probability for all elites
    - `:fitness_weighted` - Higher fitness = higher probability
    - `:novelty_weighted` - Prefer elites in sparse regions
  """
  @spec sample_elites(config(), keyword()) :: {:ok, [EliteEntry.t()]} | {:error, term()}
  def sample_elites(config, opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    strategy = Keyword.get(opts, :strategy, :uniform)

    with {:ok, elites} <- all_elites(config) do
      sampled =
        case strategy do
          :uniform ->
            Enum.take_random(elites, count)

          :fitness_weighted ->
            sample_weighted(elites, count, fn e -> e.fitness end)

          :novelty_weighted ->
            # Approximate novelty by inverse density
            sample_weighted(elites, count, fn e ->
              1.0 / max(1, e.challenge_count)
            end)
        end

      {:ok, sampled}
    end
  end

  @doc """
  Calculates archive coverage and fitness statistics.
  """
  @spec coverage(config()) :: {:ok, stats()} | {:error, term()}
  def coverage(config) do
    with {:ok, elites} <- all_elites(config) do
      total_cells = :math.pow(config.resolution, length(config.dimensions)) |> trunc()
      occupied = length(elites)

      fitness_values = Enum.map(elites, & &1.fitness)

      stats = %{
        total_cells: total_cells,
        occupied_cells: occupied,
        coverage: if(total_cells > 0, do: occupied / total_cells, else: 0.0),
        mean_fitness: safe_mean(fitness_values),
        max_fitness: Enum.max(fitness_values, fn -> 0.0 end),
        min_fitness: Enum.min(fitness_values, fn -> 0.0 end),
        generation: Enum.max_by(elites, & &1.generation, fn -> %{generation: 0} end).generation
      }

      {:ok, stats}
    end
  end

  @doc """
  Exports the archive as a map for analysis or visualization.
  """
  @spec export(config()) :: {:ok, map()} | {:error, term()}
  def export(config) do
    with {:ok, elites} <- all_elites(config),
         {:ok, stats} <- coverage(config) do
      export_data = %{
        config: config,
        stats: stats,
        elites:
          Enum.map(elites, fn e ->
            %{
              cell_key: e.cell_key,
              behavior_coords: e.behavior_coords,
              behavior_values: e.behavior_values,
              fitness: e.fitness,
              generation: e.generation,
              trait_vector: e.trait_vector
            }
          end)
      }

      {:ok, export_data}
    end
  end

  @doc """
  Gets the top N elites by fitness.
  """
  @spec top_elites(config(), pos_integer()) :: {:ok, [EliteEntry.t()]} | {:error, term()}
  def top_elites(_config, limit \\ 10) do
    EliteEntry.top_elites(limit)
  end

  @doc """
  Prunes old generations from the archive.

  Removes elites that haven't been updated in `keep_generations` generations.
  """
  @spec prune(config(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def prune(_config, keep_generations) do
    EliteEntry.prune_old_generations(keep_generations)
  end

  @doc """
  Returns descriptors for all elites (for novelty calculation).
  """
  @spec elite_descriptors(config()) :: {:ok, [BehaviorDescriptor.t()]} | {:error, term()}
  def elite_descriptors(config) do
    with {:ok, elites} <- all_elites(config) do
      descriptors =
        Enum.map(elites, fn elite ->
          values = elite.behavior_values

          %BehaviorDescriptor{
            logic_density: Map.get(values, "logic_density", 0.0),
            memory_reuse: Map.get(values, "memory_reuse", 0.0),
            action_volatility: Map.get(values, "action_volatility", 0.0),
            task_performance: Map.get(values, "task_performance", 0.0),
            novelty_score: Map.get(values, "novelty_score", 0.0)
          }
        end)

      {:ok, descriptors}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp create_elite(config, cell_key, coords, descriptor, fitness, pac, generation, metrics) do
    attrs = %{
      archive_id: config.id,
      cell_key: cell_key,
      behavior_coords: coords,
      behavior_values: behavior_values_map(descriptor),
      fitness: fitness,
      pac_id: Map.get(pac, :id),
      pac_snapshot: serialize_pac(pac),
      trait_vector: Map.get(pac, :trait_vector, []),
      generation: generation,
      discovery_metrics: metrics
    }

    case EliteEntry.create(attrs) do
      {:ok, entry} ->
        Logger.debug("[Archive] New elite at #{cell_key} with fitness #{fitness}")
        emit_archive_event(:cell_occupied, %{cell_key: cell_key, fitness: fitness})
        {:added, entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp challenge_elite(existing, new_fitness, pac, _descriptor, _generation, _metrics) do
    if new_fitness > existing.fitness do
      # Replace existing elite
      pac_snapshot = serialize_pac(pac)
      trait_vector = Map.get(pac, :trait_vector, [])

      case EliteEntry.update_elite(existing, new_fitness, pac_snapshot, trait_vector) do
        {:ok, updated} ->
          Logger.debug(
            "[Archive] Replaced elite at #{existing.cell_key}: #{existing.fitness} -> #{new_fitness}"
          )

          {:replaced, updated, existing.fitness}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Existing elite defended
      # Update challenge count (handled by update_elite action with lower fitness)
      case EliteEntry.update_elite(
             existing,
             new_fitness,
             existing.pac_snapshot,
             existing.trait_vector
           ) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end

      {:rejected, :lower_fitness}
    end
  end

  defp behavior_values_map(descriptor) do
    %{
      "logic_density" => descriptor.logic_density,
      "memory_reuse" => descriptor.memory_reuse,
      "action_volatility" => descriptor.action_volatility,
      "task_performance" => descriptor.task_performance,
      "novelty_score" => descriptor.novelty_score
    }
  end

  defp serialize_pac(pac) when is_map(pac) do
    # Extract relevant fields for reconstruction
    Map.take(pac, [:id, :name, :trait_vector, :ruleset, :metadata])
  end

  defp serialize_pac(_), do: %{}

  defp sample_weighted(items, count, weight_fn) when is_list(items) do
    if Enum.empty?(items) do
      []
    else
      # Compute weights
      weights = Enum.map(items, weight_fn)
      total_weight = Enum.sum(weights)

      if total_weight <= 0 do
        Enum.take_random(items, count)
      else
        # Normalize weights
        normalized =
          Enum.zip(items, weights)
          |> Enum.map(fn {item, w} -> {item, w / total_weight} end)

        # Sample with replacement
        sample_with_weights(normalized, count, [])
      end
    end
  end

  defp sample_with_weights(_items, 0, acc), do: Enum.reverse(acc)

  defp sample_with_weights(items, n, acc) do
    r = :rand.uniform()
    selected = pick_by_weight(items, r, 0.0)
    sample_with_weights(items, n - 1, [selected | acc])
  end

  defp pick_by_weight([{item, _weight}], _r, _cumulative), do: item

  defp pick_by_weight([{item, weight} | rest], r, cumulative) do
    new_cumulative = cumulative + weight

    if r <= new_cumulative do
      item
    else
      pick_by_weight(rest, r, new_cumulative)
    end
  end

  defp safe_mean([]), do: 0.0

  defp safe_mean(values) do
    Enum.sum(values) / length(values)
  end

  defp emit_archive_event(event_type, payload) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "evolution:archive",
      {:archive_event, event_type, Map.put(payload, :timestamp, DateTime.utc_now())}
    )

    :telemetry.execute(
      [:thunderline, :evolution, :archive, event_type],
      %{count: 1},
      payload
    )

    :ok
  end
end
