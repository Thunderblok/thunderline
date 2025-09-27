defmodule Thunderline.Thunderflow.Observability.QueueDepthCollector do
  @moduledoc """
  Queue depth derivative collector with trend analysis and P95 calculations.

  Provides sliding window analysis of Oban queue depths, tracking:
  - Current depth per queue
  - Depth delta (rate of change)  
  - P95 depth over time window
  - Queue saturation indicators

  ## Metrics Emitted

  - `[:thunderline, :queue, :depth]` - Current depth measurements
  - `[:thunderline, :queue, :trend]` - Delta and trend analysis
  - `[:thunderline, :queue, :saturation]` - Warning signals

  ## Configuration

      config :thunderline, :queue_metrics,
        collection_interval: 5_000,  # 5 seconds
        trend_window_size: 60,       # 60 samples (5 min history)
        saturation_threshold: 0.8    # 80% of max_queue_size
  """

  use GenServer
  require Logger

  @collection_interval Application.compile_env(
                         :thunderline,
                         [:queue_metrics, :collection_interval],
                         5_000
                       )
  @trend_window_size Application.compile_env(
                       :thunderline,
                       [:queue_metrics, :trend_window_size],
                       60
                     )
  @saturation_threshold Application.compile_env(
                          :thunderline,
                          [:queue_metrics, :saturation_threshold],
                          0.8
                        )

  defstruct [
    :depth_history,
    :last_collection,
    :trend_buffer,
    :queue_configs
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current queue depth statistics for BRG reporting.

  Returns map with current depths, P95, trend indicators.
  """
  def get_queue_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Get P95 queue depth across all queues for threshold checking.
  """
  def get_p95_depth do
    case get_queue_stats() do
      %{p95_depth: p95} -> p95
      _ -> 0
    end
  end

  @doc """
  Check if any queue is approaching saturation.

  Returns `:ok` or `{:warning, details}`.
  """
  def check_saturation do
    GenServer.call(__MODULE__, :check_saturation)
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    # Get Oban queue configuration
    oban_config = Application.get_env(:thunderline, Oban, [])
    queue_configs = extract_queue_configs(oban_config)

    state = %__MODULE__{
      depth_history: %{},
      last_collection: System.monotonic_time(:millisecond),
      trend_buffer: :queue.new(),
      queue_configs: queue_configs
    }

    # Start collection timer
    schedule_collection()

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = calculate_current_stats(state)
    {:reply, stats, state}
  end

  def handle_call(:check_saturation, _from, state) do
    result = check_queue_saturation(state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:collect_depths, state) do
    new_state = collect_queue_depths(state)
    schedule_collection()
    {:noreply, new_state}
  end

  # Private functions

  defp schedule_collection do
    Process.send_after(self(), :collect_depths, @collection_interval)
  end

  defp extract_queue_configs(oban_config) do
    case Keyword.get(oban_config, :queues) do
      nil ->
        # Default queue configuration
        %{"default" => 10}

      queues when is_list(queues) ->
        Map.new(queues)

      queues when is_map(queues) ->
        queues
    end
  end

  defp collect_queue_depths(state) do
    timestamp = System.monotonic_time(:millisecond)

    # Collect current depths from Oban
    current_depths =
      state.queue_configs
      |> Map.keys()
      |> Enum.map(fn queue_name ->
        depth = get_oban_queue_depth(queue_name)
        {queue_name, depth}
      end)
      |> Map.new()

    # Calculate deltas from previous collection
    deltas =
      calculate_depth_deltas(
        current_depths,
        state.depth_history,
        timestamp - state.last_collection
      )

    # Update trend buffer with new measurements
    trend_sample = %{
      timestamp: timestamp,
      depths: current_depths,
      deltas: deltas
    }

    new_trend_buffer = add_to_trend_buffer(state.trend_buffer, trend_sample)

    # Emit telemetry
    emit_depth_telemetry(current_depths, deltas)

    # Update state
    %{
      state
      | depth_history: current_depths,
        last_collection: timestamp,
        trend_buffer: new_trend_buffer
    }
  end

  defp get_oban_queue_depth(queue_name) do
    try do
      # Query Oban for current queue depth
      case Oban.check_queue(queue: queue_name) do
        %{available: available, executing: executing, scheduled: scheduled, retryable: retryable} ->
          available + executing + scheduled + retryable

        _ ->
          0
      end
    rescue
      _ -> 0
    end
  end

  defp calculate_depth_deltas(current_depths, previous_depths, time_delta_ms) do
    if map_size(previous_depths) == 0 do
      # First collection - no deltas available
      Map.new(current_depths, fn {queue, _depth} -> {queue, 0.0} end)
    else
      time_delta_sec = time_delta_ms / 1000.0

      Map.new(current_depths, fn {queue, current_depth} ->
        previous_depth = Map.get(previous_depths, queue, 0)
        delta_per_sec = (current_depth - previous_depth) / time_delta_sec
        {queue, delta_per_sec}
      end)
    end
  end

  defp add_to_trend_buffer(buffer, sample) do
    new_buffer = :queue.in(sample, buffer)

    # Trim to window size
    if :queue.len(new_buffer) > @trend_window_size do
      {_old_sample, trimmed_buffer} = :queue.out(new_buffer)
      trimmed_buffer
    else
      new_buffer
    end
  end

  defp emit_depth_telemetry(depths, deltas) do
    # Emit current depth measurements
    Enum.each(depths, fn {queue, depth} ->
      :telemetry.execute(
        [:thunderline, :queue, :depth],
        %{current_depth: depth},
        %{queue: queue}
      )
    end)

    # Emit trend analysis
    Enum.each(deltas, fn {queue, delta} ->
      :telemetry.execute(
        [:thunderline, :queue, :trend],
        %{depth_delta: delta},
        %{queue: queue, trend: classify_trend(delta)}
      )
    end)
  end

  defp classify_trend(delta) when delta > 2.0, do: :growing_fast
  defp classify_trend(delta) when delta > 0.5, do: :growing
  defp classify_trend(delta) when delta < -2.0, do: :shrinking_fast
  defp classify_trend(delta) when delta < -0.5, do: :shrinking
  defp classify_trend(_delta), do: :stable

  defp calculate_current_stats(state) do
    if :queue.is_empty(state.trend_buffer) do
      %{
        current_depths: %{},
        total_depth: 0,
        p95_depth: 0,
        max_depth: 0,
        trend_analysis: %{},
        collection_count: 0
      }
    else
      samples = :queue.to_list(state.trend_buffer)

      # Extract all depth measurements across time
      all_depths =
        samples
        |> Enum.flat_map(fn %{depths: depths} -> Map.values(depths) end)
        |> Enum.sort()

      # Current state
      current_sample = List.last(samples)
      current_depths = current_sample.depths

      # Trend analysis per queue
      trend_analysis = analyze_queue_trends(samples)

      %{
        current_depths: current_depths,
        total_depth: Enum.sum(Map.values(current_depths)),
        p95_depth: calculate_percentile(all_depths, 0.95),
        max_depth: Enum.max(all_depths, fn -> 0 end),
        trend_analysis: trend_analysis,
        collection_count: length(samples)
      }
    end
  end

  defp analyze_queue_trends(samples) do
    # Group samples by queue and calculate trend indicators
    queue_names =
      samples
      |> List.first()
      |> Map.get(:depths, %{})
      |> Map.keys()

    Map.new(queue_names, fn queue ->
      queue_depths =
        Enum.map(samples, fn sample ->
          Map.get(sample.depths, queue, 0)
        end)

      queue_deltas =
        Enum.map(samples, fn sample ->
          Map.get(sample.deltas, queue, 0.0)
        end)

      trend_info = %{
        recent_p95: calculate_percentile(queue_depths, 0.95),
        avg_delta: calculate_mean(queue_deltas),
        volatility: calculate_volatility(queue_depths),
        is_growing: calculate_mean(queue_deltas) > 0.1
      }

      {queue, trend_info}
    end)
  end

  defp check_queue_saturation(state) do
    current_stats = calculate_current_stats(state)

    saturated_queues =
      Enum.filter(current_stats.current_depths, fn {queue, depth} ->
        # Default max
        max_size = Map.get(state.queue_configs, queue, 100)
        saturation_ratio = depth / max_size
        saturation_ratio > @saturation_threshold
      end)

    if length(saturated_queues) > 0 do
      details = %{
        saturated_queues: saturated_queues,
        threshold: @saturation_threshold,
        p95_depth: current_stats.p95_depth
      }

      # Emit saturation warning telemetry
      :telemetry.execute(
        [:thunderline, :queue, :saturation],
        %{saturated_count: length(saturated_queues)},
        details
      )

      {:warning, details}
    else
      :ok
    end
  end

  defp calculate_percentile([], _percentile), do: 0

  defp calculate_percentile(sorted_values, percentile) do
    index = round(percentile * (length(sorted_values) - 1))
    Enum.at(sorted_values, index, 0)
  end

  defp calculate_mean([]), do: 0.0

  defp calculate_mean(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_volatility(values) when length(values) < 2, do: 0.0

  defp calculate_volatility(values) do
    mean = calculate_mean(values)

    variance =
      values
      |> Enum.map(fn val -> :math.pow(val - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end
end
