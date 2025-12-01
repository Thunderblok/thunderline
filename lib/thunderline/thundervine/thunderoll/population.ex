defmodule Thunderline.Thundervine.Thunderoll.Population do
  @moduledoc """
  Population management for Thunderoll EGGROLL optimization.

  Handles population-level operations including:
  - Population sizing and configuration
  - Fitness statistics tracking
  - Elite selection (for future MAP-Elites integration)
  - Population-level telemetry

  ## Population Sizing Guidelines

  From EGGROLL paper:
  - Small (256-1024): Fast iteration, good for initial exploration
  - Medium (4096-16384): Balanced throughput/update quality
  - Large (65536-262144): Full EGGROLL scale, near-inference throughput

  ## Memory Requirements

  At rank=1 with float32:
  - Population 1024, hidden 256: ~2MB
  - Population 16384, hidden 1024: ~128MB  
  - Population 262144, hidden 4096: ~8GB
  """

  defstruct [
    :size,
    :rank,
    :sigma,
    :param_shape,
    :generation_history,
    :elite_indices,
    :config
  ]

  @type t :: %__MODULE__{
          size: pos_integer(),
          rank: pos_integer(),
          sigma: float(),
          param_shape: {pos_integer(), pos_integer()},
          generation_history: [map()],
          elite_indices: [non_neg_integer()],
          config: map()
        }

  @type fitness_stats :: %{
          mean: float(),
          std: float(),
          min: float(),
          max: float(),
          median: float()
        }

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Create a new population configuration.
  """
  @spec new(pos_integer(), {pos_integer(), pos_integer()}, keyword()) :: t()
  def new(size, param_shape, opts \\ []) do
    %__MODULE__{
      size: size,
      rank: opts[:rank] || 1,
      sigma: opts[:sigma] || 0.02,
      param_shape: param_shape,
      generation_history: [],
      elite_indices: [],
      config: %{
        elite_fraction: opts[:elite_fraction] || 0.1,
        min_population: opts[:min_population] || 32,
        max_population: opts[:max_population] || 262_144
      }
    }
  end

  @doc """
  Compute statistics from a fitness vector.
  """
  @spec fitness_statistics([float()]) :: fitness_stats()
  def fitness_statistics(fitness_vector) when is_list(fitness_vector) and length(fitness_vector) > 0 do
    sorted = Enum.sort(fitness_vector)
    n = length(sorted)
    mean = Enum.sum(sorted) / n

    variance =
      sorted
      |> Enum.map(fn x -> (x - mean) * (x - mean) end)
      |> Enum.sum()
      |> Kernel./(n)

    std = :math.sqrt(variance)

    median =
      if rem(n, 2) == 0 do
        (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
      else
        Enum.at(sorted, div(n, 2))
      end

    %{
      mean: mean,
      std: std,
      min: List.first(sorted),
      max: List.last(sorted),
      median: median
    }
  end

  def fitness_statistics(_), do: %{mean: 0.0, std: 0.0, min: 0.0, max: 0.0, median: 0.0}

  @doc """
  Record generation results and update population state.
  """
  @spec record_generation(t(), [float()], non_neg_integer()) :: t()
  def record_generation(%__MODULE__{} = pop, fitness_vector, generation_idx) do
    stats = fitness_statistics(fitness_vector)

    # Find elite indices (top performers)
    elite_count = max(1, round(pop.size * pop.config.elite_fraction))

    elite_indices =
      fitness_vector
      |> Enum.with_index()
      |> Enum.sort_by(fn {fitness, _idx} -> -fitness end)
      |> Enum.take(elite_count)
      |> Enum.map(fn {_fitness, idx} -> idx end)

    generation_record = %{
      index: generation_idx,
      stats: stats,
      elite_indices: elite_indices,
      timestamp: DateTime.utc_now()
    }

    %{
      pop
      | generation_history: pop.generation_history ++ [generation_record],
        elite_indices: elite_indices
    }
  end

  @doc """
  Check if fitness has plateaued (no improvement over window).
  """
  @spec fitness_plateaued?(t(), non_neg_integer(), float()) :: boolean()
  def fitness_plateaued?(%__MODULE__{generation_history: history}, window_size, threshold) do
    if length(history) < window_size do
      false
    else
      recent = Enum.take(history, -window_size)
      first_mean = List.first(recent).stats.mean
      last_mean = List.last(recent).stats.mean

      abs(last_mean - first_mean) < threshold
    end
  end

  @doc """
  Get the best fitness achieved across all generations.
  """
  @spec best_fitness(t()) :: float() | nil
  def best_fitness(%__MODULE__{generation_history: []}) do
    nil
  end

  def best_fitness(%__MODULE__{generation_history: history}) do
    history
    |> Enum.map(& &1.stats.max)
    |> Enum.max()
  end

  @doc """
  Get improvement over last N generations.
  """
  @spec improvement_rate(t(), non_neg_integer()) :: float() | nil
  def improvement_rate(%__MODULE__{generation_history: history}, window_size)
      when length(history) >= window_size do
    recent = Enum.take(history, -window_size)
    first_mean = List.first(recent).stats.mean
    last_mean = List.last(recent).stats.mean

    if first_mean != 0 do
      (last_mean - first_mean) / abs(first_mean)
    else
      last_mean
    end
  end

  def improvement_rate(_, _), do: nil

  @doc """
  Estimate memory usage for population.
  """
  @spec estimate_memory_mb(t()) :: float()
  def estimate_memory_mb(%__MODULE__{} = pop) do
    {m, n} = pop.param_shape
    bytes_per_float = 4
    # A ∈ R^(m×r), B ∈ R^(n×r) per member
    bytes_per_member = (m * pop.rank + n * pop.rank) * bytes_per_float
    total_bytes = pop.size * bytes_per_member
    total_bytes / (1024 * 1024)
  end

  @doc """
  Recommend population size based on parameter dimensions and available memory.
  """
  @spec recommend_size({pos_integer(), pos_integer()}, pos_integer(), float()) :: pos_integer()
  def recommend_size({m, n}, rank, available_memory_mb) do
    bytes_per_float = 4
    bytes_per_member = (m * rank + n * rank) * bytes_per_float
    max_from_memory = round(available_memory_mb * 1024 * 1024 / bytes_per_member)

    # Clamp to reasonable range
    max_from_memory
    |> max(32)
    |> min(262_144)
  end
end
