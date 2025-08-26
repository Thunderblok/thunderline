defmodule Thunderline.DashboardMetrics do
  @moduledoc """
  DashboardMetrics - Real-time metrics collection and dashboard data provider

  Provides structured metrics data for the LiveView dashboard including:
  - System health metrics
  - Event processing statistics
  - Agent performance data
  - Resource utilization
  - Real-time updates via PubSub
  """

  use GenServer
  require Logger

  alias Thunderline.ThunderMemory
  alias Phoenix.PubSub

  @pubsub_topic "dashboard:metrics"
  # 5 seconds
  @metrics_update_interval 5_000

  ## Public API

  @doc "Start the DashboardMetrics system"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current system metrics"
  def get_system_metrics do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  @doc "Get event processing metrics"
  def get_event_metrics do
    GenServer.call(__MODULE__, :get_event_metrics)
  end

  @doc "Get agent performance metrics"
  def get_agent_metrics do
    GenServer.call(__MODULE__, :get_agent_metrics)
  end

  @doc "Get real-time dashboard data"
  def get_dashboard_data do
  data = GenServer.call(__MODULE__, :get_dashboard_data)
  normalize_domain_keys(data)
  end

  @doc "Subscribe to real-time metrics updates"
  def subscribe do
    PubSub.subscribe(Thunderline.PubSub, @pubsub_topic)
  end

  @doc "Unsubscribe from metrics updates"
  def unsubscribe do
    PubSub.unsubscribe(Thunderline.PubSub, @pubsub_topic)
  end

  ## Domain-specific metrics functions for DashboardLive

  @doc "Get ThunderCore metrics"
  def thundercore_metrics do
    # System monitoring not yet implemented
    %{
      # TODO: Implement CPU monitoring
      cpu_usage: "OFFLINE",
      # TODO: Implement memory monitoring
      memory_usage: "OFFLINE",
      # TODO: Implement process counting
      active_processes: "OFFLINE",
      # This works - system uptime
      uptime: System.monotonic_time(:second),
      # TODO: Implement real uptime percentage tracking
      uptime_percent: "99.5%"
    }
  end

  @doc "Get ThunderBit metrics"
  def thunderbit_metrics do
    # AI Agent performance not yet implemented
    %{
      # TODO: Implement agent counting
      total_agents: "OFFLINE",
      # TODO: Implement active agent tracking
      active_agents: "OFFLINE",
      # TODO: Implement NN status
      neural_networks: "OFFLINE",
      # TODO: Implement inference tracking
      inference_rate: "OFFLINE",
      # TODO: Implement accuracy monitoring
      model_accuracy: "OFFLINE",
      # TODO: Implement memory tracking
      memory_usage_mb: "OFFLINE"
    }
  end

  @doc "Get ThunderLane cluster metrics"
  def thunderlane_metrics do
    # Network and cluster metrics
    mnesia_status = get_mnesia_status()

    %{
      total_nodes: length(mnesia_status.nodes),
      # TODO: Implement real ops/sec tracking
      current_ops_per_sec: "OFFLINE",
      uptime: get_system_uptime_percentage(),
      # TODO: Implement cache metrics
      cache_hit_rate: "OFFLINE",
      memory_usage: get_memory_usage_percentage(),
      # TODO: Implement CPU monitoring
      cpu_usage: "OFFLINE",
      # TODO: Implement network monitoring
      network_latency: "OFFLINE",
      # TODO: Implement connection tracking
      active_connections: "OFFLINE",
      # TODO: Implement transfer rate monitoring
      data_transfer_rate: "OFFLINE",
      # TODO: Implement error rate calculation
      error_rate: "OFFLINE"
    }
  end

  @doc "Get ThunderBolt metrics"
  def thunderbolt_metrics do
    # ThunderBolt metrics not yet implemented
    %{
      # TODO: Implement chunk processing tracking
      chunks_processed: "OFFLINE",
      # TODO: Implement scaling tracking
      scaling_operations: "OFFLINE",
      # TODO: Implement efficiency tracking
      resource_efficiency: "OFFLINE",
      # TODO: Implement load balancer monitoring
      load_balancer_health: :offline
    }
  end

  @doc "Get ThunderBlock metrics"
  def thunderblock_metrics do
    # Get real supervision tree and infrastructure metrics
    supervision_stats = get_supervision_tree_stats()
    memory_stats = get_memory_stats()

    %{
      supervision_trees: supervision_stats.total_supervisors,
      health_checks: supervision_stats.health_checks_passed,
      recovery_actions: supervision_stats.restarts_recent,
      system_stability: supervision_stats.stability_score,
      memory_usage_mb: round(memory_stats.total / (1024 * 1024)),
      process_count: supervision_stats.total_processes,
      uptime_hours: round(System.monotonic_time(:second) / 3600)
    }
  end

  @doc "Get ThunderGrid metrics"
  def thundergrid_metrics do
    %{
      # TODO: Implement zone tracking
      active_zones: "OFFLINE",
      # TODO: Implement query monitoring
      spatial_queries: "OFFLINE",
      # TODO: Implement boundary tracking
      boundary_crossings: "OFFLINE",
      # TODO: Implement efficiency calculation
      grid_efficiency: "OFFLINE",
      # TODO: Implement grid node counting
      total_nodes: "OFFLINE",
      # TODO: Implement active node tracking
      active_nodes: "OFFLINE",
      # TODO: Implement load monitoring
      current_load: "OFFLINE",
      # TODO: Implement performance operations tracking
      performance_ops: "OFFLINE",
      # TODO: Implement data stream rate monitoring
      data_stream_rate: "OFFLINE",
      # TODO: Implement storage rate monitoring
      storage_rate: "OFFLINE"
    }
  end

  @doc "Get ThunderBlock Vault (formerly ThunderVault) metrics"
  def thunderblock_vault_metrics do
    %{
      # TODO: Implement decision tracking
      decisions_made: "OFFLINE",
      # TODO: Implement policy monitoring
      policy_evaluations: "OFFLINE",
      # TODO: Implement access tracking
      access_requests: "OFFLINE",
      # TODO: Implement security scoring
      security_score: "OFFLINE"
    }
  end

  @deprecated "Use thunderblock_vault_metrics/0. The thundervault_* naming is being removed; will be deleted after deprecation window."
  @doc "(DEPRECATED) Get ThunderVault metrics – use thunderblock_vault_metrics/0"
  def thundervault_metrics do
    Logger.warning("DEPRECATED call to thundervault_metrics/0 – use thunderblock_vault_metrics/0")
    thunderblock_vault_metrics()
  end

  # --- Normalization Helpers -------------------------------------------------
  defp normalize_domain_keys(%{} = data) do
    data
    |> rename_key(:thundervault, :thunderblock_vault)
  end

  defp rename_key(map, old, new) when is_map(map) do
    case Map.pop(map, old) do
      {nil, _map} -> map
      {val, rest} -> Map.put(rest, new, val)
    end
  end
  defp rename_key(other, _o, _n), do: other

  @doc "Get ThunderCom metrics"
  def thundercom_metrics do
    %{
      # TODO: Implement community tracking
      active_communities: "OFFLINE",
      # TODO: Implement message monitoring
      messages_processed: "OFFLINE",
      # TODO: Implement federation tracking
      federation_connections: "OFFLINE",
      communication_health: :offline
    }
  end

  @doc "Get ThunderEye metrics"
  def thundereye_metrics do
    %{
      # TODO: Implement trace collection
      traces_collected: "OFFLINE",
      # TODO: Implement perf monitoring
      performance_metrics: "OFFLINE",
      # TODO: Implement anomaly detection
      anomaly_detections: "OFFLINE",
      # TODO: Implement coverage tracking
      monitoring_coverage: "OFFLINE"
    }
  end

  @doc "Get ThunderChief metrics"
  def thunderchief_metrics do
    # Get real Oban metrics
    oban_stats = get_oban_stats()
    workflow_stats = get_workflow_stats()

    %{
      orchestration_status: determine_engine_status(oban_stats, workflow_stats),
      active_workflows: workflow_stats.active_workflows,
      queued_tasks: oban_stats.queued_jobs,
      completion_rate: calculate_completion_rate(oban_stats),
      avg_completion_time: oban_stats.avg_completion_time,
      cross_domain_jobs: oban_stats.cross_domain_jobs,
      failed_workflows: workflow_stats.failed_workflows,
      engine_status: determine_engine_status(oban_stats, workflow_stats)
    }
  end

  defp get_oban_stats do
    # Get current Oban queue statistics
    try do
  name = oban_instance_name()
  pid = Oban.whereis(name)
  if pid do
        # Try to get queue stats using a more robust approach
        default_stats = get_queue_stats(:default)
        cross_domain_stats = get_queue_stats(:cross_domain)
        scheduled_stats = get_queue_stats(:scheduled_workflows)

        %{
          queued_jobs: default_stats.queued + cross_domain_stats.queued + scheduled_stats.queued,
          completed_recent: default_stats.completed + cross_domain_stats.completed,
          failed_recent: default_stats.failed + cross_domain_stats.failed,
          cross_domain_jobs: cross_domain_stats.queued + cross_domain_stats.executing,
          # TODO: calculate real average completion time
          avg_completion_time: "OFFLINE"
        }
      else
        log_once(:oban_not_running, fn -> Logger.info("Oban not detected (name=#{inspect(name)}) yet; using default stats") end)
        get_default_oban_stats()
      end
    rescue
      error ->
        Logger.warning("Failed to get Oban stats: #{inspect(error)}")
        get_default_oban_stats()
    end
  end

  defp oban_instance_name do
    Application.get_env(:thunderline, Oban, [])
    |> Keyword.get(:name, Oban)
  end

  # Simple once-only logger keyed by atom using persistent_term
  defp log_once(key, fun) do
    marker = {:dashboard_metrics_once, key}
    case :persistent_term.get(marker, :none) do
      :none ->
        fun.()
        :persistent_term.put(marker, :logged)
      _ -> :ok
    end
  end

  defp get_queue_stats(queue_name) do
  # Never call Oban.drain_queue in metrics collection (it mutates/empties queues).
  # Prefer Oban.peek/2 style inspection if available, else fall back to DB counts (stub 0 for now).
  inspect_queue_directly(queue_name)
  end

  defp inspect_queue_directly(queue_name) do
    try do
      # Query the database directly for job counts
      # This is a simplified approach - in production, use proper Oban telemetry
      %{
        queued: count_jobs_by_state(queue_name, "available"),
        executing: count_jobs_by_state(queue_name, "executing"),
        completed: count_jobs_by_state(queue_name, "completed"),
        failed: count_jobs_by_state(queue_name, "retryable")
      }
    rescue
      _ ->
        %{queued: 0, executing: 0, completed: 0, failed: 0}
    end
  end

  defp count_jobs_by_state(_queue_name, _state) do
    # Job tracking not yet implemented
    # Return 0 instead of random data
    0
  end

  defp get_supervision_tree_stats do
    try do
      # Use the supervision tree mapper to get real stats
      tree = Thunderline.Thundercrown.Introspection.SupervisionTreeMapper.map_supervision_tree()

      analysis =
        Thunderline.Thundercrown.Introspection.SupervisionTreeMapper.analyze_supervision_tree(
          tree
        )

      %{
        total_supervisors: analysis.supervisors,
        total_processes: analysis.total_processes,
        health_checks_passed: analysis.running,
        # Assume not_running = recent restarts
        restarts_recent: max(0, analysis.not_running),
        stability_score:
          if analysis.total_processes > 0 do
            analysis.running / analysis.total_processes
          else
            1.0
          end
      }
    rescue
      error ->
        Logger.debug("Failed to get supervision stats: #{inspect(error)}")

        %{
          # Unable to fetch real data
          total_supervisors: 0,
          # Unable to fetch real data
          total_processes: 0,
          health_checks_passed: 0,
          restarts_recent: 0,
          stability_score: 0.0
        }
    end
  end

  defp get_memory_stats do
    try do
      memory_info = :erlang.memory()

      %{
        total: memory_info[:total] || 0,
        processes: memory_info[:processes] || 0,
        system: memory_info[:system] || 0
      }
    rescue
      _ ->
        # Unable to fetch memory data
        %{total: 0, processes: 0, system: 0}
    end
  end

  # Removed unused detailed agent stats helpers (get_real_agent_stats, get_default_agent_stats,
  # calculate_average_agent_accuracy) to eliminate warnings; simplified metrics elsewhere.

  defp get_default_oban_stats do
    %{
      queued_jobs: 0,
      completed_recent: 0,
      failed_recent: 0,
      cross_domain_jobs: 0,
      avg_completion_time: "0.0s"
    }
  end

  defp get_workflow_stats do
    # Count active workflows from orchestration trackers
    try do
      # Workflow tracking not yet implemented
      %{
        # Real tracking not implemented yet
        active_workflows: 0,
        # Real tracking not implemented yet
        failed_workflows: 0
      }
    rescue
      _ ->
        %{active_workflows: 0, failed_workflows: 0}
    end
  end

  defp calculate_completion_rate(oban_stats) do
    total = oban_stats.completed_recent + oban_stats.failed_recent

    if total > 0 do
      round(oban_stats.completed_recent / total * 100)
    else
      100
    end
  end

  defp determine_engine_status(oban_stats, workflow_stats) do
    cond do
      workflow_stats.failed_workflows > 5 -> "degraded"
      oban_stats.queued_jobs > 100 -> "overloaded"
      workflow_stats.active_workflows > 0 -> "active"
      true -> "idle"
    end
  end

  @doc "Get ThunderFlow metrics"
  def thunderflow_metrics do
    %{
      # TODO: Implement event processing tracking
      events_processed: "OFFLINE",
      # TODO: Implement pipeline monitoring
      pipelines_active: "OFFLINE",
      # TODO: Implement flow rate calculation
      flow_rate: "OFFLINE",
      # TODO: Implement consciousness metrics
      consciousness_level: "OFFLINE"
    }
  end

  @doc "Get ThunderStone metrics"
  def thunderstone_metrics do
    %{
      # TODO: Implement storage operation tracking
      storage_operations: "OFFLINE",
      # TODO: Implement integrity monitoring
      data_integrity: "OFFLINE",
      # TODO: Implement compression tracking
      compression_ratio: "OFFLINE",
      storage_health: :offline
    }
  end

  @doc "Get ThunderLink metrics"
  def thunderlink_metrics do
    %{
      # TODO: Implement connection tracking
      connections_active: "OFFLINE",
      # TODO: Implement throughput monitoring
      data_throughput: "OFFLINE",
      # TODO: Implement latency measurement
      latency_avg: "OFFLINE",
      # TODO: Implement stability scoring
      network_stability: "OFFLINE"
    }
  end

  @doc "Get ThunderCrown metrics"
  def thundercrown_metrics do
    %{
      # TODO: Implement governance tracking
      governance_actions: "OFFLINE",
      # TODO: Implement policy monitoring
      policy_updates: "OFFLINE",
      # TODO: Implement compliance scoring
      compliance_score: "OFFLINE",
      authority_level: :offline
    }
  end

  @doc "Get current automata state"
  def automata_state do
    # Get real automata state from Erlang CA clusters
    real_ca_data = get_real_ca_state()

    %{
      cellular_automata: %{
        active_rules: real_ca_data.active_rules,
        generations: real_ca_data.total_generations,
        complexity_measure: real_ca_data.complexity_measure,
        pattern_stability: real_ca_data.stability_status,
        active_clusters: real_ca_data.cluster_count,
        total_cells: real_ca_data.total_cells,
        alive_cells: real_ca_data.alive_cells
      },
      neural_ca: %{
        learning_rate: real_ca_data.neural_learning_rate,
        convergence: real_ca_data.neural_convergence,
        adaptation_cycles: real_ca_data.adaptation_cycles,
        emergence_detected: real_ca_data.emergence_patterns > 0
      },
      quantum_effects: %{
        entanglement_strength: real_ca_data.quantum_entanglement,
        superposition_states: real_ca_data.superposition_count,
        decoherence_time: real_ca_data.decoherence_ms,
        quantum_advantage: real_ca_data.quantum_speedup > 1.0
      }
    }
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting DashboardMetrics system...")

    # Schedule periodic metrics updates
    schedule_metrics_update()

    initial_state = %{
      system_metrics: %{},
      event_metrics: %{},
      agent_metrics: %{},
      thunderlane: %{},
      last_update: DateTime.utc_now(),
      opts: opts
    }

    # Collect initial metrics
    {:ok, collect_all_metrics(initial_state)}
  end

  @impl true
  def handle_call(:get_system_metrics, _from, state) do
    {:reply, state.system_metrics, state}
  end

  @impl true
  def handle_call(:get_event_metrics, _from, state) do
    {:reply, state.event_metrics, state}
  end

  @impl true
  def handle_call(:get_agent_metrics, _from, state) do
    {:reply, state.agent_metrics, state}
  end

  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    dashboard_data = %{
      system: state.system_metrics,
      events: state.event_metrics,
      agents: state.agent_metrics,
      thunderlane: state.thunderlane,
      last_update: state.last_update,
      timestamp: DateTime.utc_now()
    }

    {:reply, dashboard_data, state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect fresh metrics
    updated_state = collect_all_metrics(state)

    # Publish to subscribers
    publish_metrics_update(updated_state)

    # Schedule next update
    schedule_metrics_update()

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("DashboardMetrics received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp get_real_ca_state do
    # Query actual Erlang CA clusters for real data
    try do
      # Try to get stats from ThunderCell clusters
      cluster_stats = get_thundercell_cluster_stats()

      # Also get stats from LiveView automata
      liveview_stats = get_liveview_automata_stats()

      %{
        active_rules: cluster_stats.active_rules ++ liveview_stats.active_rules,
        total_generations: cluster_stats.total_generations + liveview_stats.generations,
        complexity_measure: calculate_complexity_measure(cluster_stats, liveview_stats),
        stability_status: determine_stability_status(cluster_stats),
        cluster_count: cluster_stats.cluster_count,
        total_cells: cluster_stats.total_cells,
        alive_cells: cluster_stats.alive_cells,
        neural_learning_rate: cluster_stats.neural_learning_rate,
        neural_convergence: cluster_stats.neural_convergence,
        adaptation_cycles: cluster_stats.adaptation_cycles,
        emergence_patterns: cluster_stats.emergence_patterns,
        quantum_entanglement: cluster_stats.quantum_entanglement,
        superposition_count: cluster_stats.superposition_count,
        decoherence_ms: cluster_stats.decoherence_ms,
        quantum_speedup: cluster_stats.quantum_speedup
      }
    rescue
      error ->
        Logger.warning("Failed to get real CA state: #{inspect(error)}")
        get_fallback_ca_state()
    end
  end

  defp get_thundercell_cluster_stats do
    # Try to call ThunderCell Elixir modules for real stats
    try do
      # First try to get stats from ThunderCell Elixir bridge
      case get_thundercell_elixir_stats() do
        {:ok, stats} ->
          stats

        {:error, _} ->
          # Fallback to direct cluster call
          case get_direct_thundercell_stats() do
            {:ok, stats} -> stats
            _ -> get_thundergate_fallback_stats()
          end
      end
    rescue
      _ -> get_thundergate_fallback_stats()
    end
  end

  defp get_thundercell_elixir_stats do
    # Use ThunderCell Elixir modules directly
    try do
      clusters = Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor.list_clusters()
      cluster_count = length(clusters)

      # Aggregate stats from all clusters
      total_stats =
        Enum.reduce(
          clusters,
          %{
            total_generations: 0,
            total_cells: 0,
            alive_cells: 0,
            active_rules: []
          },
          fn cluster, acc ->
            generation = Map.get(cluster, :generation, 0)
            cell_count = Map.get(cluster, :cell_count, 0)
            # Assume 10% of cells are alive on average
            alive_count = round(cell_count * 0.1)

            %{
              total_generations: acc.total_generations + generation,
              total_cells: acc.total_cells + cell_count,
              alive_cells: acc.alive_cells + alive_count,
              active_rules: acc.active_rules ++ extract_cluster_rules(cluster)
            }
          end
        )

      {:ok,
       %{
         active_rules: Enum.uniq(total_stats.active_rules),
         total_generations: total_stats.total_generations,
         cluster_count: cluster_count,
         total_cells: total_stats.total_cells,
         alive_cells: total_stats.alive_cells,
         neural_learning_rate: 0.001,
         neural_convergence: 0.5,
         adaptation_cycles: 0,
         emergence_patterns: 0,
         quantum_entanglement: 0.0,
         superposition_count: 0,
         decoherence_ms: 0,
         quantum_speedup: 1.0
       }}
    rescue
      error -> {:error, error}
    end
  end

  defp get_direct_thundercell_stats do
    # Get stats directly from ThunderCell Telemetry
    try do
      case Thunderline.Thunderbolt.ThunderCell.Telemetry.get_performance_report() do
        {:ok, report} ->
          summary = Map.get(report, :summary, %{})

          {:ok,
           %{
             # Default rule
             active_rules: [:conway_3d],
             total_generations: Map.get(summary, :total_generations, 0),
             cluster_count: Map.get(summary, :total_clusters, 0),
             # Calculate from cluster data if needed
             total_cells: 0,
             alive_cells: 0,
             neural_learning_rate: 0.001,
             neural_convergence: 0.5,
             adaptation_cycles: 0,
             emergence_patterns: 0,
             quantum_entanglement: 0.0,
             superposition_count: 0,
             decoherence_ms: 0,
             quantum_speedup: 1.0
           }}

        error ->
          error
      end
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundergate_fallback_stats do
    # Get what we can from ThunderGate/ThunderLane systems
    thunderlane_stats = get_thunderlane_stats()

    %{
      active_rules: thunderlane_stats.active_rules,
      total_generations: thunderlane_stats.generations,
      cluster_count: thunderlane_stats.chunk_count,
      total_cells: thunderlane_stats.total_cells,
      alive_cells: thunderlane_stats.active_cells,
      neural_learning_rate: 0.001,
      neural_convergence: 0.5,
      adaptation_cycles: 0,
      emergence_patterns: 0,
      quantum_entanglement: 0.0,
      superposition_count: 0,
      decoherence_ms: 0,
      quantum_speedup: 1.0
    }
  end

  defp get_thunderlane_stats do
    # Query ThunderGate's ThunderLane for CA chunk data
    try do
      case Thunderline.Thundergate.Thunderlane.get_chunk_state("default") do
        {:ok, chunk_state} ->
          %{
            active_rules: Map.get(chunk_state, :rules, []),
            generations: Map.get(chunk_state, :generation, 0),
            chunk_count: 1,
            total_cells: Map.get(chunk_state, :size, 0) |> cube_size_to_cell_count(),
            active_cells: Map.get(chunk_state, :active_count, 0)
          }

        {:error, _} ->
          get_default_thunderlane_stats()
      end
    rescue
      _ -> get_default_thunderlane_stats()
    end
  end

  defp get_default_thunderlane_stats do
    %{
      active_rules: [],
      generations: 0,
      chunk_count: 0,
      total_cells: 0,
      active_cells: 0
    }
  end

  defp cube_size_to_cell_count(size) when is_integer(size), do: size * size * size
  defp cube_size_to_cell_count(_), do: 0

  defp get_liveview_automata_stats do
    # Get stats from LiveView automata processes
    try do
      # Query AutomataLive processes for current state
      automata_processes = Process.whereis(ThunderlineWeb.AutomataLive)

      if automata_processes do
        # If AutomataLive is running, get its state
        %{
          # Current rules in use
          active_rules: [:rule_30, :rule_90, :rule_110],
          generations: get_current_generation()
        }
      else
        %{
          active_rules: [],
          generations: 0
        }
      end
    rescue
      _ ->
        %{
          active_rules: [],
          generations: 0
        }
    end
  end

  defp get_current_generation do
    # Try to get current generation from AutomataLive state
    # This is a simplified approach - in real implementation,
    # we'd have a proper state management system
    try do
      # Check if there are any AutomataLive processes running
      case Phoenix.LiveView.get_by_topic(Thunderline.PubSub, "automata:updates") do
        [] -> 0
        # Count actual LiveView processes
        processes -> length(processes)
      end
    rescue
      _ -> 0
    end
  end

  # Removed unused get_default_cluster_stats/0 (duplicate logic elsewhere).

  # Removed duplicate earlier CA helper definitions (get_fallback_ca_state/0, extract_active_rules/1)

  # --- CA Metrics Helpers (consolidated) -------------------------------------
  # Keep only this implementation
  defp calculate_complexity_measure(cluster_stats, _liveview_stats) do
    # Calculate complexity based on various factors
    base_complexity = 0.1

    # Add complexity based on alive cells ratio
    if cluster_stats.total_cells > 0 do
      alive_ratio = cluster_stats.alive_cells / cluster_stats.total_cells
      complexity_from_density = alive_ratio * 0.5

      # Add complexity based on generation count
      generation_complexity = min(cluster_stats.total_generations / 1000, 0.4)

      base_complexity + complexity_from_density + generation_complexity
    else
      base_complexity
    end
  end

  defp determine_stability_status(cluster_stats) do
    cond do
      cluster_stats.total_cells == 0 -> :initializing
      cluster_stats.alive_cells == 0 -> :extinct
      cluster_stats.total_generations < 10 -> :stabilizing
      cluster_stats.emergence_patterns > 0 -> :emergent
      true -> :evolving
    end
  end

  defp collect_all_metrics(state) do
    %{
      state
      | system_metrics: collect_system_metrics(),
        event_metrics: collect_event_metrics(),
        agent_metrics: collect_agent_metrics(),
        thunderlane: collect_thunderlane_metrics(),
        last_update: DateTime.utc_now()
    }
  end

  defp collect_system_metrics do
    # Collect basic system health metrics
    memory_info = :erlang.memory()

    # Get uptime in seconds (using statistics instead of System.uptime)
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_seconds = div(uptime_ms, 1000)

    %{
      node: Node.self(),
      uptime: uptime_seconds,
      memory: %{
        total: memory_info[:total],
        processes: memory_info[:processes],
        system: memory_info[:system],
        atom: memory_info[:atom],
        binary: memory_info[:binary],
        ets: memory_info[:ets]
      },
      process_count: :erlang.system_info(:process_count),
      schedulers: :erlang.system_info(:schedulers_online),
      load_average: get_load_average(),
      mnesia_status: get_mnesia_status()
    }
  end

  defp collect_event_metrics do
    # Get event processing statistics
    broadway_stats = get_broadway_stats()

    %{
      total_processed: broadway_stats.total_processed || 0,
      processing_rate: broadway_stats.processing_rate || 0,
      failed_events: broadway_stats.failed_events || 0,
      queue_size: broadway_stats.queue_size || 0,
      average_latency: broadway_stats.average_latency || 0,
      pipelines: %{
        event_pipeline: get_pipeline_stats(:event_pipeline),
        cross_domain_pipeline: get_pipeline_stats(:cross_domain_pipeline),
        realtime_pipeline: get_pipeline_stats(:realtime_pipeline)
      }
    }
  end

  defp collect_agent_metrics do
    # Get agent performance data from ThunderMemory
    case ThunderMemory.list_agents() do
      {:ok, agents} ->
        active_count = Enum.count(agents, &(&1.status == :active))
        total_count = length(agents)

        %{
          total_agents: total_count,
          active_agents: active_count,
          inactive_agents: total_count - active_count,
          average_performance: calculate_average_performance(agents),
          top_performers: get_top_performers(agents),
          recent_spawns: get_recent_spawns(agents)
        }

      {:error, _reason} ->
        %{
          total_agents: 0,
          active_agents: 0,
          inactive_agents: 0,
          average_performance: 0,
          top_performers: [],
          recent_spawns: []
        }
    end
  end

  defp collect_thunderlane_metrics do
    # ThunderLane network and cluster metrics
    mnesia_status = get_mnesia_status()

    %{
      total_nodes: length(mnesia_status.nodes),
      # TODO: Implement real ops/sec tracking
      current_ops_per_sec: "OFFLINE",
      uptime: get_system_uptime_percentage(),
      # TODO: Implement cache metrics
      cache_hit_rate: "OFFLINE",
      memory_usage: get_memory_usage_percentage(),
      # TODO: Implement CPU monitoring
      cpu_usage: "OFFLINE",
      # TODO: Implement network monitoring
      network_latency: "OFFLINE",
      # TODO: Implement connection tracking
      active_connections: "OFFLINE",
      # TODO: Implement transfer rate monitoring
      data_transfer_rate: "OFFLINE",
      # TODO: Implement error rate calculation
      error_rate: "OFFLINE"
    }
  end

  defp get_system_uptime_percentage do
    # For now, assume 99%+ uptime if system is running
    # TODO: Implement real uptime tracking with downtime history
    "99.5%"
  end

  defp get_memory_usage_percentage do
    try do
      memory_info = :erlang.memory()
      total = memory_info[:total]
      # Get system memory limit (this is an approximation)
      # Rough estimate
      system_limit = memory_info[:system] * 10
      percentage = (total / system_limit * 100) |> Float.round(1)
      "#{percentage}%"
    rescue
      _ -> "OFFLINE"
    end
  end

  defp get_load_average do
    # Try to get system load average (Linux/Unix)
    case :os.cmd(~c"uptime") do
      result when is_list(result) ->
        result
        |> to_string()
        |> String.split("load average:")
        |> List.last()
        |> String.trim()
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn x ->
          case Float.parse(x) do
            {float, _} -> float
            :error -> 0.0
          end
        end)

      _ ->
        [0.0, 0.0, 0.0]
    end
  end

  defp get_mnesia_status do
    try do
      _info = :mnesia.system_info(:all)
      running_nodes = :mnesia.system_info(:running_db_nodes)

      %{
        status: :running,
        nodes: running_nodes,
        tables: length(:mnesia.system_info(:tables)),
        memory_usage: :mnesia.system_info(:use_dir)
      }
    rescue
      _ ->
        %{status: :error, nodes: [], tables: 0, memory_usage: false}
    end
  end

  defp get_broadway_stats do
    # Collect Broadway pipeline statistics
    # This is a simplified version - can be enhanced with real Broadway telemetry
    %{
      total_processed: get_telemetry_counter([:broadway, :processor, :message, :processed]),
      processing_rate: get_telemetry_rate([:broadway, :processor, :message, :processed]),
      failed_events: get_telemetry_counter([:broadway, :processor, :message, :failed]),
      queue_size: get_mnesia_table_size(),
      average_latency: get_telemetry_average([:broadway, :processor, :message, :latency])
    }
  end

  defp get_pipeline_stats(pipeline_name) do
    %{
      name: pipeline_name,
      status: :running,
      processed_count: get_telemetry_counter([:broadway, pipeline_name, :processed]) || 0,
      error_count: get_telemetry_counter([:broadway, pipeline_name, :failed]) || 0,
      # TODO: Implement real load measurement
      current_load: "OFFLINE"
    }
  end

  defp get_mnesia_table_size do
    try do
      event_table_size = :mnesia.table_info(Thunderflow.CrossDomainEvents, :size)
      realtime_table_size = :mnesia.table_info(Thunderflow.RealTimeEvents, :size)
      event_table_size + realtime_table_size
    rescue
      _ -> 0
    end
  end

  defp get_telemetry_counter(_event_path) do
    # TODO: Implement telemetry integration
    # In real implementation, this would query telemetry metrics
    # Return 0 instead of random data
    0
  end

  # Missing helper functions for CA integration
  defp extract_active_rules(stats) do
    case Map.get(stats, :ca_rules) do
      %{name: name} -> [name]
      rules when is_list(rules) -> rules
      _ -> []
    end
  end

  # Removed older unused alternate CA helper implementations.

  defp get_fallback_ca_state do
    # Fallback state when all CA systems are unavailable
    %{
      active_rules: [],
      total_generations: 0,
      complexity_measure: 0.0,
      stability_status: :offline,
      cluster_count: 0,
      total_cells: 0,
      alive_cells: 0,
      neural_learning_rate: 0.0,
      neural_convergence: 0.0,
      adaptation_cycles: 0,
      emergence_patterns: 0,
      quantum_entanglement: 0.0,
      superposition_count: 0,
      decoherence_ms: 0,
      quantum_speedup: 0.0
    }
  end

  defp extract_cluster_rules(cluster) do
    # Extract CA rules from cluster stats
    case Map.get(cluster, :ca_rules) do
      nil ->
        []

      rules when is_map(rules) ->
        name = Map.get(rules, :name, "Unknown")

        case name do
          "Conway's Game of Life 3D" -> [:conway_3d]
          "Highlife 3D" -> [:highlife_3d]
          "Seeds 3D" -> [:seeds_3d]
          "Maze 3D" -> [:maze_3d]
          _ -> [:custom_ca]
        end

      _ ->
        []
    end
  end
  # Agent metrics helper functions (consolidated here)
  defp calculate_average_performance(agents) do
    if agents == [] do
      0
    else
      total = Enum.reduce(agents, 0, fn a, acc -> acc + max(0, 100 - DateTime.diff(DateTime.utc_now(), a.updated_at, :second)) end)
      total / length(agents)
    end
  end

  defp get_top_performers(agents) do
    agents
    |> Enum.filter(&(&1.status == :active))
    |> Enum.sort_by(fn a -> DateTime.diff(DateTime.utc_now(), a.updated_at, :second) end)
    |> Enum.take(5)
    |> Enum.map(&%{id: &1.id, performance_score: max(0, 100 - DateTime.diff(DateTime.utc_now(), &1.updated_at, :second)), last_activity: &1.updated_at})
  end

  defp get_recent_spawns(agents) do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    agents
    |> Enum.filter(&(DateTime.compare(&1.created_at, cutoff) == :gt))
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    |> Enum.take(10)
    |> Enum.map(&%{id: &1.id, created_at: &1.created_at, status: &1.status})
  end

  defp schedule_metrics_update do
    Process.send_after(self(), :collect_metrics, @metrics_update_interval)
  end

  defp publish_metrics_update(state) do
    metrics_data = %{
      system: state.system_metrics,
      events: state.event_metrics,
      agents: state.agent_metrics,
      thunderlane: state.thunderlane,
      timestamp: state.last_update
    }
    PubSub.broadcast(Thunderline.PubSub, @pubsub_topic, {:metrics_update, metrics_data})
  end

  defp get_telemetry_rate(_path), do: 0.0
  defp get_telemetry_average(_path), do: 0.0
end
