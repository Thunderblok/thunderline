defmodule Thunderline.Thunderbolt.Signal.SurpriseMetrics do
  @moduledoc """
  HC-76: Surprise metric computation for MIRAS/Titans memory integration.

  Surprise quantifies novelty/unexpectedness in PAC observations.
  Based on Titans paper: surprise = gradient magnitude ‖∇ℓ‖

  ## Theory (Titans)

  In Titans, the memory writes when the model is "surprised" by new data.
  Surprise is measured as the magnitude of the gradient that would update
  the memory weights. Higher gradients = more unexpected = write to memory.

  ## Implementation

  Since we don't always have actual gradients, we use prediction error
  as a proxy for surprise. This follows the predictive coding framework
  where surprise ∝ |prediction - observation|.

  ## Momentum Smoothing

  To prevent spurious writes from noise, we use exponential moving average:

      s_t = β * s_{t-1} + (1-β) * ‖∇ℓ_t‖

  where β ∈ [0.8, 0.95] is the momentum coefficient.

  ## Events

  Emits `[:thunderline, :bolt, :ca, :surprise]` telemetry with:
  - raw_surprise: instantaneous surprise value
  - smoothed_surprise: momentum-averaged surprise
  - pac_id: PAC identifier
  - wrote_to_memory: whether threshold was exceeded

  ## References

  - Titans: Learning to Memorize at Test Time (Google, 2025)
  - MIRAS: Unlocking Expressivity and Safety (2025)
  """

  alias Thunderline.Thunderflow.EventBus
  require Logger

  # ──────────────────────────────────────────────────────────────────────
  # Types
  # ──────────────────────────────────────────────────────────────────────

  @type surprise_state :: %{
          pac_id: String.t() | nil,
          momentum: float(),
          history: list(float()),
          history_size: pos_integer(),
          beta: float(),
          threshold: float(),
          write_count: non_neg_integer(),
          total_samples: non_neg_integer()
        }

  # ──────────────────────────────────────────────────────────────────────
  # State Management
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Creates a new surprise state tracker.

  ## Options

  - `:pac_id` - PAC identifier for telemetry (default: nil)
  - `:beta` - Momentum coefficient ∈ (0, 1), higher = slower adaptation (default: 0.9)
  - `:threshold` - Write threshold (default: 0.1)
  - `:history_size` - Number of historical values to retain (default: 100)
  """
  @spec new(keyword()) :: surprise_state()
  def new(opts \\ []) do
    %{
      pac_id: Keyword.get(opts, :pac_id),
      momentum: 0.0,
      history: [],
      history_size: Keyword.get(opts, :history_size, 100),
      beta: Keyword.get(opts, :beta, 0.9),
      threshold: Keyword.get(opts, :threshold, 0.1),
      write_count: 0,
      total_samples: 0
    }
  end

  @doc """
  Updates the surprise state with a new observation.
  Returns `{new_state, should_write?}`.
  """
  @spec update(surprise_state(), float()) :: {surprise_state(), boolean()}
  def update(state, raw_surprise) do
    smoothed = momentum_surprise(raw_surprise, state.momentum, state.beta)
    should_write = should_write?(smoothed, state.threshold)

    new_state = %{
      state
      | momentum: smoothed,
        history: [raw_surprise | state.history] |> Enum.take(state.history_size),
        write_count: if(should_write, do: state.write_count + 1, else: state.write_count),
        total_samples: state.total_samples + 1
    }

    {new_state, should_write}
  end

  # ──────────────────────────────────────────────────────────────────────
  # Core Computations (Pure Functions)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes surprise as L2 norm of prediction error.
  This is a proxy for gradient magnitude ‖∇ℓ‖.

  ## Examples

      iex> surprise_metric([1.0, 2.0, 3.0], [1.1, 2.2, 2.8])
      0.3

  """
  @spec surprise_metric(list(number()), list(number())) :: float()
  def surprise_metric(predicted, actual) when is_list(predicted) and is_list(actual) do
    if length(predicted) != length(actual) do
      0.0
    else
      predicted
      |> Enum.zip(actual)
      |> Enum.map(fn {p, a} -> (a - p) * (a - p) end)
      |> Enum.sum()
      |> :math.sqrt()
    end
  end

  @doc """
  Computes surprise from Nx tensors.
  Uses L2 norm of element-wise difference.
  """
  @spec surprise_metric_nx(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def surprise_metric_nx(predicted, actual) do
    Nx.subtract(actual, predicted)
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
    |> Nx.to_number()
  end

  @doc """
  Computes single-value surprise (absolute error).
  Useful for scalar predictions.
  """
  @spec surprise_scalar(number(), number()) :: float()
  def surprise_scalar(predicted, actual) do
    abs(actual - predicted)
  end

  @doc """
  Momentum-smoothed surprise signal (β-EMA).

      s_t = β * s_{t-1} + (1-β) * ‖∇ℓ_t‖

  ## Parameters

  - `current_surprise` - Raw surprise value at time t
  - `prev_momentum` - Smoothed surprise at time t-1
  - `beta` - Momentum coefficient ∈ (0, 1). Higher = slower adaptation.
    - β = 0.9: ~10 samples effective window
    - β = 0.95: ~20 samples effective window
    - β = 0.99: ~100 samples effective window

  ## Examples

      iex> momentum_surprise(0.5, 0.3, 0.9)
      0.32

  """
  @spec momentum_surprise(float(), float(), float()) :: float()
  def momentum_surprise(current_surprise, prev_momentum, beta \\ 0.9)
      when is_number(current_surprise) and is_number(prev_momentum) do
    beta = clamp(beta, 0.0, 0.9999)
    beta * prev_momentum + (1 - beta) * current_surprise
  end

  @doc """
  Checks if smoothed surprise exceeds write threshold.
  """
  @spec should_write?(float(), float()) :: boolean()
  def should_write?(smoothed_surprise, threshold \\ 0.1) do
    smoothed_surprise > threshold
  end

  @doc """
  Computes adaptive threshold based on recent surprise history.
  Uses percentile-based threshold: write if surprise > P{percentile} of recent values.
  """
  @spec adaptive_threshold(list(float()), float()) :: float()
  def adaptive_threshold(history, percentile \\ 0.9) when is_list(history) do
    if Enum.empty?(history) do
      0.1
    else
      sorted = Enum.sort(history)
      idx = trunc(length(sorted) * percentile)
      Enum.at(sorted, min(idx, length(sorted) - 1), 0.1)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Telemetry & Events
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Emits surprise telemetry event.
  """
  @spec emit_telemetry(String.t() | nil, float(), float(), boolean()) :: :ok
  def emit_telemetry(pac_id, raw_surprise, smoothed_surprise, wrote?) do
    :telemetry.execute(
      [:thunderline, :bolt, :ca, :surprise],
      %{
        raw_surprise: raw_surprise,
        smoothed_surprise: smoothed_surprise
      },
      %{
        pac_id: pac_id || "unknown",
        wrote_to_memory: wrote?
      }
    )

    :ok
  end

  @doc """
  Publishes a surprise event to the EventBus.
  """
  @spec publish_surprise_event(surprise_state(), float(), boolean()) :: :ok | {:error, term()}
  def publish_surprise_event(state, raw_surprise, wrote?) do
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "pac.memory.surprise",
             source: :thunderpac,
             payload: %{
               pac_id: state.pac_id,
               raw_surprise: raw_surprise,
               smoothed_surprise: state.momentum,
               threshold: state.threshold,
               wrote_to_memory: wrote?,
               write_rate: write_rate(state)
             },
             meta: %{
               component: "surprise_metrics",
               pipeline: :memory
             },
             type: :metric
           ),
         {:ok, _} <- EventBus.publish_event(ev) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("SurpriseMetrics event publish failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("SurpriseMetrics event error: #{inspect(e)}")
      {:error, e}
  end

  # ──────────────────────────────────────────────────────────────────────
  # Statistics & Analysis
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes the write rate (fraction of samples that triggered writes).
  """
  @spec write_rate(surprise_state()) :: float()
  def write_rate(%{total_samples: 0}), do: 0.0

  def write_rate(state) do
    state.write_count / state.total_samples
  end

  @doc """
  Computes surprise statistics from history.
  """
  @spec statistics(surprise_state()) :: map()
  def statistics(%{history: []} = _state) do
    %{
      mean: 0.0,
      std: 0.0,
      min: 0.0,
      max: 0.0,
      count: 0
    }
  end

  def statistics(state) do
    history = state.history
    count = length(history)
    mean = Enum.sum(history) / count
    variance = Enum.reduce(history, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / count
    std = :math.sqrt(variance)

    %{
      mean: Float.round(mean, 4),
      std: Float.round(std, 4),
      min: Float.round(Enum.min(history), 4),
      max: Float.round(Enum.max(history), 4),
      count: count,
      momentum: Float.round(state.momentum, 4),
      write_rate: Float.round(write_rate(state), 4)
    }
  end

  @doc """
  Detects surprise spikes (values > k standard deviations above mean).
  Useful for identifying highly novel events.
  """
  @spec detect_spikes(list(float()), float()) :: list({non_neg_integer(), float()})
  def detect_spikes(history, k \\ 2.0) when is_list(history) do
    if length(history) < 5 do
      []
    else
      mean = Enum.sum(history) / length(history)
      variance = Enum.reduce(history, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / length(history)
      std = :math.sqrt(variance)
      spike_threshold = mean + k * std

      history
      |> Enum.with_index()
      |> Enum.filter(fn {val, _idx} -> val > spike_threshold end)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Integration with LoopMonitor
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes surprise from LoopMonitor metrics.
  Uses deviation from criticality as surprise signal.

  When λ̂ deviates from the critical band, the system is "surprised"
  by non-edge-of-chaos dynamics.
  """
  @spec surprise_from_criticality(map()) :: float()
  def surprise_from_criticality(%{criticality_score: crit, zone: zone}) do
    # Low criticality score = high surprise (far from edge of chaos)
    base_surprise = 1.0 - crit

    # Zone-based adjustment
    zone_factor =
      case zone do
        :critical -> 0.5  # At edge of chaos - lower surprise
        :ordered -> 1.0   # Too ordered - normal surprise
        :chaotic -> 1.2   # Too chaotic - elevated surprise
      end

    base_surprise * zone_factor
  end

  def surprise_from_criticality(_), do: 0.0

  # ──────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end
end
