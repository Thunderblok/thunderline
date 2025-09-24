defmodule Thunderline.ThunderBridge do
  @moduledoc """
  Main bridge interface for Thunderline dashboard integration.

  This module serves as the primary interface between the Phoenix LiveView
  dashboard and the underlying Erlang cellular automata system. It provides
  a clean, stable API for dashboard components while managing the complexity
  of Erlang integration internally.

  ## Features

  - Real-time system metrics
  - Event streaming and subscriptions
  - Command execution interface
  - Automatic reconnection and fault tolerance
  - Performance monitoring and metrics

  ## Usage

      # Get system state for dashboard
      {:ok, state} = ThunderBridge.get_system_state()

      # Execute CA commands
      :ok = ThunderBridge.execute_command(:start_evolution, bolt_id)

      # Subscribe to events
      ThunderBridge.subscribe_dashboard_events(self())
  """

  use GenServer
  require Logger

  # Legacy ErlangBridge fully removed; ThunderBridge now operates purely via
  # Elixir ThunderCell components. Any former legacy calls return :unsupported.
  alias Thunderline.{EventBus}
  alias Thunderline.Thunderbolt.ThunderCell.Aggregator, as: ThunderCellAggregator

  # Public API

  @doc "Start the ThunderBridge GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get comprehensive system state for dashboard display"
  def get_system_state do
    GenServer.call(__MODULE__, :get_system_state, 10_000)
  end

  @doc "Get ThunderBolt registry for CA panel"
  def get_thunderbolt_registry do
    GenServer.call(__MODULE__, :get_thunderbolt_registry, 5_000)
  end

  @doc "Get ThunderBit observer data for monitoring"
  def get_thunderbit_observer do
    GenServer.call(__MODULE__, :get_thunderbit_observer, 5_000)
  end

  @doc "Execute command on CA system"
  def execute_command(command, params \\ []) do
    GenServer.call(__MODULE__, {:execute_command, command, params}, 5_000)
  end

  @doc "Subscribe to dashboard-relevant events"
  def subscribe_dashboard_events(subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe_dashboard, subscriber_pid})
  end

  @doc "Get performance metrics for system health panel"
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics, 5_000)
  end

  @doc "Get CA evolution statistics"
  def get_evolution_stats do
    GenServer.call(__MODULE__, :get_evolution_stats, 5_000)
  end

  @doc "Start real-time CA data streaming"
  def start_ca_streaming(opts \\ []) do
    GenServer.call(__MODULE__, {:start_ca_streaming, opts})
  end

  @doc "Stop CA data streaming"
  def stop_ca_streaming do
    GenServer.call(__MODULE__, :stop_ca_streaming)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    Logger.info("Starting ThunderBridge...")

  # Legacy subscription removed; no-op.


    state = %{
      dashboard_subscribers: MapSet.new(),
      last_system_state: %{},
      performance_history: [],
      ca_streaming: false,
      opts: opts,
      erlang_connected: false
    }

    # Start periodic health checks
    :timer.send_interval(30_000, self(), :health_check)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_system_state, _from, state) do
    case build_dashboard_system_state() do
      {:ok, system_state} ->
        {:reply, {:ok, system_state}, %{state | last_system_state: system_state}}

      {:error, reason} ->
        # Return cached state if available, otherwise error
        case state.last_system_state do
          %{} = cached when map_size(cached) > 0 ->
            Logger.warning("Using cached system state due to error: #{inspect(reason)}")
            cached_with_warning = Map.put(cached, :connection_warning, true)
            {:reply, {:ok, cached_with_warning}, state}

          _ ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:get_thunderbolt_registry, _from, state) do
    {:reply, {:error, :unsupported}, state}
  end

  def handle_call(:get_thunderbit_observer, _from, state) do
    {:reply, {:error, :unsupported}, state}
  end

  def handle_call({:execute_command, command, params}, _from, state) do
    Logger.info("Executing CA command: #{command} with params: #{inspect(params)}")

  result = {:error, :unsupported}

    # Broadcast command result to dashboard subscribers
    broadcast_to_dashboard_subscribers(state.dashboard_subscribers, {
      :command_result,
      command,
      params,
      result
    })

    {:reply, result, state}
  end

  def handle_call({:subscribe_dashboard, subscriber_pid}, _from, state) do
    new_subscribers = MapSet.put(state.dashboard_subscribers, subscriber_pid)
    Process.monitor(subscriber_pid)

    Logger.debug("Dashboard subscriber added: #{inspect(subscriber_pid)}")
    {:reply, :ok, %{state | dashboard_subscribers: new_subscribers}}
  end

  def handle_call(:get_performance_metrics, _from, state) do
    metrics = calculate_performance_metrics(state.performance_history)
    {:reply, {:ok, metrics}, state}
  end

  def handle_call(:get_evolution_stats, _from, state) do
    case get_ca_evolution_statistics() do
      {:ok, stats} -> {:reply, {:ok, stats}, state}
    end
  end

  def handle_call({:start_ca_streaming, _opts}, _from, state) do
    {:reply, {:error, :unsupported}, state}
  end

  def handle_call(:stop_ca_streaming, _from, state) do
    {:reply, {:error, :unsupported}, state}
  end

  @impl true
  def handle_info({:erlang_state_update, new_state}, state) do
    # Process Erlang state update and broadcast to dashboard
    dashboard_state = transform_erlang_state_for_dashboard(new_state)

    broadcast_to_dashboard_subscribers(state.dashboard_subscribers, {
      :system_state_update,
      dashboard_state
    })

    # Update performance history
    new_history = update_performance_history(state.performance_history, new_state)

    {:noreply,
     %{
       state
       | last_system_state: dashboard_state,
         performance_history: new_history,
         erlang_connected: true
     }}
  end

  def handle_info({:EXIT, _from, reason}, state) do
    # In case linked processes exit unexpectedly, downgrade impact
    Logger.warning("Linked process exit observed in ThunderBridge: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:event_bus, "system_metrics", metrics}, state) do
    # Forward EventBus metrics to dashboard subscribers
    broadcast_to_dashboard_subscribers(state.dashboard_subscribers, {
      :metrics_update,
      metrics
    })

    {:noreply, state}
  end

  def handle_info({:event_bus, "erlang_commands", command_event}, state) do
    # Forward command events to dashboard subscribers
    broadcast_to_dashboard_subscribers(state.dashboard_subscribers, {
      :command_event,
      command_event
    })

    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    # Perform periodic health check
    health_status = check_system_health()

    if health_status.erlang_connected != state.erlang_connected do
      Logger.info("Erlang connection status changed: #{health_status.erlang_connected}")

      broadcast_to_dashboard_subscribers(state.dashboard_subscribers, {
        :connection_status_changed,
        health_status.erlang_connected
      })
    end

    {:noreply, %{state | erlang_connected: health_status.erlang_connected}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead dashboard subscriber
    new_subscribers = MapSet.delete(state.dashboard_subscribers, pid)
    Logger.debug("Dashboard subscriber removed: #{inspect(pid)}")
    {:noreply, %{state | dashboard_subscribers: new_subscribers}}
  end

  def handle_info({:system_metric_updated, metric_data}, state) do
    # Handle system metric updates - forward to dashboard subscribers if needed
    Logger.debug("Received system metric update: #{inspect(metric_data)}")

    # Optionally forward to dashboard subscribers
    # broadcast_to_dashboard_subscribers(state, {:metric_update, metric_data})

    {:noreply, state}
  end

  def handle_info(msg, state) do
  # Push to noise buffer instead of spamming logs; dashboard can pull
    Thunderline.Thunderflow.Observability.RingBuffer.push({:thunder_bridge, msg}, Thunderline.NoiseBuffer)
    {:noreply, state}
  end

  # Defensive subscription wrapper so missing ErlangBridge doesn't crash init
  defp subscribe_erlang_bridge, do: :ok

  # Private Functions

  defp build_dashboard_system_state do
    # Phase 1: Prefer pure Elixir ThunderCell aggregator; fallback to Erlang bridge if needed
    case ThunderCellAggregator.get_system_state() do
      {:ok, agg} -> {:ok, build_dashboard_state_from_aggregator(agg)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_dashboard_state_from_aggregator(%{clusters: clusters, telemetry: telemetry, system: system}) do
    generation_stats = Map.get(telemetry, :generation_stats, %{})
    avg_gen_time = Map.get(generation_stats, :avg_generation_time, 0.0)
    performance = %{
      thunderbolts_per_second: 0.0,
      chunks_per_second: 0.0,
      memory_efficiency: 0.0,
      response_time: avg_gen_time
    }
    total_cells = Enum.reduce(clusters, 0, fn c, acc -> acc + (c[:cell_count] || 0) end)
    %{
      timestamp: DateTime.utc_now(),
      uptime: system[:uptime_ms],
      active_thunderbolts: length(clusters),
      total_chunks: total_cells,
      connected_nodes: system[:connected_nodes],
      memory_usage: system[:memory_usage],
      performance: performance,
      health_status: :healthy,
      connection_status: :connected,
      ca_activity: build_ca_activity_from_clusters(clusters, generation_stats),
      event_metrics: build_event_metrics_from_clusters(clusters),
      source: :aggregator
    }
  end

  defp build_ca_activity_from_clusters(clusters, generation_stats) do
    %{
      evolution_active: Enum.any?(clusters, &(not &1.paused)),
      generation_count: Map.get(generation_stats, :total_generations, estimate_generation(clusters)),
      mutation_rate: 0.0,
      energy_level: 0.0
    }
  end

  defp estimate_generation(clusters) do
    clusters
    |> Enum.map(&(&1.generation || 0))
    |> Enum.max(fn -> 0 end)
  end

  defp build_event_metrics_from_clusters(_clusters) do
    %{
      events_per_second: 0.0,
      stream_active: false,
      subscribers: 0
    }
  end

  defp transform_thunderbolt_registry(registry) when is_list(registry) do
    %{
      total_thunderbolts: length(registry),
      active_thunderbolts: count_active_bolts(registry),
      thunderbolts: Enum.map(registry, &format_thunderbolt_for_dashboard/1),
      last_updated: DateTime.utc_now()
    }
  end

  defp transform_thunderbolt_registry(registry), do: registry

  defp transform_thunderbit_data(observer_data) do
    %{
      observations_count: Map.get(observer_data, :active_observations, 0),
      monitoring_zones: Map.get(observer_data, :monitoring_zones, []),
      data_quality: Map.get(observer_data, :data_quality, 1.0),
      scan_frequency: Map.get(observer_data, :scan_frequency, 1.0),
      last_scan: Map.get(observer_data, :last_scan, DateTime.utc_now())
    }
  end

  defp transform_erlang_state_for_dashboard(erlang_state) do
    %{
      thunderbolt_metrics: extract_thunderbolt_metrics(erlang_state),
      thunderbit_metrics: extract_thunderbit_metrics(erlang_state),
      evolution_metrics: extract_evolution_metrics(erlang_state),
      stream_metrics: extract_stream_metrics(erlang_state),
      system_performance: extract_performance_metrics(erlang_state),
      timestamp: DateTime.utc_now()
    }
  end

  defp calculate_uptime(erlang_state) do
    # Extract uptime from Erlang state or calculate from start time
    case get_in(erlang_state, [:thunderbolt_registry, :uptime]) do
      uptime when is_integer(uptime) -> uptime
      # Fallback for now
      _ -> :rand.uniform(10000)
    end
  end

  defp count_active_thunderbolts(erlang_state) do
    case get_in(erlang_state, [:thunderbolt_registry, :active_count]) do
      count when is_integer(count) -> count
      # Fallback
      _ -> :rand.uniform(50)
    end
  end

  # Standard 12x12 grid
  defp get_total_chunks(_erlang_state), do: 144

  defp get_connected_nodes(erlang_state) do
    case get_in(erlang_state, [:system, :connected_nodes]) do
      nodes when is_list(nodes) -> length(nodes)
      count when is_integer(count) -> count
      # At least this node
      _ -> 1
    end
  end

  defp get_memory_usage(erlang_state) do
    case get_in(erlang_state, [:system, :memory_usage]) do
      memory when is_integer(memory) -> memory
      # Get actual Erlang memory
      _ -> :erlang.memory(:total)
    end
  end

  defp calculate_current_performance(erlang_state) do
    %{
      thunderbolts_per_second: get_in(erlang_state, [:performance, :bolts_per_second]) || 0.0,
      chunks_per_second: get_in(erlang_state, [:performance, :chunks_per_second]) || 0.0,
      memory_efficiency: get_in(erlang_state, [:performance, :memory_efficiency]) || 0.0,
      response_time: get_in(erlang_state, [:performance, :response_time]) || 0.0
    }
  end

  defp get_ca_activity(erlang_state) do
    %{
      evolution_active: get_in(erlang_state, [:thunderbolt_evolution, :active]) || false,
      generation_count: get_in(erlang_state, [:thunderbolt_evolution, :generation]) || 0,
      mutation_rate: get_in(erlang_state, [:thunderbolt_evolution, :mutation_rate]) || 0.0,
      energy_level: get_in(erlang_state, [:thunderbolt_evolution, :energy_level]) || 0.0
    }
  end

  defp get_event_metrics(erlang_state) do
    %{
      events_per_second: get_in(erlang_state, [:thunderbolt_stream, :events_per_second]) || 0.0,
      stream_active: get_in(erlang_state, [:thunderbolt_stream, :streaming]) || false,
      subscribers: get_in(erlang_state, [:thunderbolt_stream, :subscriber_count]) || 0
    }
  end

  defp count_active_bolts(registry) do
    Enum.count(registry, fn bolt ->
      Map.get(bolt, :status) == :active
    end)
  end

  defp format_thunderbolt_for_dashboard(bolt) do
    %{
      id: Map.get(bolt, :id),
      status: Map.get(bolt, :status, :unknown),
      energy: Map.get(bolt, :energy, 0),
      generation: Map.get(bolt, :generation, 0),
      last_active: Map.get(bolt, :last_update, DateTime.utc_now()),
      health: calculate_bolt_health(bolt)
    }
  end

  defp calculate_bolt_health(bolt) do
    energy = Map.get(bolt, :energy, 0)

    cond do
      energy > 80 -> :excellent
      energy > 60 -> :good
      energy > 40 -> :fair
      energy > 20 -> :poor
      true -> :critical
    end
  end

  defp get_ca_evolution_statistics do
    # Prefer Elixir aggregator; fallback to legacy Erlang system state
    case ThunderCellAggregator.get_system_state() do
      {:ok, agg} ->
        {:ok, get_evolution_stats_from_aggregator(agg)}

      {:error, _} ->
        {:ok,
         %{
           total_generations: 0,
           mutations_count: 0,
           evolution_rate: 0.0,
           active_patterns: [],
           success_rate: 0.0,
           source: :none
         }}
    end
  end

  defp calculate_performance_metrics(performance_history) do
    if performance_history != [] do
      recent_metrics = Enum.take(performance_history, -10)

      %{
        avg_response_time: calculate_average(recent_metrics, :response_time),
        avg_throughput: calculate_average(recent_metrics, :throughput),
        avg_memory_usage: calculate_average(recent_metrics, :memory_usage),
        trend: calculate_trend(recent_metrics),
        health_score: calculate_health_score(recent_metrics)
      }
    else
      %{
        avg_response_time: 0.0,
        avg_throughput: 0.0,
        avg_memory_usage: 0.0,
        trend: :stable,
        health_score: 1.0
      }
    end
  end

  defp update_performance_history(history, new_state) do
    new_metric = %{
      timestamp: DateTime.utc_now(),
      response_time: get_in(new_state, [:performance, :response_time]) || 0.0,
      throughput: get_in(new_state, [:performance, :throughput]) || 0.0,
      memory_usage: get_in(new_state, [:system, :memory_usage]) || 0
    }

    # Keep last 100 metrics
    [new_metric | Enum.take(history, 99)]
  end

  defp check_system_health do
    # Primary health from aggregator (Elixir ThunderCell path)
    case ThunderCellAggregator.get_system_state() do
      {:ok, _agg} -> %{erlang_connected: true, health: :healthy, source: :aggregator}
      {:error, _} -> %{erlang_connected: false, health: :degraded, source: :none}
    end
  end

  defp extract_thunderbolt_metrics(state), do: Map.get(state, :thunderbolt_registry, %{})
  defp extract_thunderbit_metrics(state), do: Map.get(state, :thunderbit_observer, %{})
  defp extract_evolution_metrics(state), do: Map.get(state, :thunderbolt_evolution, %{})
  defp extract_stream_metrics(state), do: Map.get(state, :thunderbolt_stream, %{})
  defp extract_performance_metrics(state), do: Map.get(state, :performance, %{})

  defp calculate_average(metrics, field) do
    values = Enum.map(metrics, &Map.get(&1, field, 0))

    case values do
      [] -> 0.0
      _ -> Enum.sum(values) / length(values)
    end
  end

  defp calculate_trend(metrics) when length(metrics) < 2, do: :stable

  defp calculate_trend(metrics) do
    recent = Enum.take(metrics, -5)
    older = Enum.take(metrics, 5)

    recent_avg = calculate_average(recent, :response_time)
    older_avg = calculate_average(older, :response_time)

    cond do
      recent_avg > older_avg * 1.1 -> :degrading
      recent_avg < older_avg * 0.9 -> :improving
      true -> :stable
    end
  end

  defp calculate_health_score(metrics) do
    # Simple health score based on recent performance
    recent_metrics = Enum.take(metrics, -5)

    if length(recent_metrics) == 0 do
      1.0
    else
      avg_response = calculate_average(recent_metrics, :response_time)
      # Health score inversely related to response time
      max(0.0, min(1.0, 1.0 - avg_response / 1000.0))
    end
  end

  defp broadcast_to_dashboard_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber ->
      send(subscriber, message)
    end)
  end

  # ------------------------------------------------------------------
  # Aggregator evolution stats synthesis
  # ------------------------------------------------------------------
  defp get_evolution_stats_from_aggregator(%{telemetry: %{generation_stats: gen_stats}}) do
    %{
      total_generations: Map.get(gen_stats, :total_generations, 0),
      mutations_count: 0, # Not yet tracked in Elixir path
      evolution_rate: Map.get(gen_stats, :avg_generation_time, 0.0),
      active_patterns: [],
      success_rate: 0.0,
      source: :aggregator
    }
  end

  defp get_evolution_stats_from_aggregator(_), do: %{
    total_generations: 0,
    mutations_count: 0,
    evolution_rate: 0.0,
    active_patterns: [],
    success_rate: 0.0,
    source: :aggregator
  }

  # Legacy helper removed; all legacy calls now return {:error, :unsupported}
end
