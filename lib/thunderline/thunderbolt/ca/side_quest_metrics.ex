defmodule Thunderline.Thunderbolt.CA.SideQuestMetrics do
  @moduledoc """
  Side-Quest Metrics for Cellular Automata.

  Extends the Criticality metrics with additional "side-quest" signals
  that emerge from automata behavior but aren't the primary objective.

  ## The Side-Quest Paradigm

  From Lex/Friedman's "Learning to Be Efficient" paper:
  - **Primary Quest**: What we force the system to do (e.g., sorting)
  - **Side Quests**: What the system wants to do (e.g., clustering, patterns)

  Thunderline's job is to observe both and harness the side quests.

  ## Metrics

  | Metric | Description | Range |
  |--------|-------------|-------|
  | clustering | Spatial clustering coefficient | [0,1] |
  | sortedness | Order/sortedness measure | [0,1] |
  | healing_rate | Damage recovery rate | [0,1] |
  | pattern_stability | Pattern persistence | [0,1] |
  | emergence_score | Novel structure detection | [0,1] |

  ## Telemetry

  Emits `[:thunderbolt, :automata, :side_quest]` with all metrics.

  ## EventBus

  Publishes `bolt.automata.side_quest.snapshot` events for Thundercore.

  ## Algotype Metrics (Operation TIGER LATTICE - Doctrine Layer)

  Additional metrics from the bubble-sort "side quest" research:

  | Metric | Description | Range |
  |--------|-------------|-------|
  | algotype_clustering | Same-doctrine spatial clustering | [0,1] |
  | algotype_ising_energy | Ising model energy from doctrine spins | unbounded |

  These metrics are observation-only and do not feed into RewardSchema.

  ## Reference

  - Lex & Friedman "Learning to Be Efficient" (2023)
  - HC Orders: Operation TIGER LATTICE, Thread 2 + Doctrine Layer
  """

  require Logger

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Thundercore.Doctrine

  @telemetry_event [:thunderbolt, :automata, :side_quest]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type side_quest_snapshot :: %{
          clustering: float(),
          sortedness: float(),
          healing_rate: float(),
          pattern_stability: float(),
          emergence_score: float(),
          entropy: float(),
          divergence: float(),
          algotype_clustering: float(),
          algotype_ising_energy: float(),
          doctrine_distribution: map(),
          tick: non_neg_integer(),
          timestamp: integer()
        }

  @type delta :: map()

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes side-quest metrics from CA deltas and rule metrics.

  Combines local metrics from rule execution with global analysis.
  """
  @spec compute(
          deltas :: [delta()],
          rule_metrics :: map(),
          opts :: keyword()
        ) :: {:ok, side_quest_snapshot()} | {:error, term()}
  def compute(deltas, rule_metrics \\ %{}, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)
    history = Keyword.get(opts, :history, [])
    lattice = Keyword.get(opts, :lattice, nil)

    try do
      metrics = do_compute(deltas, rule_metrics, history, tick, lattice)
      {:ok, metrics}
    rescue
      e ->
        Logger.warning("[SideQuestMetrics] computation error: #{inspect(e)}")
        {:error, {:computation_error, e}}
    end
  end

  @doc """
  Emits side-quest metrics to telemetry and EventBus.
  """
  @spec emit(String.t(), non_neg_integer(), side_quest_snapshot(), keyword()) :: :ok
  def emit(run_id, tick, metrics, opts \\ []) do
    emit_event = Keyword.get(opts, :emit_event, true)

    # Emit telemetry
    :telemetry.execute(
      @telemetry_event,
      %{
        clustering: metrics.clustering,
        sortedness: metrics.sortedness,
        healing_rate: metrics.healing_rate,
        pattern_stability: metrics.pattern_stability,
        emergence_score: metrics.emergence_score,
        entropy: metrics.entropy,
        divergence: metrics.divergence,
        algotype_clustering: metrics.algotype_clustering,
        algotype_ising_energy: metrics.algotype_ising_energy
      },
      %{
        run_id: run_id,
        tick: tick,
        doctrine_distribution: metrics.doctrine_distribution
      }
    )

    # Publish event
    if emit_event do
      publish_event(run_id, tick, metrics)
    end

    :ok
  end

  @doc """
  Compute and emit in one call.
  """
  @spec compute_and_emit(
          run_id :: String.t(),
          deltas :: [delta()],
          rule_metrics :: map(),
          opts :: keyword()
        ) :: {:ok, side_quest_snapshot()} | {:error, term()}
  def compute_and_emit(run_id, deltas, rule_metrics, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)

    case compute(deltas, rule_metrics, opts) do
      {:ok, metrics} ->
        emit(run_id, tick, metrics, opts)
        {:ok, metrics}

      error ->
        error
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Metric Computation
  # ═══════════════════════════════════════════════════════════════

  defp do_compute(deltas, rule_metrics, history, tick, lattice) do
    # Extract from rule metrics (local averages)
    local_clustering = Map.get(rule_metrics, :clustering, 0.5)
    local_entropy = Map.get(rule_metrics, :entropy, 0.5)
    local_divergence = Map.get(rule_metrics, :divergence, 0.0)

    # Compute global metrics from deltas
    sortedness = compute_sortedness(deltas)
    healing_rate = compute_healing_rate(deltas, history)
    pattern_stability = compute_pattern_stability(deltas, history)
    emergence_score = compute_emergence_score(deltas, rule_metrics)

    # Global clustering (if not from rules)
    clustering =
      if local_clustering == 0.5 do
        compute_global_clustering(deltas)
      else
        local_clustering
      end

    # Algotype metrics (Doctrine Layer - Operation TIGER LATTICE)
    {algotype_clustering, algotype_ising_energy, doctrine_distribution} =
      compute_algotype_metrics(deltas, lattice)

    %{
      clustering: Float.round(clustering, 4),
      sortedness: Float.round(sortedness, 4),
      healing_rate: Float.round(healing_rate, 4),
      pattern_stability: Float.round(pattern_stability, 4),
      emergence_score: Float.round(emergence_score, 4),
      entropy: Float.round(local_entropy, 4),
      divergence: Float.round(local_divergence, 4),
      algotype_clustering: Float.round(algotype_clustering, 4),
      algotype_ising_energy: Float.round(algotype_ising_energy, 4),
      doctrine_distribution: doctrine_distribution,
      tick: tick,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Sortedness (Order Measure)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes sortedness from delta flow values.

  Uses Kendall tau-b correlation with sorted order.
  Returns 1.0 for perfectly sorted, 0.0 for random, -1.0 for reversed.
  """
  def compute_sortedness(deltas) when length(deltas) < 3, do: 0.5

  def compute_sortedness(deltas) do
    # Extract flow values
    flows =
      deltas
      |> Enum.map(&extract_flow/1)
      |> Enum.take(100)

    n = length(flows)

    if n < 3 do
      0.5
    else
      # Count concordant and discordant pairs
      {concordant, discordant} =
        for i <- 0..(n - 2),
            j <- (i + 1)..(n - 1),
            reduce: {0, 0} do
          {c, d} ->
            fi = Enum.at(flows, i)
            fj = Enum.at(flows, j)

            cond do
              fi < fj -> {c + 1, d}
              fi > fj -> {c, d + 1}
              true -> {c, d}
            end
        end

      total = concordant + discordant

      if total == 0 do
        0.5
      else
        # Kendall tau
        tau = (concordant - discordant) / total
        # Normalize to [0, 1]
        (tau + 1.0) / 2.0
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Healing Rate
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes healing rate from state transitions.

  Measures how quickly damaged/inactive cells become active.
  """
  def compute_healing_rate(deltas, history) when length(history) < 2 do
    # No history - estimate from current state
    if Enum.empty?(deltas) do
      0.5
    else
      # Count recently activated cells (high flow with previously low)
      active_count = Enum.count(deltas, &is_active?/1)
      total = length(deltas)
      if total > 0, do: active_count / total, else: 0.5
    end
  end

  def compute_healing_rate(deltas, history) do
    current_ids = extract_ids(deltas)
    previous_ids = history |> List.first() |> extract_ids()

    if Enum.empty?(current_ids) or Enum.empty?(previous_ids) do
      0.5
    else
      # Find cells that were inactive and became active
      current_active = MapSet.new(Enum.filter(current_ids, fn {_id, active} -> active end), &elem(&1, 0))
      previous_inactive = MapSet.new(Enum.reject(previous_ids, fn {_id, active} -> active end), &elem(&1, 0))

      healed = MapSet.intersection(current_active, previous_inactive)
      potentially_healable = MapSet.size(previous_inactive)

      if potentially_healable > 0 do
        MapSet.size(healed) / potentially_healable
      else
        1.0
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Pattern Stability
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes pattern stability across time.

  High stability = patterns persist, low = chaotic change.
  """
  def compute_pattern_stability(_deltas, history) when length(history) < 3, do: 0.5

  def compute_pattern_stability(deltas, history) do
    # Compare current state distribution to recent history
    current_dist = state_distribution(deltas)

    avg_similarity =
      history
      |> Enum.take(5)
      |> Enum.map(fn h -> distribution_similarity(current_dist, state_distribution(h)) end)
      |> then(fn sims ->
        if Enum.empty?(sims), do: 0.5, else: Enum.sum(sims) / length(sims)
      end)

    avg_similarity
  end

  defp state_distribution(deltas) when is_list(deltas) do
    deltas
    |> Enum.map(&extract_state/1)
    |> Enum.frequencies()
  end

  defp state_distribution(_), do: %{}

  defp distribution_similarity(dist1, dist2) do
    all_keys = Map.keys(dist1) ++ Map.keys(dist2) |> Enum.uniq()

    if Enum.empty?(all_keys) do
      0.5
    else
      total1 = Map.values(dist1) |> Enum.sum() |> max(1)
      total2 = Map.values(dist2) |> Enum.sum() |> max(1)

      # Normalized histogram intersection
      intersection =
        all_keys
        |> Enum.map(fn key ->
          p1 = Map.get(dist1, key, 0) / total1
          p2 = Map.get(dist2, key, 0) / total2
          min(p1, p2)
        end)
        |> Enum.sum()

      intersection
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Emergence Score
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Detects emergent structure in the CA.

  High emergence = novel patterns beyond random noise.
  Based on deviation from expected entropy.
  """
  def compute_emergence_score(deltas, rule_metrics) do
    if Enum.empty?(deltas) do
      0.0
    else
      # Get local entropy from rules or compute
      observed_entropy = Map.get(rule_metrics, :entropy, 0.5)

      # Expected entropy for random distribution ≈ 1.0
      expected_entropy = 1.0

      # Emergence = reduction from maximum entropy
      # High structure = low entropy = high emergence
      emergence = expected_entropy - observed_entropy

      # Also factor in clustering (more clustering = more emergence)
      clustering = Map.get(rule_metrics, :clustering, 0.5)

      # Weighted combination
      score = emergence * 0.6 + clustering * 0.4

      max(0.0, min(1.0, score))
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Global Clustering
  # ═══════════════════════════════════════════════════════════════

  def compute_global_clustering(deltas) when length(deltas) < 4, do: 0.5

  def compute_global_clustering(deltas) do
    # Extract coordinates and states
    coords_with_state =
      deltas
      |> Enum.map(fn d ->
        coord = extract_coord(d)
        active = is_active?(d)
        {coord, active}
      end)
      |> Enum.reject(fn {coord, _} -> is_nil(coord) end)

    if length(coords_with_state) < 4 do
      0.5
    else
      # Simplified: ratio of active cells in spatial proximity
      active_cells = Enum.filter(coords_with_state, &elem(&1, 1))

      if Enum.empty?(active_cells) do
        0.0
      else
        # Count cells with active neighbors
        active_coords = MapSet.new(Enum.map(active_cells, &elem(&1, 0)))

        cells_with_neighbors =
          active_cells
          |> Enum.count(fn {coord, _} ->
            neighbors = get_neighbor_coords(coord)
            Enum.any?(neighbors, &MapSet.member?(active_coords, &1))
          end)

        cells_with_neighbors / length(active_cells)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Algotype Metrics (Doctrine Layer)
  # ═══════════════════════════════════════════════════════════════

  # Computes all algotype-related metrics.
  # Returns {clustering, ising_energy, distribution}.
  # If no lattice is provided, extracts doctrines from deltas (if present).
  defp compute_algotype_metrics(deltas, lattice) do
    # Build coord -> doctrine map from lattice or deltas
    doctrine_map = build_doctrine_map(deltas, lattice)

    if map_size(doctrine_map) < 2 do
      # Not enough data for meaningful metrics
      {0.5, 0.0, %{}}
    else
      clustering = compute_algotype_clustering(doctrine_map)
      ising_energy = compute_algotype_ising_energy(doctrine_map)
      distribution = Doctrine.distribution(Map.values(doctrine_map) |> Enum.map(&%{doctrine: &1}))

      {clustering, ising_energy, distribution}
    end
  end

  # Computes algotype clustering coefficient.
  # Measures the tendency for cells with the same doctrine to cluster together.
  # Returns [0, 1] where:
  # - 1.0 = perfect segregation (same doctrines always adjacent)
  # - 0.5 = random distribution
  # - 0.0 = perfect anti-clustering (opposite doctrines adjacent)
  defp compute_algotype_clustering(doctrine_map) when map_size(doctrine_map) < 3, do: 0.5

  defp compute_algotype_clustering(doctrine_map) do
    coords = Map.keys(doctrine_map)

    # Count same-doctrine neighbor pairs vs total neighbor pairs
    {same_count, total_count} =
      coords
      |> Enum.reduce({0, 0}, fn coord, {same_acc, total_acc} ->
        my_doctrine = Map.get(doctrine_map, coord)
        neighbors = get_neighbor_coords(coord)

        neighbor_matches =
          neighbors
          |> Enum.reduce({0, 0}, fn neighbor_coord, {s, t} ->
            case Map.get(doctrine_map, neighbor_coord) do
              nil -> {s, t}  # Neighbor not in grid
              ^my_doctrine -> {s + 1, t + 1}  # Same doctrine
              _ -> {s, t + 1}  # Different doctrine
            end
          end)

        {same_acc + elem(neighbor_matches, 0), total_acc + elem(neighbor_matches, 1)}
      end)

    if total_count == 0 do
      0.5
    else
      same_count / total_count
    end
  end

  # Computes the total Ising energy from doctrine spins.
  # Uses the Ising model: E = -Σ J * s_i * s_j over all neighbor pairs.
  # Low (negative) energy = like doctrines cluster together.
  # High (positive) energy = unlike doctrines are adjacent.
  # Returns the normalized energy per edge.
  defp compute_algotype_ising_energy(doctrine_map) when map_size(doctrine_map) < 2, do: 0.0

  defp compute_algotype_ising_energy(doctrine_map) do
    coords = Map.keys(doctrine_map)

    # Compute total Ising energy and count edges
    {total_energy, edge_count} =
      coords
      |> Enum.reduce({0.0, 0}, fn coord, {energy_acc, count_acc} ->
        my_doctrine = Map.get(doctrine_map, coord)
        neighbors = get_neighbor_coords(coord)

        # Only count each edge once (when coord < neighbor_coord lexicographically)
        edge_contribution =
          neighbors
          |> Enum.reduce({0.0, 0}, fn neighbor_coord, {e, c} ->
            case Map.get(doctrine_map, neighbor_coord) do
              nil ->
                {e, c}

              neighbor_doctrine when coord < neighbor_coord ->
                # Count this edge (ordered to avoid double-counting)
                interaction = Doctrine.interaction_energy(my_doctrine, neighbor_doctrine)
                {e + interaction, c + 1}

              _ ->
                # Skip - already counted from the other direction
                {e, c}
            end
          end)

        {energy_acc + elem(edge_contribution, 0), count_acc + elem(edge_contribution, 1)}
      end)

    if edge_count == 0 do
      0.0
    else
      total_energy / edge_count
    end
  end

  # Builds a coord -> doctrine map from lattice or deltas.
  defp build_doctrine_map(deltas, nil) do
    # No lattice provided - extract from deltas if they have doctrine
    deltas
    |> Enum.reduce(%{}, fn delta, acc ->
      coord = extract_coord(delta)
      doctrine = extract_doctrine_from_delta(delta)

      if coord != nil and doctrine != nil do
        Map.put(acc, coord, doctrine)
      else
        acc
      end
    end)
  end

  defp build_doctrine_map(deltas, lattice) when is_map(lattice) do
    # Lattice is a map - extract doctrines from Thunderbits
    deltas
    |> Enum.reduce(%{}, fn delta, acc ->
      coord = extract_coord(delta)

      if coord != nil do
        # Look up in lattice
        case Map.get(lattice, coord) do
          %{doctrine: doctrine} -> Map.put(acc, coord, doctrine)
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp build_doctrine_map(deltas, _lattice) do
    # Fallback to delta extraction
    build_doctrine_map(deltas, nil)
  end

  defp extract_doctrine_from_delta(%{doctrine: d}), do: d
  defp extract_doctrine_from_delta(%{bit: %{doctrine: d}}), do: d
  defp extract_doctrine_from_delta(_), do: nil

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp extract_flow(%{sigma_flow: f}), do: f
  defp extract_flow(%{flow: f}), do: f
  defp extract_flow(%{energy: e}) when is_number(e), do: e / 100.0
  defp extract_flow(_), do: 0.5

  defp extract_state(%{state: s}), do: s
  defp extract_state(_), do: :unknown

  defp extract_coord(%{coord: c}), do: c
  defp extract_coord(%{x: x, y: y, z: z}), do: {x, y, z}
  defp extract_coord(%{x: x, y: y}), do: {x, y, 0}
  defp extract_coord(_), do: nil

  defp extract_ids(deltas) when is_list(deltas) do
    Enum.map(deltas, fn d ->
      id = Map.get(d, :id) || Map.get(d, :coord)
      active = is_active?(d)
      {id, active}
    end)
  end

  defp extract_ids(_), do: []

  defp is_active?(%{state: s}) when s in [:active, :alive, :stable], do: true
  defp is_active?(%{sigma_flow: f}) when f > 0.5, do: true
  defp is_active?(%{flow: f}) when f > 0.5, do: true
  defp is_active?(_), do: false

  defp get_neighbor_coords({x, y, z}) do
    for dx <- -1..1,
        dy <- -1..1,
        dz <- -1..1,
        {dx, dy, dz} != {0, 0, 0} do
      {x + dx, y + dy, z + dz}
    end
  end

  defp get_neighbor_coords({x, y}) do
    for dx <- -1..1,
        dy <- -1..1,
        {dx, dy} != {0, 0} do
      {x + dx, y + dy, 0}
    end
  end

  defp get_neighbor_coords(_), do: []

  # ═══════════════════════════════════════════════════════════════
  # Event Publishing
  # ═══════════════════════════════════════════════════════════════

  defp publish_event(run_id, tick, metrics) do
    payload = %{
      run_id: run_id,
      tick: tick,
      clustering: metrics.clustering,
      sortedness: metrics.sortedness,
      healing_rate: metrics.healing_rate,
      pattern_stability: metrics.pattern_stability,
      emergence_score: metrics.emergence_score,
      entropy: metrics.entropy,
      divergence: metrics.divergence,
      algotype_clustering: metrics.algotype_clustering,
      algotype_ising_energy: metrics.algotype_ising_energy,
      doctrine_distribution: metrics.doctrine_distribution,
      sampled_at: System.system_time(:millisecond)
    }

    case Event.new(
           name: "bolt.automata.side_quest.snapshot",
           source: :bolt,
           payload: payload,
           meta: %{
             pipeline: :side_quest,
             component: "ca_metrics"
           }
         ) do
      {:ok, event} ->
        case EventBus.publish_event(event) do
          {:ok, _} ->
            Logger.debug("[SideQuestMetrics] emitted for run=#{run_id} tick=#{tick}")
            :ok

          {:error, reason} ->
            Logger.warning("[SideQuestMetrics] event publish failed: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("[SideQuestMetrics] event creation failed: #{inspect(reason)}")
        :ok
    end
  end
end
