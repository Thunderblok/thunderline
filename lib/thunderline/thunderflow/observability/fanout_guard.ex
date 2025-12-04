defmodule Thunderline.Thunderflow.Observability.FanoutGuard do
  @moduledoc """
  Safety guard to prevent telemetry overload during massive event fanout spikes.

  Implements sampling and rate limiting to ensure telemetry system stability
  when event volumes exceed normal operational parameters.

  ## Features

  - Adaptive sampling based on current load
  - Configurable burst tolerance
  - Dropped sample counters for visibility
  - Automatic recovery when load decreases

  ## Configuration

      config :thunderline, :metrics,
        max_fanout_samples: 500,
        fanout_burst_threshold: 100,
        sampling_window_ms: 10_000
  """

  use GenServer
  require Logger

  # Reserved for future sample limiting (currently handled in FanoutAggregator)
  @_max_samples Application.compile_env(:thunderline, [:metrics, :max_fanout_samples], 500)
  _ = @_max_samples
  @burst_threshold Application.compile_env(:thunderline, [:metrics, :fanout_burst_threshold], 100)
  @sampling_window Application.compile_env(:thunderline, [:metrics, :sampling_window_ms], 10_000)

  defstruct [
    :window_start,
    :events_in_window,
    :dropped_count,
    :sampling_rate,
    :burst_mode
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an event should be sampled for fanout tracking.

  Returns `{:sample, metadata}` or `{:drop, reason}`.
  """
  def should_sample_event(event_metadata) do
    GenServer.call(__MODULE__, {:should_sample, event_metadata})
  end

  @doc """
  Record that an event was processed (for rate calculation).
  """
  def record_event do
    GenServer.cast(__MODULE__, :record_event)
  end

  @doc """
  Get current guard statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      window_start: current_time(),
      events_in_window: 0,
      dropped_count: 0,
      sampling_rate: 1.0,
      burst_mode: false
    }

    # Schedule periodic window reset
    schedule_window_reset()

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:should_sample, metadata}, _from, state) do
    {decision, new_state} = make_sampling_decision(state, metadata)
    {:reply, decision, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      events_in_window: state.events_in_window,
      dropped_count: state.dropped_count,
      sampling_rate: state.sampling_rate,
      burst_mode: state.burst_mode,
      window_utilization: state.events_in_window / @burst_threshold
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast(:record_event, state) do
    new_state = %{state | events_in_window: state.events_in_window + 1}
    {:noreply, update_sampling_strategy(new_state)}
  end

  @impl GenServer
  def handle_info(:reset_window, state) do
    # Reset sliding window and recalculate sampling strategy
    new_state = %{state | window_start: current_time(), events_in_window: 0, dropped_count: 0}

    # Exit burst mode if we were in it
    final_state =
      if state.burst_mode do
        Logger.info("FanoutGuard exiting burst mode - load normalized")
        %{new_state | burst_mode: false, sampling_rate: 1.0}
      else
        new_state
      end

    schedule_window_reset()
    {:noreply, final_state}
  end

  # Private functions

  defp make_sampling_decision(state, metadata) do
    # Always sample high priority events
    if high_priority_event?(metadata) do
      {{:sample, add_guard_metadata(metadata, :high_priority)}, state}
    else
      # Apply sampling based on current rate
      if :rand.uniform() <= state.sampling_rate do
        {{:sample, add_guard_metadata(metadata, :sampled)}, state}
      else
        new_state = %{state | dropped_count: state.dropped_count + 1}

        # Emit dropped sample telemetry
        :telemetry.execute(
          [:thunderline, :fanout, :sampling],
          %{dropped_samples: 1},
          %{reason: :rate_limited, sampling_rate: state.sampling_rate}
        )

        {{:drop, :rate_limited}, new_state}
      end
    end
  end

  defp update_sampling_strategy(state) do
    cond do
      # Enter burst mode if we exceed threshold
      state.events_in_window > @burst_threshold and not state.burst_mode ->
        Logger.warning("FanoutGuard entering burst mode - high event volume detected")

        %{
          state
          | burst_mode: true,
            sampling_rate: calculate_burst_sampling_rate(state.events_in_window)
        }

      # Adjust sampling rate in burst mode
      state.burst_mode ->
        %{state | sampling_rate: calculate_burst_sampling_rate(state.events_in_window)}

      # Normal operation
      true ->
        state
    end
  end

  defp calculate_burst_sampling_rate(events_in_window) do
    # Adaptive sampling: higher load = lower rate
    # Target 80% of threshold
    target_events = @burst_threshold * 0.8
    rate = target_events / max(events_in_window, 1)

    # Clamp between 0.1 and 1.0
    max(0.1, min(1.0, rate))
  end

  defp high_priority_event?(metadata) do
    case metadata do
      %{priority: priority} when priority in [:high, :critical] -> true
      %{event_type: type} when type in ["system_alert", "critical_failure"] -> true
      _ -> false
    end
  end

  defp add_guard_metadata(metadata, reason) do
    Map.put(metadata, :fanout_guard, %{
      sampled_by: __MODULE__,
      sample_reason: reason,
      timestamp: current_time()
    })
  end

  defp schedule_window_reset do
    Process.send_after(self(), :reset_window, @sampling_window)
  end

  defp current_time do
    System.monotonic_time(:millisecond)
  end
end
