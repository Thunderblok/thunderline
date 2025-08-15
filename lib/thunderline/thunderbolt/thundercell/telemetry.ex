defmodule Thunderline.Thunderbolt.ThunderCell.Telemetry do
  @moduledoc """
  Collects and manages performance metrics for the THUNDERCELL compute layer.
  Provides telemetry data to Thunderlane orchestration for monitoring.
  """

  use GenServer
  require Logger

  # 5 seconds
  @collection_interval 5_000

  defstruct [
    :start_time,
    :collection_timer,
    metrics: %{}
  ]

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start do
    GenServer.call(__MODULE__, :start_monitoring)
  end

  def get_compute_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  def record_generation_time(cluster_id, generation_time) do
    GenServer.cast(__MODULE__, {:generation_time, cluster_id, generation_time})
  end

  def record_cluster_event(cluster_id, event) do
    GenServer.cast(__MODULE__, {:cluster_event, cluster_id, event})
  end

  def get_performance_report do
    GenServer.call(__MODULE__, :get_performance_report)
  end

  # ====================================================================
  # GenServer callbacks
  # ====================================================================

  @impl true
  def init(opts) do
    state = %__MODULE__{
      metrics: initialize_metrics(),
      start_time: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start_monitoring, _from, state) do
    timer = Process.send_after(self(), :collect_metrics, @collection_interval)
    {:reply, :ok, %{state | collection_timer: timer}}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = prepare_metrics_for_thunderlane(state)
    {:reply, {:ok, metrics}, state}
  end

  def handle_call(:get_performance_report, _from, state) do
    report = generate_performance_report(state)
    {:reply, {:ok, report}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:generation_time, cluster_id, generation_time}, state) do
    new_metrics = update_generation_metrics(state.metrics, cluster_id, generation_time)
    {:noreply, %{state | metrics: new_metrics}}
  end

  def handle_cast({:cluster_event, cluster_id, event}, state) do
    new_metrics = update_cluster_event_metrics(state.metrics, cluster_id, event)
    {:noreply, %{state | metrics: new_metrics}}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect system metrics
    system_metrics = collect_system_metrics()
    new_metrics = Map.merge(state.metrics, system_metrics)

    # Schedule next collection
    timer = Process.send_after(self(), :collect_metrics, @collection_interval)

    updated_state = %{state | metrics: new_metrics, collection_timer: timer}
    {:noreply, updated_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    case state.collection_timer do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # ====================================================================
  # Internal functions
  # ====================================================================

  defp initialize_metrics do
    %{
      cluster_metrics: %{},
      system_metrics: %{},
      performance_history: [],
      generation_stats: %{
        total_generations: 0,
        total_generation_time: 0,
        avg_generation_time: 0.0,
        min_generation_time: :infinity,
        max_generation_time: 0
      }
    }
  end

  defp update_generation_metrics(metrics, cluster_id, generation_time) do
    # Update cluster-specific metrics
    cluster_metrics = Map.get(metrics, :cluster_metrics, %{})

    cluster_stats =
      Map.get(cluster_metrics, cluster_id, %{
        generations: 0,
        total_time: 0,
        avg_time: 0.0,
        min_time: :infinity,
        max_time: 0
      })

    new_generations = Map.get(cluster_stats, :generations) + 1
    new_total_time = Map.get(cluster_stats, :total_time) + generation_time
    new_avg_time = new_total_time / new_generations

    updated_cluster_stats = %{
      cluster_stats
      | generations: new_generations,
        total_time: new_total_time,
        avg_time: new_avg_time,
        min_time: min(Map.get(cluster_stats, :min_time), generation_time),
        max_time: max(Map.get(cluster_stats, :max_time), generation_time),
        last_generation_time: generation_time
    }

    updated_cluster_metrics = Map.put(cluster_metrics, cluster_id, updated_cluster_stats)

    # Update global generation stats
    global_stats = Map.get(metrics, :generation_stats)
    global_generations = Map.get(global_stats, :total_generations) + 1
    global_total_time = Map.get(global_stats, :total_generation_time) + generation_time
    global_avg_time = global_total_time / global_generations

    updated_global_stats = %{
      global_stats
      | total_generations: global_generations,
        total_generation_time: global_total_time,
        avg_generation_time: global_avg_time,
        min_generation_time: min(Map.get(global_stats, :min_generation_time), generation_time),
        max_generation_time: max(Map.get(global_stats, :max_generation_time), generation_time)
    }

    %{metrics | cluster_metrics: updated_cluster_metrics, generation_stats: updated_global_stats}
  end

  defp update_cluster_event_metrics(metrics, cluster_id, event) do
    cluster_metrics = Map.get(metrics, :cluster_metrics, %{})
    cluster_stats = Map.get(cluster_metrics, cluster_id, %{})

    events = Map.get(cluster_stats, :events, [])
    timestamp = System.monotonic_time(:millisecond)

    # Keep only last 100 events per cluster
    new_events = [{timestamp, event} | events] |> Enum.take(100)

    updated_cluster_stats = Map.put(cluster_stats, :events, new_events)
    updated_cluster_metrics = Map.put(cluster_metrics, cluster_id, updated_cluster_stats)

    Map.put(metrics, :cluster_metrics, updated_cluster_metrics)
  end

  defp collect_system_metrics do
    %{
      system_metrics: %{
        timestamp: System.monotonic_time(:millisecond),
        memory_usage: :erlang.memory(),
        process_count: :erlang.system_info(:process_count),
        schedulers: :erlang.system_info(:schedulers),
        scheduler_utilization: get_scheduler_utilization(),
        node_name: Node.self(),
        uptime: get_uptime()
      }
    }
  end

  defp get_scheduler_utilization do
    # Get scheduler utilization if available
    try do
      :erlang.statistics(:scheduler_wall_time_all)
    rescue
      _ -> nil
    end
  end

  defp get_uptime do
    {up_time, _} = :erlang.statistics(:wall_clock)
    up_time
  end

  defp prepare_metrics_for_thunderlane(state) do
    current_time = System.monotonic_time(:millisecond)
    uptime = current_time - state.start_time

    %{
      node: Node.self(),
      timestamp: current_time,
      uptime_ms: uptime,
      thundercell_version: "1.0.0",
      metrics: state.metrics
    }
  end

  defp generate_performance_report(state) do
    metrics = state.metrics
    cluster_metrics = Map.get(metrics, :cluster_metrics, %{})
    global_stats = Map.get(metrics, :generation_stats)
    system_metrics = Map.get(metrics, :system_metrics, %{})

    %{
      summary: %{
        total_clusters: map_size(cluster_metrics),
        total_generations: Map.get(global_stats, :total_generations, 0),
        avg_generation_time: Map.get(global_stats, :avg_generation_time, 0.0),
        node_uptime: get_uptime()
      },
      cluster_performance: cluster_metrics,
      system_performance: system_metrics,
      generated_at: System.monotonic_time(:millisecond)
    }
  end
end
