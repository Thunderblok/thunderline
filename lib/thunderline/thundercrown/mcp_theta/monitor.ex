defmodule Thunderline.Thundercrown.MCPTheta.Monitor do
  @moduledoc """
  Runtime monitor for near-critical dynamics metrics (PLV, σ, λ̂).

  The MCP-Θ (Meta-Critical Poise) Monitor continuously measures the three
  key criticality metrics and reports system health to the Regulator.

  ## Metrics Monitored

  - **PLV** (Phase Locking Value): Attention synchrony [0-1]
  - **σ** (Sigma): Propagation coefficient [0.5-2.0]
  - **λ̂** (Lambda): Lyapunov exponent [-∞, +∞]

  ## Architecture

  The Monitor runs as a GenServer that:
  1. Receives activation/attention samples from PAC components
  2. Updates streaming estimators for each metric
  3. Publishes measurements to the EventBus
  4. Triggers Regulator actions on threshold violations

  ## Usage

      {:ok, pid} = Monitor.start_link(pac_id: "agent_001")
      Monitor.sample(pid, :attention, %{weights: [0.1, 0.2, 0.7]})
      Monitor.sample(pid, :activation, [0.5, -0.2, 0.8])
      {:ok, metrics} = Monitor.get_metrics(pid)
  """

  use GenServer

  require Logger

  alias Thunderline.Thundercrown.MCPTheta.Thresholds
  alias Thunderline.Thunderbolt.Criticality.{PLVEstimator, Propagation, Lyapunov, LoopDetector}

  @type metric_type :: :plv | :sigma | :lyapunov
  @type sample_type :: :attention | :activation | :trajectory

  @type state :: %{
          pac_id: String.t(),
          thresholds: Thresholds.t(),
          plv_state: map(),
          sigma_state: map(),
          lyapunov_state: map(),
          loop_state: map(),
          current_metrics: map(),
          last_measurement: DateTime.t() | nil,
          measurement_count: non_neg_integer(),
          regime: :healthy | :unstable | :critical,
          safe_mode?: boolean()
        }

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts a Monitor process for a specific PAC agent.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    pac_id = Keyword.get(opts, :pac_id, "default")
    name = Keyword.get(opts, :name, via_name(pac_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submits a sample to the monitor for analysis.

  ## Parameters

  - `monitor` - PID or name of monitor
  - `type` - Sample type: `:attention`, `:activation`, or `:trajectory`
  - `data` - Sample data (format depends on type)

  ## Examples

      Monitor.sample(pid, :attention, %{weights: [0.1, 0.2, 0.7]})
      Monitor.sample(pid, :activation, [0.5, -0.2, 0.8])
      Monitor.sample(pid, :trajectory, %{state: [1.0, 2.0], time: now})
  """
  @spec sample(GenServer.server(), sample_type(), any()) :: :ok
  def sample(monitor, type, data) do
    GenServer.cast(monitor, {:sample, type, data, System.monotonic_time(:microsecond)})
  end

  @doc """
  Gets current metric values.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, map()}
  def get_metrics(monitor) do
    GenServer.call(monitor, :get_metrics)
  end

  @doc """
  Gets current system regime.
  """
  @spec get_regime(GenServer.server()) :: {:ok, atom()}
  def get_regime(monitor) do
    GenServer.call(monitor, :get_regime)
  end

  @doc """
  Checks if safe mode is active.
  """
  @spec safe_mode?(GenServer.server()) :: boolean()
  def safe_mode?(monitor) do
    GenServer.call(monitor, :safe_mode?)
  end

  @doc """
  Resets monitor state.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(monitor) do
    GenServer.cast(monitor, :reset)
  end

  @doc """
  Updates thresholds.
  """
  @spec set_thresholds(GenServer.server(), Thresholds.t()) :: :ok
  def set_thresholds(monitor, thresholds) do
    GenServer.cast(monitor, {:set_thresholds, thresholds})
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    pac_id = Keyword.get(opts, :pac_id, "default")
    thresholds = Keyword.get(opts, :thresholds, Thresholds.default())

    state = %{
      pac_id: pac_id,
      thresholds: thresholds,
      plv_state: PLVEstimator.stream_init(),
      sigma_state: Propagation.stream_init(),
      lyapunov_state: Lyapunov.stream_init(),
      loop_state: LoopDetector.stream_init(),
      current_metrics: %{
        plv: 0.45,
        sigma: 1.0,
        lyapunov: 0.0,
        looping?: false
      },
      last_measurement: nil,
      measurement_count: 0,
      regime: :healthy,
      safe_mode?: false
    }

    Logger.info("[MCP-Θ Monitor] Started for PAC #{pac_id}")
    emit_telemetry(:init, state)

    {:ok, state}
  end

  @impl true
  def handle_cast({:sample, type, data, timestamp}, state) do
    new_state = process_sample(state, type, data, timestamp)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | plv_state: PLVEstimator.stream_init(),
        sigma_state: Propagation.stream_init(),
        lyapunov_state: Lyapunov.stream_init(),
        loop_state: LoopDetector.stream_init(),
        current_metrics: %{plv: 0.45, sigma: 1.0, lyapunov: 0.0, looping?: false},
        measurement_count: 0,
        regime: :healthy,
        safe_mode?: false
    }

    Logger.info("[MCP-Θ Monitor] Reset for PAC #{state.pac_id}")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_thresholds, thresholds}, state) do
    # Re-evaluate regime with new thresholds
    new_regime = Thresholds.regime(thresholds, state.current_metrics)
    new_state = %{state | thresholds: thresholds, regime: new_regime}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.current_metrics}, state}
  end

  @impl true
  def handle_call(:get_regime, _from, state) do
    {:reply, {:ok, state.regime}, state}
  end

  @impl true
  def handle_call(:safe_mode?, _from, state) do
    {:reply, state.safe_mode?, state}
  end

  # ===========================================================================
  # Private: Sample Processing
  # ===========================================================================

  defp process_sample(state, :attention, data, _timestamp) do
    # Update PLV estimator
    {plv, new_plv_state} = PLVEstimator.stream_update(state.plv_state, data)

    # Update loop detector with attention focus
    focus = extract_focus(data)
    {loop_result, new_loop_state} = LoopDetector.stream_update(state.loop_state, focus)

    update_metrics(state, %{
      plv_state: new_plv_state,
      loop_state: new_loop_state,
      current_metrics:
        Map.merge(state.current_metrics, %{
          plv: plv,
          looping?: loop_result.looping?
        })
    })
  end

  defp process_sample(state, :activation, data, _timestamp) do
    # Update sigma estimator
    activation = normalize_activation(data)
    {sigma, new_sigma_state} = Propagation.stream_update(state.sigma_state, activation)

    update_metrics(state, %{
      sigma_state: new_sigma_state,
      current_metrics: Map.put(state.current_metrics, :sigma, sigma)
    })
  end

  defp process_sample(state, :trajectory, data, _timestamp) do
    # Update Lyapunov estimator
    {lambda, new_lyapunov_state} = Lyapunov.stream_update(state.lyapunov_state, data)

    update_metrics(state, %{
      lyapunov_state: new_lyapunov_state,
      current_metrics: Map.put(state.current_metrics, :lyapunov, lambda)
    })
  end

  defp process_sample(state, _unknown_type, _data, _timestamp) do
    state
  end

  defp update_metrics(state, updates) do
    new_state = Map.merge(state, updates)

    # Evaluate regime
    new_regime = Thresholds.regime(new_state.thresholds, new_state.current_metrics)
    prev_regime = state.regime

    new_state = %{
      new_state
      | regime: new_regime,
        measurement_count: state.measurement_count + 1,
        last_measurement: DateTime.utc_now()
    }

    # Handle regime transitions
    new_state =
      cond do
        new_regime == :critical and prev_regime != :critical ->
          Logger.warning(
            "[MCP-Θ Monitor] CRITICAL regime detected for PAC #{state.pac_id}: " <>
              "λ=#{Float.round(new_state.current_metrics.lyapunov, 3)}"
          )

          emit_event(:regime_critical, new_state)
          %{new_state | safe_mode?: true}

        new_regime == :unstable and prev_regime == :healthy ->
          Logger.info(
            "[MCP-Θ Monitor] Unstable regime for PAC #{state.pac_id}: " <>
              "PLV=#{Float.round(new_state.current_metrics.plv, 2)}, " <>
              "σ=#{Float.round(new_state.current_metrics.sigma, 2)}"
          )

          emit_event(:regime_unstable, new_state)
          new_state

        new_regime == :healthy and prev_regime != :healthy ->
          Logger.info("[MCP-Θ Monitor] Recovered to healthy regime for PAC #{state.pac_id}")
          emit_event(:regime_healthy, new_state)
          %{new_state | safe_mode?: false}

        true ->
          new_state
      end

    # Periodic telemetry
    if rem(new_state.measurement_count, 10) == 0 do
      emit_telemetry(:metrics, new_state)
    end

    new_state
  end

  # ===========================================================================
  # Private: Utilities
  # ===========================================================================

  defp via_name(pac_id) do
    {:via, Registry, {Thunderline.Registry, {__MODULE__, pac_id}}}
  end

  defp extract_focus(%{focus_score: score}), do: score
  defp extract_focus(%{weights: weights}) when is_list(weights), do: Enum.max(weights, fn -> 0.5 end)
  defp extract_focus(_), do: 0.5

  defp normalize_activation(data) when is_list(data), do: data
  defp normalize_activation(%{values: v}), do: v
  defp normalize_activation(_), do: [0.0]

  defp emit_event(event, state) do
    # Publish to EventBus if available
    if Code.ensure_loaded?(Thunderline.Thunderflow.EventBus) do
      attrs = %{
        name: "crown.mcp_theta.#{event}",
        source: :mcp_theta,
        payload: %{
          pac_id: state.pac_id,
          metrics: state.current_metrics,
          regime: state.regime,
          safe_mode?: state.safe_mode?
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

  defp emit_telemetry(event, state) do
    :telemetry.execute(
      [:thunderline, :crown, :mcp_theta, event],
      %{
        plv: state.current_metrics.plv,
        sigma: state.current_metrics.sigma,
        lyapunov: state.current_metrics.lyapunov,
        measurement_count: state.measurement_count
      },
      %{
        pac_id: state.pac_id,
        regime: state.regime,
        safe_mode: state.safe_mode?
      }
    )
  end
end
