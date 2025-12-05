defmodule Thunderline.Telemetry.IRoPE do
  @moduledoc """
  iRoPE (Interleaved Rotary Position Embedding) Intervention System.

  Implements the Cinderforge Lab paper's intervention mechanism for
  breaking degenerate loops in transformer-like systems.

  ## Concepts

  - **Stern Mode**: Aggressive frequency decay when loops are detected
  - **Phase Bias**: Adds offset to break phase-locked behavior
  - **Frequency Notch**: Reduces specific frequency bands causing loops

  ## Usage

      # Apply phase bias to domain state
      new_state = IRoPE.apply_phase_bias(state, delta: 0.1)

      # Enter stern mode (aggressive loop breaking)
      new_state = IRoPE.stern_mode(state)

      # Compute intervention strength based on PLV
      strength = IRoPE.compute_strength(plv: 0.95)

  ## Integration with LoopMonitor

      LoopMonitor.register_intervention(:ml_pipeline, fn action, state ->
        case action do
          :apply_phase_bias -> IRoPE.apply_phase_bias(state)
          :stern_mode -> IRoPE.stern_mode(state)
          :throttle -> IRoPE.throttle(state)
          _ -> state
        end
      end)
  """

  require Logger

  # Default intervention parameters
  @default_omega_decay 0.9
  @default_phase_bias 0.1
  @stern_mode_omega_decay 0.7
  @stern_mode_phase_bias 0.3
  @min_omega 0.1
  @max_phase 1.0

  # Frequency notch parameters
  @notch_width 0.1
  @notch_depth 0.5

  @doc """
  Apply phase bias to break loop synchronization.

  Adds a small phase offset to the internal state, disrupting
  phase-locked behavior without causing instability.

  ## Parameters

  - `state`: Map with :omega and :phi fields (or creates them)
  - `opts`:
    - `:delta` - Phase bias amount (default: 0.1)
    - `:decay` - Omega decay factor (default: 0.9)

  ## Returns

  Updated state map with modified omega and phi
  """
  @spec apply_phase_bias(map(), keyword()) :: map()
  def apply_phase_bias(state, opts \\ []) do
    delta = Keyword.get(opts, :delta, @default_phase_bias)
    decay = Keyword.get(opts, :decay, @default_omega_decay)

    omega = Map.get(state, :omega, 1.0)
    phi = Map.get(state, :phi, 0.0)

    # Apply decay and bias
    new_omega = max(omega * decay, @min_omega)
    new_phi = rem_float(phi + delta, @max_phase)

    Logger.debug(
      "[IRoPE] Phase bias applied: omega #{omega} -> #{new_omega}, phi #{phi} -> #{new_phi}"
    )

    state
    |> Map.put(:omega, new_omega)
    |> Map.put(:phi, new_phi)
    |> Map.put(:irope_applied, DateTime.utc_now())
    |> Map.put(:irope_action, :phase_bias)
  end

  @doc """
  Enter stern mode for aggressive loop breaking.

  Used when standard phase bias is insufficient. Applies stronger
  frequency decay and larger phase shifts.

  ## Parameters

  - `state`: Current domain state
  - `opts`:
    - `:duration_ticks` - How long to maintain stern mode (default: 10)

  ## Returns

  Updated state with stern mode active
  """
  @spec stern_mode(map(), keyword()) :: map()
  def stern_mode(state, opts \\ []) do
    duration = Keyword.get(opts, :duration_ticks, 10)

    omega = Map.get(state, :omega, 1.0)
    phi = Map.get(state, :phi, 0.0)

    # Aggressive decay and large phase jump
    new_omega = max(omega * @stern_mode_omega_decay, @min_omega)
    new_phi = rem_float(phi + @stern_mode_phase_bias + :rand.uniform() * 0.1, @max_phase)

    Logger.info("[IRoPE] STERN MODE: omega #{omega} -> #{new_omega}, phi #{phi} -> #{new_phi}")

    state
    |> Map.put(:omega, new_omega)
    |> Map.put(:phi, new_phi)
    |> Map.put(:stern_mode, true)
    |> Map.put(:stern_mode_until, Map.get(state, :tick, 0) + duration)
    |> Map.put(:irope_applied, DateTime.utc_now())
    |> Map.put(:irope_action, :stern_mode)
  end

  @doc """
  Apply frequency notch filter to suppress specific frequencies.

  Reduces amplitude in frequency bands that are contributing to loops.

  ## Parameters

  - `activations`: Nx tensor of activations
  - `opts`:
    - `:center` - Center frequency of notch (0.0-1.0)
    - `:width` - Width of notch (default: 0.1)
    - `:depth` - Attenuation depth (default: 0.5)

  ## Returns

  Modified activations tensor
  """
  @spec frequency_notch(Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def frequency_notch(activations, opts \\ []) do
    center = Keyword.get(opts, :center, 0.5)
    width = Keyword.get(opts, :width, @notch_width)
    depth = Keyword.get(opts, :depth, @notch_depth)

    # Create notch filter mask
    {_batch, seq_len} = Nx.shape(activations)
    frequencies = Nx.linspace(0, 1, n: seq_len)

    # Gaussian notch centered at `center`
    notch =
      Nx.exp(Nx.negate(Nx.divide(Nx.pow(Nx.subtract(frequencies, center), 2), 2 * width * width)))

    attenuation = Nx.subtract(1.0, Nx.multiply(notch, depth))

    # Apply notch to activations
    Nx.multiply(activations, attenuation)
  end

  @doc """
  Throttle processing to reduce signal amplification.

  Returns parameters for reducing batch size or processing rate.

  ## Parameters

  - `state`: Current domain state
  - `opts`:
    - `:factor` - Throttle factor (default: 0.5)

  ## Returns

  Updated state with throttle parameters
  """
  @spec throttle(map(), keyword()) :: map()
  def throttle(state, opts \\ []) do
    factor = Keyword.get(opts, :factor, 0.5)

    current_rate = Map.get(state, :processing_rate, 1.0)
    new_rate = max(current_rate * factor, 0.1)

    Logger.info("[IRoPE] Throttle: rate #{current_rate} -> #{new_rate}")

    state
    |> Map.put(:processing_rate, new_rate)
    |> Map.put(:throttled, true)
    |> Map.put(:irope_applied, DateTime.utc_now())
    |> Map.put(:irope_action, :throttle)
  end

  @doc """
  Boost processing when signal is decaying.

  Opposite of throttle - increases processing rate to prevent collapse.

  ## Parameters

  - `state`: Current domain state
  - `opts`:
    - `:factor` - Boost factor (default: 1.5)

  ## Returns

  Updated state with boosted parameters
  """
  @spec boost(map(), keyword()) :: map()
  def boost(state, opts \\ []) do
    factor = Keyword.get(opts, :factor, 1.5)

    current_rate = Map.get(state, :processing_rate, 1.0)
    new_rate = min(current_rate * factor, 2.0)

    omega = Map.get(state, :omega, 1.0)
    new_omega = min(omega * 1.1, 1.0)

    Logger.info("[IRoPE] Boost: rate #{current_rate} -> #{new_rate}, omega -> #{new_omega}")

    state
    |> Map.put(:processing_rate, new_rate)
    |> Map.put(:omega, new_omega)
    |> Map.put(:irope_applied, DateTime.utc_now())
    |> Map.put(:irope_action, :boost)
  end

  @doc """
  Stabilize chaotic dynamics by reducing sensitivity.

  Applied when λ̂ > 0 indicates expanding/chaotic behavior.

  ## Parameters

  - `state`: Current domain state

  ## Returns

  Updated state with stabilization applied
  """
  @spec stabilize(map()) :: map()
  def stabilize(state) do
    omega = Map.get(state, :omega, 1.0)

    # Reduce omega to contract dynamics
    new_omega = max(omega * 0.8, @min_omega)

    # Add small random perturbation to break chaotic attractor
    noise = :rand.uniform() * 0.05
    phi = Map.get(state, :phi, 0.0)
    new_phi = rem_float(phi + noise, @max_phase)

    Logger.info("[IRoPE] Stabilize: omega -> #{new_omega}, adding noise")

    state
    |> Map.put(:omega, new_omega)
    |> Map.put(:phi, new_phi)
    |> Map.put(:irope_applied, DateTime.utc_now())
    |> Map.put(:irope_action, :stabilize)
  end

  @doc """
  Compute intervention strength based on observables.

  Higher PLV, sigma deviation, or lambda values result in stronger intervention.

  ## Parameters

  - `opts`:
    - `:plv` - Phase Locking Value (0-1)
    - `:sigma` - Propagation ratio
    - `:lambda` - FTLE estimate

  ## Returns

  Float in [0, 1] indicating intervention strength
  """
  @spec compute_strength(keyword()) :: float()
  def compute_strength(opts) do
    plv = Keyword.get(opts, :plv, 0.5)
    sigma = Keyword.get(opts, :sigma, 1.0)
    lambda = Keyword.get(opts, :lambda, 0.0)

    # PLV contribution (higher PLV = stronger intervention)
    plv_contrib = if plv > 0.6, do: (plv - 0.6) / 0.4, else: 0.0

    # Sigma contribution (deviation from 1.0)
    sigma_contrib = abs(sigma - 1.0)

    # Lambda contribution (positive lambda = chaotic)
    lambda_contrib = max(lambda, 0.0)

    # Weighted combination
    strength = 0.5 * plv_contrib + 0.3 * sigma_contrib + 0.2 * lambda_contrib

    min(strength, 1.0)
  end

  @doc """
  Check if stern mode should be exited.

  ## Parameters

  - `state`: Current domain state with stern mode active

  ## Returns

  `true` if stern mode should end, `false` otherwise
  """
  @spec should_exit_stern_mode?(map()) :: boolean()
  def should_exit_stern_mode?(state) do
    cond do
      not Map.get(state, :stern_mode, false) ->
        false

      Map.get(state, :tick, 0) >= Map.get(state, :stern_mode_until, 0) ->
        true

      # Exit early if PLV drops back to healthy range
      Map.get(state, :plv, 0.5) < 0.6 ->
        true

      true ->
        false
    end
  end

  @doc """
  Exit stern mode and restore normal operation.

  ## Parameters

  - `state`: Current domain state

  ## Returns

  State with stern mode deactivated
  """
  @spec exit_stern_mode(map()) :: map()
  def exit_stern_mode(state) do
    Logger.info("[IRoPE] Exiting stern mode")

    state
    |> Map.put(:stern_mode, false)
    |> Map.delete(:stern_mode_until)
  end

  @doc """
  Create a default intervention callback for LoopMonitor registration.

  Returns a function that handles all standard intervention types.
  """
  @spec default_intervention_callback() :: (atom(), map() -> map())
  def default_intervention_callback do
    fn action, state ->
      case action do
        :apply_phase_bias ->
          apply_phase_bias(state)

        :stern_mode ->
          stern_mode(state)

        :throttle ->
          throttle(state)

        :boost ->
          boost(state)

        :stabilize ->
          stabilize(state)

        _ ->
          Logger.warning("[IRoPE] Unknown action: #{action}")
          state
      end
    end
  end

  # Private helpers

  defp rem_float(a, b) when is_float(a) and is_float(b) do
    a - Float.floor(a / b) * b
  end

  defp rem_float(a, b) do
    rem_float(a / 1.0, b / 1.0)
  end
end
