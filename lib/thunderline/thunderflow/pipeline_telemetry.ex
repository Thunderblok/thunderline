defmodule Thunderline.Thunderflow.PipelineTelemetry do
  @moduledoc """
  Pipeline-level throughput and failure telemetry for Thunderflow.

  Provides unified metrics across all pipeline types (general, realtime, cross_domain)
  with support for throughput windows, failure tracking, and health scoring.

  ## Telemetry Events

  Emitted events (all prefixed with `[:thunderline, :pipeline]`):

  - `[:thunderline, :pipeline, :throughput]`
    - Measurements: `%{count: n, duration_ms: d, rate_per_sec: r}`
    - Metadata: `%{pipeline: :general|:realtime|:cross_domain, window_ms: w}`

  - `[:thunderline, :pipeline, :failure]`
    - Measurements: `%{count: 1}`
    - Metadata: `%{pipeline: atom, reason: term, event_name: string, stage: atom}`

  - `[:thunderline, :pipeline, :health]`
    - Measurements: `%{score: 0.0..1.0, success_rate: float, avg_latency_us: int}`
    - Metadata: `%{pipeline: atom}`

  - `[:thunderline, :pipeline, :backpressure]`
    - Measurements: `%{queue_depth: int, demand: int}`
    - Metadata: `%{pipeline: atom, producer: module}`

  ## Usage

  ### Recording Throughput

      # After processing a batch
      PipelineTelemetry.record_throughput(:realtime, 25, 150)

  ### Recording Failures

      PipelineTelemetry.record_failure(:general, :validation_error, "user.created", :processor)

  ### Health Check

      %{score: 0.95, success_rate: 0.98, avg_latency_us: 2500} =
        PipelineTelemetry.health_snapshot(:realtime)

  ## Window Aggregation

  The module maintains rolling windows for metrics aggregation. Default window is 60 seconds.
  Use `get_window_stats/2` for time-bounded metrics.
  """

  require Logger

  @type pipeline :: :general | :realtime | :cross_domain
  @type stage :: :producer | :processor | :batcher | :dlq

  # Telemetry event names
  @throughput_event [:thunderline, :pipeline, :throughput]
  @failure_event [:thunderline, :pipeline, :failure]
  @health_event [:thunderline, :pipeline, :health]
  @backpressure_event [:thunderline, :pipeline, :backpressure]

  # ETS table for rolling window stats
  @stats_table :thunderline_pipeline_stats

  # Default window duration (60 seconds)
  @default_window_ms 60_000

  # ==========================================================================
  # Public API
  # ==========================================================================

  @doc """
  Record throughput for a pipeline after processing a batch.

  ## Parameters

  - `pipeline` - Pipeline type (:general, :realtime, :cross_domain)
  - `count` - Number of events processed
  - `duration_ms` - Processing duration in milliseconds
  - `opts` - Optional keyword list with:
    - `:window_ms` - Custom window duration (default: 60_000)
  """
  @spec record_throughput(pipeline(), non_neg_integer(), non_neg_integer(), keyword()) :: :ok
  def record_throughput(pipeline, count, duration_ms, opts \\ []) do
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    rate_per_sec = if duration_ms > 0, do: count / (duration_ms / 1000), else: 0.0

    :telemetry.execute(
      @throughput_event,
      %{count: count, duration_ms: duration_ms, rate_per_sec: Float.round(rate_per_sec, 2)},
      %{pipeline: pipeline, window_ms: window_ms}
    )

    # Update rolling stats
    update_stats(pipeline, :throughput, %{count: count, duration_ms: duration_ms})

    :ok
  end

  @doc """
  Record a pipeline failure.

  ## Parameters

  - `pipeline` - Pipeline type
  - `reason` - Error reason (atom or term)
  - `event_name` - Name of the failed event (string)
  - `stage` - Processing stage where failure occurred
  """
  @spec record_failure(pipeline(), term(), String.t() | nil, stage()) :: :ok
  def record_failure(pipeline, reason, event_name, stage) do
    :telemetry.execute(
      @failure_event,
      %{count: 1},
      %{
        pipeline: pipeline,
        reason: normalize_reason(reason),
        event_name: event_name || "unknown",
        stage: stage
      }
    )

    # Update rolling stats
    update_stats(pipeline, :failure, %{reason: reason, stage: stage})

    :ok
  end

  @doc """
  Record backpressure metrics for a pipeline producer.

  ## Parameters

  - `pipeline` - Pipeline type
  - `queue_depth` - Current queue depth
  - `demand` - Current demand from consumers
  - `producer` - Producer module (optional)
  """
  @spec record_backpressure(pipeline(), non_neg_integer(), non_neg_integer(), module() | nil) ::
          :ok
  def record_backpressure(pipeline, queue_depth, demand, producer \\ nil) do
    :telemetry.execute(
      @backpressure_event,
      %{queue_depth: queue_depth, demand: demand},
      %{pipeline: pipeline, producer: producer}
    )

    :ok
  end

  @doc """
  Get a health snapshot for a pipeline.

  Returns a map with:
  - `score` - Overall health score (0.0-1.0)
  - `success_rate` - Ratio of successful to total events
  - `avg_latency_us` - Average processing latency in microseconds
  - `throughput_per_sec` - Average events per second
  - `failure_count` - Total failures in window
  - `total_processed` - Total events processed in window
  """
  @spec health_snapshot(pipeline()) :: map()
  def health_snapshot(pipeline) do
    stats = get_stats(pipeline)

    total = stats.success_count + stats.failure_count
    success_rate = if total > 0, do: stats.success_count / total, else: 1.0

    # Health score combines success rate and latency
    latency_score = latency_health(stats.avg_latency_us)
    score = Float.round(success_rate * 0.7 + latency_score * 0.3, 3)

    snapshot = %{
      score: score,
      success_rate: Float.round(success_rate, 4),
      avg_latency_us: stats.avg_latency_us,
      throughput_per_sec: stats.throughput_per_sec,
      failure_count: stats.failure_count,
      total_processed: total
    }

    # Emit health telemetry
    :telemetry.execute(@health_event, snapshot, %{pipeline: pipeline})

    snapshot
  end

  @doc """
  Get rolling window statistics for a pipeline.

  ## Parameters

  - `pipeline` - Pipeline type
  - `window_ms` - Window duration in milliseconds (default: 60_000)
  """
  @spec get_window_stats(pipeline(), non_neg_integer()) :: map()
  def get_window_stats(pipeline, window_ms \\ @default_window_ms) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    case :ets.lookup(@stats_table, {pipeline, :events}) do
      [{_, events}] ->
        # Filter events within window
        window_events = Enum.filter(events, fn {ts, _} -> ts >= cutoff end)

        throughput_events = Enum.filter(window_events, fn {_, %{type: t}} -> t == :throughput end)
        failure_events = Enum.filter(window_events, fn {_, %{type: t}} -> t == :failure end)

        total_count = Enum.reduce(throughput_events, 0, fn {_, %{count: c}}, acc -> acc + c end)

        total_duration =
          Enum.reduce(throughput_events, 0, fn {_, %{duration_ms: d}}, acc -> acc + d end)

        %{
          window_ms: window_ms,
          event_count: total_count,
          failure_count: length(failure_events),
          total_duration_ms: total_duration,
          avg_duration_ms:
            if(length(throughput_events) > 0,
              do: total_duration / length(throughput_events),
              else: 0
            ),
          events_per_sec: if(window_ms > 0, do: total_count / (window_ms / 1000), else: 0)
        }

      [] ->
        %{
          window_ms: window_ms,
          event_count: 0,
          failure_count: 0,
          total_duration_ms: 0,
          avg_duration_ms: 0,
          events_per_sec: 0
        }
    end
  end

  @doc """
  Initialize the stats ETS table. Called by application supervisor.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@stats_table) do
      :undefined ->
        :ets.new(@stats_table, [:named_table, :public, :set, read_concurrency: true])
        Logger.debug("[PipelineTelemetry] Stats table initialized")

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Reset all statistics. Useful for testing.
  """
  @spec reset() :: :ok
  def reset do
    case :ets.whereis(@stats_table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@stats_table)
    end

    :ok
  end

  # ==========================================================================
  # Telemetry Attach Helpers
  # ==========================================================================

  @doc """
  Attach default telemetry handlers for pipeline metrics.

  This sets up handlers that forward metrics to Logger and optionally to
  external systems (StatsD, Prometheus, etc.).

  ## Options

  - `:log_level` - Logger level for metrics (default: :debug)
  - `:log_throughput?` - Log throughput events (default: true)
  - `:log_failures?` - Log failure events (default: true)
  - `:log_health?` - Log health snapshots (default: false)
  """
  @spec attach_default_handlers(keyword()) :: :ok
  def attach_default_handlers(opts \\ []) do
    log_level = Keyword.get(opts, :log_level, :debug)
    log_throughput? = Keyword.get(opts, :log_throughput?, true)
    log_failures? = Keyword.get(opts, :log_failures?, true)
    log_health? = Keyword.get(opts, :log_health?, false)

    handler_config = %{
      log_level: log_level,
      log_throughput?: log_throughput?,
      log_failures?: log_failures?,
      log_health?: log_health?
    }

    :telemetry.attach_many(
      "thunderline-pipeline-telemetry-logger",
      [
        @throughput_event,
        @failure_event,
        @health_event,
        @backpressure_event
      ],
      &__MODULE__.handle_telemetry_event/4,
      handler_config
    )

    :ok
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, config) do
    case event do
      [:thunderline, :pipeline, :throughput] when config.log_throughput? ->
        Logger.log(config.log_level, fn ->
          "[Pipeline:#{metadata.pipeline}] Throughput: #{measurements.count} events in #{measurements.duration_ms}ms (#{measurements.rate_per_sec}/sec)"
        end)

      [:thunderline, :pipeline, :failure] when config.log_failures? ->
        Logger.warning(fn ->
          "[Pipeline:#{metadata.pipeline}] Failure at #{metadata.stage}: #{inspect(metadata.reason)} (event: #{metadata.event_name})"
        end)

      [:thunderline, :pipeline, :health] when config.log_health? ->
        Logger.log(config.log_level, fn ->
          "[Pipeline:#{metadata.pipeline}] Health: score=#{measurements.score}, success_rate=#{measurements.success_rate}, latency=#{measurements.avg_latency_us}µs"
        end)

      [:thunderline, :pipeline, :backpressure] ->
        if measurements.queue_depth > 100 do
          Logger.warning(fn ->
            "[Pipeline:#{metadata.pipeline}] Backpressure: queue_depth=#{measurements.queue_depth}, demand=#{measurements.demand}"
          end)
        end

      _ ->
        :ok
    end
  end

  # ==========================================================================
  # Private Helpers
  # ==========================================================================

  defp update_stats(pipeline, type, data) do
    # Ensure table exists
    case :ets.whereis(@stats_table) do
      :undefined ->
        init()

      _ ->
        :ok
    end

    now = System.monotonic_time(:millisecond)
    event = {now, Map.put(data, :type, type)}

    key = {pipeline, :events}

    # Append to event list, pruning old entries
    case :ets.lookup(@stats_table, key) do
      [{_, events}] ->
        # Keep last 5 minutes of events max
        cutoff = now - 300_000
        pruned = Enum.filter(events, fn {ts, _} -> ts >= cutoff end)
        :ets.insert(@stats_table, {key, [event | pruned]})

      [] ->
        :ets.insert(@stats_table, {key, [event]})
    end

    :ok
  end

  defp get_stats(pipeline) do
    window_ms = @default_window_ms
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    case :ets.lookup(@stats_table, {pipeline, :events}) do
      [{_, events}] ->
        window_events = Enum.filter(events, fn {ts, _} -> ts >= cutoff end)

        throughput_events = Enum.filter(window_events, fn {_, %{type: t}} -> t == :throughput end)
        failure_events = Enum.filter(window_events, fn {_, %{type: t}} -> t == :failure end)

        success_count =
          Enum.reduce(throughput_events, 0, fn {_, %{count: c}}, acc -> acc + c end)

        total_duration =
          Enum.reduce(throughput_events, 0, fn {_, %{duration_ms: d}}, acc -> acc + d end)

        avg_latency =
          if length(throughput_events) > 0 do
            # Convert ms to µs
            trunc(total_duration / length(throughput_events) * 1000)
          else
            0
          end

        throughput_per_sec =
          if window_ms > 0 do
            Float.round(success_count / (window_ms / 1000), 2)
          else
            0.0
          end

        %{
          success_count: success_count,
          failure_count: length(failure_events),
          avg_latency_us: avg_latency,
          throughput_per_sec: throughput_per_sec
        }

      [] ->
        %{
          success_count: 0,
          failure_count: 0,
          avg_latency_us: 0,
          throughput_per_sec: 0.0
        }
    end
  end

  defp latency_health(avg_latency_us) when avg_latency_us <= 1_000, do: 1.0
  defp latency_health(avg_latency_us) when avg_latency_us <= 5_000, do: 0.9
  defp latency_health(avg_latency_us) when avg_latency_us <= 10_000, do: 0.8
  defp latency_health(avg_latency_us) when avg_latency_us <= 50_000, do: 0.6
  defp latency_health(avg_latency_us) when avg_latency_us <= 100_000, do: 0.4
  defp latency_health(_), do: 0.2

  defp normalize_reason(reason) when is_atom(reason), do: reason
  defp normalize_reason({reason, _}) when is_atom(reason), do: reason
  defp normalize_reason(%{__struct__: struct}), do: struct
  defp normalize_reason(_), do: :unknown
end
