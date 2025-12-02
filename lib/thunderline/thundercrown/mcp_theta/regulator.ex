defmodule Thunderline.Thundercrown.MCPTheta.Regulator do
  @moduledoc """
  MCP-Θ Regulator for Thunderbeat pacing and corrective actions.

  The Regulator consumes metrics from the Monitor and adjusts the system's
  tempo to maintain near-critical dynamics. When metrics deviate from the
  optimal zone, the Regulator applies corrective actions.

  ## Control Loop

  1. Monitor reports metrics (PLV, σ, λ̂)
  2. Regulator evaluates against thresholds
  3. Appropriate action is selected and applied
  4. Thunderbeat pace is adjusted

  ## Actions

  - **:desync** - Reduce PLV when too synchronized (PLV > 0.6)
  - **:resync** - Increase PLV when too chaotic (PLV < 0.3)
  - **:dampen** - Reduce σ when runaway propagation (σ > 1.2)
  - **:boost** - Increase σ when stagnant (σ < 0.8)
  - **:safe_mode** - Emergency halt on positive λ̂

  ## Thunderbeat Pacing

  The Regulator adjusts Thunderbeat tempo:
  - Normal: 2000ms base tick
  - Unstable: Slower ticks to stabilize
  - Critical: Maximum slowdown + safe mode
  """

  use GenServer

  require Logger

  alias Thunderline.Thundercrown.MCPTheta.{Monitor, Thresholds, Actions}

  @type action :: :none | :desync | :resync | :dampen | :boost | :safe_mode
  @type pace_mode :: :normal | :cautious | :stabilizing | :emergency

  @type state :: %{
          pac_id: String.t(),
          monitor_pid: pid() | nil,
          thresholds: Thresholds.t(),
          current_pace: pos_integer(),
          base_pace: pos_integer(),
          pace_mode: pace_mode(),
          last_action: action(),
          action_history: list(),
          cooldown_until: DateTime.t() | nil,
          enabled?: boolean()
        }

  @default_pace 2000
  @min_pace 500
  @max_pace 10_000
  @action_cooldown_ms 5_000

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts a Regulator for a specific PAC agent.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    pac_id = Keyword.get(opts, :pac_id, "default")
    name = Keyword.get(opts, :name, via_name(pac_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets current pacing configuration.
  """
  @spec get_pace(GenServer.server()) :: {:ok, pos_integer()}
  def get_pace(regulator) do
    GenServer.call(regulator, :get_pace)
  end

  @doc """
  Gets current pace mode.
  """
  @spec get_pace_mode(GenServer.server()) :: {:ok, pace_mode()}
  def get_pace_mode(regulator) do
    GenServer.call(regulator, :get_pace_mode)
  end

  @doc """
  Forces an immediate regulation cycle.
  """
  @spec regulate_now(GenServer.server()) :: :ok
  def regulate_now(regulator) do
    GenServer.cast(regulator, :regulate_now)
  end

  @doc """
  Enables or disables the regulator.
  """
  @spec set_enabled(GenServer.server(), boolean()) :: :ok
  def set_enabled(regulator, enabled?) do
    GenServer.cast(regulator, {:set_enabled, enabled?})
  end

  @doc """
  Gets action history.
  """
  @spec get_action_history(GenServer.server()) :: {:ok, list()}
  def get_action_history(regulator) do
    GenServer.call(regulator, :get_action_history)
  end

  @doc """
  Resets the regulator to default state.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(regulator) do
    GenServer.cast(regulator, :reset)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    pac_id = Keyword.get(opts, :pac_id, "default")
    base_pace = Keyword.get(opts, :base_pace, @default_pace)
    thresholds = Keyword.get(opts, :thresholds, Thresholds.default())

    state = %{
      pac_id: pac_id,
      monitor_pid: nil,
      thresholds: thresholds,
      current_pace: base_pace,
      base_pace: base_pace,
      pace_mode: :normal,
      last_action: :none,
      action_history: [],
      cooldown_until: nil,
      enabled?: true
    }

    # Schedule periodic regulation
    schedule_regulation()

    Logger.info("[MCP-Θ Regulator] Started for PAC #{pac_id}")
    emit_telemetry(:init, state)

    {:ok, state}
  end

  @impl true
  def handle_cast(:regulate_now, state) do
    new_state = run_regulation_cycle(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_enabled, enabled?}, state) do
    Logger.info("[MCP-Θ Regulator] #{if enabled?, do: "Enabled", else: "Disabled"} for PAC #{state.pac_id}")
    {:noreply, %{state | enabled?: enabled?}}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | current_pace: state.base_pace,
        pace_mode: :normal,
        last_action: :none,
        action_history: [],
        cooldown_until: nil
    }

    Logger.info("[MCP-Θ Regulator] Reset for PAC #{state.pac_id}")
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_pace, _from, state) do
    {:reply, {:ok, state.current_pace}, state}
  end

  @impl true
  def handle_call(:get_pace_mode, _from, state) do
    {:reply, {:ok, state.pace_mode}, state}
  end

  @impl true
  def handle_call(:get_action_history, _from, state) do
    {:reply, {:ok, state.action_history}, state}
  end

  @impl true
  def handle_info(:regulate, state) do
    new_state =
      if state.enabled? do
        run_regulation_cycle(state)
      else
        state
      end

    schedule_regulation()
    {:noreply, new_state}
  end

  # ===========================================================================
  # Private: Regulation Logic
  # ===========================================================================

  defp run_regulation_cycle(state) do
    # Check cooldown
    if in_cooldown?(state) do
      state
    else
      case get_monitor_metrics(state.pac_id) do
        {:ok, metrics} ->
          regulate(state, metrics)

        {:error, _reason} ->
          # Monitor not available, maintain current pace
          state
      end
    end
  end

  defp regulate(state, metrics) do
    # Determine action based on metrics
    action = select_action(state.thresholds, metrics)

    if action != :none do
      apply_action(state, action, metrics)
    else
      # Gradually return to normal pace
      normalize_pace(state)
    end
  end

  defp select_action(thresholds, metrics) do
    plv = Map.get(metrics, :plv, 0.45)
    sigma = Map.get(metrics, :sigma, 1.0)
    lambda = Map.get(metrics, :lyapunov, 0.0)
    looping? = Map.get(metrics, :looping?, false)

    cond do
      # Critical: Positive Lyapunov exponent
      not Thresholds.lyapunov_stable?(thresholds, lambda) ->
        :safe_mode

      # PLV too high - hypersync
      plv > thresholds.plv.max ->
        :desync

      # PLV too low - chaos
      plv < thresholds.plv.min ->
        :resync

      # Sigma too high - runaway propagation
      sigma > thresholds.sigma.max ->
        :dampen

      # Sigma too low - stagnation
      sigma < thresholds.sigma.min ->
        :boost

      # Loop detected - needs desync
      looping? ->
        :desync

      # All metrics healthy
      true ->
        :none
    end
  end

  defp apply_action(state, action, metrics) do
    Logger.info(
      "[MCP-Θ Regulator] Applying #{action} for PAC #{state.pac_id}: " <>
        "PLV=#{Float.round(metrics.plv, 2)}, σ=#{Float.round(metrics.sigma, 2)}, λ=#{Float.round(metrics.lyapunov, 3)}"
    )

    # Execute the action
    action_result = Actions.execute(action, %{pac_id: state.pac_id, metrics: metrics})

    # Adjust pace based on action
    {new_pace, new_mode} = adjust_pace(state, action)

    # Record in history
    history_entry = %{
      action: action,
      timestamp: DateTime.utc_now(),
      metrics: metrics,
      result: action_result,
      new_pace: new_pace
    }

    new_state = %{
      state
      | current_pace: new_pace,
        pace_mode: new_mode,
        last_action: action,
        action_history: Enum.take([history_entry | state.action_history], 100),
        cooldown_until: DateTime.add(DateTime.utc_now(), @action_cooldown_ms, :millisecond)
    }

    emit_telemetry(:action, new_state, %{action: action})
    emit_event(:action_applied, new_state, action, metrics)

    new_state
  end

  defp adjust_pace(state, action) do
    case action do
      :safe_mode ->
        {@max_pace, :emergency}

      :dampen ->
        # Slow down significantly
        new_pace = min(state.current_pace * 1.5, @max_pace) |> round()
        {new_pace, :stabilizing}

      :boost ->
        # Speed up carefully
        new_pace = max(state.current_pace * 0.8, @min_pace) |> round()
        {new_pace, :cautious}

      :desync ->
        # Moderate slowdown
        new_pace = min(state.current_pace * 1.2, @max_pace) |> round()
        {new_pace, :stabilizing}

      :resync ->
        # Slight speedup
        new_pace = max(state.current_pace * 0.9, @min_pace) |> round()
        {new_pace, :cautious}

      :none ->
        {state.current_pace, state.pace_mode}
    end
  end

  defp normalize_pace(state) do
    case state.pace_mode do
      :normal ->
        state

      :emergency ->
        # Stay in emergency until explicitly reset
        state

      _other ->
        # Gradually return to base pace
        if state.current_pace != state.base_pace do
          step = (state.base_pace - state.current_pace) / 5
          new_pace = round(state.current_pace + step)

          new_mode =
            if abs(new_pace - state.base_pace) < 100 do
              :normal
            else
              :cautious
            end

          %{state | current_pace: new_pace, pace_mode: new_mode}
        else
          %{state | pace_mode: :normal}
        end
    end
  end

  # ===========================================================================
  # Private: Utilities
  # ===========================================================================

  defp schedule_regulation do
    Process.send_after(self(), :regulate, 1000)
  end

  defp in_cooldown?(%{cooldown_until: nil}), do: false

  defp in_cooldown?(%{cooldown_until: until}) do
    DateTime.compare(DateTime.utc_now(), until) == :lt
  end

  defp get_monitor_metrics(pac_id) do
    try do
      Monitor.get_metrics({:via, Registry, {Thunderline.Registry, {Monitor, pac_id}}})
    catch
      :exit, _ -> {:error, :monitor_not_found}
    end
  end

  defp via_name(pac_id) do
    {:via, Registry, {Thunderline.Registry, {__MODULE__, pac_id}}}
  end

  defp emit_event(event, state, action, metrics) do
    if Code.ensure_loaded?(Thunderline.Thunderflow.EventBus) do
      attrs = %{
        name: "crown.mcp_theta.#{event}",
        source: :mcp_theta,
        payload: %{
          pac_id: state.pac_id,
          action: action,
          metrics: metrics,
          pace: state.current_pace,
          pace_mode: state.pace_mode
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

  defp emit_telemetry(event, state, extra \\ %{}) do
    :telemetry.execute(
      [:thunderline, :crown, :mcp_theta, :regulator, event],
      %{
        pace: state.current_pace,
        base_pace: state.base_pace
      },
      Map.merge(
        %{
          pac_id: state.pac_id,
          pace_mode: state.pace_mode,
          enabled: state.enabled?
        },
        extra
      )
    )
  end
end
