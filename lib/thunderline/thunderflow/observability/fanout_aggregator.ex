defmodule Thunderline.Thunderflow.Observability.FanoutAggregator do
  @moduledoc """
  Telemetry handler for aggregating event fanout distribution metrics.

  Tracks how many target domains each event type is routed to, providing
  visibility into coupling patterns and potential fanout explosion.

  Emits metrics for:
  - Per-event fanout counts
  - P95 fanout distribution  
  - Coupling trend analysis

  ## Usage

      # Attach to telemetry on application start
      Thunderline.Thunderflow.Observability.FanoutAggregator.attach()
      
      # Events are automatically tracked when cross-domain pipeline processes them
      # Metrics emitted: [:thunderline, :events, :fanout]
  """

  use GenServer
  require Logger

  @table_name :thunderline_fanout_metrics
  @max_samples Application.compile_env(:thunderline, [:metrics, :max_fanout_samples], 500)
  # 1 minute
  @cleanup_interval 60_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attach telemetry handlers for fanout tracking.

  Call this on application start to begin tracking fanout metrics.
  """
  def attach do
    events = [
      [:thunderline, :cross_domain, :fanout],
      [:thunderline, :events, :broadcast]
    ]

    :telemetry.attach_many(
      "fanout-aggregator",
      events,
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @doc """
  Get current fanout statistics.

  Returns aggregated metrics for the current sampling window.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Get P95 fanout count for BRG reporting.
  """
  def get_p95_fanout do
    case get_stats() do
      %{p95_fanout: p95} -> p95
      _ -> 0
    end
  end

  @doc """
  Reset all collected metrics (primarily for testing).
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Telemetry event handler

  def handle_event([:thunderline, :cross_domain, :fanout], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:record_fanout, measurements, metadata})
  end

  def handle_event([:thunderline, :events, :broadcast], measurements, metadata, _config) do
    # Broadcast events have implicit high fanout
    GenServer.cast(__MODULE__, {:record_broadcast, measurements, metadata})
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    # Create ETS table for efficient fanout tracking
    table = :ets.new(@table_name, [:named_table, :public, :bag, read_concurrency: true])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    state = %{
      table: table,
      sample_count: 0,
      start_time: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = calculate_current_stats(state.table)
    {:reply, stats, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.table)
    new_state = %{state | sample_count: 0, start_time: System.monotonic_time(:millisecond)}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_cast({:record_fanout, measurements, metadata}, state) do
    # Extract fanout information
    target_count = Map.get(measurements, :target_count, 1)
    event_type = Map.get(metadata, :event_type, "unknown")
    timestamp = System.monotonic_time(:millisecond)

    # Apply sampling if we're at capacity
    new_state = maybe_record_sample(state, {event_type, target_count, timestamp})

    # Emit telemetry for real-time monitoring
    :telemetry.execute(
      [:thunderline, :events, :fanout],
      %{target_count: target_count, sample_count: new_state.sample_count},
      %{event_type: event_type}
    )

    {:noreply, new_state}
  end

  def handle_cast({:record_broadcast, measurements, metadata}, state) do
    # Broadcast events implicitly fan out to all domains (assume 7)
    target_count = 7
    event_type = Map.get(metadata, :event_type, "broadcast")
    timestamp = System.monotonic_time(:millisecond)

    new_state = maybe_record_sample(state, {event_type, target_count, timestamp})

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Remove old samples (older than 5 minutes)
    cutoff_time = System.monotonic_time(:millisecond) - 300_000

    old_count = :ets.info(state.table, :size)

    :ets.select_delete(state.table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", cutoff_time}], [true]}
    ])

    new_count = :ets.info(state.table, :size)
    cleaned = old_count - new_count

    if cleaned > 0 do
      Logger.debug("FanoutAggregator cleaned up #{cleaned} old samples")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    {:noreply, %{state | sample_count: new_count}}
  end

  # Private functions

  defp maybe_record_sample(state, {event_type, target_count, timestamp}) do
    if state.sample_count < @max_samples do
      # Room for more samples
      :ets.insert(state.table, {event_type, target_count, timestamp})
      %{state | sample_count: state.sample_count + 1}
    else
      # At capacity - apply reservoir sampling to replace random existing sample
      random_position = :rand.uniform(@max_samples)

      # Replace a random existing sample
      all_samples = :ets.tab2list(state.table)

      if length(all_samples) > 0 do
        sample_to_replace = Enum.at(all_samples, random_position - 1)
        :ets.delete_object(state.table, sample_to_replace)
        :ets.insert(state.table, {event_type, target_count, timestamp})
      end

      # Emit dropped sample counter
      :telemetry.execute(
        [:thunderline, :fanout, :sampling],
        %{dropped_samples: 1},
        %{reason: :capacity_limit}
      )

      state
    end
  end

  defp calculate_current_stats(table) do
    samples = :ets.tab2list(table)

    if length(samples) == 0 do
      %{
        total_samples: 0,
        mean_fanout: 0,
        median_fanout: 0,
        p95_fanout: 0,
        max_fanout: 0,
        event_types: [],
        coupling_score: 0.0
      }
    else
      fanout_counts =
        Enum.map(samples, fn {_event_type, target_count, _timestamp} -> target_count end)

      sorted_counts = Enum.sort(fanout_counts)

      event_type_counts =
        samples
        |> Enum.group_by(fn {event_type, _count, _ts} -> event_type end)
        |> Enum.map(fn {type, samples} -> {type, length(samples)} end)
        |> Enum.sort_by(fn {_type, count} -> count end, :desc)

      %{
        total_samples: length(samples),
        mean_fanout: calculate_mean(fanout_counts),
        median_fanout: calculate_percentile(sorted_counts, 0.5),
        p95_fanout: calculate_percentile(sorted_counts, 0.95),
        max_fanout: Enum.max(fanout_counts),
        event_types: event_type_counts,
        coupling_score: calculate_coupling_score(fanout_counts)
      }
    end
  end

  defp calculate_mean([]), do: 0

  defp calculate_mean(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_percentile([], _percentile), do: 0

  defp calculate_percentile(sorted_values, percentile) do
    index = round(percentile * (length(sorted_values) - 1))
    Enum.at(sorted_values, index, 0)
  end

  defp calculate_coupling_score(fanout_counts) do
    # Simple coupling score: higher is more coupled
    # Based on variance in fanout distribution
    mean = calculate_mean(fanout_counts)

    if mean == 0 do
      0.0
    else
      variance =
        fanout_counts
        |> Enum.map(fn count -> :math.pow(count - mean, 2) end)
        |> Enum.sum()
        |> Kernel./(length(fanout_counts))

      # Normalize to 0-10 scale
      min(10.0, variance / mean)
    end
  end
end
