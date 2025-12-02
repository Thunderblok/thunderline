defmodule Thunderline.Thundercrown.MCPTheta.Thresholds do
  @moduledoc """
  Configurable thresholds for near-critical dynamics regulation.

  Based on "Loop-Controlled Near-Critical Dynamics for LLMs" (2025), these
  thresholds define the optimal operating regime for PAC agents.

  ## Metric Bands

  ### PLV (Phase Locking Value)
  - Measures synchrony between attention heads / processing units
  - Range 0.0 to 1.0
  - Optimal: 0.30 - 0.60 (metastable thinking zone)
  - Too high (>0.60): Repetitive loops, collapse to fixed points
  - Too low (<0.30): Incoherent, rambling, unfocused

  ### σ (Propagation Coefficient)
  - Measures information flow between layers
  - Target: ~1.0 (edge of chaos)
  - σ < 1.0: Stagnant, ideas don't propagate
  - σ > 1.0: Runaway, hallucinations escalate

  ### λ̂ (Lyapunov Exponent)
  - Measures trajectory divergence (stability)
  - λ̂ ≤ 0: Stable thought paths converge
  - λ̂ > 0: Chaotic divergence, trigger safe mode
  """

  @type t :: %__MODULE__{
          plv_min: float(),
          plv_max: float(),
          sigma_target: float(),
          sigma_tolerance: float(),
          lyapunov_threshold: float(),
          measurement_window_ms: pos_integer(),
          regulation_cooldown_ms: pos_integer(),
          safe_mode_duration_ms: pos_integer()
        }

  defstruct plv_min: 0.30,
            plv_max: 0.60,
            sigma_target: 1.0,
            sigma_tolerance: 0.2,
            lyapunov_threshold: 0.0,
            measurement_window_ms: 500,
            regulation_cooldown_ms: 100,
            safe_mode_duration_ms: 5000

  @doc """
  Creates default thresholds for standard operation.
  """
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc """
  Creates conservative thresholds for sensitive contexts.
  Tighter PLV band, lower Lyapunov tolerance.
  """
  @spec conservative() :: t()
  def conservative do
    %__MODULE__{
      plv_min: 0.35,
      plv_max: 0.55,
      sigma_target: 1.0,
      sigma_tolerance: 0.15,
      lyapunov_threshold: -0.1,
      measurement_window_ms: 300,
      regulation_cooldown_ms: 50,
      safe_mode_duration_ms: 10_000
    }
  end

  @doc """
  Creates permissive thresholds for creative/exploratory contexts.
  Wider PLV band, higher Lyapunov tolerance.
  """
  @spec exploratory() :: t()
  def exploratory do
    %__MODULE__{
      plv_min: 0.20,
      plv_max: 0.70,
      sigma_target: 1.1,
      sigma_tolerance: 0.3,
      lyapunov_threshold: 0.1,
      measurement_window_ms: 1000,
      regulation_cooldown_ms: 200,
      safe_mode_duration_ms: 3000
    }
  end

  @doc """
  Loads thresholds from application config.
  """
  @spec from_config() :: t()
  def from_config do
    config = Application.get_env(:thunderline, :mcp_theta, [])

    %__MODULE__{
      plv_min: Keyword.get(config, :plv_min, 0.30),
      plv_max: Keyword.get(config, :plv_max, 0.60),
      sigma_target: Keyword.get(config, :sigma_target, 1.0),
      sigma_tolerance: Keyword.get(config, :sigma_tolerance, 0.2),
      lyapunov_threshold: Keyword.get(config, :lyapunov_threshold, 0.0),
      measurement_window_ms: Keyword.get(config, :measurement_window_ms, 500),
      regulation_cooldown_ms: Keyword.get(config, :regulation_cooldown_ms, 100),
      safe_mode_duration_ms: Keyword.get(config, :safe_mode_duration_ms, 5000)
    }
  end

  # ===========================================================================
  # Threshold Checks
  # ===========================================================================

  @doc """
  Checks if PLV is within the healthy band.
  """
  @spec plv_healthy?(t(), float()) :: boolean()
  def plv_healthy?(%__MODULE__{plv_min: min, plv_max: max}, plv) do
    plv >= min and plv <= max
  end

  @doc """
  Returns PLV status: :low, :healthy, or :high
  """
  @spec plv_status(t(), float()) :: :low | :healthy | :high
  def plv_status(%__MODULE__{plv_min: min, plv_max: max}, plv) do
    cond do
      plv < min -> :low
      plv > max -> :high
      true -> :healthy
    end
  end

  @doc """
  Checks if sigma is within tolerance of target.
  """
  @spec sigma_healthy?(t(), float()) :: boolean()
  def sigma_healthy?(%__MODULE__{sigma_target: target, sigma_tolerance: tol}, sigma) do
    abs(sigma - target) <= tol
  end

  @doc """
  Returns sigma status: :stagnant, :healthy, or :runaway
  """
  @spec sigma_status(t(), float()) :: :stagnant | :healthy | :runaway
  def sigma_status(%__MODULE__{sigma_target: target, sigma_tolerance: tol}, sigma) do
    cond do
      sigma < target - tol -> :stagnant
      sigma > target + tol -> :runaway
      true -> :healthy
    end
  end

  @doc """
  Checks if Lyapunov exponent indicates stability.
  """
  @spec lyapunov_stable?(t(), float()) :: boolean()
  def lyapunov_stable?(%__MODULE__{lyapunov_threshold: threshold}, lyapunov) do
    lyapunov <= threshold
  end

  @doc """
  Returns overall system regime based on all metrics.
  """
  @spec regime(t(), map()) :: :healthy | :unstable | :critical
  def regime(thresholds, %{plv: plv, sigma: sigma, lyapunov: lyapunov}) do
    cond do
      not lyapunov_stable?(thresholds, lyapunov) ->
        :critical

      not plv_healthy?(thresholds, plv) or not sigma_healthy?(thresholds, sigma) ->
        :unstable

      true ->
        :healthy
    end
  end
end
