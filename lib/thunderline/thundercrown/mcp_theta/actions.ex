defmodule Thunderline.Thundercrown.MCPTheta.Actions do
  @moduledoc """
  Corrective actions for MCP-Θ regulation.

  When the Regulator detects metric deviations, it applies corrective
  actions to restore near-critical dynamics. Each action targets a
  specific type of deviation.

  ## Actions

  | Action | Trigger | Effect |
  |--------|---------|--------|
  | :desync | PLV > 0.6 | Inject noise to break hypersync |
  | :resync | PLV < 0.3 | Apply coherence signal |
  | :dampen | σ > 1.2 | Reduce propagation gain |
  | :boost | σ < 0.8 | Increase propagation gain |
  | :safe_mode | λ̂ > 0 | Emergency halt, minimal processing |

  ## Implementation Notes

  Actions are applied through the PAC's configuration system.
  The actual implementation depends on the PAC's architecture.
  """

  require Logger

  @type action ::
          :desync
          | :resync
          | :dampen
          | :boost
          | :safe_mode
          | :none

  @type context :: %{
          pac_id: String.t(),
          metrics: map()
        }

  @type result :: %{
          action: action(),
          success: boolean(),
          effects: list(),
          timestamp: DateTime.t()
        }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Executes a corrective action.

  ## Parameters

  - `action` - The action to execute
  - `context` - Context including PAC ID and current metrics

  ## Returns

  A result map describing what was done.
  """
  @spec execute(action(), context()) :: result()
  def execute(action, context) do
    Logger.debug("[MCP-Θ Actions] Executing #{action} for PAC #{context.pac_id}")

    effects = apply_action(action, context)

    result = %{
      action: action,
      success: true,
      effects: effects,
      timestamp: DateTime.utc_now()
    }

    emit_telemetry(action, context, result)
    result
  rescue
    e ->
      Logger.error("[MCP-Θ Actions] Failed to execute #{action}: #{inspect(e)}")

      %{
        action: action,
        success: false,
        effects: [{:error, Exception.message(e)}],
        timestamp: DateTime.utc_now()
      }
  end

  @doc """
  Lists all available actions.
  """
  @spec available_actions() :: [action()]
  def available_actions do
    [:desync, :resync, :dampen, :boost, :safe_mode]
  end

  @doc """
  Describes what an action does.
  """
  @spec describe(action()) :: String.t()
  def describe(:desync), do: "Inject noise to break hypersynchronization"
  def describe(:resync), do: "Apply coherence signal to restore synchronization"
  def describe(:dampen), do: "Reduce propagation gain to prevent runaway"
  def describe(:boost), do: "Increase propagation gain to escape stagnation"
  def describe(:safe_mode), do: "Emergency halt with minimal processing"
  def describe(:none), do: "No action required"

  # ===========================================================================
  # Private: Action Implementations
  # ===========================================================================

  defp apply_action(:desync, context) do
    # Desync: Inject noise into attention weights
    # This breaks hypersynchronization by introducing diversity

    noise_level = calculate_noise_level(context.metrics.plv)

    effects = [
      {:attention_noise, noise_level},
      {:focus_jitter, noise_level * 0.5},
      {:temporal_shift, :randomize}
    ]

    apply_to_pac(context.pac_id, :desync, effects)
    effects
  end

  defp apply_action(:resync, context) do
    # Resync: Apply coherence signal
    # This restores synchronization when too chaotic

    coherence_strength = calculate_coherence_strength(context.metrics.plv)

    effects = [
      {:coherence_signal, coherence_strength},
      {:attention_align, :centroid},
      {:temporal_lock, :gradual}
    ]

    apply_to_pac(context.pac_id, :resync, effects)
    effects
  end

  defp apply_action(:dampen, context) do
    # Dampen: Reduce propagation coefficient
    # Prevents runaway activation propagation

    damping_factor = calculate_damping_factor(context.metrics.sigma)

    effects = [
      {:propagation_scale, damping_factor},
      {:activation_cap, 0.8},
      {:layer_skip_prob, 0.1}
    ]

    apply_to_pac(context.pac_id, :dampen, effects)
    effects
  end

  defp apply_action(:boost, context) do
    # Boost: Increase propagation coefficient
    # Escapes stagnation by amplifying signals

    boost_factor = calculate_boost_factor(context.metrics.sigma)

    effects = [
      {:propagation_scale, boost_factor},
      {:activation_floor, 0.1},
      {:layer_skip_prob, 0.0}
    ]

    apply_to_pac(context.pac_id, :boost, effects)
    effects
  end

  defp apply_action(:safe_mode, context) do
    # Safe Mode: Emergency measures
    # Triggered on positive Lyapunov exponent

    Logger.warning(
      "[MCP-Θ Actions] SAFE MODE activated for PAC #{context.pac_id}, " <>
        "λ=#{Float.round(context.metrics.lyapunov, 3)}"
    )

    effects = [
      {:processing_mode, :minimal},
      {:external_calls, :disabled},
      {:memory_writes, :disabled},
      {:tick_rate, :minimum},
      {:rollback_state, :last_stable}
    ]

    apply_to_pac(context.pac_id, :safe_mode, effects)
    emit_safe_mode_event(context)
    effects
  end

  defp apply_action(:none, _context) do
    []
  end

  # ===========================================================================
  # Private: Calculations
  # ===========================================================================

  defp calculate_noise_level(plv) do
    # More noise for higher PLV (more synchronized = more noise needed)
    # PLV of 0.6-0.7 -> low noise, 0.8-1.0 -> high noise
    cond do
      plv > 0.9 -> 0.5
      plv > 0.8 -> 0.3
      plv > 0.7 -> 0.2
      true -> 0.1
    end
  end

  defp calculate_coherence_strength(plv) do
    # More coherence for lower PLV (more chaotic = more coherence needed)
    # PLV of 0.0-0.1 -> high coherence, 0.2-0.3 -> low coherence
    cond do
      plv < 0.1 -> 0.8
      plv < 0.2 -> 0.5
      plv < 0.25 -> 0.3
      true -> 0.2
    end
  end

  defp calculate_damping_factor(sigma) do
    # Lower factor for higher sigma (more runaway = more damping)
    # Returns a multiplier < 1.0
    cond do
      sigma > 2.0 -> 0.5
      sigma > 1.5 -> 0.7
      sigma > 1.2 -> 0.85
      true -> 0.95
    end
  end

  defp calculate_boost_factor(sigma) do
    # Higher factor for lower sigma (more stagnant = more boost)
    # Returns a multiplier > 1.0
    cond do
      sigma < 0.3 -> 2.0
      sigma < 0.5 -> 1.5
      sigma < 0.7 -> 1.25
      true -> 1.1
    end
  end

  # ===========================================================================
  # Private: PAC Interface
  # ===========================================================================

  defp apply_to_pac(pac_id, action, effects) do
    # Apply effects to PAC configuration
    # This integrates with the PAC's runtime configuration system

    if Code.ensure_loaded?(Thunderline.Thunderpac.Runtime) do
      try do
        Thunderline.Thunderpac.Runtime.apply_mcp_action(pac_id, action, effects)
      rescue
        _ -> :ok
      end
    else
      # Log for debugging when Runtime not available
      Logger.debug("[MCP-Θ Actions] Would apply to PAC #{pac_id}: #{inspect(effects)}")
    end

    :ok
  end

  defp emit_safe_mode_event(context) do
    if Code.ensure_loaded?(Thunderline.Thunderflow.EventBus) do
      attrs = %{
        name: "crown.mcp_theta.safe_mode",
        source: :mcp_theta,
        priority: :critical,
        payload: %{
          pac_id: context.pac_id,
          metrics: context.metrics,
          reason: "positive_lyapunov",
          action: "emergency_halt"
        }
      }

      case Thunderline.Event.new(attrs) do
        {:ok, ev} ->
          Thunderline.Thunderflow.EventBus.publish_event(ev)

        {:error, _} ->
          :ok
      end
    end

    :ok
  end

  defp emit_telemetry(action, context, result) do
    :telemetry.execute(
      [:thunderline, :crown, :mcp_theta, :action],
      %{
        effect_count: length(result.effects),
        success: if(result.success, do: 1, else: 0)
      },
      %{
        pac_id: context.pac_id,
        action: action,
        metrics: context.metrics
      }
    )
  end
end
