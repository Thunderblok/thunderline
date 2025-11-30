defmodule Thunderline.Thunderbolt.Cerebros.LoopMonitor do
  @moduledoc """
  LoopMonitor: Criticality Metrics for Self-Optimizing CA (HC-40).

  Computes real-time criticality metrics to guide the CA toward the
  "edge of chaos" - the phase transition where computation is maximized.

  ## Metrics

  | Metric | Symbol | Range | Edge of Chaos |
  |--------|--------|-------|---------------|
  | Phase-Locking Value | PLV | [0,1] | ~0.4 |
  | Permutation Entropy | H_p | [0,1] | ~0.5 |
  | Langton's λ̂ | λ̂ | [0,1] | ~0.273 |
  | Lyapunov Exponent | λ_L | (-∞,∞) | ~0 |

  ## Usage

      # Initialize monitor for a CA run
      {:ok, monitor} = LoopMonitor.start_link(run_id: "pac_123", sample_window: 50)

      # Update with each tick's voxel states
      LoopMonitor.observe(monitor, tick, voxel_states)

      # Get current metrics
      {:ok, metrics} = LoopMonitor.get_metrics(monitor)

  ## Theory

  **Edge of Chaos**: Cellular automata exhibit maximal computational capability
  at the phase transition between ordered (Class I/II) and chaotic (Class III)
  regimes. Langton showed this occurs near λ̂ ≈ 0.273 for 2-state CAs.

  **PLV (Phase-Locking Value)**: Measures synchronization across voxels.
  High PLV → rigid order, Low PLV → desynchronized chaos.

  **Permutation Entropy**: Measures temporal complexity of state sequences.
  Normalized to [0,1] where 0 = deterministic, 1 = random.

  **Lyapunov Exponent**: Rate of divergence of nearby trajectories.
  λ > 0 → chaos, λ < 0 → order, λ ≈ 0 → edge of chaos.

  ## Reference

  - Langton, C.G. (1990) "Computation at the Edge of Chaos"
  - Packard, N.H. (1988) "Adaptation Toward the Edge of Chaos"
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Cerebros.PACCompute

  @telemetry_event [:thunderline, :cerebros, :loop_monitor]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type voxel_state :: %{
          coord: {pos_integer(), pos_integer(), pos_integer()},
          sigma_flow: float(),
          phi_phase: float()
        }

  @type metrics :: %{
          plv: float(),
          entropy: float(),
          lambda_hat: float(),
          lyapunov: float(),
          tick: non_neg_integer()
        }

  @type state :: %{
          run_id: String.t(),
          sample_window: pos_integer(),
          history: :queue.queue(),
          tick: non_neg_integer(),
          metrics: metrics(),
          emit_interval: pos_integer()
        }

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts a LoopMonitor for tracking CA criticality metrics.

  ## Options

  - `:run_id` - Required. Unique identifier for the CA run.
  - `:sample_window` - Number of ticks to keep for analysis (default: 50)
  - `:emit_interval` - Emit metrics event every N ticks (default: 10)
  - `:name` - Process name registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = Keyword.get(opts, :name, via(run_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records voxel states for a tick. Should be called after each CA step.

  `voxel_states` should be a list of maps with `:sigma_flow` and `:phi_phase`.
  """
  @spec observe(GenServer.server(), non_neg_integer(), [voxel_state()]) :: :ok
  def observe(server, tick, voxel_states) do
    GenServer.cast(server, {:observe, tick, voxel_states})
  end

  @doc """
  Gets the current criticality metrics.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, metrics()} | {:error, term()}
  def get_metrics(server) do
    GenServer.call(server, :get_metrics)
  end

  @doc """
  Gets the edge-of-chaos fitness score.

  Higher scores indicate the CA is closer to the critical phase transition.
  """
  @spec get_fitness(GenServer.server()) :: {:ok, float()} | {:error, term()}
  def get_fitness(server) do
    GenServer.call(server, :get_fitness)
  end

  @doc """
  Resets the monitor state.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    sample_window = Keyword.get(opts, :sample_window, 50)
    emit_interval = Keyword.get(opts, :emit_interval, 10)

    state = %{
      run_id: run_id,
      sample_window: sample_window,
      history: :queue.new(),
      tick: 0,
      metrics: empty_metrics(),
      emit_interval: emit_interval
    }

    Logger.debug("[LoopMonitor] Started for run=#{run_id} window=#{sample_window}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:observe, tick, voxel_states}, state) do
    started = System.monotonic_time(:microsecond)

    # Extract observable values
    snapshot = extract_snapshot(voxel_states)

    # Update history queue
    history =
      state.history
      |> :queue.in({tick, snapshot})
      |> trim_history(state.sample_window)

    # Compute metrics if we have enough history
    history_list = :queue.to_list(history)
    metrics = compute_metrics(history_list, tick)

    # Emit telemetry
    duration_us = System.monotonic_time(:microsecond) - started

    :telemetry.execute(
      @telemetry_event,
      %{duration_us: duration_us, voxel_count: length(voxel_states)},
      %{run_id: state.run_id, tick: tick}
    )

    # Emit event periodically
    new_state = %{state | history: history, tick: tick, metrics: metrics}
    new_state = maybe_emit_event(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.metrics}, state}
  end

  @impl true
  def handle_call(:get_fitness, _from, state) do
    fitness = PACCompute.compute_edge_score(state.metrics)
    {:reply, {:ok, fitness}, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{state | history: :queue.new(), tick: 0, metrics: empty_metrics()}
    {:reply, :ok, new_state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Metrics Computation
  # ═══════════════════════════════════════════════════════════════

  defp extract_snapshot(voxel_states) when is_list(voxel_states) do
    flows = Enum.map(voxel_states, fn v -> Map.get(v, :sigma_flow, 0.0) end)
    phases = Enum.map(voxel_states, fn v -> Map.get(v, :phi_phase, 0.0) end)
    states = Enum.map(voxel_states, fn v -> Map.get(v, :state, :unknown) end)

    %{flows: flows, phases: phases, states: states}
  end

  defp compute_metrics(history_list, tick) when length(history_list) < 3 do
    Map.put(empty_metrics(), :tick, tick)
  end

  defp compute_metrics(history_list, tick) do
    # Extract time series
    flow_series = Enum.map(history_list, fn {_t, s} -> mean(s.flows) end)
    phase_series = Enum.map(history_list, fn {_t, s} -> s.phases end)
    state_series = Enum.map(history_list, fn {_t, s} -> s.states end)

    # Compute each metric
    plv = compute_plv(phase_series)
    entropy = compute_permutation_entropy(flow_series)
    lambda_hat = compute_langton_lambda(state_series)
    lyapunov = estimate_lyapunov(flow_series)

    %{
      plv: plv,
      entropy: entropy,
      lambda_hat: lambda_hat,
      lyapunov: lyapunov,
      tick: tick
    }
  end

  @doc """
  Computes Phase-Locking Value (PLV) measuring synchronization.

  PLV = |⟨e^{i(φ_j - φ_k)}⟩| averaged over all voxel pairs.

  High PLV (→1) = synchronized/ordered
  Low PLV (→0) = desynchronized/chaotic
  """
  @spec compute_plv([[float()]]) :: float()
  def compute_plv([]), do: 0.5
  def compute_plv([_]), do: 0.5

  def compute_plv(phase_series) do
    # Use the most recent phase snapshot
    phases = List.last(phase_series)

    if length(phases) < 2 do
      0.5
    else
      # Compute pairwise phase differences
      n = length(phases)
      phases_list = Enum.to_list(phases)

      # Sample pairs to avoid O(n²) for large grids
      max_pairs = min(1000, div(n * (n - 1), 2))
      pairs = sample_pairs(n, max_pairs)

      # Compute PLV as magnitude of mean complex exponential
      {sum_cos, sum_sin, count} =
        Enum.reduce(pairs, {0.0, 0.0, 0}, fn {i, j}, {sc, ss, c} ->
          phi_i = Enum.at(phases_list, i)
          phi_j = Enum.at(phases_list, j)
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

  @doc """
  Computes permutation entropy for temporal complexity.

  Analyzes the distribution of ordinal patterns in the time series.
  Normalized to [0,1] where:
  - 0 = completely deterministic (single pattern)
  - 1 = completely random (uniform distribution)

  Uses embedding dimension m=3 by default.
  """
  @spec compute_permutation_entropy([float()]) :: float()
  def compute_permutation_entropy(series) when length(series) < 4, do: 0.5

  def compute_permutation_entropy(series) do
    # Embedding dimension (pattern length)
    m = 3
    n = length(series)

    # Extract ordinal patterns
    patterns =
      0..(n - m)
      |> Enum.map(fn i ->
        window = Enum.slice(series, i, m)
        ordinal_pattern(window)
      end)

    # Count pattern frequencies
    counts =
      patterns
      |> Enum.frequencies()
      |> Map.values()

    total = length(patterns)

    # Compute Shannon entropy
    entropy =
      counts
      |> Enum.map(fn c ->
        p = c / total
        -p * :math.log2(p)
      end)
      |> Enum.sum()

    # Normalize by maximum entropy (log2 of m!)
    max_entropy = :math.log2(factorial(m))

    if max_entropy == 0 do
      0.5
    else
      min(1.0, max(0.0, entropy / max_entropy))
    end
  end

  @doc """
  Estimates Langton's λ parameter from state distribution.

  λ̂ = fraction of rule table entries that produce non-quiescent states.

  For our continuous-state CA, we approximate by counting active states
  (sigma_flow > threshold) vs total.

  Critical value: λ ≈ 0.273 for edge of chaos
  """
  @spec compute_langton_lambda([[atom()]]) :: float()
  def compute_langton_lambda([]), do: 0.5

  def compute_langton_lambda(state_series) do
    # Use most recent state snapshot
    states = List.last(state_series)

    if length(states) == 0 do
      0.5
    else
      # Count non-quiescent states
      active_count =
        Enum.count(states, fn s ->
          s not in [:inactive, :dormant, :unknown]
        end)

      active_count / length(states)
    end
  end

  @doc """
  Estimates the largest Lyapunov exponent from time series.

  Uses the Rosenstein algorithm (simplified):
  Track divergence of initially nearby points over time.

  λ_L > 0: chaotic
  λ_L < 0: ordered/periodic
  λ_L ≈ 0: edge of chaos
  """
  @spec estimate_lyapunov([float()]) :: float()
  def estimate_lyapunov(series) when length(series) < 10, do: 0.0

  def estimate_lyapunov(series) do
    n = length(series)
    series_list = Enum.to_list(series)

    # Find pairs of nearby points (embedding dimension 1 for simplicity)
    pairs = find_nearby_pairs(series_list, n)

    if length(pairs) < 2 do
      0.0
    else
      # Track divergence over time
      divergences =
        pairs
        |> Enum.take(min(50, length(pairs)))
        |> Enum.map(fn {i, j} ->
          compute_divergence(series_list, i, j, min(10, n - max(i, j) - 1))
        end)
        |> Enum.reject(&is_nil/1)

      if length(divergences) == 0 do
        0.0
      else
        # Average log divergence rate ≈ Lyapunov exponent
        avg_divergence = mean(divergences)
        # Clamp to reasonable range
        max(-2.0, min(2.0, avg_divergence))
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════

  defp empty_metrics do
    %{plv: 0.5, entropy: 0.5, lambda_hat: 0.5, lyapunov: 0.0, tick: 0}
  end

  defp trim_history(queue, max_size) do
    if :queue.len(queue) > max_size do
      {_dropped, trimmed} = :queue.out(queue)
      trimmed
    else
      queue
    end
  end

  defp maybe_emit_event(%{tick: tick, emit_interval: interval} = state)
       when rem(tick, interval) == 0 and tick > 0 do
    # Emit metrics event
    case PACCompute.publish_metrics(state.run_id, tick, state.metrics) do
      {:ok, _event} ->
        Logger.debug("[LoopMonitor] Emitted metrics for tick=#{tick}")

      {:error, reason} ->
        Logger.warning("[LoopMonitor] Failed to emit metrics: #{inspect(reason)}")
    end

    state
  end

  defp maybe_emit_event(state), do: state

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)

  # Convert a sequence to its ordinal pattern (rank ordering)
  defp ordinal_pattern(window) do
    window
    |> Enum.with_index()
    |> Enum.sort_by(fn {val, _idx} -> val end)
    |> Enum.map(fn {_val, idx} -> idx end)
  end

  # Sample random pairs of indices
  defp sample_pairs(n, max_pairs) do
    total_pairs = div(n * (n - 1), 2)

    if total_pairs <= max_pairs do
      for i <- 0..(n - 2), j <- (i + 1)..(n - 1), do: {i, j}
    else
      # Random sampling
      1..max_pairs
      |> Enum.map(fn _ ->
        i = :rand.uniform(n) - 1
        j = :rand.uniform(n) - 1
        if i < j, do: {i, j}, else: {j, i}
      end)
      |> Enum.uniq()
    end
  end

  # Find pairs of points that are initially close in value
  defp find_nearby_pairs(series_list, n) do
    threshold = compute_threshold(series_list)

    for i <- 0..(n - 2),
        j <- (i + 1)..(n - 1),
        abs(Enum.at(series_list, i) - Enum.at(series_list, j)) < threshold do
      {i, j}
    end
    |> Enum.take(100)
  end

  defp compute_threshold(series_list) do
    # Use 10% of standard deviation as threshold
    mean_val = mean(series_list)
    variance = series_list |> Enum.map(fn x -> (x - mean_val) ** 2 end) |> mean()
    std_dev = :math.sqrt(variance)
    max(0.01, std_dev * 0.1)
  end

  # Compute how fast two initially nearby trajectories diverge
  defp compute_divergence(series_list, i, j, steps) when steps < 1, do: nil

  defp compute_divergence(series_list, i, j, steps) do
    initial_dist = abs(Enum.at(series_list, i) - Enum.at(series_list, j))

    if initial_dist < 1.0e-10 do
      nil
    else
      final_dist =
        abs(Enum.at(series_list, i + steps) - Enum.at(series_list, j + steps))

      if final_dist < 1.0e-10 do
        # Converged - negative Lyapunov
        -1.0
      else
        # Log of ratio gives average exponential growth
        :math.log(final_dist / initial_dist) / steps
      end
    end
  end

  defp via(run_id) do
    {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, {:loop_monitor, run_id}}}
  end
end
