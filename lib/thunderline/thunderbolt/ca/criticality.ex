defmodule Thunderline.Thunderbolt.CA.Criticality do
  @moduledoc """
  CA Criticality Metrics Integration (HC-40).

  Bridges the CA Stepper with LoopMonitor criticality metrics.
  Computes PLV, permutation entropy, Langton's λ̂, and Lyapunov exponent
  from CA deltas and emits to telemetry + EventBus.

  ## Usage

      # Compute metrics from deltas
      {:ok, metrics} = Criticality.compute_from_deltas(deltas)

      # Step grid and compute metrics in one call
      {:ok, deltas, new_grid, metrics} = Criticality.step_with_metrics(grid, ruleset)

      # Emit to telemetry/EventBus
      :ok = Criticality.emit_metrics(run_id, tick, metrics)

  ## Metrics

  | Metric | Symbol | Range | Edge of Chaos |
  |--------|--------|-------|---------------|
  | Phase-Locking Value | PLV | [0,1] | ~0.4 |
  | Permutation Entropy | H_p | [0,1] | ~0.5 |
  | Langton's λ̂ | λ̂ | [0,1] | ~0.273 |
  | Lyapunov Exponent | λ_L | (-∞,∞) | ~0 |
  | Edge Score | score | [0,1] | ~1.0 |

  ## Telemetry

  Emits `[:thunderline, :bolt, :ca, :criticality]` with:
  - `plv`, `entropy`, `lambda_hat`, `lyapunov` - raw metrics
  - `edge_score` - composite edge-of-chaos score
  - `zone` - :ordered | :critical | :chaotic

  ## Reference

  - Langton, C.G. (1990) "Computation at the Edge of Chaos"
  - HC_ARCHITECTURE_SYNTHESIS.md §3.3.2 Criticality Metrics
  """

  alias Thunderline.Thunderbolt.CA.Stepper
  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  require Logger

  @telemetry_event [:thunderline, :bolt, :ca, :criticality]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type criticality_metrics :: %{
          plv: float(),
          entropy: float(),
          lambda_hat: float(),
          lyapunov: float(),
          edge_score: float(),
          zone: :ordered | :critical | :chaotic,
          tick: non_neg_integer(),
          timestamp: integer()
        }

  @type delta :: map()

  # Edge of chaos targets (Langton's empirical values)
  @lambda_target 0.273
  @lambda_tolerance 0.15
  @plv_target 0.4
  @entropy_target 0.5

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes criticality metrics from a list of CA deltas.

  Analyzes the delta distribution to compute all four metrics:
  - PLV from phi_phase values
  - Permutation entropy from sigma_flow time series
  - Langton's λ̂ from state distribution
  - Lyapunov estimate from flow variance

  Returns `{:ok, metrics}` or `{:error, reason}`.
  """
  @spec compute_from_deltas([delta()], keyword()) :: {:ok, criticality_metrics()} | {:error, term()}
  def compute_from_deltas(deltas, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)
    history = Keyword.get(opts, :history, [])

    try do
      metrics = do_compute_metrics(deltas, history, tick)
      {:ok, metrics}
    rescue
      e ->
        Logger.warning("[Criticality] computation error: #{inspect(e)}")
        {:error, {:computation_error, e}}
    end
  end

  @doc """
  Computes criticality metrics from deltas (raising version).
  """
  @spec compute_from_deltas!([delta()], keyword()) :: criticality_metrics()
  def compute_from_deltas!(deltas, opts \\ []) do
    case compute_from_deltas(deltas, opts) do
      {:ok, metrics} -> metrics
      {:error, reason} -> raise "Criticality computation failed: #{inspect(reason)}"
    end
  end

  @doc """
  Steps the grid and computes criticality metrics in a single operation.

  Wraps `Stepper.next/2` and adds metrics computation.
  Returns `{:ok, deltas, new_grid, metrics}`.
  """
  @spec step_with_metrics(Stepper.grid(), Stepper.ruleset(), keyword()) ::
          {:ok, [delta()], Stepper.grid(), criticality_metrics()}
  def step_with_metrics(grid, ruleset, opts \\ []) do
    history = Keyword.get(opts, :history, [])

    {:ok, deltas, new_grid} = Stepper.next(grid, ruleset)

    tick = Map.get(new_grid, :tick, 0)
    {:ok, metrics} = compute_from_deltas(deltas, tick: tick, history: history)

    {:ok, deltas, new_grid, metrics}
  end

  @doc """
  Emits criticality metrics to telemetry and optionally to EventBus.

  Options:
  - `:emit_event` - If true, also publishes to EventBus (default: true)
  - `:run_id` - Required for EventBus publishing
  """
  @spec emit_metrics(String.t(), non_neg_integer(), criticality_metrics(), keyword()) :: :ok
  def emit_metrics(run_id, tick, metrics, opts \\ []) do
    emit_event = Keyword.get(opts, :emit_event, true)

    # Emit telemetry
    :telemetry.execute(
      @telemetry_event,
      %{
        plv: metrics.plv,
        entropy: metrics.entropy,
        lambda_hat: metrics.lambda_hat,
        lyapunov: metrics.lyapunov,
        edge_score: metrics.edge_score
      },
      %{
        run_id: run_id,
        tick: tick,
        zone: metrics.zone
      }
    )

    # Emit event
    if emit_event do
      publish_metrics_event(run_id, tick, metrics)
    end

    :ok
  end

  @doc """
  Computes the edge-of-chaos score from raw metrics.

  Score is maximized (→1.0) when:
  - λ̂ ≈ 0.273 (Langton's critical parameter)
  - PLV ≈ 0.4 (moderate synchronization)
  - Entropy ≈ 0.5 (neither ordered nor chaotic)
  - Lyapunov ≈ 0 (marginal stability)
  """
  @spec compute_edge_score(map()) :: float()
  def compute_edge_score(metrics) do
    lambda = Map.get(metrics, :lambda_hat, 0.5)
    plv = Map.get(metrics, :plv, 0.5)
    entropy = Map.get(metrics, :entropy, 0.5)
    lyapunov = Map.get(metrics, :lyapunov, 0.0)

    # Distance from targets (normalized)
    lambda_dist = abs(lambda - @lambda_target) / @lambda_tolerance
    plv_dist = abs(plv - @plv_target)
    entropy_dist = abs(entropy - @entropy_target)
    lyapunov_dist = min(1.0, abs(lyapunov))

    # Convert distances to scores (Gaussian decay)
    lambda_score = :math.exp(-lambda_dist * lambda_dist)
    plv_score = 1.0 - 2.0 * plv_dist
    entropy_score = 1.0 - 2.0 * entropy_dist
    lyapunov_score = 1.0 - lyapunov_dist

    # Clamp scores to [0, 1]
    lambda_score = max(0.0, min(1.0, lambda_score))
    plv_score = max(0.0, min(1.0, plv_score))
    entropy_score = max(0.0, min(1.0, entropy_score))
    lyapunov_score = max(0.0, min(1.0, lyapunov_score))

    # Weighted combination (λ̂ is primary indicator)
    score =
      lambda_score * 0.35 +
        entropy_score * 0.25 +
        plv_score * 0.25 +
        lyapunov_score * 0.15

    Float.round(score, 4)
  end

  @doc """
  Classifies the dynamical zone based on metrics.

  - `:ordered` - λ̂ < 0.2, low entropy, high PLV
  - `:chaotic` - λ̂ > 0.4, high entropy, low PLV
  - `:critical` - λ̂ ∈ [0.2, 0.4], balanced entropy/PLV
  """
  @spec classify_zone(map()) :: :ordered | :critical | :chaotic
  def classify_zone(metrics) do
    lambda = Map.get(metrics, :lambda_hat, 0.5)
    entropy = Map.get(metrics, :entropy, 0.5)

    cond do
      lambda < 0.2 and entropy < 0.3 -> :ordered
      lambda > 0.4 and entropy > 0.7 -> :chaotic
      lambda >= @lambda_target - @lambda_tolerance and
          lambda <= @lambda_target + @lambda_tolerance ->
        :critical

      true ->
        # Determine by distance from critical
        if lambda < @lambda_target, do: :ordered, else: :chaotic
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Metric Computation
  # ═══════════════════════════════════════════════════════════════

  defp do_compute_metrics(deltas, history, tick) do
    # Extract observables from deltas
    phases = extract_phases(deltas)
    flows = extract_flows(deltas)
    states = extract_states(deltas)

    # Compute individual metrics
    plv = compute_plv(phases)
    entropy = compute_permutation_entropy(flows, history)
    lambda_hat = compute_langton_lambda(states)
    lyapunov = estimate_lyapunov(flows, history)

    # Build metrics map for scoring
    raw_metrics = %{
      plv: plv,
      entropy: entropy,
      lambda_hat: lambda_hat,
      lyapunov: lyapunov
    }

    # Compute derived metrics
    edge_score = compute_edge_score(raw_metrics)
    zone = classify_zone(raw_metrics)

    %{
      plv: Float.round(plv, 4),
      entropy: Float.round(entropy, 4),
      lambda_hat: Float.round(lambda_hat, 4),
      lyapunov: Float.round(lyapunov, 4),
      edge_score: edge_score,
      zone: zone,
      tick: tick,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # ───────────────────────────────────────────────────────────────
  # Phase-Locking Value (PLV)
  # ───────────────────────────────────────────────────────────────

  @doc """
  Computes Phase-Locking Value measuring synchronization.

  PLV = |⟨e^{i(φ_j - φ_k)}⟩| averaged over all pairs.

  Returns:
  - 1.0 for perfectly synchronized phases
  - ~0.1 for random phases
  - ~0.4 for edge of chaos
  """
  @spec compute_plv([float()]) :: float()
  def compute_plv([]), do: 0.5
  def compute_plv([_single]), do: 0.5

  def compute_plv(phases) when is_list(phases) do
    n = length(phases)

    if n < 2 do
      0.5
    else
      # Sample pairs for efficiency (O(n) instead of O(n²))
      max_pairs = min(500, div(n * (n - 1), 2))

      {sum_cos, sum_sin, count} =
        sample_phase_pairs(phases, n, max_pairs)
        |> Enum.reduce({0.0, 0.0, 0}, fn {phi_i, phi_j}, {sc, ss, c} ->
          diff = phi_i - phi_j
          {sc + :math.cos(diff), ss + :math.sin(diff), c + 1}
        end)

      if count == 0 do
        0.5
      else
        mean_cos = sum_cos / count
        mean_sin = sum_sin / count
        :math.sqrt(mean_cos * mean_cos + mean_sin * mean_sin)
      end
    end
  end

  defp sample_phase_pairs(phases, n, max_pairs) when n <= 50 do
    # Small n: compute all pairs
    for i <- 0..(n - 2),
        j <- (i + 1)..(n - 1) do
      {Enum.at(phases, i), Enum.at(phases, j)}
    end
    |> Enum.take(max_pairs)
  end

  defp sample_phase_pairs(phases, n, max_pairs) do
    # Large n: random sampling
    phases_list = Enum.to_list(phases)

    1..max_pairs
    |> Enum.map(fn _ ->
      i = :rand.uniform(n) - 1
      j = :rand.uniform(n) - 1

      if i != j do
        {Enum.at(phases_list, i), Enum.at(phases_list, j)}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ───────────────────────────────────────────────────────────────
  # Permutation Entropy
  # ───────────────────────────────────────────────────────────────

  @doc """
  Computes permutation entropy for temporal complexity.

  Analyzes ordinal patterns in the time series.
  Normalized to [0,1]:
  - 0 = deterministic (single pattern)
  - 1 = random (uniform distribution)
  - ~0.5 = edge of chaos

  Uses embedding dimension m=3.
  """
  @spec compute_permutation_entropy([float()], [[float()]]) :: float()
  def compute_permutation_entropy(current_flows, history) do
    # Flatten history (which is list of flow lists) and append current
    series =
      history
      |> Enum.flat_map(fn h ->
        case h do
          flows when is_list(flows) -> Enum.take(flows, 10)
          _ -> []
        end
      end)
      |> Kernel.++(Enum.take(current_flows, 10))

    compute_permutation_entropy_series(series)
  end

  defp compute_permutation_entropy_series(series) when length(series) < 4, do: 0.5

  defp compute_permutation_entropy_series(series) do
    # Filter out non-numeric values
    series = Enum.filter(series, &is_number/1)

    if length(series) < 4 do
      0.5
    else
      m = 3
      n = length(series)

      patterns =
        0..(n - m)
        |> Enum.map(fn i ->
          window = Enum.slice(series, i, m)
          ordinal_pattern(window)
        end)

      counts = Enum.frequencies(patterns) |> Map.values()
      total = length(patterns)

      entropy =
        counts
        |> Enum.map(fn c ->
          p = c / total
          -p * :math.log2(p + 1.0e-12)
        end)
        |> Enum.sum()

      # Normalize by max entropy (log2 of m!)
      max_entropy = :math.log2(factorial(m))

      if max_entropy > 0 do
        min(1.0, entropy / max_entropy)
      else
        0.5
      end
    end
  end

  defp ordinal_pattern(window) do
    window
    |> Enum.with_index()
    |> Enum.sort_by(fn {val, _idx} -> val end)
    |> Enum.map(fn {_val, idx} -> idx end)
  end

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)

  # ───────────────────────────────────────────────────────────────
  # Langton's λ̂
  # ───────────────────────────────────────────────────────────────

  @doc """
  Computes Langton's λ̂ from state distribution.

  λ̂ = fraction of non-quiescent states
  Critical value: λ̂ ≈ 0.273
  """
  @spec compute_langton_lambda([atom()]) :: float()
  def compute_langton_lambda([]), do: 0.5

  def compute_langton_lambda(states) when is_list(states) do
    total = length(states)

    if total == 0 do
      0.5
    else
      # Non-quiescent = not :inactive, :dormant, :unknown, :dead
      quiescent_states = [:inactive, :dormant, :unknown, :dead]
      active_count = Enum.count(states, &(&1 not in quiescent_states))
      active_count / total
    end
  end

  # ───────────────────────────────────────────────────────────────
  # Lyapunov Exponent Estimation
  # ───────────────────────────────────────────────────────────────

  @doc """
  Estimates Lyapunov exponent from flow time series.

  Uses simplified Rosenstein algorithm:
  - λ > 0: chaotic (exponential divergence)
  - λ < 0: ordered (convergence)
  - λ ≈ 0: edge of chaos (marginal stability)
  """
  @spec estimate_lyapunov([float()], [[float()]]) :: float()
  def estimate_lyapunov(current_flows, history) do
    series =
      history
      |> Enum.flat_map(fn h ->
        case h do
          flows when is_list(flows) -> Enum.take(flows, 5)
          _ -> []
        end
      end)
      |> Kernel.++(Enum.take(current_flows, 5))

    estimate_lyapunov_series(series)
  end

  defp estimate_lyapunov_series(series) when length(series) < 10, do: 0.0

  defp estimate_lyapunov_series(series) do
    # Filter out non-numeric values
    series = Enum.filter(series, &is_number/1)

    if length(series) < 10 do
      0.0
    else
      n = length(series)
      series_list = Enum.to_list(series)
      threshold = compute_threshold(series_list)

      # Find nearby pairs
      pairs =
        for i <- 0..(n - 2),
            j <- (i + 1)..(n - 1),
            abs(Enum.at(series_list, i) - Enum.at(series_list, j)) < threshold do
          {i, j}
        end
        |> Enum.take(50)

      if length(pairs) < 2 do
        0.0
      else
        divergences =
          pairs
          |> Enum.map(fn {i, j} ->
            max_step = min(5, min(n - i - 1, n - j - 1))

            if max_step > 0 do
              compute_divergence(series_list, i, j, max_step)
            else
              nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if length(divergences) > 0 do
          avg = Enum.sum(divergences) / length(divergences)
          # Clamp to reasonable range
          max(-2.0, min(2.0, avg))
        else
          0.0
        end
      end
    end
  end

  defp compute_threshold(series_list) do
    mean_val = Enum.sum(series_list) / length(series_list)
    variance = series_list |> Enum.map(fn x -> (x - mean_val) ** 2 end) |> then(&(Enum.sum(&1) / length(&1)))
    std_dev = :math.sqrt(variance)
    max(0.01, std_dev * 0.1)
  end

  defp compute_divergence(series_list, i, j, steps) do
    initial = abs(Enum.at(series_list, i) - Enum.at(series_list, j))

    if initial < 1.0e-10 do
      nil
    else
      final = abs(Enum.at(series_list, i + steps) - Enum.at(series_list, j + steps))

      if final < 1.0e-10 do
        -1.0
      else
        :math.log(final / initial) / steps
      end
    end
  end

  # ───────────────────────────────────────────────────────────────
  # Observable Extraction
  # ───────────────────────────────────────────────────────────────

  defp extract_phases(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :phase) -> delta.phase
        is_map_key(delta, :phi_phase) -> delta.phi_phase
        true -> :rand.uniform() * 2 * :math.pi()
      end
    end)
  end

  defp extract_flows(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :flow) -> delta.flow
        is_map_key(delta, :sigma_flow) -> delta.sigma_flow
        is_map_key(delta, :energy) -> delta.energy / 100.0
        true -> 0.5
      end
    end)
  end

  defp extract_states(deltas) do
    Enum.map(deltas, fn delta ->
      Map.get(delta, :state, :unknown)
    end)
  end

  # ───────────────────────────────────────────────────────────────
  # Event Publishing
  # ───────────────────────────────────────────────────────────────

  defp publish_metrics_event(run_id, tick, metrics) do
    payload = %{
      run_id: run_id,
      tick: tick,
      plv: metrics.plv,
      entropy: metrics.entropy,
      lambda_hat: metrics.lambda_hat,
      lyapunov: metrics.lyapunov,
      edge_score: metrics.edge_score,
      zone: metrics.zone,
      sampled_at: System.system_time(:millisecond)
    }

    case Event.new(
           name: "bolt.ca.metrics.snapshot",
           source: :bolt,
           payload: payload,
           meta: %{
             pipeline: :criticality,
             component: "ca_criticality"
           }
         ) do
      {:ok, event} ->
        case EventBus.publish_event(event) do
          {:ok, _} ->
            Logger.debug("[Criticality] emitted metrics for run=#{run_id} tick=#{tick}")
            :ok

          {:error, reason} ->
            Logger.warning("[Criticality] event publish failed: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("[Criticality] event creation failed: #{inspect(reason)}")
        :ok
    end
  end
end
