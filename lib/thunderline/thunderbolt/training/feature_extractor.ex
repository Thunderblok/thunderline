defmodule Thunderline.Thunderbolt.Training.FeatureExtractor do
  @moduledoc """
  Enhanced Feature Extraction for ML Training Pipeline.

  Builds on `CerebrosFacade.Mini.Feature` to provide training-specific features:
  - 24-dimension training vector (vs 12-dim inference)
  - Context-aware features (active count, energy state, etc.)
  - Normalized and clipped for neural network training
  - Batch extraction for efficient training data prep

  ## Architecture

  ```
  Thunderbit ──▶ Mini.Feature (12-dim) ──┐
                                          ├──▶ TrainingFeatures (24-dim)
  PAC Context ──▶ Context Features ───────┘
  ```

  ## Feature Vector (24 dimensions)

  ### Thunderbit Features (12 dims from Mini.Feature)
  - `bit_hash_norm` - Normalized bit ID hash
  - `pac_hash_norm` - Normalized PAC ID hash
  - `zone_idx` - Zone index (normalized)
  - `category_idx` - Category index (normalized)
  - `energy` - Energy level [0, 1]
  - `age_ticks` - Normalized age in ticks
  - `health` - Health score [0, 1]
  - `salience` - Salience score [0, 1]
  - `chain_depth` - Workflow chain depth (normalized)
  - `role_idx` - Role index (normalized)
  - `status_idx` - Status index (normalized)
  - `link_count` - Outgoing link count (normalized)

  ### Context Features (12 dims)
  - `active_bit_count` - Active bits in PAC (normalized)
  - `pending_bit_count` - Pending bits in PAC (normalized)
  - `total_energy` - Sum energy of active bits (normalized)
  - `avg_health` - Average health across active bits
  - `avg_salience` - Average salience across active bits
  - `tick_norm` - Current tick (normalized)
  - `workflow_density` - Active workflows (normalized)
  - `entropy_level` - System entropy estimate
  - `cerebros_score` - Latest Cerebros evaluation
  - `recent_transitions` - Transition count in window (normalized)
  - `stale_ratio` - Stale bits / total bits
  - `governance_score` - Crown governance rating

  ## Usage

      # Single extraction
      {:ok, features} = FeatureExtractor.extract(bit, context)
      features.vector  # => [0.1, 0.5, 0.3, ...]

      # Batch extraction for training
      {:ok, batch} = FeatureExtractor.extract_batch(bits, context)
      batch.states  # => [[0.1, 0.5, ...], [0.2, 0.4, ...], ...]

      # Export metadata for Python
      FeatureExtractor.feature_metadata()
      # => %{dimension: 24, names: [...], ranges: [...]}
  """

  alias Thunderline.Thunderbolt.CerebrosFacade.Mini.Feature, as: MiniFeature

  @feature_dimension 24
  @bit_feature_dim 12
  @context_feature_dim 12

  @feature_names [
    # Bit features (0-11)
    :bit_hash_norm,
    :pac_hash_norm,
    :zone_idx,
    :category_idx,
    :energy,
    :age_ticks,
    :health,
    :salience,
    :chain_depth,
    :role_idx,
    :status_idx,
    :link_count,
    # Context features (12-23)
    :active_bit_count,
    :pending_bit_count,
    :total_energy,
    :avg_health,
    :avg_salience,
    :tick_norm,
    :workflow_density,
    :entropy_level,
    :cerebros_score,
    :recent_transitions,
    :stale_ratio,
    :governance_score
  ]

  @type feature_struct :: %{
          vector: [float()],
          dimension: non_neg_integer(),
          bit_features: [float()],
          context_features: [float()],
          metadata: map()
        }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Extracts 24-dimension training features from a Thunderbit and context.

  ## Parameters

  - `bit` - Thunderbit map with id, category, energy, health, etc.
  - `context` - PAC context with active_bits, tick, etc.

  ## Returns

  ```elixir
  {:ok, %{
    vector: [0.1, 0.5, 0.3, ...],  # 24 floats
    dimension: 24,
    bit_features: [...],    # First 12
    context_features: [...], # Last 12
    metadata: %{bit_id: ..., category: ...}
  }}
  ```
  """
  @spec extract(map(), map()) :: {:ok, feature_struct()} | {:error, term()}
  def extract(bit, context \\ %{}) do
    bit_features = extract_bit_features(bit)
    context_features = extract_context_features(context)

    vector = bit_features ++ context_features

    {:ok,
     %{
       vector: vector,
       dimension: @feature_dimension,
       bit_features: bit_features,
       context_features: context_features,
       metadata: %{
         bit_id: Map.get(bit, :id),
         category: Map.get(bit, :category),
         status: Map.get(bit, :status),
         tick: Map.get(context, :tick, 0)
       }
     }}
  rescue
    e -> {:error, {:extraction_failed, e}}
  end

  @doc """
  Extracts features from a batch of Thunderbits.

  Efficient for preparing training datasets.
  """
  @spec extract_batch([map()], map()) :: {:ok, map()} | {:error, term()}
  def extract_batch(bits, context \\ %{}) when is_list(bits) do
    results =
      bits
      |> Enum.map(&extract(&1, context))
      |> Enum.map(fn
        {:ok, f} -> f.vector
        {:error, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok,
     %{
       states: results,
       count: length(results),
       dimension: @feature_dimension
     }}
  end

  @doc """
  Returns feature metadata for Python training scripts.
  """
  @spec feature_metadata() :: map()
  def feature_metadata do
    %{
      dimension: @feature_dimension,
      bit_feature_dim: @bit_feature_dim,
      context_feature_dim: @context_feature_dim,
      names: @feature_names,
      ranges: Enum.map(@feature_names, fn _ -> [0.0, 1.0] end),
      description: "24-dim training features for Thunderbit ML pipeline"
    }
  end

  @doc """
  Returns the feature dimension.
  """
  @spec dimension() :: non_neg_integer()
  def dimension, do: @feature_dimension

  @doc """
  Returns list of feature names in order.
  """
  @spec feature_names() :: [atom()]
  def feature_names, do: @feature_names

  @doc """
  Converts a feature vector to a labeled map.
  """
  @spec vector_to_map([float()]) :: map()
  def vector_to_map(vector) when is_list(vector) do
    @feature_names
    |> Enum.zip(vector)
    |> Map.new()
  end

  # ===========================================================================
  # Bit Feature Extraction
  # ===========================================================================

  defp extract_bit_features(nil), do: List.duplicate(0.0, @bit_feature_dim)

  defp extract_bit_features(bit) when is_map(bit) do
    # Try Mini.Feature first
    case extract_via_mini_feature(bit) do
      {:ok, vector} -> vector
      :error -> extract_bit_features_manual(bit)
    end
  end

  defp extract_bit_features(_), do: List.duplicate(0.0, @bit_feature_dim)

  defp extract_via_mini_feature(bit) do
    if Code.ensure_loaded?(MiniFeature) do
      case MiniFeature.from_bit(bit) do
        {:ok, feature} -> {:ok, MiniFeature.to_vector(feature)}
        _ -> :error
      end
    else
      :error
    end
  rescue
    _ -> :error
  end

  defp extract_bit_features_manual(bit) do
    [
      hash_to_float(Map.get(bit, :id)),
      hash_to_float(Map.get(bit, :pac_id)),
      zone_to_float(Map.get(bit, :zone)),
      category_to_float(Map.get(bit, :category)),
      normalize(Map.get(bit, :energy, 0.5), 0.0, 1.0),
      normalize(Map.get(bit, :age_ticks, 0), 0, 10000),
      normalize(Map.get(bit, :health, 0.5), 0.0, 1.0),
      normalize(Map.get(bit, :salience, 0.5), 0.0, 1.0),
      normalize(Map.get(bit, :chain_depth, 0), 0, 20),
      role_to_float(Map.get(bit, :role)),
      status_to_float(Map.get(bit, :status)),
      normalize(Map.get(bit, :link_count, 0), 0, 50)
    ]
  end

  # ===========================================================================
  # Context Feature Extraction
  # ===========================================================================

  defp extract_context_features(nil), do: List.duplicate(0.0, @context_feature_dim)

  defp extract_context_features(context) when is_map(context) do
    active_bits = Map.get(context, :active_bits, [])
    pending_bits = Map.get(context, :pending_bits, [])
    all_bits = Map.get(context, :bits, active_bits ++ pending_bits)

    active_count = length(active_bits)
    pending_count = length(pending_bits)

    # Calculate aggregate statistics
    {total_energy, avg_health, avg_salience} = calculate_bit_stats(active_bits)

    [
      normalize(active_count, 0, 100),
      normalize(pending_count, 0, 50),
      normalize(total_energy, 0.0, 100.0),
      avg_health,
      avg_salience,
      normalize(Map.get(context, :tick, 0), 0, 100_000),
      normalize(Map.get(context, :workflow_count, 0), 0, 50),
      normalize(Map.get(context, :entropy, 0.0), 0.0, 1.0),
      normalize(Map.get(context, :cerebros_score, 0.5), 0.0, 1.0),
      normalize(Map.get(context, :recent_transitions, 0), 0, 100),
      calculate_stale_ratio(all_bits),
      normalize(Map.get(context, :governance_score, 0.5), 0.0, 1.0)
    ]
  end

  defp extract_context_features(_), do: List.duplicate(0.0, @context_feature_dim)

  defp calculate_bit_stats([]), do: {0.0, 0.5, 0.5}

  defp calculate_bit_stats(bits) when is_list(bits) do
    {energies, healths, saliences} =
      bits
      |> Enum.reduce({[], [], []}, fn bit, {e, h, s} ->
        {
          [Map.get(bit, :energy, 0.5) | e],
          [Map.get(bit, :health, 0.5) | h],
          [Map.get(bit, :salience, 0.5) | s]
        }
      end)

    total_energy = Enum.sum(energies)
    avg_health = safe_mean(healths)
    avg_salience = safe_mean(saliences)

    {total_energy, avg_health, avg_salience}
  end

  defp calculate_stale_ratio([]), do: 0.0

  defp calculate_stale_ratio(bits) do
    stale_count =
      Enum.count(bits, fn bit ->
        Map.get(bit, :status) in [:stale, :retired]
      end)

    stale_count / max(length(bits), 1)
  end

  # ===========================================================================
  # Normalization Helpers
  # ===========================================================================

  defp normalize(value, _min, _max) when is_nil(value), do: 0.0

  defp normalize(value, min, max) when is_number(value) do
    result = (value - min) / max(max - min, 1.0e-6)
    clamp(result, 0.0, 1.0)
  end

  defp normalize(_, _, _), do: 0.0

  defp clamp(value, min, max) do
    value |> max(min) |> min(max)
  end

  defp safe_mean([]), do: 0.5

  defp safe_mean(values) do
    Enum.sum(values) / length(values)
  end

  # ===========================================================================
  # Encoding Helpers
  # ===========================================================================

  @zones %{
    spark: 0,
    active: 1,
    dormant: 2,
    retired: 3
  }

  @categories %{
    memory: 0,
    task: 1,
    goal: 2,
    skill: 3,
    preference: 4,
    context: 5,
    relationship: 6,
    plan: 7
  }

  @roles %{
    primary: 0,
    secondary: 1,
    support: 2,
    background: 3
  }

  @statuses %{
    pending: 0,
    active: 1,
    dormant: 2,
    stale: 3,
    retired: 4,
    archived: 5
  }

  defp hash_to_float(nil), do: 0.0

  defp hash_to_float(id) when is_binary(id) do
    :erlang.phash2(id, 1_000_000) / 1_000_000
  end

  defp hash_to_float(_), do: 0.0

  defp zone_to_float(zone) do
    Map.get(@zones, zone, 0) / max(map_size(@zones) - 1, 1)
  end

  defp category_to_float(category) do
    Map.get(@categories, category, 0) / max(map_size(@categories) - 1, 1)
  end

  defp role_to_float(role) do
    Map.get(@roles, role, 0) / max(map_size(@roles) - 1, 1)
  end

  defp status_to_float(status) do
    Map.get(@statuses, status, 0) / max(map_size(@statuses) - 1, 1)
  end
end
