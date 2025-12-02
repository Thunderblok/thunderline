defmodule Thunderline.Thunderbolt.Cerebros.Features do
  @moduledoc """
  Extract feature vectors from PAC runs for TPE optimization (HC-Δ-10).

  ## Layer Architecture

  ```
  CA.Snapshot.capture()          ←  Read lattice state
         ↓
  Cerebros.Features.extract()    ←  YOU ARE HERE (feature extraction)
         ↓
  Cerebros.TPEBridge.record()    ←  Log to Optuna for Bayesian optimization
  ```

  ## Feature Categories

  The feature vector contains ~24 metrics across 4 categories:

  1. **Config (6)** - Hyperparameter settings (ca_diffusion, decay, model_kind, etc.)
  2. **Thunderbit Activity (6)** - Symbolic layer metrics (bit counts, degrees, chains)
  3. **CA Dynamics (6)** - Lattice physics (activation, entropy, error signals)
  4. **Outcomes (6)** - Run results (reward, latency, token counts, errors)

  ## Usage

      # Capture CA state
      {:ok, snapshot} = Thunderbolt.CA.Snapshot.capture(cluster_id)

      # Extract features
      features = Features.extract(config, context, snapshot, metrics)

      # Log to TPE for optimization
      TPEBridge.record(bridge, features.params, fitness: features.fitness)

  ## TPE Integration

  The `extract/4` function returns a map suitable for `TPEBridge.record/3`:

  - `params` - Config parameters (hyperparameters being optimized)
  - `features` - Full feature vector for analysis
  - `metrics` - Outcome metrics used to compute fitness
  - `fitness` - Computed fitness score (higher = better)
  """

  alias Thunderline.Thunderbolt.CA.Snapshot

  require Logger

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type config :: %{
          optional(:ca_diffusion) => float(),
          optional(:ca_decay) => float(),
          optional(:ca_neighbor_radius) => pos_integer(),
          optional(:pac_model_kind) => atom(),
          optional(:max_chain_length) => pos_integer(),
          optional(:policy_strictness) => float(),
          optional(atom()) => term()
        }

  @type context :: %{
          optional(:thunderbit_ids) => [binary()],
          optional(:thunderbit_links) => [{binary(), binary()}],
          optional(:thunderbit_categories) => %{binary() => atom()},
          optional(:thunderbit_kinds) => %{binary() => atom()},
          optional(atom()) => term()
        }

  @type outcome_metrics :: %{
          optional(:reward) => float(),
          optional(:token_input) => non_neg_integer(),
          optional(:token_output) => non_neg_integer(),
          optional(:latency_ms) => non_neg_integer(),
          optional(:num_policy_violations) => non_neg_integer(),
          optional(:num_errors) => non_neg_integer(),
          optional(atom()) => term()
        }

  @type feature_vector :: %{
          # Config features
          ca_diffusion: float(),
          ca_decay: float(),
          ca_neighbor_radius: pos_integer(),
          pac_model_kind: atom(),
          max_chain_length: pos_integer(),
          policy_strictness: float(),
          # Thunderbit Activity
          num_bits_total: non_neg_integer(),
          num_bits_cognitive: non_neg_integer(),
          num_bits_dataset: non_neg_integer(),
          avg_bit_degree: float(),
          max_chain_depth: non_neg_integer(),
          num_variable_bits: non_neg_integer(),
          # CA Dynamics
          mean_activation: float(),
          max_activation: float(),
          activation_entropy: float(),
          active_cell_fraction: float(),
          error_potential_mean: float(),
          error_cell_fraction: float(),
          # Outcomes
          reward: float(),
          token_input: non_neg_integer(),
          token_output: non_neg_integer(),
          latency_ms: non_neg_integer(),
          num_policy_violations: non_neg_integer(),
          num_errors: non_neg_integer()
        }

  @type extraction_result :: %{
          config: config(),
          features: feature_vector(),
          metrics: outcome_metrics(),
          params: map(),
          fitness: float(),
          timestamp: DateTime.t()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Extract a complete feature vector from a PAC run.

  ## Parameters

  - `config` - Hyperparameter configuration used for this run
  - `context` - Thunderbit context (IDs, links, categories)
  - `ca_snapshot` - CA.Snapshot struct from the lattice
  - `metrics` - Outcome metrics (reward, latency, errors, etc.)

  ## Returns

  A map containing:
  - `config` - The original config
  - `features` - Full 24-feature vector
  - `metrics` - Outcome metrics
  - `params` - Config params for TPE (subset of features)
  - `fitness` - Computed fitness score
  - `timestamp` - When features were extracted

  ## Examples

      {:ok, snapshot} = CA.Snapshot.capture(cluster_id)

      result = Features.extract(
        %{ca_diffusion: 0.1, ca_decay: 0.05, pac_model_kind: :gpt4},
        %{thunderbit_ids: ["bit1", "bit2"], thunderbit_links: [{"bit1", "bit2"}]},
        snapshot,
        %{reward: 0.85, latency_ms: 150, num_errors: 0}
      )

      # result.fitness => 0.82
      # result.params => %{ca_diffusion: 0.1, ca_decay: 0.05, ...}
  """
  @spec extract(config(), context(), Snapshot.t(), outcome_metrics()) :: extraction_result()
  def extract(config, context, %Snapshot{} = ca_snapshot, metrics) do
    # Extract features from each category
    config_features = extract_config_features(config)
    thunderbit_features = extract_thunderbit_features(context)
    ca_features = extract_ca_features(ca_snapshot)
    outcome_features = extract_outcome_features(metrics)

    # Merge all features
    features =
      Map.merge(config_features, thunderbit_features)
      |> Map.merge(ca_features)
      |> Map.merge(outcome_features)

    # Compute fitness from outcomes
    fitness = compute_fitness(outcome_features, ca_features)

    # Params for TPE (just the tunable hyperparameters)
    params = extract_tpe_params(config_features)

    %{
      config: config,
      features: features,
      metrics: metrics,
      params: params,
      fitness: fitness,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Extract features from a snapshot without full context.

  Useful for monitoring or lightweight feature extraction.
  """
  @spec extract_from_snapshot(Snapshot.t()) :: map()
  def extract_from_snapshot(%Snapshot{} = snapshot) do
    extract_ca_features(snapshot)
  end

  @doc """
  Compute a fitness score from feature values.

  The fitness function balances:
  - Reward (primary objective)
  - Efficiency (lower latency, fewer tokens)
  - Stability (fewer errors, moderate activation)
  """
  @spec compute_fitness(map(), map()) :: float()
  def compute_fitness(outcomes, ca_features) do
    reward = Map.get(outcomes, :reward, 0.0)
    latency_ms = Map.get(outcomes, :latency_ms, 1000)
    num_errors = Map.get(outcomes, :num_errors, 0)
    num_violations = Map.get(outcomes, :num_policy_violations, 0)

    # CA stability: penalize extreme activation (0 or 1)
    mean_activation = Map.get(ca_features, :mean_activation, 0.5)
    activation_penalty = abs(mean_activation - 0.5) * 0.2

    # Error penalty
    error_penalty = (num_errors + num_violations) * 0.1

    # Latency efficiency (normalize to 0-1, lower is better)
    latency_factor = 1.0 - min(1.0, latency_ms / 5000.0)

    # Combine factors
    fitness =
      (reward * 0.6 +
         latency_factor * 0.2 +
         (1.0 - activation_penalty) * 0.1 +
         (1.0 - min(1.0, error_penalty)) * 0.1)
      |> max(0.0)
      |> min(1.0)

    Float.round(fitness, 4)
  end

  # ============================================================================
  # TPE Integration Convenience Functions
  # ============================================================================

  @doc """
  Capture CA state, extract features, and log trial to TPE in one call.

  This is the primary integration point between the CA lattice and TPE optimizer.

  ## Parameters

  - `bridge` - TPEBridge GenServer reference
  - `cluster_id` - CA cluster to capture state from
  - `config` - Hyperparameter configuration
  - `context` - Thunderbit context (IDs, links, etc.)
  - `metrics` - Outcome metrics from the PAC run

  ## Returns

  - `{:ok, result}` - Extraction result with fitness logged to TPE
  - `{:error, reason}` - Error during capture or recording

  ## Example

      {:ok, result} = Features.capture_and_record(
        bridge,
        cluster_id,
        config,
        context,
        metrics
      )
      # result.fitness => 0.82 (already logged to TPE)
  """
  @spec capture_and_record(GenServer.server(), term(), config(), context(), outcome_metrics()) ::
          {:ok, extraction_result()} | {:error, term()}
  def capture_and_record(bridge, cluster_id, config, context, metrics) do
    alias Thunderline.Thunderbolt.Cerebros.TPEBridge

    with {:ok, snapshot} <- Snapshot.capture(cluster_id) do
      result = extract(config, context, snapshot, metrics)

      case TPEBridge.record(bridge, result.params, fitness: result.fitness) do
        :ok ->
          Logger.debug("[Features] Logged trial: fitness=#{result.fitness}")
          {:ok, result}

        {:error, reason} = error ->
          Logger.warning("[Features] Failed to record trial: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Extract and record with an existing snapshot (no capture needed).

  Use when you already have a snapshot from a previous capture.
  """
  @spec extract_and_record(
          GenServer.server(),
          config(),
          context(),
          Snapshot.t(),
          outcome_metrics()
        ) ::
          {:ok, extraction_result()} | {:error, term()}
  def extract_and_record(bridge, config, context, snapshot, metrics) do
    alias Thunderline.Thunderbolt.Cerebros.TPEBridge

    result = extract(config, context, snapshot, metrics)

    case TPEBridge.record(bridge, result.params, fitness: result.fitness) do
      :ok ->
        {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Builds a feature vector suitable for logging or analysis.

  Returns a flat map of all 24 features without computing fitness.
  """
  @spec to_feature_map(extraction_result()) :: map()
  def to_feature_map(%{features: features}) do
    features
  end

  # ============================================================================
  # Feature Extraction Functions
  # ============================================================================

  @doc false
  def extract_config_features(config) do
    %{
      ca_diffusion: Map.get(config, :ca_diffusion, 0.1),
      ca_decay: Map.get(config, :ca_decay, 0.05),
      ca_neighbor_radius: Map.get(config, :ca_neighbor_radius, 1),
      pac_model_kind: Map.get(config, :pac_model_kind, :unknown),
      max_chain_length: Map.get(config, :max_chain_length, 10),
      policy_strictness: Map.get(config, :policy_strictness, 0.5)
    }
  end

  @doc false
  def extract_thunderbit_features(context) do
    bit_ids = Map.get(context, :thunderbit_ids, [])
    links = Map.get(context, :thunderbit_links, [])
    categories = Map.get(context, :thunderbit_categories, %{})
    kinds = Map.get(context, :thunderbit_kinds, %{})

    num_bits = length(bit_ids)

    # Count by category
    cognitive_count = Enum.count(categories, fn {_id, cat} -> cat == :cognitive end)
    dataset_count = Enum.count(categories, fn {_id, cat} -> cat == :dataset end)

    # Count variable kinds
    variable_count = Enum.count(kinds, fn {_id, kind} -> kind == :variable end)

    # Calculate average degree (links per bit)
    degree_map =
      Enum.reduce(links, %{}, fn {from, to}, acc ->
        acc
        |> Map.update(from, 1, &(&1 + 1))
        |> Map.update(to, 1, &(&1 + 1))
      end)

    avg_degree =
      if num_bits > 0 do
        total_degree = Enum.sum(Map.values(degree_map))
        total_degree / num_bits
      else
        0.0
      end

    # Calculate max chain depth (BFS from each root)
    max_depth = calculate_max_chain_depth(bit_ids, links)

    %{
      num_bits_total: num_bits,
      num_bits_cognitive: cognitive_count,
      num_bits_dataset: dataset_count,
      avg_bit_degree: Float.round(avg_degree, 2),
      max_chain_depth: max_depth,
      num_variable_bits: variable_count
    }
  end

  @doc false
  def extract_ca_features(%Snapshot{} = snapshot) do
    agg = Snapshot.aggregate_stats(snapshot)

    # Calculate entropy of activation distribution
    activation_entropy = calculate_activation_entropy(snapshot.cells)

    # Active cell fraction (activation > 0.5)
    active_fraction =
      if map_size(snapshot.cells) > 0 do
        active_count =
          Enum.count(snapshot.cells, fn {_coord, cell} -> cell.activation > 0.5 end)

        active_count / map_size(snapshot.cells)
      else
        0.0
      end

    # Error cell fraction (error_potential > 0.1)
    error_fraction =
      if map_size(snapshot.cells) > 0 do
        error_count =
          Enum.count(snapshot.cells, fn {_coord, cell} -> cell.error_potential > 0.1 end)

        error_count / map_size(snapshot.cells)
      else
        0.0
      end

    %{
      mean_activation: Float.round(agg.mean_activation, 4),
      max_activation: Float.round(agg.max_activation, 4),
      activation_entropy: Float.round(activation_entropy, 4),
      active_cell_fraction: Float.round(active_fraction, 4),
      error_potential_mean: Float.round(agg.mean_error, 4),
      error_cell_fraction: Float.round(error_fraction, 4)
    }
  end

  @doc false
  def extract_outcome_features(metrics) do
    %{
      reward: Map.get(metrics, :reward, 0.0),
      token_input: Map.get(metrics, :token_input, 0),
      token_output: Map.get(metrics, :token_output, 0),
      latency_ms: Map.get(metrics, :latency_ms, 0),
      num_policy_violations: Map.get(metrics, :num_policy_violations, 0),
      num_errors: Map.get(metrics, :num_errors, 0)
    }
  end

  @doc false
  def extract_tpe_params(config_features) do
    # Only include numeric params that TPE can optimize
    %{
      ca_diffusion: config_features.ca_diffusion,
      ca_decay: config_features.ca_decay,
      ca_neighbor_radius: config_features.ca_neighbor_radius,
      max_chain_length: config_features.max_chain_length,
      policy_strictness: config_features.policy_strictness
    }
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp calculate_activation_entropy(cells) when map_size(cells) == 0, do: 0.0

  defp calculate_activation_entropy(cells) do
    # Bin activations into 10 buckets
    buckets =
      Enum.reduce(cells, %{}, fn {_coord, cell}, acc ->
        bucket = floor(cell.activation * 10) |> min(9)
        Map.update(acc, bucket, 1, &(&1 + 1))
      end)

    total = map_size(cells)

    # Calculate Shannon entropy
    entropy =
      buckets
      |> Enum.reduce(0.0, fn {_bucket, count}, acc ->
        p = count / total

        if p > 0 do
          acc - p * :math.log2(p)
        else
          acc
        end
      end)

    # Normalize to 0-1 (max entropy for 10 buckets is log2(10) ≈ 3.32)
    entropy / :math.log2(10)
  end

  defp calculate_max_chain_depth([], _links), do: 0

  defp calculate_max_chain_depth(bit_ids, links) do
    # Build adjacency list
    adj =
      Enum.reduce(links, %{}, fn {from, to}, acc ->
        Map.update(acc, from, [to], &[to | &1])
      end)

    # Find roots (bits with no incoming edges)
    targets = Enum.map(links, fn {_from, to} -> to end) |> MapSet.new()
    roots = Enum.reject(bit_ids, &MapSet.member?(targets, &1))

    # BFS from each root to find max depth
    roots
    |> Enum.map(&bfs_depth(&1, adj))
    |> Enum.max(fn -> 0 end)
  end

  defp bfs_depth(root, adj) do
    bfs_depth_helper([{root, 0}], adj, MapSet.new(), 0)
  end

  defp bfs_depth_helper([], _adj, _visited, max_depth), do: max_depth

  defp bfs_depth_helper([{node, depth} | rest], adj, visited, max_depth) do
    if MapSet.member?(visited, node) do
      bfs_depth_helper(rest, adj, visited, max_depth)
    else
      new_visited = MapSet.put(visited, node)
      new_max = max(max_depth, depth)

      neighbors = Map.get(adj, node, [])
      next_nodes = Enum.map(neighbors, &{&1, depth + 1})

      bfs_depth_helper(rest ++ next_nodes, adj, new_visited, new_max)
    end
  end
end
