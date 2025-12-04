defmodule Thunderline.Thunderwall.GCScheduler do
  @moduledoc """
  Garbage collection coordinator for Thunderline.

  The GCScheduler orchestrates cleanup across all domains by:

  1. Running on slow-tick intervals (default: every 60 seconds)
  2. Querying each domain for cleanup candidates
  3. Coordinating decay and pruning operations
  4. Tracking GC effectiveness

  ## GC Policies

  - **TickState**: Prune states older than 1 hour
  - **DecayRecords**: Prune records older than 24 hours
  - **EventLog**: Prune processed events older than 7 days
  - **Sessions**: Prune expired sessions

  ## Usage

      # Trigger manual GC
      GCScheduler.run_gc()

      # Get GC statistics
      GCScheduler.stats()

      # Configure GC interval
      GCScheduler.set_interval(120_000)  # 2 minutes
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderwall.EntropyMetrics
  alias Thunderline.Thundercore.Resources.TickState

  # 1 minute
  @default_gc_interval_ms 60_000
  @telemetry_prefix [:thunderline, :wall, :gc]

  # GC policies: {module, action, retention_value}
  @gc_policies [
    # Prune tick states older than 72000 ticks (~1 hour at 20Hz)
    {:tick_state, TickState, :prune_before_tick, 72_000}
    # Add more policies as domains are implemented
  ]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc "Starts the GCScheduler."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Manually trigger a GC cycle."
  @spec run_gc(GenServer.server()) :: {:ok, map()}
  def run_gc(server \\ __MODULE__) do
    GenServer.call(server, :run_gc, 30_000)
  end

  @doc "Get GC statistics."
  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc "Set GC interval in milliseconds."
  @spec set_interval(pos_integer(), GenServer.server()) :: :ok
  def set_interval(interval_ms, server \\ __MODULE__) when interval_ms > 0 do
    GenServer.call(server, {:set_interval, interval_ms})
  end

  @doc "Pause automatic GC."
  @spec pause(GenServer.server()) :: :ok
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @doc "Resume automatic GC."
  @spec resume(GenServer.server()) :: :ok
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_gc_interval_ms)

    state = %{
      interval: interval,
      paused: false,
      timer: nil,
      stats: %{
        total_runs: 0,
        total_collected: 0,
        last_run: nil,
        last_duration_ms: 0,
        by_policy: %{}
      }
    }

    # Schedule first GC
    state = schedule_gc(state)

    Logger.info("[Thunderwall.GCScheduler] Started with #{interval}ms interval")

    {:ok, state}
  end

  @impl true
  def handle_call(:run_gc, _from, state) do
    {result, new_state} = do_gc(state)
    {:reply, {:ok, result}, new_state}
  end

  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  def handle_call({:set_interval, interval_ms}, _from, state) do
    state = cancel_timer(state)
    new_state = schedule_gc(%{state | interval: interval_ms})
    {:reply, :ok, new_state}
  end

  def handle_call(:pause, _from, state) do
    state = cancel_timer(state)
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, %{paused: true} = state) do
    new_state = schedule_gc(%{state | paused: false})
    {:reply, :ok, new_state}
  end

  def handle_call(:resume, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:gc_tick, %{paused: true} = state) do
    {:noreply, state}
  end

  def handle_info(:gc_tick, state) do
    {_result, new_state} = do_gc(state)
    new_state = schedule_gc(new_state)
    {:noreply, new_state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp do_gc(state) do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("[Thunderwall.GCScheduler] Starting GC cycle")

    # Run each policy
    results =
      Enum.map(@gc_policies, fn {name, module, action, retention} ->
        run_policy(name, module, action, retention)
      end)

    total_collected = Enum.sum(Enum.map(results, fn {_, count} -> count end))
    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Update stats
    by_policy =
      Enum.reduce(results, state.stats.by_policy, fn {name, count}, acc ->
        Map.update(acc, name, count, &(&1 + count))
      end)

    new_stats = %{
      total_runs: state.stats.total_runs + 1,
      total_collected: state.stats.total_collected + total_collected,
      last_run: DateTime.utc_now(),
      last_duration_ms: duration_ms,
      by_policy: by_policy
    }

    # Report to EntropyMetrics
    EntropyMetrics.record_gc(total_collected)

    # Emit telemetry
    :telemetry.execute(
      @telemetry_prefix ++ [:cycle],
      %{
        collected: total_collected,
        duration_ms: duration_ms
      },
      %{}
    )

    # Emit event
    emit_event(total_collected, duration_ms, results)

    Logger.info(
      "[Thunderwall.GCScheduler] GC cycle complete: collected=#{total_collected} duration=#{duration_ms}ms"
    )

    result = %{
      collected: total_collected,
      duration_ms: duration_ms,
      by_policy: results
    }

    {result, %{state | stats: new_stats}}
  end

  defp run_policy(name, module, action, retention) do
    try do
      # Get current tick for tick-based retention
      current_tick =
        try do
          Thunderline.Thundercore.TickEmitter.current_tick()
        rescue
          _ -> 0
        catch
          :exit, _ -> 0
        end

      threshold =
        case name do
          :tick_state -> max(0, current_tick - retention)
          _ -> retention
        end

      case apply(module, action, [threshold]) do
        {:ok, count} when is_integer(count) ->
          Logger.debug("[Thunderwall.GCScheduler] #{name}: collected #{count}")
          {name, count}

        _ ->
          {name, 0}
      end
    rescue
      e ->
        Logger.error("[Thunderwall.GCScheduler] Policy #{name} failed: #{inspect(e)}")
        {name, 0}
    end
  end

  defp schedule_gc(%{paused: true} = state), do: state

  defp schedule_gc(state) do
    timer = Process.send_after(self(), :gc_tick, state.interval)
    %{state | timer: timer}
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end

  defp emit_event(total_collected, duration_ms, results) do
    event = %{
      type: "wall.gc.completed",
      collected: total_collected,
      duration_ms: duration_ms,
      by_policy: Enum.into(results, %{}),
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Thunderline.PubSub, "wall:gc", {:wall_event, event})
  end
end
