defmodule Thunderline.Thunderbolt.Signal.LoopMonitor do
  @moduledoc """
  HC-40: Criticality feedback loop monitor for SNN/Photonic integration.

  Aggregates multiple criticality metrics to provide real-time feedback for:
  - Perturbation layer intensity (SLiM-style decorrelation)
  - Spiking cell dynamics tuning
  - CA rule adaptation

  ## Metrics Computed

  - **PLV (Phase Locking Value)**: Phase coherence across oscillators
  - **Permutation Entropy**: Temporal complexity/order measure
  - **Langton's λ̂**: Non-quiescent rule fraction (edge-of-chaos indicator)
  - **Local Lyapunov Exponent**: Sensitivity to initial conditions

  ## Criticality Targets

  The "edge of chaos" for CA systems typically occurs at:
  - λ̂ ∈ [0.25, 0.35] (Langton's empirical range)
  - PLV moderate (neither fully synchronized nor random)
  - Permutation entropy at intermediate values

  ## Telemetry

  Emits `[:thunderline, :bolt, :ca, :criticality]` with all computed metrics.
  """
  use GenServer
  require Logger
  alias Thunderline.Thunderbolt.Signal.PLV

  @type metrics :: %{
          plv: float(),
          permutation_entropy: float(),
          lambda_hat: float(),
          lyapunov_local: float(),
          criticality_score: float(),
          zone: :ordered | :critical | :chaotic
        }

  @type t :: %__MODULE__{
          phase_buffer: list(float()),
          state_buffer: list(list(integer())),
          trajectory_buffer: list(list(integer())),
          buffer_size: pos_integer(),
          lambda_target_min: float(),
          lambda_target_max: float(),
          last_metrics: metrics() | nil
        }

  defstruct phase_buffer: [],
            state_buffer: [],
            trajectory_buffer: [],
            buffer_size: 64,
            lambda_target_min: 0.25,
            lambda_target_max: 0.35,
            last_metrics: nil

  # ──────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Starts the LoopMonitor GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    buffer_size = Keyword.get(opts, :buffer_size, 64)
    lambda_min = Keyword.get(opts, :lambda_target_min, 0.25)
    lambda_max = Keyword.get(opts, :lambda_target_max, 0.35)

    GenServer.start_link(
      __MODULE__,
      %__MODULE__{
        buffer_size: buffer_size,
        lambda_target_min: lambda_min,
        lambda_target_max: lambda_max
      },
      name: name
    )
  end

  @doc """
  Records a phase observation (normalized to [0,1)).
  Used for PLV computation.
  """
  @spec record_phase(GenServer.server(), float()) :: :ok
  def record_phase(server \\ __MODULE__, phase) when is_float(phase) do
    GenServer.cast(server, {:record_phase, phase})
  end

  @doc """
  Records a CA state vector for λ̂ and trajectory analysis.
  State should be a list of cell states (e.g., 0/1 for Conway, integers for multi-state).
  """
  @spec record_state(GenServer.server(), list(integer())) :: :ok
  def record_state(server \\ __MODULE__, state) when is_list(state) do
    GenServer.cast(server, {:record_state, state})
  end

  @doc """
  Records a trajectory point for Lyapunov exponent estimation.
  """
  @spec record_trajectory(GenServer.server(), list(integer())) :: :ok
  def record_trajectory(server \\ __MODULE__, trajectory) when is_list(trajectory) do
    GenServer.cast(server, {:record_trajectory, trajectory})
  end

  @doc """
  Retrieves the current criticality metrics.
  """
  @spec get_metrics(GenServer.server()) :: metrics()
  def get_metrics(server \\ __MODULE__) do
    GenServer.call(server, :get_metrics)
  end

  @doc """
  Computes metrics from current buffers and optionally emits telemetry/event.
  Returns the computed metrics.
  """
  @spec compute_and_emit(GenServer.server()) :: metrics()
  def compute_and_emit(server \\ __MODULE__) do
    GenServer.call(server, :compute_and_emit)
  end

  @doc """
  Returns the recommended perturbation intensity based on current λ̂.
  Higher intensity when λ̂ is outside the critical band.
  """
  @spec recommended_perturbation(GenServer.server()) :: float()
  def recommended_perturbation(server \\ __MODULE__) do
    GenServer.call(server, :recommended_perturbation)
  end

  # ──────────────────────────────────────────────────────────────────────
  # Pure Functions (Public for testing)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes Phase Locking Value from a list of phases ∈ [0,1).
  Delegates to PLV module.
  """
  @spec plv(list(float())) :: float()
  def plv(phases), do: PLV.plv(phases)

  @doc """
  Computes permutation entropy for a time series.
  Uses embedding dimension m=3 by default.

  Higher values indicate more complex/chaotic dynamics.
  Normalized to [0,1] where 1 = maximum entropy.
  """
  @spec permutation_entropy(list(number()), pos_integer()) :: float()
  def permutation_entropy(series, m \\ 3)
  def permutation_entropy(series, _m) when length(series) < 3, do: 0.0

  def permutation_entropy(series, m) when is_list(series) and m > 0 do
    n = length(series)

    if n < m do
      0.0
    else
      # Generate ordinal patterns
      patterns =
        0..(n - m)
        |> Enum.map(fn i ->
          window = Enum.slice(series, i, m)
          ordinal_pattern(window)
        end)

      # Count pattern frequencies
      freqs = Enum.frequencies(patterns)
      _num_unique = map_size(freqs) |> max(1)
      count = Enum.count(patterns)

      # Compute normalized entropy
      entropy =
        freqs
        |> Map.values()
        |> Enum.reduce(0.0, fn c, acc ->
          p = c / count
          acc - p * :math.log(p + 1.0e-12)
        end)

      # Normalize by maximum possible entropy (log of m!)
      max_entropy = :math.log(factorial(m))

      if max_entropy > 0.0 do
        min(entropy / max_entropy, 1.0)
      else
        0.0
      end
    end
  end

  @doc """
  Computes Langton's λ̂ (lambda-hat) for a CA rule table or state distribution.

  λ̂ = fraction of non-quiescent states in transition table
  For binary CA: λ̂ = (# of 1s in rule output) / (total outputs)

  Edge of chaos typically at λ̂ ∈ [0.25, 0.35].
  """
  @spec lambda_hat(list(integer())) :: float()
  def lambda_hat([]), do: 0.0

  def lambda_hat(states) when is_list(states) do
    total = length(states)
    # Count non-quiescent (non-zero) states
    active = Enum.count(states, &(&1 != 0))
    active / total
  end

  @doc """
  Computes λ̂ from a CA rule table (e.g., Wolfram rule number).
  For a k=2, r=1 CA: 8 possible neighborhoods → 8-bit rule.
  """
  @spec lambda_from_rule(non_neg_integer(), pos_integer()) :: float()
  def lambda_from_rule(rule_number, neighborhood_size \\ 8) do
    # Count 1-bits in the rule number
    ones =
      0..(neighborhood_size - 1)
      |> Enum.count(fn i ->
        import Bitwise
        (rule_number >>> i &&& 1) == 1
      end)

    ones / neighborhood_size
  end

  @doc """
  Estimates local Lyapunov exponent from trajectory divergence.

  Measures rate of separation between nearby trajectories.
  Positive values indicate chaos, negative indicate stability.
  """
  @spec lyapunov_local(list(list(integer()))) :: float()
  def lyapunov_local([]), do: 0.0
  def lyapunov_local([_]), do: 0.0

  def lyapunov_local(trajectories) when length(trajectories) < 3, do: 0.0

  def lyapunov_local(trajectories) when is_list(trajectories) do
    # Compute divergence rate between consecutive states
    pairs = Enum.chunk_every(trajectories, 2, 1, :discard)

    divergences =
      Enum.map(pairs, fn [s1, s2] ->
        d = hamming_distance(s1, s2)
        if d > 0, do: :math.log(d + 1.0e-10), else: -10.0
      end)

    if length(divergences) > 0 do
      Enum.sum(divergences) / length(divergences)
    else
      0.0
    end
  end

  @doc """
  Determines the dynamical zone based on metrics.
  - :ordered - λ̂ < target_min, low entropy
  - :critical - λ̂ in target range
  - :chaotic - λ̂ > target_max, high entropy
  """
  @spec classify_zone(float(), float(), float(), float()) :: :ordered | :critical | :chaotic
  def classify_zone(lambda_hat, _perm_entropy, target_min, target_max) do
    cond do
      lambda_hat < target_min -> :ordered
      lambda_hat > target_max -> :chaotic
      true -> :critical
    end
  end

  @doc """
  Computes overall criticality score.
  Returns 1.0 when system is at optimal edge-of-chaos.
  Lower values indicate deviation from criticality.
  """
  @spec criticality_score(float(), float(), float()) :: float()
  def criticality_score(lambda_hat, target_min, target_max) do
    target_mid = (target_min + target_max) / 2.0
    target_range = (target_max - target_min) / 2.0

    # Distance from target center, normalized
    distance = abs(lambda_hat - target_mid) / max(target_range, 0.01)

    # Gaussian-like falloff from optimal
    :math.exp(-distance * distance)
  end

  # ──────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_phase, phase}, state) do
    new_phases = [phase | state.phase_buffer] |> Enum.take(state.buffer_size)
    {:noreply, %{state | phase_buffer: new_phases}}
  end

  @impl true
  def handle_cast({:record_state, ca_state}, state) do
    new_states = [ca_state | state.state_buffer] |> Enum.take(state.buffer_size)
    {:noreply, %{state | state_buffer: new_states}}
  end

  @impl true
  def handle_cast({:record_trajectory, trajectory}, state) do
    new_trajectories = [trajectory | state.trajectory_buffer] |> Enum.take(state.buffer_size)
    {:noreply, %{state | trajectory_buffer: new_trajectories}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = state.last_metrics || compute_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:compute_and_emit, _from, state) do
    metrics = compute_metrics(state)

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :bolt, :ca, :criticality],
      %{
        plv: metrics.plv,
        permutation_entropy: metrics.permutation_entropy,
        lambda_hat: metrics.lambda_hat,
        lyapunov_local: metrics.lyapunov_local,
        criticality_score: metrics.criticality_score
      },
      %{zone: metrics.zone}
    )

    # Optionally emit event
    maybe_emit_event(metrics)

    {:reply, metrics, %{state | last_metrics: metrics}}
  end

  @impl true
  def handle_call(:recommended_perturbation, _from, state) do
    metrics = state.last_metrics || compute_metrics(state)

    # If λ̂ is too low (ordered), increase perturbation to add chaos
    # If λ̂ is too high (chaotic), decrease perturbation to add order
    # At critical point, use minimal perturbation
    perturbation =
      case metrics.zone do
        :ordered -> 0.05 + 0.1 * (1.0 - metrics.criticality_score)
        :chaotic -> 0.01 + 0.05 * (1.0 - metrics.criticality_score)
        :critical -> 0.01
      end

    {:reply, perturbation, state}
  end

  # ──────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────

  defp compute_metrics(state) do
    # Flatten state buffer for λ̂ computation
    all_states = List.flatten(state.state_buffer)

    plv_val = plv(Enum.reverse(state.phase_buffer))

    # Use flattened trajectory for permutation entropy
    series =
      state.trajectory_buffer
      |> Enum.reverse()
      |> List.flatten()
      |> Enum.map(&abs/1)

    perm_entropy = permutation_entropy(series)
    lh = lambda_hat(all_states)
    lyap = lyapunov_local(Enum.reverse(state.trajectory_buffer))

    zone = classify_zone(lh, perm_entropy, state.lambda_target_min, state.lambda_target_max)
    crit_score = criticality_score(lh, state.lambda_target_min, state.lambda_target_max)

    %{
      plv: Float.round(plv_val, 4),
      permutation_entropy: Float.round(perm_entropy, 4),
      lambda_hat: Float.round(lh, 4),
      lyapunov_local: Float.round(lyap, 4),
      criticality_score: Float.round(crit_score, 4),
      zone: zone
    }
  end

  defp maybe_emit_event(metrics) do
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "bolt.ca.metrics.snapshot",
             source: :bolt,
             payload: Map.from_struct(metrics) |> Map.delete(:__struct__),
             meta: %{
               component: "loop_monitor",
               pipeline: :criticality
             },
             type: :metric
           ),
         {:ok, _} <- Thunderline.Thunderflow.EventBus.publish_event(ev) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("LoopMonitor event publish failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp ordinal_pattern(window) do
    # Convert window to ordinal pattern (permutation index)
    window
    |> Enum.with_index()
    |> Enum.sort_by(fn {val, _idx} -> val end)
    |> Enum.map(fn {_val, idx} -> idx end)
  end

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)

  defp hamming_distance(s1, s2) do
    # Pad shorter list
    len = max(length(s1), length(s2))
    s1_padded = s1 ++ List.duplicate(0, len - length(s1))
    s2_padded = s2 ++ List.duplicate(0, len - length(s2))

    Enum.zip(s1_padded, s2_padded)
    |> Enum.count(fn {a, b} -> a != b end)
  end
end
