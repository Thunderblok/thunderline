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
  @pipeline_steps [:ingest, :embed, :curate, :propose, :train, :serve]
  @telemetry_table :thunderline_dashboard_telemetry
  @ml_pipeline_table :thunderline_dashboard_ml_pipeline
  @pipeline_handler_id "thunderline-dashboard-metrics-pipeline"
  @trial_handler_id "thunderline-dashboard-metrics-ml"
  @notes_key {:notes, :ml_pipeline}

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

  @doc "Return the latest ML pipeline telemetry snapshot with statuses and metrics"
  def get_ml_pipeline_snapshot do
    ensure_tables()

    status_map =
      Enum.reduce(@pipeline_steps, %{}, fn step, acc ->
        Map.put(acc, step, pipeline_status(step))
      end)

    status_map
    |> Map.put(:order, @pipeline_steps)
    |> Map.put(
      :notes,
      current_pipeline_note() || "HC directive staged — awaiting live pipeline telemetry"
    )
    |> Map.put(:trial_metrics, current_trial_metrics())
    |> Map.put(:parzen_metrics, current_parzen_metrics())
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
      # Estimate active zones from ETS table if present
      active_zones: active_zone_count(),
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
        log_once(:oban_not_running, fn ->
          Logger.info("Oban not detected (name=#{inspect(name)}) yet; using default stats")
        end)

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

      _ ->
        :ok
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

    ensure_tables()
    attach_pipeline_handlers()
    attach_trial_handlers()

    # Schedule periodic metrics updates
    schedule_metrics_update()

    initial_state = %{
      system_metrics: %{},
      event_metrics: %{},
      agent_metrics: %{},
      thunderlane: %{},
      ml_pipeline: %{},
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
      ml_pipeline: state.ml_pipeline,
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
    # Return early if ClusterSupervisor is not running to avoid crashes
    {:error, :cluster_supervisor_not_running}
  end

  defp get_thundercell_elixir_stats_disabled do
    # DISABLED: ClusterSupervisor causes crashes when not running
    # Use ThunderCell Elixir modules directly
    try do
      # Check if the supervisor process is alive first
      supervisor_name = Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor

      case Process.whereis(supervisor_name) do
        nil ->
          {:error, :cluster_supervisor_not_running}

        _pid ->
          clusters = supervisor_name.list_clusters()
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
      end
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
    # ThunderGate's ThunderLane component has been removed. Return default stats.
    get_default_thunderlane_stats()
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
    # Previous implementation attempted to introspect LiveView processes via
    # Phoenix.LiveView.get_by_topic/2 (removed / private). Return 0 until a
    # supported telemetry-based approach is implemented.
    0
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
        ml_pipeline: collect_ml_pipeline_metrics(),
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
    dropped = get_telemetry_counter([:thunderline, :event, :dropped])

    %{
      total_processed: broadway_stats.total_processed || 0,
      processing_rate: broadway_stats.processing_rate || 0,
      failed_events: broadway_stats.failed_events || 0,
      queue_size: broadway_stats.queue_size || 0,
      average_latency: broadway_stats.average_latency || 0,
      dropped_events: dropped || 0,
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

  defp collect_ml_pipeline_metrics do
    get_ml_pipeline_snapshot()
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

  defp get_telemetry_counter(event_path) when is_list(event_path) do
    ensure_tables()

    key = telemetry_counter_key(event_path)

    case :ets.lookup(@telemetry_table, key) do
      [{^key, value}] -> value
      _ -> 0
    end
  end

  defp get_telemetry_counter(_), do: 0

  defp telemetry_counter_key(event_path) do
    {:telemetry, List.to_tuple(event_path)}
  end

  defp active_zone_count do
    try do
      :ets.info(:thundergrid_zones, :size)
    rescue
      _ -> 0
    end
  end

  defp ensure_tables do
    ensure_table(@telemetry_table)
    ensure_table(@ml_pipeline_table)
  end

  defp ensure_table(name) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [
          :named_table,
          :public,
          :set,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp attach_pipeline_handlers do
    events = [
      [:thunderline, :pipeline, :domain_events, :start],
      [:thunderline, :pipeline, :domain_events, :stop],
      [:thunderline, :pipeline, :domain_events, :error],
      [:thunderline, :pipeline, :critical_events, :start],
      [:thunderline, :pipeline, :critical_events, :stop],
      [:thunderline, :pipeline, :critical_events, :error],
      [:thunderline, :pipeline, :dlq],
      [:thunderline, :event, :enqueue],
      [:thunderline, :event, :publish],
      [:thunderline, :event, :dedup],
      [:thunderline, :event, :dropped]
    ]

    maybe_attach_many(@pipeline_handler_id, events, &__MODULE__.handle_pipeline_telemetry/4)
  end

  defp attach_trial_handlers do
    events = [
      [:thunderline, :domain_processor, :ml, :trial, :allowed],
      [:thunderline, :domain_processor, :ml, :trial, :enqueued],
      [:thunderline, :domain_processor, :ml, :trial, :denied],
      [:thunderline, :domain_processor, :ml, :trial, :completed],
      [:thunderline, :domain_processor, :ml, :run, :metrics],
      [:thunderline, :domain_processor, :ml, :run, :completed],
      [:thunderline, :domain_processor, :ml, :artifact, :created],
      [:thunderline, :domain_processor, :error]
    ]

    maybe_attach_many(@trial_handler_id, events, &__MODULE__.handle_trial_telemetry/4)
  end

  defp maybe_attach_many(id, events, handler) do
    :telemetry.attach_many(id, events, handler, %{})
  rescue
    ArgumentError -> :ok
  end

  def handle_pipeline_telemetry(
        [:thunderline, :pipeline, :dlq] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    update_pipeline_from_stage(:domain_events, :dlq, metadata)
  end

  def handle_pipeline_telemetry(
        [:thunderline, :pipeline, pipeline, stage] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    update_pipeline_from_stage(pipeline, stage, metadata)
  end

  def handle_pipeline_telemetry(event, measurements, _metadata, _config) do
    increment_telemetry_counter(event, measurement_count(measurements))
  end

  def handle_trial_telemetry(
        [:thunderline, :domain_processor, :ml, :trial, status],
        measurements,
        metadata,
        _config
      )
      when status in [:allowed, :enqueued, :denied, :completed] do
    increment_telemetry_counter(
      [:thunderline, :domain_processor, :ml, :trial, status],
      measurement_count(measurements)
    )

    update_trial_metric(status, metadata)

    case status do
      :allowed ->
        maybe_set_status(:propose, :online, metadata)

      :enqueued ->
        maybe_set_status(:train, :online, metadata)

      :completed ->
        maybe_set_status(:train, :online, metadata)

      :denied ->
        maybe_set_status(:propose, :degraded, metadata)
        append_pipeline_note("trial denied #{format_trial_identifier(metadata)}")
    end
  end

  def handle_trial_telemetry(
        [:thunderline, :domain_processor, :ml, :run, :metrics] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    update_parzen_metrics(measurements, metadata)
    maybe_set_status(:curate, :online, metadata)
  end

  def handle_trial_telemetry(
        [:thunderline, :domain_processor, :ml, :run, :completed] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    update_trial_metric(:completed, metadata)
    maybe_set_status(:train, :online, metadata)
  end

  def handle_trial_telemetry(
        [:thunderline, :domain_processor, :ml, :artifact, :created] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    update_parzen_metrics(measurements, metadata)
    maybe_set_status(:serve, :online, metadata)
  end

  def handle_trial_telemetry(
        [:thunderline, :domain_processor, :error] = event,
        measurements,
        metadata,
        _config
      ) do
    increment_telemetry_counter(event, measurement_count(measurements))
    maybe_set_status(:train, :degraded, metadata)
    append_pipeline_note("domain processor error #{inspect(meta_get(metadata, :error))}")
  end

  def handle_trial_telemetry(event, measurements, _metadata, _config) do
    increment_telemetry_counter(event, measurement_count(measurements))
  end

  defp increment_telemetry_counter(event, value) do
    ensure_tables()

    count =
      cond do
        is_integer(value) -> value
        is_float(value) -> trunc(value)
        true -> 1
      end

    key = telemetry_counter_key(event)
    :ets.update_counter(@telemetry_table, key, {2, max(count, 0)}, {key, 0})
    :ets.insert(@telemetry_table, {{:last_seen, key}, DateTime.utc_now()})
  end

  defp measurement_count(measurements) when is_map(measurements) do
    cond do
      is_number(measurements[:count]) -> measurements[:count]
      is_number(measurements["count"]) -> measurements["count"]
      true -> 1
    end
  end

  defp measurement_count(_), do: 1

  defp update_pipeline_from_stage(pipeline, :start, metadata) do
    maybe_set_status(pipeline_to_step(pipeline), :processing, metadata)
  end

  defp update_pipeline_from_stage(pipeline, :stop, metadata) do
    maybe_set_status(pipeline_to_step(pipeline), :online, metadata)
  end

  defp update_pipeline_from_stage(pipeline, :error, metadata) do
    step = pipeline_to_step(pipeline)
    maybe_set_status(step, :degraded, metadata)
    append_pipeline_note("#{format_pipeline_step(step)} error #{format_reason(metadata)}")
  end

  defp update_pipeline_from_stage(_pipeline, :dlq, metadata) do
    maybe_set_status(:ingest, :degraded, metadata)
    append_pipeline_note("DLQ activity detected #{format_reason(metadata)}")
  end

  defp update_pipeline_from_stage(_pipeline, _stage, _metadata), do: :ok

  defp pipeline_to_step(:domain_events), do: :ingest
  defp pipeline_to_step(:critical_events), do: :ingest
  defp pipeline_to_step(_), do: nil

  defp maybe_set_status(nil, _status, _metadata), do: :ok

  defp maybe_set_status(step, status, metadata) do
    set_pipeline_status(step, status, metadata)
  end

  defp set_pipeline_status(step, status, metadata) do
    ensure_tables()

    entry = %{
      status: status,
      updated_at: DateTime.utc_now(),
      metadata: sanitize_metadata(metadata)
    }

    :ets.insert(@ml_pipeline_table, {{:status, step}, entry})
  end

  defp pipeline_status(step) do
    ensure_tables()

    case :ets.lookup(@ml_pipeline_table, {{:status, step}}) do
      [{{:status, ^step}, %{status: status}}] -> status
      _ -> nil
    end
  end

  defp append_pipeline_note(message) when is_binary(message) do
    ensure_tables()

    entry = %{message: message, at: DateTime.utc_now()}

    notes =
      case :ets.lookup(@ml_pipeline_table, @notes_key) do
        [{@notes_key, existing}] when is_list(existing) -> Enum.take([entry | existing], 5)
        _ -> [entry]
      end

    :ets.insert(@ml_pipeline_table, {@notes_key, notes})
  end

  defp current_pipeline_note do
    ensure_tables()

    case :ets.lookup(@ml_pipeline_table, @notes_key) do
      [{@notes_key, [first | _]}] -> format_note(first)
      _ -> nil
    end
  end

  defp format_note(%{message: message, at: %DateTime{} = at}) when is_binary(message) do
    "#{DateTime.to_iso8601(at)} — #{message}"
  rescue
    _ -> message
  end

  defp format_note(%{message: message}) when is_binary(message), do: message
  defp format_note(_), do: nil

  defp current_trial_metrics do
    ensure_tables()

    last_event =
      case :ets.lookup(@ml_pipeline_table, {:trial, :last_event}) do
        [{_, value}] -> value
        _ -> nil
      end

    %{
      allowed: get_counter({:trial, :allowed}),
      enqueued: get_counter({:trial, :enqueued}),
      denied: get_counter({:trial, :denied}),
      completed: get_counter({:trial, :completed}),
      last_event: last_event
    }
  end

  defp current_parzen_metrics do
    ensure_tables()

    last_metrics =
      case :ets.lookup(@ml_pipeline_table, {:parzen, :last_metrics}) do
        [{_, value}] -> value
        _ -> %{}
      end

    %{
      observations: get_counter({:parzen, :observations}),
      best_metric: Map.get(last_metrics, :best_metric),
      last_run_id: Map.get(last_metrics, :run_id),
      metrics: Map.get(last_metrics, :metrics),
      updated_at: Map.get(last_metrics, :at)
    }
  end

  defp get_counter(key) do
    ensure_tables()

    counter_key = {:counter, key}

    case :ets.lookup(@ml_pipeline_table, counter_key) do
      [{^counter_key, value}] -> value
      _ -> 0
    end
  end

  defp increment_counter(key, amount \\ 1) do
    ensure_tables()
    counter_key = {:counter, key}
    :ets.update_counter(@ml_pipeline_table, counter_key, {2, amount}, {counter_key, 0})
  end

  defp update_trial_metric(type, metadata) do
    increment_counter({:trial, type})

    entry = %{
      type: type,
      run_id: meta_get(metadata, :run_id),
      trial_id: meta_get(metadata, :trial_id),
      at: DateTime.utc_now()
    }

    :ets.insert(@ml_pipeline_table, {{:trial, :last_event}, entry})
  end

  defp update_parzen_metrics(_measurements, metadata) do
    increment_counter({:parzen, :observations})

    metrics = meta_get(metadata, :metrics)
    best_metric = best_metric_from(metrics)

    entry = %{
      run_id: meta_get(metadata, :run_id),
      metrics: metrics,
      best_metric: best_metric,
      at: DateTime.utc_now()
    }

    :ets.insert(@ml_pipeline_table, {{:parzen, :last_metrics}, entry})
  end

  defp best_metric_from(%{} = metrics) do
    metrics
    |> Map.values()
    |> Enum.filter(&is_number/1)
    |> case do
      [] -> nil
      values -> Enum.max(values)
    end
  end

  defp best_metric_from(_), do: nil

  defp sanitize_metadata(metadata) when is_map(metadata) do
    Enum.reduce(metadata, %{}, fn {k, v}, acc ->
      key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> safe_existing_atom(k)
          true -> k
        end

      Map.put(acc, key, v)
    end)
  end

  defp sanitize_metadata(_), do: %{}

  defp safe_existing_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> value
    end
  end

  defp safe_existing_atom(value), do: value

  defp meta_get(metadata, key) when is_map(metadata) and is_atom(key) do
    cond do
      Map.has_key?(metadata, key) -> Map.get(metadata, key)
      Map.has_key?(metadata, Atom.to_string(key)) -> Map.get(metadata, Atom.to_string(key))
      true -> nil
    end
  end

  defp meta_get(_metadata, _key), do: nil

  defp format_reason(metadata) do
    meta_get(metadata, :reason) || inspect(metadata)
  end

  defp format_pipeline_step(nil), do: "pipeline"

  defp format_pipeline_step(step) when is_atom(step) do
    step |> Atom.to_string() |> String.upcase()
  end

  defp format_trial_identifier(metadata) do
    trial = meta_get(metadata, :trial_id) || "unknown"
    run = meta_get(metadata, :run_id)

    case run do
      nil -> "(trial #{inspect(trial)})"
      _ -> "(trial #{inspect(trial)}, run #{inspect(run)})"
    end
  end

  # Removed unused extract_active_rules/1 (legacy CA rules helper)

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
      total =
        Enum.reduce(agents, 0, fn a, acc ->
          acc + max(0, 100 - DateTime.diff(DateTime.utc_now(), a.updated_at, :second))
        end)

      total / length(agents)
    end
  end

  defp get_top_performers(agents) do
    agents
    |> Enum.filter(&(&1.status == :active))
    |> Enum.sort_by(fn a -> DateTime.diff(DateTime.utc_now(), a.updated_at, :second) end)
    |> Enum.take(5)
    |> Enum.map(
      &%{
        id: &1.id,
        performance_score:
          max(0, 100 - DateTime.diff(DateTime.utc_now(), &1.updated_at, :second)),
        last_activity: &1.updated_at
      }
    )
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
      ml_pipeline: state.ml_pipeline,
      timestamp: state.last_update
    }

    PubSub.broadcast(Thunderline.PubSub, @pubsub_topic, {:metrics_update, metrics_data})
  end

  defp get_telemetry_rate(_path), do: 0.0
  defp get_telemetry_average(_path), do: 0.0
end
