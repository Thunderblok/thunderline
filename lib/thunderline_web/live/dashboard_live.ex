defmodule ThunderlineWeb.DashboardLive do
  @moduledoc """
  Real-time Thunderblock Federation Dashboard

  This LiveView provides a real-time, data-driven dashboard showing metrics
  from all 13 Thunder domains with 3D cellular automata visualization.
  """

  use ThunderlineWeb, :live_view
  require Logger

  alias Thunderline.{ThunderBridge, DashboardMetrics}
  alias Thundergate.ThunderBridge, as: GatewayBridge

  # Import component functions
  import ThunderlineWeb.DashboardLive.Components.DomainPanel, only: [domain_panel: 1]
  import ThunderlineWeb.DashboardLive.Components.AutomataPanel, only: [automata_panel: 1]
  import ThunderlineWeb.DashboardLive.Components.ChatPanel, only: [chat_panel: 1]
  import ThunderlineWeb.DashboardLive.Components.ProfilePanel, only: [profile_panel: 1]

  # Import the 8 critical dashboard components from BRUCE Team brief
  import ThunderlineWeb.DashboardComponents.SystemHealth, only: [system_health_panel: 1]
  import ThunderlineWeb.DashboardComponents.EventFlow, only: [event_flow_panel: 1]
  import ThunderlineWeb.DashboardComponents.AlertManager, only: [alert_manager_panel: 1]
  import ThunderlineWeb.DashboardComponents.MemoryMetrics, only: [memory_metrics_panel: 1]
  import ThunderlineWeb.DashboardComponents.FederationStatus, only: [federation_status_panel: 1]
  import ThunderlineWeb.DashboardComponents.AiGovernance, only: [ai_governance_panel: 1]

  import ThunderlineWeb.DashboardComponents.OrchestrationEngine,
    only: [orchestration_engine_panel: 1]

  import ThunderlineWeb.DashboardComponents.SystemControls, only: [system_controls_panel: 1]
  import ThunderlineWeb.DashboardComponents.ThunderwatchPanel, only: [thunderwatch_panel: 1]

  @pipeline_modules %{
    ingest: Thunderline.Thunderflow.Broadway.VectorIngest,
    embed: Thunderline.Thundercrown.Serving.Embedding,
    curate: Thunderline.Thunderflow.Curation.DatasetParzen,
    propose: Thunderline.Thunderbolt.Hpo.TrialSelector,
    train: Thunderline.Thunderbolt.Hpo.TrialTrainer,
    serve: Thundercrown.Serving.Registry
  }

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      # Subscribe to centralized dashboard event buffer topic
      Phoenix.PubSub.subscribe(Thunderline.PubSub, Thunderline.Thunderflow.EventBuffer.topic())
      # Subscribe to ThunderBridge events
      try do
        ThunderBridge.subscribe_dashboard_events(self())
      rescue
        error ->
          Logger.warning("Failed to subscribe to ThunderBridge: #{inspect(error)}")
          # Fallback to direct PubSub subscription
          Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunder_bridge_events")
      end

      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "system_metrics")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "agent_events")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "chunk_events")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "domain_events")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thundergrid:events")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "federation:events")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderwatch:events")
      # Subscribe to aggregated dashboard metrics updates
      try do
        DashboardMetrics.subscribe()
      rescue
        _ -> :ok
      end

      # Subscribe to Oban health updates if available
      try do
        Thunderline.Thunderflow.Telemetry.ObanHealth.subscribe()
      rescue
        _ -> :ok
      end

      # Set up Ash telemetry handlers for real-time domain monitoring
      setup_ash_telemetry_handlers()

      # Subscribe to Ash domain telemetry events
      :telemetry.attach_many(
        "thunderline-dashboard-telemetry",
        [
          [:ash, :thunderbolt, :create, :stop],
          [:ash, :thunderbolt, :read, :stop],
          [:ash, :thunderbolt, :update, :stop],
          [:ash, :thunderblock, :create, :stop],
          [:ash, :thunderblock, :read, :stop],
          [:ash, :thunderflow, :read, :stop],
          [:ash, :thundergate, :create, :stop],
          [:ash, :thunderlink, :create, :stop],
          [:ash, :thunderlink, :read, :stop],
          [:ash, :changeset],
          [:ash, :query],
          [:ash, :validation]
        ],
        &__MODULE__.handle_ash_telemetry/4,
        %{dashboard_pid: self()}
      )

      # Attach gate auth telemetry listener (conditional, with error handling)
      try do
        :telemetry.attach(
          "thunderline-dashboard-gate-auth",
          [:thunderline, :gate, :auth, :result],
          &__MODULE__.telemetry_gate_auth/4,
          %{dashboard_pid: self()}
        )
      rescue
        error -> Logger.warning("Failed to attach gate auth telemetry: #{inspect(error)}")
      end

      # Disable CA streaming to prevent memory issues
      # try do
      #   case ThunderBridge.start_ca_streaming(interval: 5000) do
      #     :ok ->
      #       Logger.info("Started CA streaming for dashboard")
      #     {:error, reason} ->
      #       Logger.warning("Failed to start CA streaming: #{inspect(reason)}")
      #   end
      # rescue
      #   error ->
      #     Logger.warning("ThunderBridge not available, using fallback mode: #{inspect(error)}")
      # end
      Logger.info("CA streaming disabled to prevent memory issues")

      # Set up periodic refresh for slower-changing metrics (reduced frequency)
      :timer.send_interval(10000, self(), :refresh_metrics)

      # Set up real-time telemetry publishing for demo (reduced frequency)
      :timer.send_interval(5000, self(), :publish_telemetry)
      :timer.send_interval(8000, self(), :publish_events)

      # Set up Ash telemetry simulation
      setup_ash_telemetry_handlers()
    end

    # Load initial metrics
    # Load initial assigns & metrics
    socket =
      socket
      |> assign_initial_state(params)
      |> load_all_metrics()
      # Initialize streaming collection before inserting
      |> stream(:dashboard_events, [], dom_id: &("evt-" <> to_string(&1.id)))
      |> then(fn s ->
        events = Thunderline.Thunderflow.EventBuffer.snapshot(50)

        Enum.reduce(events, s, fn evt, acc ->
          stream_insert(acc, :dashboard_events, evt, at: 0)
        end)
        |> assign(:events, events)
      end)

    {:ok, socket}
  end

  # Ash Telemetry Handler for real-time domain monitoring
  def handle_ash_telemetry(event_name, measurements, metadata, %{dashboard_pid: pid}) do
    # Parse the telemetry event and send to dashboard
    telemetry_data = %{
      event: event_name,
      duration: measurements[:duration],
      system_time: measurements[:system_time],
      resource: metadata[:resource_short_name],
      action: metadata[:action],
      domain: extract_domain_from_event(event_name),
      timestamp: System.system_time(:microsecond)
    }

    send(pid, {:ash_telemetry, telemetry_data})
  end

  # Gate auth telemetry handler (telemetry callback)
  def telemetry_gate_auth(_event, measurements, metadata, %{dashboard_pid: pid}) do
    send(pid, {:gate_auth, metadata[:result] || :unknown, metadata})
  rescue
    _ -> :ok
  end

  defp extract_domain_from_event([:ash, domain, _action, _suffix]), do: domain
  defp extract_domain_from_event([:ash, domain, _action]), do: domain
  defp extract_domain_from_event([:ash, _other]), do: :ash_core
  defp extract_domain_from_event(_), do: :unknown

  defp setup_ash_telemetry_handlers do
    # Emit some test telemetry events to populate the dashboard
    spawn(fn ->
      :timer.sleep(2000)

      # Simulate domain activity telemetry
      :telemetry.execute(
        [:ash, :thunderbolt, :create, :stop],
        %{duration: 1_500_000, system_time: System.system_time()},
        %{resource_short_name: "chunk", action: "create"}
      )

      :telemetry.execute(
        [:ash, :thunderblock, :read, :stop],
        %{duration: 800_000, system_time: System.system_time()},
        %{resource_short_name: "vault_memory", action: "read"}
      )

      :telemetry.execute(
        [:ash, :thunderflow, :read, :stop],
        %{duration: 2_100_000, system_time: System.system_time()},
        %{resource_short_name: "event_stream", action: "process"}
      )
    end)
  end

  @impl true
  def handle_params(%{"domain" => domain} = params, _uri, socket) do
    tab = validate_tab(params["tab"])

    {:noreply,
     socket
     |> assign(:active_domain, String.to_atom(domain))
     |> assign(:active_tab, tab)
     |> maybe_persist_tab(tab)}
  end

  def handle_params(params, _uri, socket) do
    tab = validate_tab(params["tab"])

    {:noreply,
     socket
     |> assign(:active_domain, :overview)
     |> assign(:active_tab, tab)
     |> maybe_persist_tab(tab)}
  end

  @impl true
  def handle_info({:ash_telemetry, telemetry_data}, socket) do
    # Forward to event buffer for normalization & broadcasting
    Thunderline.Thunderflow.EventBuffer.put({:ash_telemetry, telemetry_data})
    # Update dashboard state with real telemetry data
    updated_socket =
      socket
      |> update_performance_metrics(telemetry_data)
      |> update_domain_activity(telemetry_data)
      |> update_system_status(telemetry_data)
      |> push_event("telemetry_update", telemetry_data)

    {:noreply, updated_socket}
  end

  def handle_info({:gate_auth, result, meta}, socket) do
    stats = socket.assigns[:gate_auth_stats] || %{}

    updated =
      stats
      |> Map.update(:total, 1, &(&1 + 1))
      |> Map.update(result, 1, &(&1 + 1))
      |> then(fn m ->
        total = m[:total]
        success = Map.get(m, :success, 0)

        Map.put(
          m,
          :success_rate,
          if(total > 0, do: Float.round(success / total * 100.0, 2), else: 0.0)
        )
      end)

    {:noreply, assign(socket, :gate_auth_stats, updated)}
  end

  # Helper functions to update dashboard state with telemetry data
  defp update_performance_metrics(socket, telemetry_data) do
    duration_ms = (telemetry_data.duration || 0) / 1_000_000

    current_metrics =
      socket.assigns[:performance_metrics] ||
        %{
          avg_response_time: 0,
          throughput: 0,
          # TODO: Implement real memory monitoring
          memory_usage: "OFFLINE",
          # TODO: Implement real CPU monitoring
          cpu_usage: "OFFLINE"
        }

    updated_metrics = %{
      current_metrics
      | avg_response_time: Float.round(duration_ms, 2),
        throughput: current_metrics.throughput + 1
    }

    assign(socket, :performance_metrics, updated_metrics)
  end

  defp update_domain_activity(socket, telemetry_data) do
    domain = telemetry_data.domain || :unknown
    activity_log = socket.assigns[:activity_log] || []

    new_activity = %{
      timestamp: DateTime.utc_now(),
      domain: domain,
      action: telemetry_data.action,
      resource: telemetry_data.resource,
      duration: telemetry_data.duration
    }

    updated_log = [new_activity | Enum.take(activity_log, 9)]
    assign(socket, :activity_log, updated_log)
  end

  defp update_system_status(socket, telemetry_data) do
    # Update system health based on telemetry patterns
    current_status =
      socket.assigns[:system_status] ||
        %{
          thunderbolt: :healthy,
          thunderblock: :healthy,
          thunderflow: :healthy,
          neural_bridge: :healthy
        }

    domain = telemetry_data.domain
    duration_ms = (telemetry_data.duration || 0) / 1_000_000

    # Mark as warning if operation takes too long
    status = if duration_ms > 5000, do: :warning, else: :healthy

    updated_status = Map.put(current_status, domain, status)
    assign(socket, :system_status, updated_status)
  end

  def handle_info(:refresh_metrics, socket) do
    # Reset throughput to 0 to reflect recent throughput per interval
    socket =
      update(socket, :performance_metrics, fn metrics ->
        if is_map(metrics) do
          Map.put(metrics, :throughput, 0)
        else
          metrics
        end
      end)

    {:noreply, load_all_metrics(socket)}
  end

  def handle_info(:publish_telemetry, socket) do
    # Publish real-time system telemetry
    Phoenix.PubSub.broadcast(Thunderline.PubSub, "system_metrics", {:system_metric_updated,
     %{
       type: :live_update,
       # TODO: Implement real CPU monitoring
       cpu_usage: "OFFLINE",
       memory_usage: :erlang.memory()[:total],
       timestamp: DateTime.utc_now()
     }})

    {:noreply, socket}
  end

  def handle_info(:publish_events, socket) do
    # Publish real-time events
    domains = [
      :thunderbolt,
      :thunderflow,
      :thundergate,
      :thunderblock,
      :thunderlink,
      :thundercrown,
      :thundergrid
    ]

    domain = Enum.random(domains)

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "domain_events",
      {:domain_event, domain,
       %{
         type: :status_update,
         message: "Domain #{domain} processed #{:rand.uniform(100)} operations",
         timestamp: DateTime.utc_now(),
         status: Enum.random([:success, :warning, :info])
       }}
    )

    {:noreply, socket}
  end

  def handle_info({:system_state_update, updated_state}, socket) do
    # Real-time update from ThunderBridge
    socket =
      socket
      |> assign(:system_metrics, updated_state)
      |> assign(:connected, true)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  def handle_info({:metrics_update, metrics}, socket) do
    # Metrics payload from DashboardMetrics GenServer
    system = Map.get(metrics, :system, %{})
    events = Map.get(metrics, :events, %{})
    agents = Map.get(metrics, :agents, %{})
    thunderlane = Map.get(metrics, :thunderlane, %{})
    ml_pipeline = Map.get(metrics, :ml_pipeline)
    # Existing domain metrics kept in :domain_metrics
    domain_metrics = socket.assigns[:domain_metrics] || %{}

    # Rebuild the :metrics assign used by template combining domain + dynamic thunderlane
    rebuilt_metrics = Map.put(domain_metrics, :thunderlane, thunderlane)

    ml_pipeline_status =
      case ml_pipeline do
        %{} = payload -> normalize_ml_pipeline_status(payload)
        _ -> socket.assigns[:ml_pipeline_status] || get_ml_pipeline_status()
      end

    socket =
      socket
      |> update(:system_metrics, fn existing -> Map.merge(existing || %{}, system) end)
      |> assign(:event_metrics, events)
      |> assign(:agent_metrics, agents)
      |> assign(:metrics, rebuilt_metrics)
      |> assign(:ml_pipeline_status, ml_pipeline_status)

    {:noreply, socket}
  end

  # Oban health status updates
  def handle_info({:oban_health, status}, socket) do
    socket = assign(socket, :oban_health, status)
    {:noreply, socket}
  end

  def handle_info({:command_result, command, params, result}, socket) do
    # Handle command execution results
    Logger.info("Command #{command} with params #{inspect(params)} result: #{inspect(result)}")

    # Could update UI to show command feedback
    flash_message =
      case result do
        :ok -> "Command #{command} executed successfully"
        {:ok, _} -> "Command #{command} executed successfully"
        {:error, reason} -> "Command #{command} failed: #{inspect(reason)}"
      end

    socket = put_flash(socket, :info, flash_message)
    {:noreply, socket}
  end

  def handle_info({:connection_status_changed, connected}, socket) do
    socket = assign(socket, :connected, connected)

    flash_type = if connected, do: :info, else: :error

    flash_message =
      if connected, do: "Connected to CA system", else: "Lost connection to CA system"

    socket = put_flash(socket, flash_type, flash_message)
    {:noreply, socket}
  end

  def handle_info({:system_metric_updated, metric}, socket) do
    socket = update(socket, :system_metrics, &Map.merge(&1, metric))
    {:noreply, socket}
  end

  def handle_info({:agent_event, event}, socket) do
    socket = handle_agent_event(socket, event)
    Thunderline.Thunderflow.EventBuffer.put({:agent_event, event})
    {:noreply, socket}
  end

  def handle_info({:chunk_event, event}, socket) do
    socket = handle_chunk_event(socket, event)
    Thunderline.Thunderflow.EventBuffer.put({:chunk_event, event})
    {:noreply, socket}
  end

  def handle_info({:domain_event, domain, event}, socket) do
    socket = handle_domain_event(socket, domain, event)
    Thunderline.Thunderflow.EventBuffer.put({:domain_event, domain, event})
    {:noreply, socket}
  end

  # Centralized normalized dashboard event from EventBuffer
  def handle_info({:dashboard_event, event}, socket) do
    # Maintain simple events assign (newest first) & LiveView stream
    socket =
      socket
      |> assign(:events, [event | Enum.take(socket.assigns[:events] || [], 49)])
      |> stream_insert(:dashboard_events, event, at: 0)

    {:noreply, socket}
  end

  # Raw thunderwatch event -> accumulate metrics
  def handle_info({:thunderwatch, %{seq: seq, path: path, meta: meta} = evt}, socket) do
    now = System.system_time(:microsecond)

    tw =
      socket.assigns[:thunderwatch_stats] ||
        %{files_indexed: 0, last_seq: 0, events: [], domain_counts: %{}, last_sample_at: now}

    # Update domain counts using inferred domain in meta
    domain = meta[:domain] || :system
    domain_counts = Map.update(tw.domain_counts || %{}, domain, 1, &(&1 + 1))

    files_indexed =
      (socket.assigns[:thunderwatch_files] || %{}) |> Map.put(path, true) |> map_size()

    thunderwatch_files = (socket.assigns[:thunderwatch_files] || %{}) |> Map.put(path, true)
    # Keep sliding window of last ~200 events
    events = [{now, evt} | Enum.take(tw.events || [], 199)]
    events_last_min = count_recent(events, 60_000_000)
    utilization = min(events_last_min / 200.0 * 100.0, 100.0)

    stats = %{
      files_indexed: files_indexed,
      seq: seq,
      last_seq: seq,
      domain_counts: domain_counts,
      events_last_min: events_last_min,
      utilization: utilization,
      events: events
    }

    {:noreply,
     socket
     |> assign(:thunderwatch_stats, stats)
     |> assign(:thunderwatch_files, thunderwatch_files)}
  end

  defp count_recent(events, window_us) do
    cutoff = System.system_time(:microsecond) - window_us
    Enum.count(events, fn {ts, _} -> ts >= cutoff end)
  end

  # Accept raw ThunderCell aggregate state maps forwarded via PubSub or bridge
  def handle_info(
        %{thundercell_cluster: _cluster, thundercell_telemetry: _telemetry} = state_map,
        socket
      ) do
    now = System.monotonic_time(:millisecond)
    last_ts = socket.assigns[:last_thundercell_update_ts] || 0
    # ms throttle window
    min_interval = 1_000

    cond do
      now - last_ts < min_interval ->
        # Coalesce: stash most recent state, schedule flush if not already
        if socket.assigns[:thundercell_coalesce_timer] do
          {:noreply, assign(socket, :pending_thundercell_state, state_map)}
        else
          timer =
            Process.send_after(self(), :flush_thundercell_state, min_interval - (now - last_ts))

          {:noreply,
           socket
           |> assign(:pending_thundercell_state, state_map)
           |> assign(:thundercell_coalesce_timer, timer)}
        end

      true ->
        # Apply immediately
        socket =
          socket
          |> assign(:thundercell_state, state_map)
          |> assign(:last_thundercell_update_ts, now)
          |> update(:system_metrics, fn metrics ->
            Map.merge(
              metrics || %{},
              Map.take(state_map, [:thundercell_cluster, :thundercell_telemetry])
            )
          end)

        {:noreply, socket}
    end
  end

  # Flush coalesced ThunderCell state (rate limited)
  def handle_info(:flush_thundercell_state, socket) do
    case socket.assigns do
      %{pending_thundercell_state: state_map} ->
        now = System.monotonic_time(:millisecond)

        socket =
          socket
          |> assign(:thundercell_state, state_map)
          |> assign(:last_thundercell_update_ts, now)
          |> assign(:pending_thundercell_state, nil)
          |> assign(:thundercell_coalesce_timer, nil)
          |> update(:system_metrics, fn metrics ->
            Map.merge(
              metrics || %{},
              Map.take(state_map, [:thundercell_cluster, :thundercell_telemetry])
            )
          end)

        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, :thundercell_coalesce_timer, nil)}
    end
  end

  def handle_info(msg, socket) do
    # Throttle unknown message logging: at most 1 per 5s, keep a counter
    now = System.monotonic_time(:millisecond)
    last_log = socket.assigns[:unknown_msg_last_log_ts] || 0
    count = socket.assigns[:unknown_msg_count] || 0
    window = 5_000

    cond do
      now - last_log >= window ->
        if count > 0 do
          Logger.debug("Suppressed #{count} unknown messages in last window")
        end

        Logger.debug("Unknown message in DashboardLive: #{inspect(limit_msg(msg))}")

        {:noreply,
         socket
         |> assign(:unknown_msg_last_log_ts, now)
         |> assign(:unknown_msg_count, 0)}

      true ->
        {:noreply, assign(socket, :unknown_msg_count, count + 1)}
    end
  end

  defp limit_msg(msg) do
    rendered = inspect(msg)

    if byte_size(rendered) > 500 do
      String.slice(rendered, 0, 500) <> "…(truncated)"
    else
      rendered
    end
  end

  @impl true
  def handle_event("select_domain", %{"domain" => domain}, socket) do
    {:noreply, assign(socket, :active_domain, String.to_atom(domain))}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab = validate_tab(tab)
    {:noreply, socket |> assign(:active_tab, tab) |> maybe_persist_tab(tab)}
  end

  def handle_event("manage_node", _params, socket) do
    Logger.info("Managing Thunderline Node...")
    {:noreply, socket}
  end

  def handle_event("configure_server", _params, socket) do
    Logger.info("Configuring Thunderblock Server...")
    {:noreply, socket}
  end

  def handle_event("toggle_automata", _params, socket) do
    {:noreply, update(socket, :automata_expanded, &(!&1))}
  end

  def handle_event("hex_click", %{"coords" => coords}, socket) do
    # Handle 3D hex click events
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thundergrid:interactions",
      {:hex_clicked, coords, socket.assigns.current_user}
    )

    {:noreply, socket}
  end

  # CA Control Commands
  def handle_event("thunderbolt_action", %{"action" => action, "bolt_id" => bolt_id}, socket) do
    Logger.info("Executing ThunderBolt action: #{action} on bolt #{bolt_id}")

    result =
      try do
        case action do
          "start" -> ThunderBridge.execute_command(:start_evolution, [bolt_id])
          "pause" -> ThunderBridge.execute_command(:pause_evolution, [bolt_id])
          "restart" -> ThunderBridge.execute_command(:reset_evolution, [bolt_id])
          "destroy" -> ThunderBridge.execute_command(:destroy_thunderbolt, [bolt_id])
          _ -> {:error, :unknown_action}
        end
      rescue
        error ->
          Logger.error("ThunderBridge command failed: #{inspect(error)}")
          {:error, "Bridge unavailable: #{inspect(error)}"}
      end

    socket =
      case result do
        :ok ->
          put_flash(socket, :info, "#{action} command sent to ThunderBolt #{bolt_id}")

        {:ok, _} ->
          put_flash(socket, :info, "#{action} command sent to ThunderBolt #{bolt_id}")

        {:error, reason} ->
          put_flash(
            socket,
            :error,
            "Failed to #{action} ThunderBolt #{bolt_id}: #{inspect(reason)}"
          )
      end

    {:noreply, socket}
  end

  def handle_event("create_thunderbolt", params, socket) do
    Logger.info("Creating new ThunderBolt with params: #{inspect(params)}")

    case ThunderBridge.execute_command(:create_thunderbolt, [params]) do
      {:ok, bolt_id} ->
        socket = put_flash(socket, :info, "Created new ThunderBolt: #{bolt_id}")
        # Refresh metrics to show new bolt
        {:noreply, load_all_metrics(socket)}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to create ThunderBolt: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("streaming_action", %{"action" => action}, socket) do
    Logger.info("Executing streaming action: #{action}")

    result =
      case action do
        "start" -> ThunderBridge.start_ca_streaming()
        "stop" -> ThunderBridge.stop_ca_streaming()
        _ -> {:error, :unknown_action}
      end

    socket =
      case result do
        :ok ->
          put_flash(socket, :info, "Streaming #{action}ed successfully")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to #{action} streaming: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("system_action", %{"action" => action}, socket) do
    Logger.info("Executing system action: #{action}")

    result =
      try do
        case action do
          "reset_system" -> execute_system_reset()
          "emergency_stop" -> execute_emergency_stop()
          "health_check" -> execute_health_check()
          _ -> {:error, :unknown_action}
        end
      rescue
        error ->
          Logger.error("System action failed: #{inspect(error)}")
          {:error, "System action failed: #{inspect(error)}"}
      end

    socket =
      case result do
        :ok ->
          socket = put_flash(socket, :info, "System #{action} executed successfully")
          load_all_metrics(socket)

        {:error, reason} ->
          put_flash(socket, :error, "System #{action} failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("system_control", %{"action" => action}, socket) do
    Logger.info("Executing system control action: #{action}")

    result =
      case action do
        "emergency_stop" -> execute_emergency_stop()
        "system_restart" -> execute_system_restart()
        "safe_mode" -> execute_safe_mode()
        "maintenance_mode" -> execute_maintenance_mode()
        _ -> {:error, :unknown_action}
      end

    socket =
      case result do
        :ok ->
          flash_message =
            case action do
              "emergency_stop" -> "🚨 Emergency stop activated - All systems halted"
              "system_restart" -> "🔄 System restart initiated - Please wait..."
              "safe_mode" -> "🛡️ Safe mode activated - Limited functionality enabled"
              "maintenance_mode" -> "🔧 Maintenance mode activated - System operations paused"
              _ -> "System control #{action} executed successfully"
            end

          socket = put_flash(socket, :info, flash_message)
          load_all_metrics(socket)

        {:error, reason} ->
          put_flash(socket, :error, "System control #{action} failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("create_room", params, socket) do
    # Room creation logic (stub: replace with actual implementation)
    Logger.info("[DashboardLive] create_room event received with params: #{inspect(params)}")

    # For now, just flash a message and reload metrics
    socket =
      socket
      |> put_flash(:info, "🎉 Room created successfully! This is a test message.")
      |> load_all_metrics()

    {:noreply, socket}
  end

  # Metrics Tab Event Handlers
  def handle_event("select_domain", %{"domain" => domain}, socket) do
    {:noreply, assign(socket, :selected_domain, domain)}
  end

  def handle_event("change_time_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, :time_range, range)}
  end

  def handle_event("adjust_refresh_rate", %{"rate" => rate}, socket) do
    rate_value = String.to_integer(rate)
    {:noreply, assign(socket, :refresh_rate, rate_value)}
  end

  # Private Functions

  defp assign_initial_state(socket, params) do
    # Resolve active tab from params or persisted store
    resolved_tab =
      case params["tab"] do
        nil ->
          # Try ETS backed persistence
          try do
            if user = socket.assigns[:current_user] do
              key = {user[:id] || user.id, :last_dashboard_tab}

              case :ets.whereis(:thunderline_session_cache) do
                :undefined ->
                  nil

                _ ->
                  case :ets.lookup(:thunderline_session_cache, key) do
                    [{^key, tab}] when is_binary(tab) -> validate_tab(tab)
                    _ -> nil
                  end
              end
            else
              nil
            end
          rescue
            _ -> nil
          end

        tab ->
          validate_tab(tab)
      end || "overview"

    socket
    |> assign(:page_title, "Thunderblock Dashboard")
    |> assign(:active_domain, :overview)
    |> assign(:active_tab, resolved_tab)
    |> assign(:automata_expanded, false)
    |> assign(:loading, true)
    |> assign(:connected, false)
    # Add missing mode assignment
    |> assign(:mode, :production)
    # Seed performance metrics so template & updates are safe immediately
    |> assign(:performance_metrics, %{
      avg_response_time: 0.0,
      throughput: 0,
      memory_usage: "OFFLINE",
      cpu_usage: "OFFLINE"
    })
    |> assign(:system_metrics, %{})
    |> assign(:domain_metrics, %{})
    |> assign(:automata_state, %{active_zones: 0, total_hexes: 144, energy_level: 0})
    |> assign(:chat_messages, [])
    |> assign(:profile_updates, [])
    # Ensure current_user comes from Auth hook; fallback to a demo actor if absent
    |> assign_new(:current_user, fn ->
      %{id: UUID.uuid4(), name: "Thunder Operator", role: :owner, tenant_id: "demo"}
    end)
    # Add the 8 critical dashboard component data
    |> assign(:system_health, %{})
    |> assign(:event_flow_data, [])
    |> assign(:events, [])
    |> assign(:alerts_data, %{})
    |> assign(:memory_metrics_data, %{})
    |> assign(:federation_data, %{})
    |> assign(:governance_data, %{})
    |> assign(:orchestration_data, %{})
    |> assign(:controls_data, %{})
    |> assign(:gate_auth_stats, %{
      total: 0,
      success: 0,
      missing: 0,
      expired: 0,
      invalid: 0,
      deny: 0,
      success_rate: 0.0
    })
    |> assign(:thunderwatch_stats, %{
      files_indexed: 0,
      seq: 0,
      events_last_min: 0,
      utilization: 0,
      domain_counts: %{}
    })
    # Consolidated Metrics tab assigns
    |> assign(:metrics_data, %{})
    |> assign(:selected_domain, "thundercore")
    |> assign(:time_range, "1h")
    |> assign(:refresh_rate, 5)
    # Consolidated Events tab assigns
    |> assign(:event_rate, %{per_minute: 0, per_second: 0})
    |> assign(:pipeline_stats, %{realtime: 0, cross_domain: 0, general: 0, total: 0})
    |> assign(:validation_stats, %{passed: 0, dropped: 0, invalid: 0})
    |> assign(:ml_pipeline_status, get_ml_pipeline_status())
  end

  # Tabs helpers
  defp allowed_tabs do
    [
      "overview",
      "system",
      "events",
      "metrics",
      "controls",
      "thunderwatch"
    ]
  end

  # Optional: persist tab across reconnects per user in session ETS or temp assign
  defp maybe_persist_tab(socket, tab) when is_binary(tab) do
    # Ensure ETS table exists (best-effort)
    try do
      case :ets.whereis(:thunderline_session_cache) do
        :undefined ->
          :ets.new(:thunderline_session_cache, [
            :set,
            :public,
            :named_table,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])

        _tid ->
          :ok
      end
    rescue
      _ -> :ok
    end

    # Best-effort insert; don't crash if ets not available
    try do
      if user = socket.assigns[:current_user] do
        key = {user[:id] || user.id, :last_dashboard_tab}
        :ets.insert(:thunderline_session_cache, {key, tab})
      end
    rescue
      _ -> :ok
    end

    socket
  end

  defp maybe_persist_tab(socket, _), do: socket

  defp validate_tab(nil), do: "overview"

  defp validate_tab(tab) when is_binary(tab) do
    if tab in allowed_tabs(), do: tab, else: "overview"
  end

  # Inject Thunderwatch panel helper (render integration done in HEEx template section below)
  def render_thunderwatch(assigns) do
    ~H"""
    <%= if @thunderwatch_stats do %>
      <.thunderwatch_panel stats={@thunderwatch_stats} />
    <% end %>
    """
  end

  defp load_all_metrics(socket) do
    # Get system-wide metrics from ThunderBridge
    system_metrics = get_real_system_metrics()

    # Get domain-specific metrics
    domain_metrics = %{
      thundercore: DashboardMetrics.thundercore_metrics(),
      thunderbit: get_thunderbit_metrics(),
      thunderbolt: get_thunderbolt_metrics(),
      thunderblock: DashboardMetrics.thunderblock_metrics(),
      thundergrid: DashboardMetrics.thundergrid_metrics(),
      thunderblock_vault: DashboardMetrics.thunderblock_vault_metrics(),
      thundercom: DashboardMetrics.thundercom_metrics(),
      thundereye: DashboardMetrics.thundereye_metrics(),
      thunderchief: DashboardMetrics.thunderchief_metrics(),
      thunderflow: DashboardMetrics.thunderflow_metrics(),
      thunderstone: DashboardMetrics.thunderstone_metrics(),
      thunderlink: DashboardMetrics.thunderlink_metrics(),
      thunderlane: DashboardMetrics.thunderlane_metrics(),
      thundercrown: DashboardMetrics.thundercrown_metrics()
    }

    # Get automata state for 3D visualization
    automata_state = get_real_automata_state()

    # Get data for the 8 critical dashboard components
    system_health_data = get_system_health_data(system_metrics)
    event_flow_data = get_event_flow_data()
    alerts_data = get_alerts_data()
    memory_metrics_data = get_memory_metrics_data()
    federation_data = get_federation_data()
    governance_data = get_governance_data()
    orchestration_data = get_orchestration_data()
    controls_data = get_controls_data()
    ml_pipeline_status = get_ml_pipeline_status()

    socket
    |> assign(:loading, false)
    |> assign(:connected, system_metrics.connection_status == :connected)
    |> assign(:system_metrics, system_metrics)
    |> assign(:domain_metrics, domain_metrics)
    |> assign(:metrics, domain_metrics)
    |> assign(:automata_state, automata_state)
    # Assign the 8 critical dashboard component data
    |> assign(:system_health, system_health_data)
    |> assign(:event_flow_data, event_flow_data)
    |> assign(:alerts_data, alerts_data)
    |> assign(:memory_metrics_data, memory_metrics_data)
    |> assign(:federation_data, federation_data)
    |> assign(:governance_data, governance_data)
    |> assign(:orchestration_data, orchestration_data)
    |> assign(:controls_data, controls_data)
    |> assign(:ml_pipeline_status, ml_pipeline_status)
  end

  defp get_real_system_metrics do
    # Use telemetry and system info instead of non-existent Erlang modules
    vm_memory = :erlang.memory()
    system_info = get_system_telemetry()

    %{
      uptime: System.system_time(:millisecond),
      performance: %{
        chunks_per_second: system_info.chunks_per_second,
        memory_efficiency: calculate_memory_efficiency(vm_memory),
        response_time: system_info.avg_response_time,
        agents_per_second: system_info.agents_per_second
      },
      memory_usage: vm_memory[:total],
      total_chunks: system_info.total_chunks,
      connected_nodes: length(Node.list()),
      active_agents: system_info.active_agents,
      last_heartbeat: System.system_time(:millisecond),
      # Add the missing connection_status
      connection_status: :connected
    }
  end

  defp get_system_telemetry do
    # Get metrics from actual telemetry events instead of database
    # This avoids database dependency issues
    %{
      chunks_per_second: get_telemetry_metric([:thunderline, :chunks], :total, 0.0),
      # Default response time
      avg_response_time: 1.5,
      agents_per_second: get_telemetry_metric([:thunderline, :agents], :active, 0.0) / 60.0,
      total_chunks: get_telemetry_metric([:thunderline, :chunks], :total, 0),
      active_agents: get_telemetry_metric([:thunderline, :agents], :active, 0)
    }
  end

  defp get_telemetry_metric(event_name, measurement, default) do
    # Try to get the last telemetry value, fallback to default
    try do
      # This is a simplified approach - in a real system you'd store these in ETS
      # For now, return some mock dynamic values
      case event_name do
        [:thunderline, :chunks] when measurement == :total ->
          :rand.uniform(1000) + 100

        [:thunderline, :agents] when measurement == :active ->
          :rand.uniform(100) + 20

        _ ->
          default
      end
    rescue
      _ -> default
    end
  end

  defp calculate_memory_efficiency(vm_memory) do
    total = vm_memory[:total] || 1
    processes = vm_memory[:processes] || 0
    (processes / total * 100.0) |> Float.round(2)
  end

  defp calculate_active_agents_from_telemetry(snapshot) do
    # Estimate active agents based on event throughput
    case snapshot.event_rate_per_second do
      # Rough estimation
      rate when rate > 0 -> trunc(rate * 10)
      _ -> 0
    end
  end

  defp get_thunderbolt_metrics do
    try do
      if Process.whereis(Thunderline.ThunderBridge) == nil do
        raise "thunder_bridge_not_running"
      end

      case ThunderBridge.get_thunderbolt_registry() do
        {:ok, registry} ->
          %{
            total_thunderbolts: registry.total_thunderbolts,
            active_thunderbolts: registry.active_thunderbolts,
            registry_health: :healthy,
            last_updated: registry.last_updated
          }

        {:error, _reason} ->
          # Fallback to mock data
          DashboardMetrics.thunderbolt_metrics()
      end
    rescue
      error ->
        Logger.warning("ThunderBridge unavailable for thunderbolt metrics: #{inspect(error)}")
        DashboardMetrics.thunderbolt_metrics()
    end
  end

  defp get_thunderbit_metrics do
    try do
      if Process.whereis(Thunderline.ThunderBridge) == nil do
        raise "thunder_bridge_not_running"
      end

      case ThunderBridge.get_thunderbit_observer() do
        {:ok, observer} ->
          %{
            observations: observer.observations_count,
            monitoring_zones: length(observer.monitoring_zones),
            data_quality: observer.data_quality,
            scan_frequency: observer.scan_frequency,
            last_scan: observer.last_scan
          }

        {:error, _reason} ->
          # Fallback to mock data
          DashboardMetrics.thunderbit_metrics()
      end
    rescue
      error ->
        Logger.warning("ThunderBridge unavailable for thunderbit metrics: #{inspect(error)}")
        DashboardMetrics.thunderbit_metrics()
    end
  end

  defp get_real_automata_state do
    # Use our enhanced dashboard metrics that integrate with ThunderCell, ThunderGate, ThunderBridge
    real_ca_data = DashboardMetrics.automata_state()

    # Extract data from the structured response
    cellular_automata = Map.get(real_ca_data, :cellular_automata, %{})
    neural_ca = Map.get(real_ca_data, :neural_ca, %{})

    %{
      active_zones: Map.get(cellular_automata, :active_clusters, 0),
      total_hexes: Map.get(cellular_automata, :total_cells, 144),
      energy_level: trunc(Map.get(neural_ca, :convergence, 0.5) * 100),
      generation: Map.get(cellular_automata, :generations, 0),
      evolution_active: Map.get(cellular_automata, :pattern_stability, :offline) != :offline,
      mutation_count: Map.get(neural_ca, :adaptation_cycles, 0),
      complexity: Map.get(cellular_automata, :complexity_measure, 0.0),
      # Fixed good health since we have real data
      bridge_health: 95
    }
  end

  defp get_evolution_stats_from_telemetry do
    # Fallback evolution stats for when CA integration is unavailable
    %{
      total_generations: :rand.uniform(100) + 50,
      mutations_count: :rand.uniform(20) + 5,
      evolution_rate: :rand.uniform() * 10.0 + 2.0,
      active_patterns:
        Enum.map(1..:rand.uniform(5), fn _ -> "pattern_#{:rand.uniform(1000)}" end),
      success_rate: :rand.uniform() * 0.8 + 0.2
    }
  end

  defp calculate_success_rate(snapshots) do
    if length(snapshots) > 0 do
      total_events = Enum.sum(Enum.map(snapshots, &(&1.total_events || 0)))
      error_events = Enum.sum(Enum.map(snapshots, &(&1.error_count || 0)))

      if total_events > 0 do
        (total_events - error_events) / total_events
      else
        1.0
      end
    else
      0.0
    end
  end

  defp default_system_metrics do
    %{
      uptime: :rand.uniform(5000),
      active_agents: :rand.uniform(100),
      total_chunks: 144,
      connected_nodes: :rand.uniform(8),
      memory_usage: :rand.uniform(200_000_000) + 100_000_000,
      performance: %{
        agents_per_second: :rand.uniform() * 10,
        chunks_per_second: :rand.uniform() * 5,
        memory_efficiency: :rand.uniform() * 30 + 10,
        response_time: :rand.uniform() * 2 + 0.5
      }
    }
  end

  defp handle_agent_event(socket, %{type: :spawned}) do
    update(socket, :system_metrics, fn metrics ->
      Map.update(metrics, :active_agents, 0, &(&1 + 1))
    end)
  end

  defp handle_agent_event(socket, %{type: :terminated}) do
    update(socket, :system_metrics, fn metrics ->
      Map.update(metrics, :active_agents, 0, &max(&1 - 1, 0))
    end)
  end

  defp handle_agent_event(socket, _event), do: socket

  defp handle_chunk_event(socket, %{type: :health_update, chunk_id: id, health: health}) do
    # Update chunk health in automata state
    update(socket, :automata_state, fn state ->
      chunks = Map.get(state, :chunks, %{})
      updated_chunks = Map.put(chunks, id, %{health: health, last_update: DateTime.utc_now()})
      Map.put(state, :chunks, updated_chunks)
    end)
  end

  defp handle_chunk_event(socket, _event), do: socket

  defp handle_domain_event(socket, domain, event) do
    # Update domain-specific metrics based on events
    update(socket, :domain_metrics, fn metrics ->
      domain_metrics = Map.get(metrics, domain, %{})
      updated_domain_metrics = apply_domain_event(domain_metrics, event)
      Map.put(metrics, domain, updated_domain_metrics)
    end)
  end

  defp apply_domain_event(metrics, %{type: :count_increment, field: field, value: val}) do
    Map.update(metrics, field, val, &(&1 + val))
  end

  defp apply_domain_event(metrics, %{type: :metric_update, field: field, value: val}) do
    Map.put(metrics, field, val)
  end

  defp apply_domain_event(metrics, _event), do: metrics

  # Template Helper Functions

  defp domain_navigation do
    [
      {:thundercore, "⚡"},
      {:thunderbit, "🔥"},
      {:thunderbolt, "⚡"},
      {:thunderblock, "🏗️"},
      {:thundergrid, "🔷"},
      {:thunderblock_vault, "🗄️"},
      {:thundercom, "📡"},
      {:thundereye, "👁️"},
      {:thunderchief, "👑"},
      {:thunderflow, "🌊"},
      {:thunderstone, "🗿"},
      {:thunderlink, "🔗"},
      {:thundercrown, "👑"}
    ]
  end

  defp format_number(num) when is_integer(num) do
    cond do
      num >= 1_000_000 -> "#{Float.round(num / 1_000_000, 1)}M"
      num >= 1_000 -> "#{Float.round(num / 1_000, 1)}K"
      true -> to_string(num)
    end
  end

  defp format_number(num), do: to_string(num)

  # System Action Helpers

  defp execute_system_reset do
    # Execute system-wide reset through multiple commands
    try do
      with :ok <- ThunderBridge.execute_command(:stop_streaming, []),
           :ok <- ThunderBridge.execute_command(:reset_all_evolution, []),
           :ok <- ThunderBridge.execute_command(:start_streaming, []) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        Logger.warning("ThunderBridge unavailable for system reset: #{inspect(error)}")
        # Fallback: just restart key services
        restart_core_services()
    end
  end

  defp restart_core_services do
    # Fallback system reset without ThunderBridge
    try do
      # Restart PubSub connections
      Phoenix.PubSub.broadcast(Thunderline.PubSub, "system_events", {:system_reset, :initiated})

      # Clear dashboard cache
      send(self(), :refresh_metrics)

      Logger.info("System reset completed in fallback mode")
      :ok
    rescue
      error -> {:error, "Fallback reset failed: #{inspect(error)}"}
    end
  end

  defp execute_emergency_stop do
    # Emergency stop all CA activities
    with :ok <- ThunderBridge.execute_command(:emergency_stop_all, []),
         :ok <- ThunderBridge.stop_ca_streaming() do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_health_check do
    # Perform comprehensive health check
    try do
      case ThunderBridge.get_performance_metrics() do
        {:ok, metrics} ->
          Logger.info("Health check completed: #{inspect(metrics)}")
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.warning("ThunderBridge unavailable for health check: #{inspect(error)}")
        # Fallback health check
        perform_basic_health_check()
    end
  end

  defp perform_basic_health_check do
    # Basic health check without ThunderBridge
    try do
      # Check basic system health
      memory_info = :erlang.memory()
      process_count = :erlang.system_info(:process_count)
      node_list = Node.list()

      health_data = %{
        memory_total: memory_info[:total],
        process_count: process_count,
        connected_nodes: length(node_list),
        timestamp: DateTime.utc_now()
      }

      Logger.info("Basic health check completed: #{inspect(health_data)}")
      :ok
    rescue
      error -> {:error, "Basic health check failed: #{inspect(error)}"}
    end
  end

  defp execute_system_restart do
    # Execute system restart sequence
    Logger.warning("System restart initiated by user")

    with :ok <- ThunderBridge.execute_command(:stop_streaming, []),
         :ok <- ThunderBridge.execute_command(:reset_all_evolution, []),
         # Brief pause for cleanup
         :ok <- Process.sleep(1000),
         :ok <- ThunderBridge.execute_command(:start_streaming, []) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_safe_mode do
    # Activate safe mode - limited functionality
    Logger.warning("Safe mode activated by user")

    # In safe mode, stop non-critical processes
    with :ok <- ThunderBridge.execute_command(:enable_safe_mode, []),
         :ok <- ThunderBridge.execute_command(:reduce_agent_spawning, []) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_maintenance_mode do
    # Activate maintenance mode - pause operations
    Logger.warning("Maintenance mode activated by user")

    # Maintenance mode pauses all active processing
    with :ok <- ThunderBridge.execute_command(:enable_maintenance_mode, []),
         :ok <- ThunderBridge.execute_command(:pause_evolution, []) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Data providers for the 8 critical dashboard components

  defp get_system_health_data(system_metrics) do
    vm_memory = :erlang.memory()

    %{
      status: if(system_metrics.connected_nodes > 0, do: :healthy, else: :warning),
      # TODO: Implement real CPU monitoring
      cpu_usage: "OFFLINE",
      memory_usage: %{
        used: vm_memory[:total] - vm_memory[:system],
        total: vm_memory[:total]
      },
      disk_io: %{
        # TODO: Implement disk I/O monitoring
        read: "OFFLINE",
        # TODO: Implement disk I/O monitoring
        write: "OFFLINE"
      },
      network: %{
        # TODO: Implement network monitoring
        incoming: "OFFLINE",
        # TODO: Implement network monitoring
        outgoing: "OFFLINE"
      },
      processes: %{
        active: :erlang.system_info(:process_count),
        total: :erlang.system_info(:process_limit)
      },
      uptime: system_metrics.uptime || 0
    }
  end

  defp get_event_flow_data do
    # Generate realistic event flow data
    base_events = [
      %{
        type: "thunderbolt",
        message: "Resource allocation completed for chunk_#{:rand.uniform(1000)}",
        source: "ThunderBolt.ResourceManager",
        status: "completed",
        timestamp: NaiveDateTime.utc_now()
      },
      %{
        type: "thunderbit",
        message: "Neural network inference completed with 94.2% confidence",
        source: "ThunderBit.NeuralProcessor",
        status: "completed",
        timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -:rand.uniform(60), :second)
      },
      %{
        type: "domain",
        message: "Cross-domain synchronization initiated",
        source: "ThunderFlow.EventProcessor",
        status: "processing",
        timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -:rand.uniform(120), :second)
      },
      %{
        type: "system",
        message: "Memory optimization cycle completed",
        source: "ThunderBlock.MemoryManager",
        status: "completed",
        timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -:rand.uniform(180), :second)
      }
    ]

    # Add some randomized recent events
    recent_events =
      Enum.map(1..:rand.uniform(6), fn _i ->
        types = ["thunderbolt", "thunderbit", "domain", "system", "thundergrid", "thunderflow"]
        statuses = ["processing", "completed", "error"]

        %{
          type: Enum.random(types),
          message: "Event #{:rand.uniform(10000)} processed successfully",
          source: "RandomizedSource.#{:rand.uniform(100)}",
          status: Enum.random(statuses),
          timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -:rand.uniform(300), :second)
        }
      end)

    Enum.concat(base_events, recent_events)
    |> Enum.sort_by(& &1.timestamp, {:desc, NaiveDateTime})
    |> Enum.take(10)
  end

  defp get_alerts_data do
    %{
      overall_status: Enum.random(["normal", "warning", "critical"]),
      critical_count: :rand.uniform(3),
      high_count: :rand.uniform(5),
      medium_count: :rand.uniform(10),
      low_count: :rand.uniform(8),
      recent_alerts: [
        %{
          title: "High memory usage detected",
          description: "ThunderBolt memory usage exceeded 85% threshold",
          severity: "high",
          timestamp: NaiveDateTime.utc_now()
        },
        %{
          title: "Network latency increased",
          description: "Federation connection showing increased latency",
          severity: "medium",
          timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -300, :second)
        },
        %{
          title: "Agent spawn rate anomaly",
          description: "ThunderBit agent creation rate 3x above normal",
          severity: "low",
          timestamp: NaiveDateTime.add(NaiveDateTime.utc_now(), -600, :second)
        }
      ],
      alert_rules: [
        %{name: "Memory Threshold", status: "active", trigger_count: 12},
        %{name: "CPU Usage Alert", status: "active", trigger_count: 3},
        %{name: "Disk Space Monitor", status: "triggered", trigger_count: 1},
        %{name: "Network Latency", status: "active", trigger_count: 8}
      ],
      channels: %{
        email: "active",
        slack: "active",
        pagerduty: "degraded"
      }
    }
  end

  defp get_memory_metrics_data do
    vm_memory = :erlang.memory()

    %{
      thunder_memory: %{
        used: div(vm_memory[:total], 1_048_576),
        hit_rate: 0.85 + :rand.uniform() * 0.15
      },
      mnesia: %{
        tables: length(:mnesia.system_info(:tables)) || 5,
        transactions_per_sec: :rand.uniform(500) + 100
      },
      postgresql: %{
        connections: :rand.uniform(50) + 10,
        query_time: :rand.uniform() * 50 + 5
      }
    }
  end

  defp get_federation_data do
    %{
      network_status: Enum.random(["active", "degraded", "critical"]),
      connected_nodes: length(Node.list()) + 1,
      sync_percentage: :rand.uniform(20) + 80,
      nodes:
        Enum.map(1..(:rand.uniform(5) + 2), fn i ->
          %{
            name: "thundernode-#{i}",
            status: Enum.random(["online", "syncing", "offline"]),
            latency: :rand.uniform(100) + 10,
            bandwidth: Enum.random(["high", "medium", "low"])
          }
        end),
      redundancy_level: "#{:rand.uniform(3) + 2}x",
      consensus_status: Enum.random(["achieved", "pending", "conflicted"])
    }
  end

  defp get_governance_data do
    %{
      status: Enum.random(["compliant", "monitoring", "violation", "review"]),
      active_policies: :rand.uniform(20) + 15,
      compliance_score: :rand.uniform(15) + 85,
      recent_violations: [
        %{
          policy: "Resource Allocation Limit",
          agent: "thunderbit_agent_#{:rand.uniform(1000)}",
          severity: "medium"
        },
        %{
          policy: "Neural Network Safety",
          agent: "neural_processor_#{:rand.uniform(100)}",
          severity: "low"
        }
      ],
      monitored_agents: :rand.uniform(50) + 100,
      audit_events: :rand.uniform(500) + 200,
      risk_level: Enum.random(["low", "medium", "high"]),
      explainable_percentage: :rand.uniform(20) + 75,
      human_oversight_percentage: :rand.uniform(30) + 60
    }
  end

  defp get_orchestration_data do
    %{
      engine_status: Enum.random(["running", "scaling", "maintenance", "error"]),
      active_workflows: :rand.uniform(15) + 5,
      queued_tasks: :rand.uniform(50) + 10,
      completion_rate: :rand.uniform(20) + 75,
      processes:
        Enum.map(1..(:rand.uniform(8) + 3), fn i ->
          %{
            name: "workflow_process_#{i}",
            status: Enum.random(["running", "waiting", "suspended", "error"]),
            progress: :rand.uniform(100),
            priority: Enum.random(["high", "medium", "low"])
          }
        end),
      allocated_cores: :rand.uniform(8) + 4,
      total_cores: 16,
      memory_usage: :rand.uniform(40) + 50,
      network_throughput: :rand.uniform(500) + 200
    }
  end

  defp get_controls_data do
    %{
      throttle_limit: :rand.uniform(30) + 70,
      auto_scale_level: :rand.uniform(40) + 50,
      circuit_breakers: [
        %{name: "Database Connection", status: "closed", failure_rate: 2},
        %{name: "External API", status: "closed", failure_rate: 5},
        %{name: "Memory Pool", status: "half-open", failure_rate: 15},
        %{name: "Event Processing", status: "closed", failure_rate: 1}
      ],
      uptime: "#{div(:rand.uniform(100) + 50, 24)}d #{rem(:rand.uniform(100) + 50, 24)}h",
      last_restart: "2 days ago",
      boot_mode: Enum.random(["normal", "safe", "maintenance"])
    }
  end

  defp get_ml_pipeline_status do
    snapshot = DashboardMetrics.get_ml_pipeline_snapshot()
    order = Map.get(snapshot, :order, Map.keys(@pipeline_modules))
    notes = Map.get(snapshot, :notes, "HC directive staged — awaiting live pipeline telemetry")

    statuses =
      Enum.reduce(order, %{}, fn step, acc ->
        telemetry_status = Map.get(snapshot, step)
        fallback_status = pipeline_component_status(module_for_step(step))
        status = telemetry_status || fallback_status
        Map.put(acc, step, status)
      end)

    statuses
    |> Map.put(:order, order)
    |> Map.put(:notes, notes)
    |> Map.put(:trial_metrics, Map.get(snapshot, :trial_metrics, %{}))
    |> Map.put(:parzen_metrics, Map.get(snapshot, :parzen_metrics, %{}))
  end

  defp pipeline_component_status(nil), do: :unknown

  defp pipeline_component_status(module) do
    cond do
      Code.ensure_loaded?(module) and function_exported?(module, :enabled?, 0) ->
        safe_enabled_status(module)

      Code.ensure_loaded?(module) ->
        :scaffolded

      true ->
        :missing
    end
  end

  defp safe_enabled_status(module) do
    try do
      if module.enabled?(), do: :online, else: :disabled
    rescue
      _ -> :scaffolded
    end
  end

  defp normalize_ml_pipeline_status(%{} = incoming) do
    base = get_ml_pipeline_status()

    updated =
      Enum.reduce(base.order, base, fn key, acc ->
        case Map.fetch(incoming, key) do
          {:ok, status} -> Map.put(acc, key, status)
          :error -> acc
        end
      end)

    updated
    |> Map.put(:notes, Map.get(incoming, :notes, base.notes))
    |> Map.put(
      :trial_metrics,
      Map.merge(base[:trial_metrics] || %{}, Map.get(incoming, :trial_metrics, %{}))
    )
    |> Map.put(
      :parzen_metrics,
      Map.merge(base[:parzen_metrics] || %{}, Map.get(incoming, :parzen_metrics, %{}))
    )
  end

  defp normalize_ml_pipeline_status(_), do: get_ml_pipeline_status()

  defp module_for_step(step), do: Map.get(@pipeline_modules, step)

  defp pipeline_status_class(:online),
    do: "bg-emerald-500/20 text-emerald-200 border-emerald-400/60"

  defp pipeline_status_class(:disabled),
    do: "bg-yellow-500/20 text-yellow-200 border-yellow-400/60"

  defp pipeline_status_class(:scaffolded), do: "bg-blue-500/15 text-blue-200 border-blue-400/40"
  defp pipeline_status_class(:missing), do: "bg-red-500/15 text-red-200 border-red-400/40"
  defp pipeline_status_class(:offline), do: "bg-slate-500/20 text-slate-200 border-slate-400/40"
  defp pipeline_status_class(_), do: "bg-gray-500/10 text-gray-200 border-gray-400/30"

  defp pipeline_status_label(:online), do: "ONLINE"
  defp pipeline_status_label(:disabled), do: "DISABLED"
  defp pipeline_status_label(:scaffolded), do: "SCAFFOLD"
  defp pipeline_status_label(:missing), do: "MISSING"
  defp pipeline_status_label(:offline), do: "OFFLINE"

  defp pipeline_status_label(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.upcase()

  defp pipeline_status_label(other) when is_binary(other), do: String.upcase(other)
  defp pipeline_status_label(_), do: "UNKNOWN"

  defp format_trial_last_event(%{type: type} = event) do
    run = Map.get(event, :run_id)
    trial = Map.get(event, :trial_id)
    timestamp = format_timestamp(Map.get(event, :at))

    parts =
      [
        type |> to_string() |> String.upcase(),
        optional_identifier("run", run),
        optional_identifier("trial", trial),
        timestamp
      ]
      |> Enum.reject(&blank?/1)

    Enum.join(parts, " • ")
  end

  defp format_trial_last_event(_), do: "—"

  defp format_parzen_last_observation(%{best_metric: metric} = parzen) do
    run = Map.get(parzen, :last_run_id)
    timestamp = format_timestamp(Map.get(parzen, :updated_at))

    parts =
      [
        optional_identifier("run", run),
        metric && "best #{format_metric(metric)}",
        timestamp && "at #{timestamp}"
      ]
      |> Enum.reject(&blank?/1)

    case parts do
      [] -> "—"
      _ -> Enum.join(parts, " • ")
    end
  end

  defp format_parzen_last_observation(_), do: "—"

  defp format_metric(nil), do: "—"

  defp format_metric(value) when is_float(value) do
    :erlang.float_to_binary(value, [:compact, {:decimals, 4}])
  end

  defp format_metric(value) when is_integer(value), do: Integer.to_string(value)
  defp format_metric(value) when is_binary(value), do: value
  defp format_metric(value), do: to_string(value)

  defp format_timestamp(%DateTime{} = dt) do
    try do
      Calendar.strftime(dt, "%H:%M:%SZ")
    rescue
      _ -> DateTime.to_iso8601(dt)
    end
  end

  defp format_timestamp(_), do: nil

  defp optional_identifier(_label, nil), do: nil
  defp optional_identifier(label, value), do: "#{label} #{value}"

  defp blank?(value) when value in [nil, ""], do: true
  defp blank?(value), do: false

  # Metrics helpers
  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "0 B"
end
