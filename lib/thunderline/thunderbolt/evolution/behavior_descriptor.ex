defmodule Thunderline.Thunderbolt.Evolution.BehaviorDescriptor do
  @moduledoc """
  Defines behavior dimensions for MAP-Elites quality-diversity search (HC-Δ-4).

  Each dimension represents a distinct axis of agent behavior that defines
  a "niche" in the behavior space. The archive stores the best-performing
  agent for each niche (cell).

  ## Behavior Dimensions

  1. **LogicDensity** - Number of active gates in agent's CA ruleset
  2. **MemoryReuse** - Frequency of state pattern reuse (0.0-1.0)
  3. **ActionVolatility** - Rate of behavioral change over time (0.0-1.0)
  4. **TaskPerformance** - Objective fitness score (0.0-1.0)
  5. **NoveltyScore** - Distance from existing elites (0.0-1.0)

  ## Grid Resolution

  Each dimension is discretized into bins. Default resolution is 10 bins
  per dimension, creating a 5D grid with 10^5 = 100,000 possible cells.

  ## Usage

  ```elixir
  # Extract behavior descriptors from a PAC snapshot
  {:ok, descriptors} = BehaviorDescriptor.extract(pac, metrics)

  # Convert to grid coordinates
  coords = BehaviorDescriptor.to_grid_coords(descriptors, resolution: 10)

  # Get cell key for archive lookup
  cell_key = BehaviorDescriptor.cell_key(coords)
  ```
  """

  alias Thunderline.Thunderpac.Resources.PAC

  @type dimension :: :logic_density | :memory_reuse | :action_volatility | :task_performance | :novelty_score

  @type t :: %__MODULE__{
          logic_density: float(),
          memory_reuse: float(),
          action_volatility: float(),
          task_performance: float(),
          novelty_score: float(),
          raw_values: map()
        }

  @type grid_coords :: %{
          logic_density: non_neg_integer(),
          memory_reuse: non_neg_integer(),
          action_volatility: non_neg_integer(),
          task_performance: non_neg_integer(),
          novelty_score: non_neg_integer()
        }

  @dimensions [:logic_density, :memory_reuse, :action_volatility, :task_performance, :novelty_score]
  @default_resolution 10

  defstruct logic_density: 0.0,
            memory_reuse: 0.0,
            action_volatility: 0.0,
            task_performance: 0.0,
            novelty_score: 0.0,
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
         {:ok, novelty_score} <- calculate_novelty(pac, metrics, existing_elites) do
      descriptor = %__MODULE__{
        logic_density: normalize(logic_density, :logic_density),
        memory_reuse: normalize(memory_reuse, :memory_reuse),
        action_volatility: normalize(action_volatility, :action_volatility),
        task_performance: normalize(task_performance, :task_performance),
        novelty_score: normalize(novelty_score, :novelty_score),
        raw_values: %{
          logic_density: logic_density,
          memory_reuse: memory_reuse,
          action_volatility: action_volatility,
          task_performance: task_performance,
          novelty_score: novelty_score
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

    %{
      logic_density: discretize(descriptor.logic_density, resolution),
      memory_reuse: discretize(descriptor.memory_reuse, resolution),
      action_volatility: discretize(descriptor.action_volatility, resolution),
      task_performance: discretize(descriptor.task_performance, resolution),
      novelty_score: discretize(descriptor.novelty_score, resolution)
    }
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
  def from_vector(vector) when is_list(vector) and length(vector) == 5 do
    values =
      @dimensions
      |> Enum.zip(vector)
      |> Map.new()

    {:ok,
     %__MODULE__{
       logic_density: values.logic_density,
       memory_reuse: values.memory_reuse,
       action_volatility: values.action_volatility,
       task_performance: values.task_performance,
       novelty_score: values.novelty_score
     }}
  end

  def from_vector(_), do: {:error, :invalid_vector}

  @doc """
  Returns dimension metadata including value ranges.
  """
  @spec dimension_metadata(dimension()) :: map()
  def dimension_metadata(dim) do
    case dim do
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

    avg_distance = if Enum.empty?(distances), do: 1.0, else: Enum.sum(distances) / length(distances)

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
end
