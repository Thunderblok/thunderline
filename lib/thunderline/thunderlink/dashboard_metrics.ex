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
  alias Thunderline.Repo
  alias Phoenix.PubSub
  alias Oban.Job

  import Ecto.Query

  @pubsub_topic "dashboard:metrics"
  # 5 seconds
  @metrics_update_interval 5_000
  @heartbeat_tolerance 15_000
  @downtime_history_limit 10
  @completion_sample_limit 100
  @pipeline_steps [:ingest, :embed, :curate, :propose, :train, :serve]
  @telemetry_table :thunderline_dashboard_telemetry
  @ml_pipeline_table :thunderline_dashboard_ml_pipeline
  @uptime_table :thunderline_dashboard_uptime
  @rate_cache_table :thunderline_dashboard_rates

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
    metrics = collect_system_metrics()
    memory = metrics.memory

    %{
      cpu_usage: metrics.cpu_usage,
      memory_usage: %{
        used: memory.used,
        total: memory.total,
        percent: metrics.memory_used_percent
      },
      active_processes: metrics.process_count,
      uptime_seconds: metrics.uptime,
      uptime_percent: metrics.uptime_percent
    }
  end

  @doc "Get ThunderBit metrics"
  def thunderbit_metrics do
    snapshot = agent_snapshot()
    trial_metrics = current_trial_metrics()
    parzen_metrics = current_parzen_metrics()

    %{
      total_agents: snapshot.total,
      active_agents: snapshot.active,
      neural_networks: snapshot.neural,
      inference_rate_per_sec:
        Float.round(
          rate_per_second({:thunderbit, :inference}, fn -> trial_metrics.completed end),
          2
        ),
      model_accuracy: Float.round(parzen_metrics.best_metric || 0.0, 4),
      memory_usage_mb: Float.round(snapshot.memory_mb, 2)
    }
  end

  @doc "Get ThunderLane cluster metrics"
  def thunderlane_metrics do
    mnesia_status = get_mnesia_status()
    enqueue = get_telemetry_counter([:thunderline, :event, :enqueue])
    dedup = get_telemetry_counter([:thunderline, :event, :dedup])
    dropped = get_telemetry_counter([:thunderline, :event, :dropped])

    %{
      total_nodes: length(mnesia_status.nodes),
      current_ops_per_sec:
        Float.round(
          rate_per_second({:thunderlane, :ops}, fn ->
            get_telemetry_counter([:thunderline, :event, :publish])
          end),
          2
        ),
      uptime: uptime_seconds(),
      uptime_percent: uptime_percentage(),
      cache_hit_rate_percent: cache_hit_rate(enqueue, dedup),
      memory_usage: memory_usage_snapshot(),
      cpu_usage_percent: cpu_usage_percent(),
      network_latency_ms: network_latency_ms(),
      active_connections: 1 + length(Node.list()),
      data_transfer_mb_s: Float.round(io_bytes_per_second(:output) / 1_048_576, 3),
      error_rate_percent: error_rate_percent(enqueue, dropped)
    }
  end

  @doc "Get ThunderBolt metrics"
  def thunderbolt_metrics do
    trial_metrics = current_trial_metrics()
    scaling = trial_metrics.allowed + trial_metrics.denied

    efficiency =
      if scaling > 0 do
        Float.round(trial_metrics.completed / scaling * 100.0, 2)
      else
        100.0
      end

    %{
      chunks_processed: trial_metrics.completed,
      scaling_operations: scaling,
      resource_efficiency_percent: efficiency,
      load_balancer_health: load_balancer_health(efficiency)
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
    snapshot = grid_snapshot()
    queries_total = get_telemetry_counter([:thundergrid, :query, :total])
    crossings = get_telemetry_counter([:thundergrid, :boundary, :crossing])
    operations = get_telemetry_counter([:thundergrid, :operation, :processed])

    %{
      active_zones: snapshot.active_zones,
      spatial_queries_per_min:
        Float.round(
          rate_per_second({:thundergrid, :queries}, fn -> queries_total end) * 60,
          2
        ),
      boundary_crossings: crossings,
      grid_efficiency_percent: snapshot.efficiency,
      total_nodes: snapshot.total_nodes,
      active_nodes: snapshot.active_nodes,
      current_load_percent: snapshot.current_load,
      performance_ops_per_min:
        Float.round(rate_per_second({:thundergrid, :ops}, fn -> operations end) * 60, 2),
      data_stream_rate_mbps: Float.round(io_bytes_per_second(:input) / 1_048_576, 3),
      storage_rate_mbps: Float.round(io_bytes_per_second(:output) / 1_048_576, 3)
    }
  end

  @doc "Get ThunderBlock Vault (formerly ThunderVault) metrics"
  def thunderblock_vault_metrics do
    snapshot = vault_snapshot()

    %{
      decisions_made: snapshot.decisions,
      policy_evaluations: snapshot.policy_evaluations,
      access_requests: snapshot.access_requests,
      security_score: snapshot.security_score
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
    snapshot = communication_snapshot()

    %{
      active_communities: snapshot.active_communities,
      messages_processed_per_min: snapshot.messages_per_min,
      federation_connections: snapshot.federation_connections,
      communication_health: snapshot.health
    }
  end

  @doc "Get ThunderEye metrics"
  def thundereye_metrics do
    snapshot = observability_snapshot()

    %{
      traces_collected: snapshot.traces_collected,
      performance_metrics: snapshot.performance_rate,
      anomaly_detections: snapshot.anomaly_count,
      monitoring_coverage: snapshot.coverage_percent
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

        avg_completion_time =
          case average_job_completion_time() do
            {:ok, seconds} -> format_duration(seconds)
            {:error, _} -> "OFFLINE"
          end

        %{
          queued_jobs: default_stats.queued + cross_domain_stats.queued + scheduled_stats.queued,
          completed_recent: default_stats.completed + cross_domain_stats.completed,
          failed_recent: default_stats.failed + cross_domain_stats.failed,
          cross_domain_jobs: cross_domain_stats.queued + cross_domain_stats.executing,
          avg_completion_time: avg_completion_time
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

  defp average_job_completion_time(limit \\ @completion_sample_limit) do
    try do
      jobs =
        Job
        |> where([j], j.state == "completed" and not is_nil(j.completed_at))
        |> order_by([j], desc: j.completed_at)
        |> limit(^limit)
        |> select([j], %{
          completed_at: j.completed_at,
          scheduled_at: j.scheduled_at,
          inserted_at: j.inserted_at
        })
        |> Repo.all()

      durations =
        jobs
        |> Enum.map(&job_duration_seconds/1)
        |> Enum.filter(&is_number/1)

      case durations do
        [] -> {:error, :no_samples}
        _ -> {:ok, Enum.sum(durations) / length(durations)}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  defp job_duration_seconds(%{completed_at: %NaiveDateTime{} = completed} = job) do
    start_at =
      case Map.get(job, :scheduled_at) do
        %NaiveDateTime{} = scheduled -> scheduled
        _ -> Map.get(job, :inserted_at)
      end

    case start_at do
      %NaiveDateTime{} = starting_point ->
        duration_ms = NaiveDateTime.diff(completed, starting_point, :millisecond)

        if duration_ms > 0 do
          duration_ms / 1_000
        else
          0.0
        end

      _ ->
        nil
    end
  end

  defp job_duration_seconds(_), do: nil

  defp format_duration(seconds) when is_number(seconds) do
    cond do
      seconds >= 3_600 ->
        hours = trunc(seconds / 3_600)
        minutes = trunc((seconds - hours * 3_600) / 60)
        remaining = seconds - hours * 3_600 - minutes * 60
        "#{hours}h #{minutes}m #{Float.round(remaining, 1)}s"

      seconds >= 60 ->
        minutes = trunc(seconds / 60)
        remaining = seconds - minutes * 60
        "#{minutes}m #{Float.round(remaining, 1)}s"

      seconds >= 1 ->
        "#{Float.round(seconds, 2)}s"

      seconds > 0 ->
        "#{Float.round(seconds * 1_000, 2)}ms"

      true ->
        "0ms"
    end
  end

  defp format_duration(_), do: "OFFLINE"

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
      avg_completion_time: format_duration(0)
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
    snapshot = flow_snapshot()

    %{
      events_processed: snapshot.events_processed,
      pipelines_active: snapshot.pipelines_active,
      flow_rate_per_sec: snapshot.flow_rate,
      consciousness_level: snapshot.consciousness_level
    }
  end

  @doc "Get ThunderStone metrics"
  def thunderstone_metrics do
    snapshot = storage_snapshot()

    %{
      storage_operations: snapshot.operations,
      data_integrity: snapshot.integrity_percent,
      compression_ratio: snapshot.compression_ratio,
      storage_health: snapshot.health
    }
  end

  @doc "Get ThunderLink metrics"
  def thunderlink_metrics do
    throughput_mb = Float.round(io_bytes_per_second(:output) / 1_048_576, 3)
    latency_ms = network_latency_ms()

    error_rate =
      error_rate_percent(
        get_telemetry_counter([:thunderline, :event, :enqueue]),
        get_telemetry_counter([:thunderline, :event, :dropped])
      )

    %{
      connections_active: 1 + length(Node.list()),
      data_throughput_mb_s: throughput_mb,
      latency_avg_ms: latency_ms,
      network_stability: network_stability(error_rate)
    }
  end

  @doc "Get ThunderCrown metrics"
  def thundercrown_metrics do
    snapshot = governance_snapshot()

    %{
      governance_actions: snapshot.actions,
      policy_updates: snapshot.policy_updates,
      compliance_score: snapshot.compliance_score,
      authority_level: snapshot.authority_level
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
    initialize_uptime_tracking()
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
    record_uptime_heartbeat()

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
    ensure_tables()
    initialize_uptime_tracking()
    memory_info = :erlang.memory()
    memory_snapshot = system_memory_snapshot(memory_info)

    %{
      node: Node.self(),
      uptime: uptime_seconds(),
      uptime_percent: uptime_percentage(),
      cpu_usage: cpu_usage_percent(),
      memory: memory_snapshot,
      memory_used_percent: memory_snapshot.percent,
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
    snapshot = agent_snapshot()
    agents = snapshot.agents

    %{
      total_agents: snapshot.total,
      active_agents: snapshot.active,
      inactive_agents: max(snapshot.total - snapshot.active, 0),
      average_performance: if(agents == [], do: 0, else: calculate_average_performance(agents)),
      top_performers: get_top_performers(agents),
      recent_spawns: get_recent_spawns(agents)
    }
  end

  defp collect_thunderlane_metrics do
    thunderlane_metrics()
  end

  defp collect_ml_pipeline_metrics do
    get_ml_pipeline_snapshot()
  end

  defp rate_per_second(key, value_fun) when is_function(value_fun, 0) do
    ensure_tables()

    now_ms = System.monotonic_time(:millisecond)

    case safe_number(value_fun.()) do
      {:ok, current_value} ->
        cache_key = {:rate, key}

        case :ets.lookup(@rate_cache_table, cache_key) do
          [{^cache_key, {previous_value, previous_timestamp}}] ->
            time_diff_ms = max(now_ms - previous_timestamp, 1)
            value_diff = current_value - previous_value
            rate = value_diff / (time_diff_ms / 1_000)
            :ets.insert(@rate_cache_table, {cache_key, {current_value, now_ms}})
            max(rate, 0.0)

          _ ->
            :ets.insert(@rate_cache_table, {cache_key, {current_value, now_ms}})
            0.0
        end

      :error ->
        0.0
    end
  end

  defp rate_per_second(_key, _fun), do: 0.0

  defp io_bytes_per_second(direction) when direction in [:input, :output] do
    ensure_tables()
    {{:input, input_bytes}, {:output, output_bytes}} = :erlang.statistics(:io)
    now_ms = System.monotonic_time(:millisecond)
    current_bytes = if direction == :input, do: input_bytes, else: output_bytes
    cache_key = {:io_rate, direction}

    case :ets.lookup(@rate_cache_table, cache_key) do
      [{^cache_key, {previous_bytes, previous_timestamp}}] ->
        time_diff_ms = max(now_ms - previous_timestamp, 1)
        byte_diff = current_bytes - previous_bytes
        rate = byte_diff / (time_diff_ms / 1_000)
        :ets.insert(@rate_cache_table, {cache_key, {current_bytes, now_ms}})
        max(rate, 0.0)

      _ ->
        :ets.insert(@rate_cache_table, {cache_key, {current_bytes, now_ms}})
        0.0
    end
  rescue
    _ -> 0.0
  end

  defp io_bytes_per_second(_), do: 0.0

  defp cpu_usage_percent do
    case :erlang.statistics(:scheduler_wall_time) do
      :undefined ->
        :erlang.system_flag(:scheduler_wall_time, true)
        0.0

      scheduler_times when is_list(scheduler_times) ->
        scheduler_times
        |> Enum.map(fn {_id, active, total} ->
          if total > 0, do: active / total, else: 0.0
        end)
        |> case do
          [] -> 0.0
          utilizations -> Float.round(Enum.sum(utilizations) / length(utilizations) * 100, 2)
        end

      _ ->
        0.0
    end
  rescue
    _ -> 0.0
  end

  defp memory_usage_snapshot do
    memory_info = :erlang.memory()
    snapshot = system_memory_snapshot(memory_info)

    %{
      used_mb: Float.round(snapshot.used / (1024 * 1024), 2),
      total_mb: Float.round(snapshot.total / (1024 * 1024), 2),
      percent: snapshot.percent
    }
  rescue
    _ -> %{used_mb: 0.0, total_mb: 0.0, percent: 0.0}
  end

  defp system_memory_snapshot(memory_info) when is_map(memory_info) do
    total = memory_info[:total] || 0
    processes = memory_info[:processes] || 0
    system = memory_info[:system] || 0
    used = processes + system

    percent =
      if total > 0 do
        Float.round(used / total * 100, 2)
      else
        0.0
      end

    %{
      total: total,
      used: used,
      processes: processes,
      system: system,
      atom: memory_info[:atom] || 0,
      binary: memory_info[:binary] || 0,
      code: memory_info[:code] || 0,
      ets: memory_info[:ets] || 0,
      percent: percent
    }
  end

  defp system_memory_snapshot(_), do: %{total: 0, used: 0, processes: 0, system: 0, percent: 0.0}

  defp uptime_seconds do
    case :ets.lookup(@uptime_table, {:boot, :monotonic}) do
      [{{:boot, :monotonic}, boot_ms}] ->
        now_ms = System.monotonic_time(:millisecond)
        max(div(now_ms - boot_ms, 1_000), 0)

      _ ->
        0
    end
  end

  defp uptime_percentage do
    case :ets.lookup(@uptime_table, {:boot, :monotonic}) do
      [{{:boot, :monotonic}, boot_ms}] ->
        now_ms = System.monotonic_time(:millisecond)
        total_ms = max(now_ms - boot_ms, 1)
        downtime_ms = min(downtime_total_ms(), total_ms)
        uptime_ms = max(total_ms - downtime_ms, 0)
        Float.round(uptime_ms / total_ms * 100.0, 4)

      _ ->
        100.0
    end
  end

  defp error_rate_percent(total, errors) when is_number(total) and is_number(errors) do
    cond do
      total <= 0 -> 0.0
      errors <= 0 -> 0.0
      true -> Float.round(errors / total * 100.0, 2)
    end
  end

  defp error_rate_percent(_, _), do: 0.0

  defp cache_hit_rate(total, hits) when is_number(total) and is_number(hits) do
    cond do
      total <= 0 -> 0.0
      hits <= 0 -> 0.0
      true -> Float.round(hits / total * 100.0, 2)
    end
  end

  defp cache_hit_rate(_, _), do: 0.0

  defp network_latency_ms do
    nodes = Node.list()

    if nodes == [] do
      0.0
    else
      nodes
      |> Enum.map(fn node ->
        start = System.monotonic_time(:microsecond)

        try do
          :rpc.call(node, :erlang, :node, [])
          stop = System.monotonic_time(:microsecond)
          max(stop - start, 0) / 1_000
        catch
          _ -> 0.0
        end
      end)
      |> case do
        [] -> 0.0
        latencies -> Float.round(Enum.sum(latencies) / length(latencies), 2)
      end
    end
  rescue
    _ -> 0.0
  end

  defp load_balancer_health(efficiency) when is_number(efficiency) do
    cond do
      efficiency >= 95 -> :healthy
      efficiency >= 85 -> :active
      efficiency >= 70 -> :watch
      true -> :degraded
    end
  end

  defp load_balancer_health(_), do: :unknown

  defp network_stability(error_rate) when is_number(error_rate) do
    cond do
      error_rate < 1.0 -> :excellent
      error_rate < 5.0 -> :good
      error_rate < 10.0 -> :degraded
      true -> :critical
    end
  end

  defp network_stability(_), do: :unknown

  defp agent_snapshot do
    with {:ok, agents} <- ThunderMemory.list_agents() do
      {active, inactive} = Enum.split_with(agents, &(&1.status in [:active, "active"]))

      neural =
        Enum.count(agents, fn agent ->
          case agent.data do
            %{} = data -> to_string(Map.get(data, :type) || Map.get(data, "type")) == "neural"
            _ -> false
          end
        end)

      memory_bytes =
        Enum.reduce(agents, 0, fn agent, acc ->
          metrics = Map.get(agent, :metadata) || %{}
          acc + (metrics[:memory_usage_bytes] || metrics["memory_usage_bytes"] || 0)
        end)

      %{
        total: length(agents),
        active: length(active),
        inactive: length(inactive),
        neural: neural,
        memory_mb: Float.round(memory_bytes / (1024 * 1024), 2),
        agents: agents
      }
    else
      _ -> %{total: 0, active: 0, inactive: 0, neural: 0, memory_mb: 0.0, agents: []}
    end
  rescue
    _ -> %{total: 0, active: 0, inactive: 0, neural: 0, memory_mb: 0.0, agents: []}
  end

  defp grid_snapshot do
    active_zones =
      try do
        :ets.info(:thundergrid_zones, :size)
      rescue
        _ -> 0
      end

    total_nodes =
      try do
        :ets.info(:thundergrid_nodes, :size)
      rescue
        _ -> 0
      end

    %{
      active_zones: active_zones || 0,
      total_nodes: total_nodes || 0,
      active_nodes: total_nodes || 0,
      current_load: 0.0,
      efficiency: 0.0
    }
  end

  defp vault_snapshot do
    with {:ok, decisions} <- metric_total("thunderblock.vault.decision"),
         {:ok, evaluations} <- metric_total("thunderblock.vault.policy_eval"),
         {:ok, access} <- metric_total("thunderblock.vault.access") do
      %{
        decisions: decisions,
        policy_evaluations: evaluations,
        access_requests: access,
        security_score: 100.0
      }
    else
      _ ->
        %{decisions: 0, policy_evaluations: 0, access_requests: 0, security_score: 0.0}
    end
  end

  defp communication_snapshot do
    %{
      active_communities: 0,
      messages_per_min:
        rate_per_second({:thunderlink, :messages}, fn ->
          get_telemetry_counter([:thunderlink, :message, :processed])
        end) * 60,
      federation_connections: Node.list() |> length(),
      health: :unknown
    }
  end

  defp observability_snapshot do
    %{
      traces_collected: get_telemetry_counter([:thundereye, :traces, :collected]),
      performance_rate:
        rate_per_second({:thundereye, :performance}, fn ->
          get_telemetry_counter([:thundereye, :metrics, :processed])
        end),
      anomaly_count: get_telemetry_counter([:thundereye, :anomaly, :detected]),
      coverage_percent: 0.0
    }
  end

  defp flow_snapshot do
    processed = get_telemetry_counter([:thunderline, :event, :publish])

    %{
      events_processed: processed,
      pipelines_active: 3,
      flow_rate: rate_per_second({:thunderflow, :events}, fn -> processed end),
      consciousness_level: if(processed > 0, do: :active, else: :idle)
    }
  end

  defp storage_snapshot do
    %{
      operations: get_telemetry_counter([:thunderblock, :storage, :operations]),
      integrity_percent: 100.0,
      compression_ratio: 1.0,
      health: :unknown
    }
  end

  defp governance_snapshot do
    %{
      actions: get_telemetry_counter([:thundercrown, :governance, :action]),
      policy_updates: get_telemetry_counter([:thundercrown, :policy, :update]),
      compliance_score: 100.0,
      authority_level: :active
    }
  end

  defp metric_total(metric_name) when is_binary(metric_name) do
    case ThunderMemory.get_metrics(metric_name, :minute) do
      {:ok, metrics} ->
        total =
          metrics
          |> Enum.map(&(&1.value || 0))
          |> Enum.reduce(0, &+/2)

        {:ok, total}

      other ->
        other
    end
  end

  defp metric_total(_), do: {:ok, 0}

  defp safe_number(value) when is_integer(value) or is_float(value), do: {:ok, value}

  defp safe_number(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      :error -> :error
    end
  end

  defp safe_number(_), do: :error

  defp initialize_uptime_tracking(force \\ false) do
    ensure_tables()

    if force do
      [
        {:boot, :monotonic},
        {:boot, :timestamp},
        {:downtime, :total_ms},
        {:downtime, :events},
        {:heartbeat, :monotonic},
        {:heartbeat, :last}
      ]
      |> Enum.each(fn key -> :ets.delete(@uptime_table, key) end)
    end

    case :ets.lookup(@uptime_table, {:boot, :monotonic}) do
      [] ->
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        now_ms = System.monotonic_time(:millisecond)
        boot_monotonic = max(now_ms - uptime_ms, 0)
        boot_timestamp = DateTime.add(DateTime.utc_now(), -div(uptime_ms, 1_000), :second)

        :ets.insert(@uptime_table, {{:boot, :monotonic}, boot_monotonic})
        :ets.insert(@uptime_table, {{:boot, :timestamp}, boot_timestamp})
        :ets.insert(@uptime_table, {{:downtime, :total_ms}, 0})
        :ets.insert(@uptime_table, {{:downtime, :events}, []})
        :ets.insert(@uptime_table, {{:heartbeat, :monotonic}, now_ms})
        :ets.insert(@uptime_table, {{:heartbeat, :last}, DateTime.utc_now()})

      _ ->
        :ok
    end
  end

  defp record_uptime_heartbeat do
    ensure_tables()
    initialize_uptime_tracking()

    now_ms = System.monotonic_time(:millisecond)

    last_ms =
      case :ets.lookup(@uptime_table, {:heartbeat, :monotonic}) do
        [{{:heartbeat, :monotonic}, value}] -> value
        _ -> nil
      end

    cond do
      is_nil(last_ms) ->
        :ok

      now_ms < last_ms ->
        initialize_uptime_tracking(true)

      true ->
        gap = now_ms - last_ms
        threshold = @metrics_update_interval + @heartbeat_tolerance

        if gap > threshold do
          downtime_ms = max(gap - @metrics_update_interval, 0)
          increment_downtime(downtime_ms)
        end
    end

    :ets.insert(@uptime_table, {{:heartbeat, :monotonic}, now_ms})
    :ets.insert(@uptime_table, {{:heartbeat, :last}, DateTime.utc_now()})
    :ok
  end

  defp increment_downtime(duration_ms) when is_integer(duration_ms) and duration_ms > 0 do
    :ets.update_counter(
      @uptime_table,
      {:downtime, :total_ms},
      {2, duration_ms},
      {{:downtime, :total_ms}, 0}
    )

    store_downtime_event(duration_ms)
  end

  defp increment_downtime(_), do: :ok

  defp store_downtime_event(duration_ms) when is_integer(duration_ms) and duration_ms > 0 do
    entry = %{duration_ms: duration_ms, detected_at: DateTime.utc_now()}

    history =
      case :ets.lookup(@uptime_table, {:downtime, :events}) do
        [{{:downtime, :events}, events}] when is_list(events) -> [entry | events]
        _ -> [entry]
      end

    :ets.insert(
      @uptime_table,
      {{:downtime, :events}, Enum.take(history, @downtime_history_limit)}
    )
  end

  defp store_downtime_event(_), do: :ok

  defp downtime_total_ms do
    case :ets.lookup(@uptime_table, {:downtime, :total_ms}) do
      [{{:downtime, :total_ms}, value}] when is_integer(value) -> value
      _ -> 0
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
      average_latency_ms: get_telemetry_average([:broadway, :processor, :message, :latency])
    }
  end

  defp get_pipeline_stats(pipeline_name) do
    processed_total = get_telemetry_counter([:broadway, pipeline_name, :processed]) || 0
    failures_total = get_telemetry_counter([:broadway, pipeline_name, :failed]) || 0

    %{
      name: pipeline_name,
      status: :running,
      processed_count: processed_total,
      error_count: failures_total,
      current_load_per_sec:
        Float.round(rate_per_second({:pipeline, pipeline_name}, fn -> processed_total end), 2)
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

  defp ensure_tables do
    ensure_table(@telemetry_table)
    ensure_table(@ml_pipeline_table)
    ensure_table(@uptime_table)
    ensure_table(@rate_cache_table)
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
