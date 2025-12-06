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

  ## Reference

  - Lex & Friedman "Learning to Be Efficient" (2023)
  - HC Orders: Operation TIGER LATTICE, Thread 2
  """

  require Logger

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus

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

    try do
      metrics = do_compute(deltas, rule_metrics, history, tick)
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
        divergence: metrics.divergence
      },
      %{
        run_id: run_id,
        tick: tick
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

  defp do_compute(deltas, rule_metrics, history, tick) do
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

    %{
      clustering: Float.round(clustering, 4),
      sortedness: Float.round(sortedness, 4),
      healing_rate: Float.round(healing_rate, 4),
      pattern_stability: Float.round(pattern_stability, 4),
      emergence_score: Float.round(emergence_score, 4),
      entropy: Float.round(local_entropy, 4),
      divergence: Float.round(local_divergence, 4),
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
