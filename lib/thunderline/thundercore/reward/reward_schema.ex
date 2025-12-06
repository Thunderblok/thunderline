defmodule Thunderline.Thundercore.Reward.RewardSchema do
  @moduledoc """
  RewardSchema — Edge-of-Chaos Reward Signal Computation.

  Transforms criticality and side-quest metrics into a reward signal
  that drives automata toward optimal edge-of-chaos behavior.

  ## The Reward Loop

  ```
  ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
  │   Automata  │────▶│   Metrics    │────▶│   Reward    │
  │   (CA/NCA)  │     │ (Crit + SQ)  │     │   Signal    │
  └─────────────┘     └──────────────┘     └──────────────┘
         ▲                                        │
         │                                        │
         └────────────── Tuning ◀─────────────────┘
  ```

  ## Reward Components

  | Component | Weight | Target | Description |
  |-----------|--------|--------|-------------|
  | Edge Score | 0.40 | ~1.0 | Composite criticality measure |
  | Emergence | 0.25 | high | Novel structure detection |
  | Pattern Stability | 0.20 | balanced | Not too rigid, not chaotic |
  | Healing Rate | 0.15 | high | Self-repair capability |

  ## Tuning Signals

  The reward schema also provides directional tuning signals:
  - `lambda_delta` — Adjust Langton's λ toward 0.273
  - `temp_delta` — Adjust temperature for entropy tuning
  - `coupling_delta` — Adjust neighbor coupling strength

  ## Telemetry

  Emits `[:thunderline, :core, :reward, :computed]` with:
  - `reward` — The scalar reward [0, 1]
  - `components` — Individual component scores
  - `tuning` — Directional adjustment signals

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  - Langton, C.G. (1990) "Computation at the Edge of Chaos"
  """

  require Logger

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus

  @telemetry_event [:thunderline, :core, :reward, :computed]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type criticality_metrics :: %{
          plv: float(),
          entropy: float(),
          lambda_hat: float(),
          lyapunov: float(),
          edge_score: float(),
          zone: :ordered | :critical | :chaotic
        }

  @type side_quest_metrics :: %{
          clustering: float(),
          sortedness: float(),
          healing_rate: float(),
          pattern_stability: float(),
          emergence_score: float()
        }

  @type tuning_signal :: %{
          lambda_delta: float(),
          temp_delta: float(),
          coupling_delta: float()
        }

  @type reward_result :: %{
          reward: float(),
          components: map(),
          tuning: tuning_signal(),
          zone: :ordered | :critical | :chaotic,
          tick: non_neg_integer(),
          timestamp: integer()
        }

  # Component weights (must sum to 1.0)
  @weight_edge_score 0.40
  @weight_emergence 0.25
  @weight_stability 0.20
  @weight_healing 0.15

  # Targets
  @lambda_target 0.273
  @entropy_target 0.5
  @plv_target 0.4

  # Tuning sensitivity
  @tuning_sensitivity 0.1

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes reward signal from criticality and side-quest metrics.

  Returns a reward result with:
  - `reward` — Scalar reward [0, 1], maximized at edge of chaos
  - `components` — Individual component scores
  - `tuning` — Directional signals for parameter adjustment

  ## Examples

      criticality = %{edge_score: 0.85, lambda_hat: 0.28, ...}
      side_quest = %{emergence_score: 0.7, healing_rate: 0.8, ...}

      {:ok, result} = RewardSchema.compute(criticality, side_quest, tick: 42)
      # => %{reward: 0.78, tuning: %{lambda_delta: -0.007, ...}}
  """
  @spec compute(criticality_metrics(), side_quest_metrics(), keyword()) ::
          {:ok, reward_result()} | {:error, term()}
  def compute(criticality, side_quest, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)

    try do
      result = do_compute(criticality, side_quest, tick)
      {:ok, result}
    rescue
      e ->
        Logger.warning("[RewardSchema] computation error: #{inspect(e)}")
        {:error, {:computation_error, e}}
    end
  end

  @doc """
  Computes reward signal (raising version).
  """
  @spec compute!(criticality_metrics(), side_quest_metrics(), keyword()) :: reward_result()
  def compute!(criticality, side_quest, opts \\ []) do
    case compute(criticality, side_quest, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "RewardSchema computation failed: #{inspect(reason)}"
    end
  end

  @doc """
  Computes and emits reward signal to telemetry and EventBus.
  """
  @spec compute_and_emit(
          run_id :: String.t(),
          criticality_metrics(),
          side_quest_metrics(),
          keyword()
        ) :: {:ok, reward_result()} | {:error, term()}
  def compute_and_emit(run_id, criticality, side_quest, opts \\ []) do
    case compute(criticality, side_quest, opts) do
      {:ok, result} ->
        emit(run_id, result, opts)
        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Emits reward result to telemetry and EventBus.
  """
  @spec emit(String.t(), reward_result(), keyword()) :: :ok
  def emit(run_id, result, opts \\ []) do
    emit_event = Keyword.get(opts, :emit_event, true)

    # Emit telemetry
    :telemetry.execute(
      @telemetry_event,
      %{
        reward: result.reward,
        edge_score: result.components.edge_score,
        emergence: result.components.emergence,
        stability: result.components.stability,
        healing: result.components.healing,
        lambda_delta: result.tuning.lambda_delta,
        temp_delta: result.tuning.temp_delta,
        coupling_delta: result.tuning.coupling_delta
      },
      %{
        run_id: run_id,
        tick: result.tick,
        zone: result.zone
      }
    )

    # Publish event
    if emit_event do
      publish_event(run_id, result)
    end

    :ok
  end

  @doc """
  Returns the current reward weights configuration.
  """
  @spec weights() :: map()
  def weights do
    %{
      edge_score: @weight_edge_score,
      emergence: @weight_emergence,
      stability: @weight_stability,
      healing: @weight_healing
    }
  end

  @doc """
  Returns the target values for edge-of-chaos.
  """
  @spec targets() :: map()
  def targets do
    %{
      lambda: @lambda_target,
      entropy: @entropy_target,
      plv: @plv_target
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Reward Computation
  # ═══════════════════════════════════════════════════════════════

  defp do_compute(criticality, side_quest, tick) do
    # Extract component scores
    edge_score = Map.get(criticality, :edge_score, 0.5)
    emergence = Map.get(side_quest, :emergence_score, 0.5)
    stability = compute_stability_score(side_quest)
    healing = Map.get(side_quest, :healing_rate, 0.5)

    # Weighted reward
    reward =
      edge_score * @weight_edge_score +
        emergence * @weight_emergence +
        stability * @weight_stability +
        healing * @weight_healing

    # Clamp to [0, 1]
    reward = max(0.0, min(1.0, reward))

    # Compute tuning signals
    tuning = compute_tuning_signals(criticality, side_quest)

    # Get zone
    zone = Map.get(criticality, :zone, :critical)

    %{
      reward: Float.round(reward, 4),
      components: %{
        edge_score: Float.round(edge_score, 4),
        emergence: Float.round(emergence, 4),
        stability: Float.round(stability, 4),
        healing: Float.round(healing, 4)
      },
      tuning: tuning,
      zone: zone,
      tick: tick,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Stability Score (Goldilocks — not too rigid, not too chaotic)
  # ═══════════════════════════════════════════════════════════════

  defp compute_stability_score(side_quest) do
    pattern_stability = Map.get(side_quest, :pattern_stability, 0.5)

    # Optimal stability is around 0.5-0.7
    # Too high = frozen, too low = chaotic
    # Parabolic reward centered at 0.6
    optimal = 0.6
    distance = abs(pattern_stability - optimal)

    # Gaussian reward peaked at optimal
    score = :math.exp(-4.0 * distance * distance)

    max(0.0, min(1.0, score))
  end

  # ═══════════════════════════════════════════════════════════════
  # Tuning Signals
  # ═══════════════════════════════════════════════════════════════

  defp compute_tuning_signals(criticality, side_quest) do
    lambda = Map.get(criticality, :lambda_hat, 0.5)
    entropy = Map.get(criticality, :entropy, 0.5)
    plv = Map.get(criticality, :plv, 0.5)
    clustering = Map.get(side_quest, :clustering, 0.5)

    # Lambda tuning: push toward 0.273
    lambda_delta = (@lambda_target - lambda) * @tuning_sensitivity

    # Temperature tuning: push entropy toward 0.5
    # High entropy → decrease temp, low entropy → increase temp
    temp_delta = (@entropy_target - entropy) * @tuning_sensitivity

    # Coupling tuning: based on PLV and clustering balance
    # Low PLV + low clustering → increase coupling
    # High PLV + high clustering → decrease coupling (overly synchronized)
    coupling_target = 0.5
    current_coupling_proxy = (plv + clustering) / 2.0
    coupling_delta = (coupling_target - current_coupling_proxy) * @tuning_sensitivity

    %{
      lambda_delta: Float.round(lambda_delta, 4),
      temp_delta: Float.round(temp_delta, 4),
      coupling_delta: Float.round(coupling_delta, 4)
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Publishing
  # ═══════════════════════════════════════════════════════════════

  defp publish_event(run_id, result) do
    payload = %{
      run_id: run_id,
      tick: result.tick,
      reward: result.reward,
      components: result.components,
      tuning: result.tuning,
      zone: result.zone,
      sampled_at: System.system_time(:millisecond)
    }

    case Event.new(
           name: "core.reward.computed",
           source: :core,
           payload: payload,
           meta: %{
             pipeline: :reward_loop,
             component: "reward_schema"
           }
         ) do
      {:ok, event} ->
        case EventBus.publish_event(event) do
          {:ok, _} ->
            Logger.debug("[RewardSchema] emitted for run=#{run_id} tick=#{result.tick}")
            :ok

          {:error, reason} ->
            Logger.warning("[RewardSchema] event publish failed: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("[RewardSchema] event creation failed: #{inspect(reason)}")
        :ok
    end
  end
end
