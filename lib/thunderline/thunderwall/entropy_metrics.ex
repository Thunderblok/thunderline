defmodule Thunderline.Thunderwall.EntropyMetrics do
  @moduledoc """
  System entropy and decay telemetry collector.

  EntropyMetrics tracks the "health" of the system by measuring:

  - Resource turnover (creation vs decay rates)
  - Queue depths and overflow frequency
  - Memory pressure indicators
  - GC effectiveness

  ## Metrics

  - `decay_rate` - Resources decayed per minute
  - `overflow_rate` - Overflows per minute
  - `archive_count` - Total archived resources
  - `gc_effectiveness` - Ratio of GC'd resources to total
  - `memory_pressure` - Process memory trends

  ## Usage

      # Get current metrics
      EntropyMetrics.snapshot()

      # Get specific metric
      EntropyMetrics.get(:decay_rate)

      # Subscribe to metric updates
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "wall:metrics")
  """

  use GenServer
  require Logger

  # Collect every 10 seconds
  @collect_interval_ms 10_000
  # Keep 60 samples (10 minutes of data)
  @window_size 60

  @telemetry_prefix [:thunderline, :wall, :entropy]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc "Starts the EntropyMetrics collector."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns a snapshot of all current metrics."
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  @doc "Returns a specific metric value."
  @spec get(atom(), GenServer.server()) :: term()
  def get(metric_name, server \\ __MODULE__) do
    GenServer.call(server, {:get, metric_name})
  end

  @doc "Records a decay event (called by DecayProcessor)."
  @spec record_decay(GenServer.server()) :: :ok
  def record_decay(server \\ __MODULE__) do
    GenServer.cast(server, :decay)
  end

  @doc "Records an overflow event (called by OverflowHandler)."
  @spec record_overflow(GenServer.server()) :: :ok
  def record_overflow(server \\ __MODULE__) do
    GenServer.cast(server, :overflow)
  end

  @doc "Records a GC event (called by GCScheduler)."
  @spec record_gc(non_neg_integer(), GenServer.server()) :: :ok
  def record_gc(items_collected, server \\ __MODULE__) do
    GenServer.cast(server, {:gc, items_collected})
  end

  @doc "Returns PubSub topic for metric updates."
  @spec topic() :: String.t()
  def topic, do: "wall:metrics"

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :collect_interval_ms, @collect_interval_ms)

    state = %{
      interval: interval,
      # Current window counters
      current: %{
        decays: 0,
        overflows: 0,
        gc_items: 0
      },
      # Historical samples (ring buffer)
      samples: [],
      # Aggregated metrics
      metrics: %{
        decay_rate: 0.0,
        overflow_rate: 0.0,
        gc_rate: 0.0,
        memory_mb: 0.0,
        process_count: 0
      }
    }

    # Schedule first collection
    Process.send_after(self(), :collect, interval)

    Logger.info("[Thunderwall.EntropyMetrics] Started with #{interval}ms collection interval")

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.metrics, state}
  end

  def handle_call({:get, metric_name}, _from, state) do
    value = Map.get(state.metrics, metric_name)
    {:reply, value, state}
  end

  @impl true
  def handle_cast(:decay, state) do
    new_current = Map.update!(state.current, :decays, &(&1 + 1))
    {:noreply, %{state | current: new_current}}
  end

  def handle_cast(:overflow, state) do
    new_current = Map.update!(state.current, :overflows, &(&1 + 1))
    {:noreply, %{state | current: new_current}}
  end

  def handle_cast({:gc, items}, state) do
    new_current = Map.update!(state.current, :gc_items, &(&1 + items))
    {:noreply, %{state | current: new_current}}
  end

  @impl true
  def handle_info(:collect, state) do
    # Take current sample
    sample = %{
      timestamp: DateTime.utc_now(),
      decays: state.current.decays,
      overflows: state.current.overflows,
      gc_items: state.current.gc_items
    }

    # Add to samples, keep window size
    samples = [sample | Enum.take(state.samples, @window_size - 1)]

    # Calculate metrics
    metrics = calculate_metrics(samples)

    # Emit telemetry
    emit_telemetry(metrics)

    # Broadcast update
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(), {:entropy_metrics, metrics})

    # Reset current counters
    new_current = %{decays: 0, overflows: 0, gc_items: 0}

    # Schedule next collection
    Process.send_after(self(), :collect, state.interval)

    {:noreply, %{state | current: new_current, samples: samples, metrics: metrics}}
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp calculate_metrics(samples) do
    # Calculate rates per minute
    window_minutes = length(samples) * (@collect_interval_ms / 60_000)
    # Avoid division by zero
    window_minutes = max(window_minutes, 0.1)

    total_decays = Enum.sum(Enum.map(samples, & &1.decays))
    total_overflows = Enum.sum(Enum.map(samples, & &1.overflows))
    total_gc = Enum.sum(Enum.map(samples, & &1.gc_items))

    # Get system metrics
    memory_info = :erlang.memory()
    total_memory_mb = memory_info[:total] / (1024 * 1024)
    process_count = :erlang.system_info(:process_count)

    %{
      decay_rate: total_decays / window_minutes,
      overflow_rate: total_overflows / window_minutes,
      gc_rate: total_gc / window_minutes,
      memory_mb: Float.round(total_memory_mb, 2),
      process_count: process_count,
      sample_count: length(samples),
      window_minutes: Float.round(window_minutes, 2)
    }
  end

  defp emit_telemetry(metrics) do
    :telemetry.execute(
      @telemetry_prefix ++ [:snapshot],
      %{
        decay_rate: metrics.decay_rate,
        overflow_rate: metrics.overflow_rate,
        gc_rate: metrics.gc_rate,
        memory_mb: metrics.memory_mb,
        process_count: metrics.process_count
      },
      %{}
    )
  end
end
