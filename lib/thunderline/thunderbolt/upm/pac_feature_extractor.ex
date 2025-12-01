defmodule Thunderline.Thunderbolt.UPM.PACFeatureExtractor do
  @moduledoc """
  Extracts features from PAC state for UPM training.

  This module bridges Thunderpac (PAC lifecycle, intents, state) with
  Thunderbolt's UPM (Unified Persistent Model) for online learning.

  ## Feature Categories

  1. **Trait Features** - PAC's trait_vector (personality/behavioral traits)
  2. **State Features** - Encoded lifecycle state, activity metrics
  3. **Memory Features** - Hashed/embedded memory state
  4. **Intent Features** - Current intent queue characteristics
  5. **Temporal Features** - Time since last activity, tick counts

  ## Usage

      pac = Ash.get!(PAC, pac_id)
      features = PACFeatureExtractor.extract(pac)
      # => %{features: Nx.Tensor, labels: Nx.Tensor, metadata: map()}
  """

  alias Thunderline.Thunderpac.Resources.{PAC, PACState, PACIntent}
  require Logger

  @feature_dim 64
  @trait_dim 16
  @state_dim 8
  @memory_dim 24
  @intent_dim 8
  @temporal_dim 8

  @status_encoding %{
    seed: 0.0,
    dormant: 0.2,
    active: 1.0,
    suspended: 0.5,
    archived: 0.1
  }

  @intent_status_encoding %{
    pending: 0.0,
    queued: 0.25,
    processing: 0.5,
    completed: 1.0,
    failed: 0.1,
    cancelled: 0.05
  }

  @doc """
  Extract features from a PAC for UPM training.

  Returns a map with:
  - `:features` - Nx tensor of shape {1, feature_dim}
  - `:labels` - Nx tensor (optional, derived from PAC metrics)
  - `:metadata` - Extraction metadata for debugging
  """
  @spec extract(PAC.t()) :: map()
  def extract(%PAC{} = pac) do
    trait_features = extract_traits(pac.trait_vector)
    state_features = extract_state(pac)
    memory_features = extract_memory(pac.memory_state)
    intent_features = extract_intents(pac.intent_queue)
    temporal_features = extract_temporal(pac)

    # Concatenate all features
    all_features =
      [
        trait_features,
        state_features,
        memory_features,
        intent_features,
        temporal_features
      ]
      |> Nx.concatenate()
      |> Nx.reshape({1, @feature_dim})

    # Generate labels from PAC performance (if available)
    labels = generate_labels(pac)

    %{
      features: all_features,
      labels: labels,
      metadata: %{
        pac_id: pac.id,
        pac_status: pac.status,
        extracted_at: DateTime.utc_now(),
        feature_dim: @feature_dim,
        trait_count: length(pac.trait_vector || []),
        intent_count: length(pac.intent_queue || []),
        memory_keys: map_size(pac.memory_state || %{})
      }
    }
  end

  @doc """
  Extract features from a PAC state snapshot.
  """
  @spec extract_from_state(PACState.t()) :: map()
  def extract_from_state(%PACState{} = state) do
    # Decode full state from snapshot
    full_state = state.full_state || %{}

    trait_features = extract_traits(Map.get(full_state, :trait_vector, []))
    memory_features = extract_memory(Map.get(full_state, :memory_state, %{}))
    intent_features = extract_intents(Map.get(full_state, :intent_queue, []))

    # State-specific features
    state_features =
      [
        # Snapshot type encoding
        encode_snapshot_type(state.snapshot_type),
        # Checksum entropy (high entropy = more randomness in state)
        checksum_entropy(state.checksum),
        # Normalized sizes
        normalize(state.state_size_bytes || 0, 0, 100_000),
        normalize(state.memory_size_bytes || 0, 0, 50_000),
        normalize(state.intent_count || 0, 0, 100),
        # Padding
        0.0,
        0.0,
        0.0
      ]
      |> Nx.tensor()

    temporal_features =
      [
        # Time since snapshot (assuming now)
        time_since(state.inserted_at),
        # Version normalized
        normalize(state.version || 1, 1, 1000),
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0
      ]
      |> Nx.tensor()

    all_features =
      [
        trait_features,
        state_features,
        memory_features,
        intent_features,
        temporal_features
      ]
      |> Nx.concatenate()
      |> Nx.reshape({1, @feature_dim})

    %{
      features: all_features,
      labels: nil,
      metadata: %{
        pac_id: state.pac_id,
        snapshot_type: state.snapshot_type,
        version: state.version,
        extracted_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Batch extract features from multiple PACs.
  """
  @spec batch_extract([PAC.t()]) :: {Nx.Tensor.t(), Nx.Tensor.t() | nil, [map()]}
  def batch_extract(pacs) when is_list(pacs) do
    extracted = Enum.map(pacs, &extract/1)

    features =
      extracted
      |> Enum.map(& &1.features)
      |> Nx.concatenate()

    labels =
      extracted
      |> Enum.map(& &1.labels)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        labels -> Nx.concatenate(labels)
      end

    metadata = Enum.map(extracted, & &1.metadata)

    {features, labels, metadata}
  end

  # ═══════════════════════════════════════════════════════════════
  # TRAIT EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  defp extract_traits(nil), do: Nx.broadcast(0.0, {@trait_dim})

  defp extract_traits(traits) when is_list(traits) do
    traits
    |> pad_or_truncate(@trait_dim)
    |> Nx.tensor()
  end

  # ═══════════════════════════════════════════════════════════════
  # STATE EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  defp extract_state(%PAC{} = pac) do
    [
      # Status encoding
      Map.get(@status_encoding, pac.status, 0.0),
      # Capability count normalized
      normalize(length(pac.capabilities || []), 0, 20),
      # Role presence
      if(pac.active_role_id, do: 1.0, else: 0.0),
      # Identity kernel presence
      if(pac.identity_kernel_id, do: 1.0, else: 0.0),
      # Total ticks normalized (log scale)
      log_normalize(pac.total_active_ticks || 0),
      # Padding
      0.0,
      0.0,
      0.0
    ]
    |> Nx.tensor()
  end

  # ═══════════════════════════════════════════════════════════════
  # MEMORY EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  defp extract_memory(nil), do: Nx.broadcast(0.0, {@memory_dim})

  defp extract_memory(memory_state) when is_map(memory_state) do
    # Extract numerical features from memory state
    numeric_values =
      memory_state
      |> flatten_map()
      |> Enum.filter(&is_number/1)
      |> Enum.map(&normalize(&1, -100, 100))
      |> pad_or_truncate(@memory_dim)

    # Memory structure features
    structure_features = [
      # Key count normalized
      normalize(map_size(memory_state), 0, 100),
      # Depth estimate
      normalize(estimate_depth(memory_state), 0, 10),
      # String content ratio
      string_ratio(memory_state),
      # Numeric content ratio
      numeric_ratio(memory_state)
    ]

    combined =
      (Enum.take(numeric_values, @memory_dim - 4) ++ structure_features)
      |> pad_or_truncate(@memory_dim)

    Nx.tensor(combined)
  end

  # ═══════════════════════════════════════════════════════════════
  # INTENT EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  defp extract_intents(nil), do: Nx.broadcast(0.0, {@intent_dim})

  defp extract_intents(intent_queue) when is_list(intent_queue) do
    if Enum.empty?(intent_queue) do
      Nx.broadcast(0.0, {@intent_dim})
    else
      # Aggregate intent statistics
      intent_count = length(intent_queue)

      priority_stats =
        intent_queue
        |> Enum.map(&Map.get(&1, :priority, 5))
        |> compute_stats()

      status_distribution =
        intent_queue
        |> Enum.frequencies_by(&Map.get(&1, :status, :pending))
        |> Enum.map(fn {status, count} ->
          Map.get(@intent_status_encoding, status, 0.0) * count / intent_count
        end)
        |> Enum.sum()

      [
        # Count normalized
        normalize(intent_count, 0, 50),
        # Priority mean
        normalize(priority_stats.mean, 0, 10),
        # Priority variance
        normalize(priority_stats.variance, 0, 25),
        # Status distribution score
        status_distribution,
        # Max priority normalized
        normalize(priority_stats.max, 0, 10),
        # Min priority normalized
        normalize(priority_stats.min, 0, 10),
        # Pending ratio
        pending_ratio(intent_queue),
        # Padding
        0.0
      ]
      |> Nx.tensor()
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # TEMPORAL EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  defp extract_temporal(%PAC{} = pac) do
    now = DateTime.utc_now()

    [
      # Hours since last activity (capped at 24*7)
      time_since(pac.last_active_at),
      # Hours since creation
      time_since(pac.inserted_at),
      # Activity ratio (ticks per hour since creation)
      activity_ratio(pac),
      # Day of week encoding (cyclical)
      day_of_week_sin(now),
      day_of_week_cos(now),
      # Hour encoding (cyclical)
      hour_sin(now),
      hour_cos(now),
      # Padding
      0.0
    ]
    |> Nx.tensor()
  end

  # ═══════════════════════════════════════════════════════════════
  # LABEL GENERATION
  # ═══════════════════════════════════════════════════════════════

  defp generate_labels(%PAC{} = pac) do
    # Generate labels for supervised learning
    # These represent "target" behaviors we want to predict/learn

    labels =
      [
        # Target: will PAC be active soon? (1.0 if currently active)
        if(pac.status == :active, do: 1.0, else: 0.0),
        # Target: intent completion likelihood
        intent_completion_likelihood(pac.intent_queue),
        # Target: memory utilization efficiency
        memory_efficiency(pac.memory_state),
        # Target: tick efficiency (activity per tick)
        tick_efficiency(pac),
        # Padding to match output_dim
        0.0,
        0.0,
        0.0,
        0.0
      ]
      |> pad_or_truncate(32)
      |> Nx.tensor()
      |> Nx.reshape({1, 32})
  end

  # ═══════════════════════════════════════════════════════════════
  # UTILITY FUNCTIONS
  # ═══════════════════════════════════════════════════════════════

  defp normalize(value, min, max) when max > min do
    clamped = max(min, min(max, value))
    (clamped - min) / (max - min)
  end

  defp normalize(_, _, _), do: 0.0

  defp log_normalize(value) when value > 0 do
    :math.log(value + 1) / :math.log(1_000_000)
  end

  defp log_normalize(_), do: 0.0

  defp time_since(nil), do: 1.0

  defp time_since(%DateTime{} = dt) do
    hours = DateTime.diff(DateTime.utc_now(), dt, :hour)
    normalize(hours, 0, 24 * 7)
  end

  defp pad_or_truncate(list, target_len) when length(list) >= target_len do
    Enum.take(list, target_len)
  end

  defp pad_or_truncate(list, target_len) do
    list ++ List.duplicate(0.0, target_len - length(list))
  end

  defp flatten_map(map) when is_map(map) do
    Enum.flat_map(map, fn
      {_k, v} when is_map(v) -> flatten_map(v)
      {_k, v} when is_list(v) -> List.flatten(v)
      {_k, v} -> [v]
    end)
  end

  defp estimate_depth(map, depth \\ 0) when is_map(map) do
    if map_size(map) == 0 do
      depth
    else
      max_child_depth =
        map
        |> Map.values()
        |> Enum.filter(&is_map/1)
        |> Enum.map(&estimate_depth(&1, depth + 1))
        |> Enum.max(fn -> depth end)

      max_child_depth
    end
  end

  defp string_ratio(map) do
    values = flatten_map(map)
    strings = Enum.count(values, &is_binary/1)
    if length(values) > 0, do: strings / length(values), else: 0.0
  end

  defp numeric_ratio(map) do
    values = flatten_map(map)
    nums = Enum.count(values, &is_number/1)
    if length(values) > 0, do: nums / length(values), else: 0.0
  end

  defp compute_stats(values) when is_list(values) and length(values) > 0 do
    count = length(values)
    sum = Enum.sum(values)
    mean = sum / count
    variance = Enum.reduce(values, 0, fn v, acc -> acc + (v - mean) ** 2 end) / count

    %{
      mean: mean,
      variance: variance,
      min: Enum.min(values),
      max: Enum.max(values),
      count: count
    }
  end

  defp compute_stats(_), do: %{mean: 0.0, variance: 0.0, min: 0.0, max: 0.0, count: 0}

  defp pending_ratio(intents) do
    pending = Enum.count(intents, &(Map.get(&1, :status) in [:pending, :queued]))
    if length(intents) > 0, do: pending / length(intents), else: 0.0
  end

  defp activity_ratio(%PAC{total_active_ticks: ticks, inserted_at: created_at}) do
    hours = max(1, DateTime.diff(DateTime.utc_now(), created_at || DateTime.utc_now(), :hour))
    normalize((ticks || 0) / hours, 0, 100)
  end

  defp day_of_week_sin(dt) do
    day = Date.day_of_week(DateTime.to_date(dt))
    :math.sin(2 * :math.pi() * day / 7)
  end

  defp day_of_week_cos(dt) do
    day = Date.day_of_week(DateTime.to_date(dt))
    :math.cos(2 * :math.pi() * day / 7)
  end

  defp hour_sin(dt) do
    hour = dt.hour
    :math.sin(2 * :math.pi() * hour / 24)
  end

  defp hour_cos(dt) do
    hour = dt.hour
    :math.cos(2 * :math.pi() * hour / 24)
  end

  defp encode_snapshot_type(type) do
    case type do
      :periodic -> 0.25
      :checkpoint -> 0.5
      :manual -> 0.75
      :migration -> 1.0
      _ -> 0.0
    end
  end

  defp checksum_entropy(nil), do: 0.0

  defp checksum_entropy(checksum) when is_binary(checksum) do
    # Simple entropy estimate from hex string
    checksum
    |> String.graphemes()
    |> Enum.frequencies()
    |> Map.values()
    |> Enum.reduce(0.0, fn count, acc ->
      p = count / String.length(checksum)
      if p > 0, do: acc - p * :math.log2(p), else: acc
    end)
    |> normalize(0, 4)
  end

  defp intent_completion_likelihood(nil), do: 0.0

  defp intent_completion_likelihood(intents) when is_list(intents) do
    if Enum.empty?(intents) do
      0.5
    else
      completed = Enum.count(intents, &(Map.get(&1, :status) == :completed))
      completed / length(intents)
    end
  end

  defp memory_efficiency(nil), do: 0.5

  defp memory_efficiency(memory) when is_map(memory) do
    # Heuristic: more keys with actual values = more efficient use
    total = map_size(memory)
    non_empty = Enum.count(memory, fn {_k, v} -> v not in [nil, %{}, [], ""] end)
    if total > 0, do: non_empty / total, else: 0.5
  end

  defp tick_efficiency(%PAC{total_active_ticks: ticks}) do
    # Normalize ticks to 0-1 range (assuming 10000 ticks is "high")
    normalize(ticks || 0, 0, 10000)
  end
end
