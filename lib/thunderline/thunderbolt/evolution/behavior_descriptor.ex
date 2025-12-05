defmodule Thunderline.Thunderbolt.Evolution.BehaviorDescriptor do
  @moduledoc """
  Defines behavior dimensions for MAP-Elites quality-diversity search (HC-Δ-4, HC-79).

  Each dimension represents a distinct axis of agent behavior that defines
  a "niche" in the behavior space. The archive stores the best-performing
  agent for each niche (cell).

  ## Behavior Dimensions

  ### Core Dimensions (HC-Δ-4)
  1. **LogicDensity** - Number of active gates in agent's CA ruleset
  2. **MemoryReuse** - Frequency of state pattern reuse (0.0-1.0)
  3. **ActionVolatility** - Rate of behavioral change over time (0.0-1.0)
  4. **TaskPerformance** - Objective fitness score (0.0-1.0)
  5. **NoveltyScore** - Distance from existing elites (0.0-1.0)

  ### Memory Dimensions (HC-79: MIRAS/Titans)
  6. **MemoryUtilization** - Fraction of memory capacity used (0.0-1.0)
  7. **WriteFrequency** - Memory updates per tick (0.0-1.0)
  8. **RetrievalAccuracy** - Memory hit rate / relevance (0.0-1.0)
  9. **SurpriseDistribution** - Entropy of surprise signal (0.0-1.0)
  10. **TemporalCoherence** - Memory-output correlation over time (0.0-1.0)

  ## Memory Phenotypes (HC-79)

  The memory dimensions enable discovery of diverse memory behaviors:
  - **Fast Writers** - High write frequency, low temporal coherence
  - **Long Retainers** - High memory utilization, low write frequency
  - **Selective Memorizers** - High retrieval accuracy, moderate writes
  - **Surprise Seekers** - High surprise distribution entropy

  ## Grid Resolution

  Each dimension is discretized into bins. Default resolution is 10 bins
  per dimension. With 10 dimensions, this creates 10^10 possible cells,
  though in practice only a sparse subset are occupied.

  ## Usage

  ```elixir
  # Extract behavior descriptors from a PAC snapshot (with memory metrics)
  {:ok, descriptors} = BehaviorDescriptor.extract(pac, metrics)

  # Convert to grid coordinates
  coords = BehaviorDescriptor.to_grid_coords(descriptors, resolution: 10)

  # Get cell key for archive lookup
  cell_key = BehaviorDescriptor.cell_key(coords)

  # Use core-only dimensions for backward compatibility
  coords = BehaviorDescriptor.to_grid_coords(descriptors, 
    resolution: 10, 
    dimensions: :core
  )
  ```
  """

  alias Thunderline.Thunderpac.Resources.PAC

  @type dimension ::
          :logic_density
          | :memory_reuse
          | :action_volatility
          | :task_performance
          | :novelty_score
          # HC-79: Memory dimensions
          | :memory_utilization
          | :write_frequency
          | :retrieval_accuracy
          | :surprise_distribution
          | :temporal_coherence

  @type t :: %__MODULE__{
          logic_density: float(),
          memory_reuse: float(),
          action_volatility: float(),
          task_performance: float(),
          novelty_score: float(),
          # HC-79: Memory dimensions
          memory_utilization: float(),
          write_frequency: float(),
          retrieval_accuracy: float(),
          surprise_distribution: float(),
          temporal_coherence: float(),
          raw_values: map()
        }

  @type grid_coords :: %{
          logic_density: non_neg_integer(),
          memory_reuse: non_neg_integer(),
          action_volatility: non_neg_integer(),
          task_performance: non_neg_integer(),
          novelty_score: non_neg_integer(),
          # HC-79: Memory dimensions
          memory_utilization: non_neg_integer(),
          write_frequency: non_neg_integer(),
          retrieval_accuracy: non_neg_integer(),
          surprise_distribution: non_neg_integer(),
          temporal_coherence: non_neg_integer()
        }

  # Core dimensions (original HC-Δ-4)
  @core_dimensions [
    :logic_density,
    :memory_reuse,
    :action_volatility,
    :task_performance,
    :novelty_score
  ]

  # Memory dimensions (HC-79: MIRAS/Titans)
  @memory_dimensions [
    :memory_utilization,
    :write_frequency,
    :retrieval_accuracy,
    :surprise_distribution,
    :temporal_coherence
  ]

  # All dimensions combined
  @dimensions @core_dimensions ++ @memory_dimensions
  @default_resolution 10

  defstruct logic_density: 0.0,
            memory_reuse: 0.0,
            action_volatility: 0.0,
            task_performance: 0.0,
            novelty_score: 0.0,
            # HC-79: Memory dimensions
            memory_utilization: 0.0,
            write_frequency: 0.0,
            retrieval_accuracy: 0.0,
            surprise_distribution: 0.0,
            temporal_coherence: 0.0,
            raw_values: %{}

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns the list of all behavior dimensions.
  """
  @spec dimensions() :: [dimension()]
  def dimensions, do: @dimensions

  @doc """
  Returns the list of core behavior dimensions (original HC-Δ-4).
  """
  @spec core_dimensions() :: [dimension()]
  def core_dimensions, do: @core_dimensions

  @doc """
  Returns the list of memory dimensions (HC-79: MIRAS/Titans).
  """
  @spec memory_dimensions() :: [dimension()]
  def memory_dimensions, do: @memory_dimensions

  @doc """
  Returns the default grid resolution per dimension.
  """
  @spec default_resolution() :: pos_integer()
  def default_resolution, do: @default_resolution

  @doc """
  Extracts behavior descriptors from a PAC and its metrics.

  ## Parameters
  - `pac` - The PAC resource
  - `metrics` - Map of metrics from the PAC run
  - `opts` - Options:
    - `:existing_elites` - List of existing elite descriptors for novelty calculation

  ## Returns
  - `{:ok, %BehaviorDescriptor{}}` on success
  - `{:error, reason}` on failure
  """
  @spec extract(PAC.t() | map(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def extract(pac, metrics, opts \\ []) do
    existing_elites = Keyword.get(opts, :existing_elites, [])

    with {:ok, logic_density} <- extract_logic_density(pac, metrics),
         {:ok, memory_reuse} <- extract_memory_reuse(pac, metrics),
         {:ok, action_volatility} <- extract_action_volatility(pac, metrics),
         {:ok, task_performance} <- extract_task_performance(metrics),
         {:ok, novelty_score} <- calculate_novelty(pac, metrics, existing_elites),
         # HC-79: Extract memory dimensions
         {:ok, memory_utilization} <- extract_memory_utilization(pac, metrics),
         {:ok, write_frequency} <- extract_write_frequency(pac, metrics),
         {:ok, retrieval_accuracy} <- extract_retrieval_accuracy(pac, metrics),
         {:ok, surprise_distribution} <- extract_surprise_distribution(pac, metrics),
         {:ok, temporal_coherence} <- extract_temporal_coherence(pac, metrics) do
      descriptor = %__MODULE__{
        # Core dimensions
        logic_density: normalize(logic_density, :logic_density),
        memory_reuse: normalize(memory_reuse, :memory_reuse),
        action_volatility: normalize(action_volatility, :action_volatility),
        task_performance: normalize(task_performance, :task_performance),
        novelty_score: normalize(novelty_score, :novelty_score),
        # HC-79: Memory dimensions
        memory_utilization: normalize(memory_utilization, :memory_utilization),
        write_frequency: normalize(write_frequency, :write_frequency),
        retrieval_accuracy: normalize(retrieval_accuracy, :retrieval_accuracy),
        surprise_distribution: normalize(surprise_distribution, :surprise_distribution),
        temporal_coherence: normalize(temporal_coherence, :temporal_coherence),
        raw_values: %{
          logic_density: logic_density,
          memory_reuse: memory_reuse,
          action_volatility: action_volatility,
          task_performance: task_performance,
          novelty_score: novelty_score,
          memory_utilization: memory_utilization,
          write_frequency: write_frequency,
          retrieval_accuracy: retrieval_accuracy,
          surprise_distribution: surprise_distribution,
          temporal_coherence: temporal_coherence
        }
      }

      {:ok, descriptor}
    end
  end

  @doc """
  Converts behavior descriptors to grid coordinates.

  ## Parameters
  - `descriptor` - The behavior descriptor struct
  - `opts` - Options:
    - `:resolution` - Number of bins per dimension (default: 10)

  ## Returns
  A map of dimension -> bin index
  """
  @spec to_grid_coords(t(), keyword()) :: grid_coords()
  def to_grid_coords(%__MODULE__{} = descriptor, opts \\ []) do
    resolution = Keyword.get(opts, :resolution, @default_resolution)
    dimension_set = Keyword.get(opts, :dimensions, :all)

    dims =
      case dimension_set do
        :core -> @core_dimensions
        :memory -> @memory_dimensions
        :all -> @dimensions
        custom when is_list(custom) -> custom
      end

    dims
    |> Enum.reduce(%{}, fn dim, acc ->
      value = Map.get(descriptor, dim, 0.0)
      Map.put(acc, dim, discretize(value, resolution))
    end)
  end

  @doc """
  Generates a unique cell key from grid coordinates.

  The key is a string representation of the coordinates that can be
  used as a map key or for archive lookup.
  """
  @spec cell_key(grid_coords()) :: String.t()
  def cell_key(%{} = coords) do
    @dimensions
    |> Enum.map(fn dim -> Map.get(coords, dim, 0) end)
    |> Enum.join(":")
  end

  @doc """
  Parses a cell key back to grid coordinates.
  """
  @spec parse_cell_key(String.t()) :: {:ok, grid_coords()} | {:error, :invalid_key}
  def parse_cell_key(key) when is_binary(key) do
    parts = String.split(key, ":")

    if length(parts) == length(@dimensions) do
      coords =
        @dimensions
        |> Enum.zip(parts)
        |> Enum.reduce(%{}, fn {dim, val}, acc ->
          Map.put(acc, dim, String.to_integer(val))
        end)

      {:ok, coords}
    else
      {:error, :invalid_key}
    end
  rescue
    _ -> {:error, :invalid_key}
  end

  @doc """
  Calculates the Euclidean distance between two descriptors in normalized space.
  """
  @spec distance(t(), t()) :: float()
  def distance(%__MODULE__{} = d1, %__MODULE__{} = d2) do
    @dimensions
    |> Enum.map(fn dim ->
      v1 = Map.get(d1, dim)
      v2 = Map.get(d2, dim)
      (v1 - v2) * (v1 - v2)
    end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  @doc """
  Converts a descriptor to a flat vector representation.
  """
  @spec to_vector(t()) :: [float()]
  def to_vector(%__MODULE__{} = descriptor) do
    Enum.map(@dimensions, fn dim -> Map.get(descriptor, dim) end)
  end

  @doc """
  Creates a descriptor from a vector representation.
  """
  @spec from_vector([float()]) :: {:ok, t()} | {:error, :invalid_vector}
  def from_vector(vector) when is_list(vector) and length(vector) == 10 do
    values =
      @dimensions
      |> Enum.zip(vector)
      |> Map.new()

    {:ok,
     %__MODULE__{
       # Core dimensions
       logic_density: values.logic_density,
       memory_reuse: values.memory_reuse,
       action_volatility: values.action_volatility,
       task_performance: values.task_performance,
       novelty_score: values.novelty_score,
       # HC-79: Memory dimensions
       memory_utilization: values.memory_utilization,
       write_frequency: values.write_frequency,
       retrieval_accuracy: values.retrieval_accuracy,
       surprise_distribution: values.surprise_distribution,
       temporal_coherence: values.temporal_coherence
     }}
  end

  # Backward compatibility: accept 5-element vectors (core dimensions only)
  def from_vector(vector) when is_list(vector) and length(vector) == 5 do
    values =
      @core_dimensions
      |> Enum.zip(vector)
      |> Map.new()

    {:ok,
     %__MODULE__{
       logic_density: values.logic_density,
       memory_reuse: values.memory_reuse,
       action_volatility: values.action_volatility,
       task_performance: values.task_performance,
       novelty_score: values.novelty_score
       # Memory dimensions default to 0.0
     }}
  end

  def from_vector(_), do: {:error, :invalid_vector}

  @doc """
  Returns dimension metadata including value ranges.
  """
  @spec dimension_metadata(dimension()) :: map()
  def dimension_metadata(dim) do
    case dim do
      # Core dimensions (HC-Δ-4)
      :logic_density ->
        %{
          name: "Logic Density",
          description: "Number of active gates in agent's CA ruleset",
          min_raw: 0,
          max_raw: 256,
          unit: "gates"
        }

      :memory_reuse ->
        %{
          name: "Memory Reuse",
          description: "Frequency of state pattern reuse",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "ratio"
        }

      :action_volatility ->
        %{
          name: "Action Volatility",
          description: "Rate of behavioral change over time",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "ratio"
        }

      :task_performance ->
        %{
          name: "Task Performance",
          description: "Objective fitness score",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "score"
        }

      :novelty_score ->
        %{
          name: "Novelty Score",
          description: "Distance from existing elites",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "normalized distance"
        }

      # HC-79: Memory dimensions (MIRAS/Titans)
      :memory_utilization ->
        %{
          name: "Memory Utilization",
          description: "Fraction of memory capacity actively used",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "ratio"
        }

      :write_frequency ->
        %{
          name: "Write Frequency",
          description: "Rate of memory updates per tick",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "updates/tick"
        }

      :retrieval_accuracy ->
        %{
          name: "Retrieval Accuracy",
          description: "Memory hit rate / retrieval relevance",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "accuracy"
        }

      :surprise_distribution ->
        %{
          name: "Surprise Distribution",
          description: "Entropy of surprise signal over time",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "normalized entropy"
        }

      :temporal_coherence ->
        %{
          name: "Temporal Coherence",
          description: "Memory-output correlation over time window",
          min_raw: 0.0,
          max_raw: 1.0,
          unit: "correlation"
        }
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # DIMENSION EXTRACTORS
  # ═══════════════════════════════════════════════════════════════

  defp extract_logic_density(pac, metrics) do
    # Try multiple sources for logic density
    cond do
      # From metrics (if CA snapshot available)
      is_map(metrics) and Map.has_key?(metrics, :ca_stats) ->
        ca_stats = metrics.ca_stats
        gate_count = Map.get(ca_stats, :active_gates, 0)
        {:ok, gate_count}

      # From PAC ruleset size
      is_map(pac) and Map.has_key?(pac, :ruleset) ->
        ruleset = pac.ruleset || %{}
        gate_count = map_size(ruleset)
        {:ok, gate_count}

      # From metrics trait vector (proxy)
      is_map(metrics) and Map.has_key?(metrics, :trait_vector) ->
        traits = metrics.trait_vector || []
        # Use vector variance as proxy for gate complexity
        complexity = vector_variance(traits) * 256
        {:ok, complexity}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_memory_reuse(pac, metrics) do
    cond do
      # From CA pattern analysis
      is_map(metrics) and Map.has_key?(metrics, :pattern_reuse_ratio) ->
        {:ok, metrics.pattern_reuse_ratio}

      # From CA stats
      is_map(metrics) and Map.has_key?(metrics, :ca_stats) ->
        ca_stats = metrics.ca_stats
        # Use state overlap as proxy
        overlap = Map.get(ca_stats, :state_overlap, 0.0)
        {:ok, overlap}

      # From memory context if available
      is_map(pac) and Map.has_key?(pac, :memory_context) ->
        ctx = pac.memory_context || %{}
        # Measure how much context is reused
        reuse = Map.get(ctx, :reuse_count, 0) / max(Map.get(ctx, :access_count, 1), 1)
        {:ok, reuse}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_action_volatility(_pac, metrics) do
    cond do
      # From action history variance
      is_map(metrics) and Map.has_key?(metrics, :action_variance) ->
        {:ok, metrics.action_variance}

      # From decision entropy
      is_map(metrics) and Map.has_key?(metrics, :decision_entropy) ->
        # Normalize entropy to 0-1
        entropy = metrics.decision_entropy
        normalized = min(1.0, entropy / 3.0)
        {:ok, normalized}

      # From trait vector change rate
      is_map(metrics) and Map.has_key?(metrics, :trait_delta) ->
        delta = metrics.trait_delta || 0.0
        {:ok, min(1.0, delta)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_task_performance(metrics) do
    cond do
      # Direct fitness score
      is_map(metrics) and Map.has_key?(metrics, :fitness) ->
        {:ok, metrics.fitness}

      # Reward-based
      is_map(metrics) and Map.has_key?(metrics, :cumulative_reward) ->
        # Normalize assuming max reward of 100
        reward = metrics.cumulative_reward
        normalized = min(1.0, max(0.0, reward / 100.0))
        {:ok, normalized}

      # Success rate
      is_map(metrics) and Map.has_key?(metrics, :success_rate) ->
        {:ok, metrics.success_rate}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # HC-79: MEMORY DIMENSION EXTRACTORS (MIRAS/Titans)
  # ═══════════════════════════════════════════════════════════════

  defp extract_memory_utilization(pac, metrics) do
    cond do
      # From memory module metrics
      is_map(metrics) and Map.has_key?(metrics, :memory_utilization) ->
        {:ok, metrics.memory_utilization}

      # From PAC memory context
      is_map(pac) and Map.has_key?(pac, :memory_module) ->
        mem = pac.memory_module || %{}
        used = Map.get(mem, :slots_used, 0)
        total = Map.get(mem, :total_slots, 1)
        {:ok, min(1.0, used / max(total, 1))}

      # From memory stats in metrics
      is_map(metrics) and Map.has_key?(metrics, :memory_stats) ->
        stats = metrics.memory_stats
        {:ok, Map.get(stats, :utilization, 0.0)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_write_frequency(_pac, metrics) do
    cond do
      # Direct write frequency
      is_map(metrics) and Map.has_key?(metrics, :write_frequency) ->
        {:ok, metrics.write_frequency}

      # From memory write count / tick count
      is_map(metrics) and Map.has_key?(metrics, :memory_writes) and Map.has_key?(metrics, :tick_count) ->
        writes = metrics.memory_writes
        ticks = max(metrics.tick_count, 1)
        # Normalize: expect ~0.1-0.5 writes per tick
        normalized = min(1.0, (writes / ticks) * 2.0)
        {:ok, normalized}

      # From memory stats
      is_map(metrics) and Map.has_key?(metrics, :memory_stats) ->
        stats = metrics.memory_stats
        {:ok, Map.get(stats, :write_rate, 0.0)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_retrieval_accuracy(_pac, metrics) do
    cond do
      # Direct retrieval accuracy
      is_map(metrics) and Map.has_key?(metrics, :retrieval_accuracy) ->
        {:ok, metrics.retrieval_accuracy}

      # From hit/miss ratio
      is_map(metrics) and Map.has_key?(metrics, :memory_hits) and Map.has_key?(metrics, :memory_queries) ->
        hits = metrics.memory_hits
        queries = max(metrics.memory_queries, 1)
        {:ok, hits / queries}

      # From memory stats
      is_map(metrics) and Map.has_key?(metrics, :memory_stats) ->
        stats = metrics.memory_stats
        {:ok, Map.get(stats, :hit_rate, 0.0)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_surprise_distribution(_pac, metrics) do
    cond do
      # Direct surprise entropy
      is_map(metrics) and Map.has_key?(metrics, :surprise_entropy) ->
        {:ok, metrics.surprise_entropy}

      # From surprise history
      is_map(metrics) and Map.has_key?(metrics, :surprise_history) ->
        history = metrics.surprise_history || []
        entropy = calculate_entropy(history)
        # Normalize assuming max entropy of ~3 bits
        {:ok, min(1.0, entropy / 3.0)}

      # From memory stats
      is_map(metrics) and Map.has_key?(metrics, :memory_stats) ->
        stats = metrics.memory_stats
        {:ok, Map.get(stats, :surprise_distribution, 0.0)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp extract_temporal_coherence(_pac, metrics) do
    cond do
      # Direct temporal coherence
      is_map(metrics) and Map.has_key?(metrics, :temporal_coherence) ->
        {:ok, metrics.temporal_coherence}

      # From memory-output correlation
      is_map(metrics) and Map.has_key?(metrics, :memory_output_correlation) ->
        {:ok, abs(metrics.memory_output_correlation)}

      # From memory stats
      is_map(metrics) and Map.has_key?(metrics, :memory_stats) ->
        stats = metrics.memory_stats
        {:ok, Map.get(stats, :temporal_coherence, 0.0)}

      # Default
      true ->
        {:ok, 0.0}
    end
  end

  defp calculate_novelty(_pac, _metrics, []) do
    # No existing elites, maximum novelty
    {:ok, 1.0}
  end

  defp calculate_novelty(_pac, metrics, existing_elites) when is_list(existing_elites) do
    # Calculate average distance to k-nearest neighbors
    k = min(15, length(existing_elites))

    # Create a temporary descriptor for distance calculation
    current_vector = [
      Map.get(metrics, :logic_density, 0.0),
      Map.get(metrics, :memory_reuse, 0.0),
      Map.get(metrics, :action_volatility, 0.0),
      Map.get(metrics, :task_performance, 0.0),
      0.0
    ]

    distances =
      existing_elites
      |> Enum.map(fn elite ->
        elite_vector = to_vector(elite)
        euclidean_distance(current_vector, elite_vector)
      end)
      |> Enum.sort()
      |> Enum.take(k)

    avg_distance =
      if Enum.empty?(distances), do: 1.0, else: Enum.sum(distances) / length(distances)

    # Normalize distance (assuming max dimension distance of sqrt(5) ≈ 2.24)
    normalized = min(1.0, avg_distance / 2.24)
    {:ok, normalized}
  end

  # ═══════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp normalize(value, dimension) do
    meta = dimension_metadata(dimension)
    min_val = meta.min_raw
    max_val = meta.max_raw

    cond do
      max_val == min_val -> 0.0
      value <= min_val -> 0.0
      value >= max_val -> 1.0
      true -> (value - min_val) / (max_val - min_val)
    end
  end

  defp discretize(value, resolution) when is_float(value) and value >= 0.0 and value <= 1.0 do
    bin = trunc(value * resolution)
    min(bin, resolution - 1)
  end

  defp discretize(_, resolution), do: resolution - 1

  defp euclidean_distance(v1, v2) when is_list(v1) and is_list(v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> (a - b) * (a - b) end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  defp vector_variance([]), do: 0.0

  defp vector_variance(vector) do
    n = length(vector)
    mean = Enum.sum(vector) / n

    variance =
      vector
      |> Enum.map(fn x -> (x - mean) * (x - mean) end)
      |> Enum.sum()
      |> Kernel./(n)

    variance
  end

  # HC-79: Calculate entropy for surprise distribution
  defp calculate_entropy([]), do: 0.0

  defp calculate_entropy(values) when is_list(values) do
    # Bin values into histogram (10 bins from 0 to 1)
    bins = 10
    counts = Enum.reduce(values, List.duplicate(0, bins), fn val, acc ->
      bin = min(bins - 1, trunc(val * bins))
      List.update_at(acc, bin, &(&1 + 1))
    end)

    total = length(values)
    if total == 0 do
      0.0
    else
      # Calculate Shannon entropy
      counts
      |> Enum.map(fn count ->
        if count == 0 do
          0.0
        else
          p = count / total
          -p * :math.log2(p)
        end
      end)
      |> Enum.sum()
    end
  end
end
