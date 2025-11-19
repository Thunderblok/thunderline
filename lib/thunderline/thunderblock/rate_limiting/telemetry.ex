defmodule Thunderline.Thunderblock.RateLimiting.Telemetry do
  @moduledoc """
  Telemetry event aggregation and metrics reporting for rate limiting.

  Subscribes to rate limiting telemetry events and exposes aggregated metrics
  for monitoring and alerting.

  ## Usage

      # Start the telemetry handler
      {:ok, _} = Thunderline.Thunderblock.RateLimiting.Telemetry.start_link()

      # Query current metrics
      {:ok, metrics} = Telemetry.get_metrics()

      # Query metrics for specific bucket
      {:ok, bucket_metrics} = Telemetry.get_bucket_metrics(:api_calls)
  """

  use GenServer
  require Logger

  @table_name :rate_limiting_metrics
  # 1 minute
  @aggregation_window_ms 60_000

  # Telemetry events we subscribe to
  @events [
    [:thunderline, :rate_limiting, :check],
    [:thunderline, :rate_limiting, :allowed],
    [:thunderline, :rate_limiting, :blocked],
    [:thunderline, :rate_limiting, :bucket_created],
    [:thunderline, :rate_limiting, :refill],
    [:thunderline, :timing, :timer_created],
    [:thunderline, :timing, :timer_fired],
    [:thunderline, :timing, :timer_cancelled]
  ]

  # Client API

  @doc """
  Starts the telemetry aggregation GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets aggregated metrics for all buckets.

  Returns a map with total counts and per-bucket statistics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets metrics for a specific bucket.
  """
  def get_bucket_metrics(bucket_name) do
    GenServer.call(__MODULE__, {:get_bucket_metrics, bucket_name})
  end

  @doc """
  Resets all metrics. Useful for testing.
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for metrics
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Attach telemetry handlers
    :telemetry.attach_many(
      "rate-limiting-metrics",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )

    # Schedule periodic aggregation
    schedule_aggregation()

    Logger.info("Rate limiting telemetry started")

    {:ok, %{window_start: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = aggregate_metrics()
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call({:get_bucket_metrics, bucket_name}, _from, state) do
    bucket_metrics = get_bucket_stats(bucket_name)
    {:reply, {:ok, bucket_metrics}, state}
  end

  @impl true
  def handle_call(:reset_metrics, _from, state) do
    :ets.delete_all_objects(@table_name)
    Logger.info("Rate limiting metrics reset")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:aggregate, state) do
    # Perform periodic aggregation
    metrics = aggregate_metrics()

    # Log summary
    Logger.debug("Rate limiting metrics",
      total_checks: metrics.total_checks,
      total_allowed: metrics.total_allowed,
      total_blocked: metrics.total_blocked,
      allow_rate: metrics.allow_rate
    )

    # Reset window
    new_state = %{state | window_start: System.monotonic_time(:millisecond)}

    schedule_aggregation()

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach("rate-limiting-metrics")
    :ok
  end

  # Telemetry Event Handlers

  @doc false
  def handle_event([:thunderline, :rate_limiting, :check], measurements, metadata, _config) do
    increment_counter(:total_checks)
    increment_bucket_counter(metadata[:bucket], :checks)
    record_latency(:check_latency, measurements[:duration])
  end

  def handle_event([:thunderline, :rate_limiting, :allowed], _measurements, metadata, _config) do
    increment_counter(:total_allowed)
    increment_bucket_counter(metadata[:bucket], :allowed)
  end

  def handle_event([:thunderline, :rate_limiting, :blocked], _measurements, metadata, _config) do
    increment_counter(:total_blocked)
    increment_bucket_counter(metadata[:bucket], :blocked)
  end

  def handle_event(
        [:thunderline, :rate_limiting, :bucket_created],
        _measurements,
        metadata,
        _config
      ) do
    increment_counter(:buckets_created)
    record_bucket_config(metadata[:bucket], metadata[:config])
  end

  def handle_event([:thunderline, :rate_limiting, :refill], measurements, metadata, _config) do
    increment_bucket_counter(metadata[:bucket], :refills)
    update_gauge({:bucket_tokens, metadata[:bucket]}, measurements[:tokens_after])
  end

  def handle_event([:thunderline, :timing, event], measurements, metadata, _config)
      when event in [:timer_created, :timer_fired, :timer_cancelled] do
    increment_counter(:"timing_#{event}")

    if delay_ms = measurements[:delay_ms] do
      record_value(:"timing_#{event}_delay", delay_ms)
    end
  end

  # Private functions

  defp increment_counter(key) do
    :ets.update_counter(@table_name, key, {2, 1}, {key, 0})
  end

  defp increment_bucket_counter(bucket, key) do
    counter_key = {:bucket, bucket, key}
    :ets.update_counter(@table_name, counter_key, {2, 1}, {counter_key, 0})
  end

  defp update_gauge(key, value) do
    :ets.insert(@table_name, {key, value})
  end

  defp record_latency(key, duration_ns) when is_integer(duration_ns) do
    duration_ms = duration_ns / 1_000_000
    record_value(key, duration_ms)
  end

  defp record_latency(_key, _duration), do: :ok

  defp record_value(key, value) do
    # Simple histogram: track min, max, sum, count
    case :ets.lookup(@table_name, key) do
      [] ->
        :ets.insert(
          @table_name,
          {key,
           %{
             min: value,
             max: value,
             sum: value,
             count: 1
           }}
        )

      [{^key, stats}] ->
        :ets.insert(
          @table_name,
          {key,
           %{
             min: min(stats.min, value),
             max: max(stats.max, value),
             sum: stats.sum + value,
             count: stats.count + 1
           }}
        )
    end
  end

  defp record_bucket_config(bucket, config) do
    :ets.insert(@table_name, {{:bucket_config, bucket}, config})
  end

  defp aggregate_metrics do
    # Collect all counters
    counters =
      :ets.foldl(
        fn
          {key, value}, acc when is_atom(key) ->
            Map.put(acc, key, value)

          _other, acc ->
            acc
        end,
        %{},
        @table_name
      )

    # Collect bucket metrics
    bucket_metrics = collect_bucket_metrics()

    # Calculate rates
    total_checks = Map.get(counters, :total_checks, 0)
    total_allowed = Map.get(counters, :total_allowed, 0)
    total_blocked = Map.get(counters, :total_blocked, 0)

    allow_rate =
      if total_checks > 0 do
        Float.round(total_allowed / total_checks * 100, 2)
      else
        0.0
      end

    Map.merge(counters, %{
      buckets: bucket_metrics,
      allow_rate: allow_rate,
      block_rate: 100.0 - allow_rate
    })
  end

  defp collect_bucket_metrics do
    :ets.foldl(
      fn
        {{:bucket, bucket, key}, value}, acc ->
          bucket_stats = Map.get(acc, bucket, %{})
          Map.put(acc, bucket, Map.put(bucket_stats, key, value))

        _other, acc ->
          acc
      end,
      %{},
      @table_name
    )
  end

  defp get_bucket_stats(bucket) do
    :ets.foldl(
      fn
        {{:bucket, ^bucket, key}, value}, acc ->
          Map.put(acc, key, value)

        {{:bucket_config, ^bucket}, config}, acc ->
          Map.put(acc, :config, config)

        {{:bucket_tokens, ^bucket}, tokens}, acc ->
          Map.put(acc, :current_tokens, tokens)

        _other, acc ->
          acc
      end,
      %{},
      @table_name
    )
  end

  defp schedule_aggregation do
    Process.send_after(self(), :aggregate, @aggregation_window_ms)
  end
end
