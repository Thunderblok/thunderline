defmodule Thunderline.Thundercore.Reward.DelayedGratificationDetector do
  @moduledoc """
  DelayedGratificationDetector — Detects "dip-then-recover" patterns in reward signals.

  From the bubble sort research (Lex/Friedman "Learning to Be Efficient"):
  Some algorithms exhibit "delayed gratification" behavior — temporary performance
  dips that enable later improvements. Bubble sort's far swaps create short-term
  disorder that leads to faster overall sorting.

  ## Detection Heuristic

  A delayed gratification event is detected when:
  1. Reward drops below baseline by more than `dip_threshold`
  2. Reward stays depressed for at least `min_dip_ticks`
  3. Reward recovers above baseline within `max_recovery_ticks`

  ```
  reward
    ^
    |      ___________
    |     /           \
    | ___/             \___  <- baseline
    |                      \
    |                       \_____  <- dip
    |                              \____/  <- recovery
    +---------------------------------> tick
         ^start     ^bottom    ^recover
  ```

  ## Telemetry

  Emits `[:thundercore, :reward, :delayed_gratification]` when detected.

  ## Reference

  - Lex/Friedman "Learning to Be Efficient" (2023)
  - HC Orders: Operation TIGER LATTICE, Doctrine Layer
  """

  require Logger

  @telemetry_event [:thundercore, :reward, :delayed_gratification]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type gratification_event :: %{
          tick_start: non_neg_integer(),
          tick_bottom: non_neg_integer(),
          tick_recover: non_neg_integer(),
          depth: float(),
          duration: non_neg_integer(),
          baseline: float(),
          recovered_to: float()
        }

  @type detection_result ::
          {:gratification, gratification_event()}
          | :none
          | {:in_progress, map()}

  @type detector_config :: %{
          dip_threshold: float(),
          min_dip_ticks: non_neg_integer(),
          max_recovery_ticks: non_neg_integer(),
          baseline_window: non_neg_integer(),
          recovery_margin: float()
        }

  # ═══════════════════════════════════════════════════════════════
  # Default Configuration
  # ═══════════════════════════════════════════════════════════════

  @default_config %{
    dip_threshold: 0.15,
    min_dip_ticks: 3,
    max_recovery_ticks: 20,
    baseline_window: 10,
    recovery_margin: 0.05
  }

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns the default detector configuration.
  """
  @spec default_config() :: detector_config()
  def default_config, do: @default_config

  @doc """
  Analyzes a reward history for delayed gratification events.

  The history should be ordered from oldest to newest [oldest, ..., newest].

  Returns a list of detected gratification events.
  """
  @spec analyze(reward_history :: [float()], opts :: keyword()) :: [gratification_event()]
  def analyze(reward_history, opts \\ []) when is_list(reward_history) do
    config = build_config(opts)

    if length(reward_history) < config.baseline_window + config.min_dip_ticks do
      []
    else
      do_analyze(reward_history, config)
    end
  end

  @doc """
  Detects if a gratification event is occurring given the current state.

  This is for real-time detection during CA execution.

  State should contain:
  - `:in_dip` - boolean, are we currently in a dip?
  - `:dip_start_tick` - tick when dip started
  - `:dip_start_reward` - baseline reward before dip
  - `:min_reward` - minimum reward seen during dip
  - `:min_tick` - tick of minimum reward
  - `:dip_ticks` - count of ticks in dip state

  Returns `{result, new_state}` where result is:
  - `:none` - no event detected
  - `{:gratification, event}` - event detected
  - `{:in_progress, progress_info}` - currently in a dip
  """
  @spec detect(
          reward :: float(),
          tick :: non_neg_integer(),
          state :: map(),
          opts :: keyword()
        ) :: {detection_result(), map()}
  def detect(reward, tick, state, opts \\ []) do
    config = build_config(opts)
    baseline = Map.get(state, :baseline, 0.5)

    new_state = update_state(reward, tick, state, baseline, config)

    result = check_for_event(new_state, reward, baseline, config)

    case result do
      {:gratification, event} ->
        # Reset state after detection
        emit_telemetry(event, tick)
        {result, reset_state(new_state)}

      _ ->
        {result, new_state}
    end
  end

  @doc """
  Creates an initial detector state with optional baseline.
  """
  @spec init_state(opts :: keyword()) :: map()
  def init_state(opts \\ []) do
    %{
      in_dip: false,
      dip_start_tick: 0,
      dip_start_reward: 0.5,
      min_reward: 1.0,
      min_tick: 0,
      dip_ticks: 0,
      baseline: Keyword.get(opts, :baseline, 0.5),
      reward_history: []
    }
  end

  @doc """
  Updates the baseline from recent reward history.
  """
  @spec update_baseline(state :: map(), recent_rewards :: [float()], window :: non_neg_integer()) ::
          map()
  def update_baseline(state, recent_rewards, window \\ 10) do
    baseline =
      recent_rewards
      |> Enum.take(window)
      |> then(fn rewards ->
        if Enum.empty?(rewards), do: 0.5, else: Enum.sum(rewards) / length(rewards)
      end)

    Map.put(state, :baseline, baseline)
  end

  # ═══════════════════════════════════════════════════════════════
  # Internal State Machine
  # ═══════════════════════════════════════════════════════════════

  defp update_state(reward, tick, state, baseline, config) do
    cond do
      # Not in dip - check if entering one
      not state.in_dip and reward < baseline - config.dip_threshold ->
        %{state |
          in_dip: true,
          dip_start_tick: tick,
          dip_start_reward: baseline,
          min_reward: reward,
          min_tick: tick,
          dip_ticks: 1
        }

      # In dip - track progress
      state.in_dip ->
        new_min_reward = min(state.min_reward, reward)
        new_min_tick = if reward <= state.min_reward, do: tick, else: state.min_tick

        %{state |
          min_reward: new_min_reward,
          min_tick: new_min_tick,
          dip_ticks: state.dip_ticks + 1
        }

      # Not in dip, not entering one
      true ->
        state
    end
  end

  defp check_for_event(state, reward, baseline, config) do
    cond do
      # Not in a dip
      not state.in_dip ->
        :none

      # In dip but haven't met minimum duration
      state.dip_ticks < config.min_dip_ticks ->
        {:in_progress, %{
          dip_ticks: state.dip_ticks,
          current_depth: baseline - reward,
          max_depth: baseline - state.min_reward
        }}

      # In dip too long - timeout, reset
      state.dip_ticks > config.max_recovery_ticks ->
        :none

      # Check for recovery
      reward >= baseline - config.recovery_margin ->
        depth = state.dip_start_reward - state.min_reward

        {:gratification, %{
          tick_start: state.dip_start_tick,
          tick_bottom: state.min_tick,
          tick_recover: state.dip_start_tick + state.dip_ticks,
          depth: Float.round(depth, 4),
          duration: state.dip_ticks,
          baseline: Float.round(baseline, 4),
          recovered_to: Float.round(reward, 4)
        }}

      # Still in dip, not recovered yet
      true ->
        {:in_progress, %{
          dip_ticks: state.dip_ticks,
          current_depth: baseline - reward,
          max_depth: baseline - state.min_reward
        }}
    end
  end

  defp reset_state(state) do
    %{state |
      in_dip: false,
      dip_start_tick: 0,
      dip_start_reward: 0.5,
      min_reward: 1.0,
      min_tick: 0,
      dip_ticks: 0
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Batch Analysis
  # ═══════════════════════════════════════════════════════════════

  defp do_analyze(history, config) do
    # Calculate baseline as moving average
    history_with_index = Enum.with_index(history)

    {events, _final_state} =
      history_with_index
      |> Enum.reduce({[], init_state()}, fn {reward, tick}, {events, state} ->
        # Update baseline from trailing window
        trailing = Enum.take(Enum.drop(history, max(0, tick - config.baseline_window)), config.baseline_window)
        state = update_baseline(state, trailing, config.baseline_window)

        {result, new_state} = detect(reward, tick, state, Map.to_list(config))

        case result do
          {:gratification, event} -> {[event | events], new_state}
          _ -> {events, new_state}
        end
      end)

    Enum.reverse(events)
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp build_config(opts) do
    Enum.reduce(opts, @default_config, fn {key, value}, config ->
      if Map.has_key?(config, key), do: Map.put(config, key, value), else: config
    end)
  end

  defp emit_telemetry(event, tick) do
    :telemetry.execute(
      @telemetry_event,
      %{
        depth: event.depth,
        duration: event.duration,
        baseline: event.baseline,
        recovered_to: event.recovered_to
      },
      %{
        tick: tick,
        tick_start: event.tick_start,
        tick_bottom: event.tick_bottom,
        tick_recover: event.tick_recover
      }
    )

    Logger.debug(
      "[DelayedGratificationDetector] detected: depth=#{event.depth} duration=#{event.duration} ticks"
    )
  end
end
