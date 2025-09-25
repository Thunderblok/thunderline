defmodule Thunderline.Application do
  @moduledoc """
  Main Thunderline Application - 7-Domain Federation Architecture

  Supervises all core domains and their coordination services:
  - ThunderBolt: High-performance compute and acceleration
  - ThunderFlow: Event streams and data rivers
  - ThunderGate: Gateway and external integrations
  - ThunderBlock: Storage and persistence
  - ThunderLink: Connection and communication
  - ThunderCrown: Governance and orchestration
  - ThunderGuard: Security and access control
  - ThunderGrid: Spatial coordinate and mesh management
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    minimal? = Application.get_env(:thunderline, :minimal_test_boot, false)

    skip_db? = System.get_env("SKIP_ASH_SETUP") in ["1", "true"]
    start_endpoint? = case System.get_env("START_ENDPOINT") do
      val when val in ["0", "false", "FALSE", "no", "No"] -> false
      _ -> true
    end
    start_compute? = case System.get_env("START_COMPUTE") do
      val when val in ["0", "false", "FALSE", "no", "No"] -> false
      _ -> true
    end

    phoenix_foundation = [
      ThunderlineWeb.Telemetry,
      {Phoenix.PubSub, name: Thunderline.PubSub},
      ThunderlineWeb.Presence
    ]

    db_children =
      if skip_db? do
        []
      else
        base = [
          Thunderline.Repo,
          Thunderline.Thunderblock.MigrationRunner
        ]

        # In minimal test boot we avoid starting Oban & its diagnostics/health reporters
        # to prevent noisy sandbox ownership errors & speed up the suite. They can be
        # explicitly enabled by setting START_OBAN=1.
        start_oban? =
          (not minimal?) and (System.get_env("START_OBAN") not in ["0", "false", "FALSE"])

        oban_children =
          if start_oban? do
            [
              {Oban, oban_config()},
              Thunderline.Thunderflow.Telemetry.ObanHealth,
              Thunderline.Thunderflow.Telemetry.ObanDiagnostics,
              {AshAuthentication.Supervisor, [otp_app: :thunderline]}
            ]
          else
            []
          end

        base ++ oban_children
      end

    # Container runtime role (infrastructure segregation)
    # Supported ROLE values:
    #  web      -> Phoenix endpoint + minimal supporting processes (no heavy pipelines)
    #  worker   -> All pipelines & Oban + no web endpoint
  #  ingest   -> Only ingest pipelines (supporting telemetry)
    #  realtime -> Only RealTimePipeline (for ultra-low latency fanout)
    #  compute  -> Thunderbolt compute supervision tree only
    #  all      -> Full stack (current default if unset)
    role = System.get_env("ROLE", "all") |> String.downcase()

    endpoint_child = if start_endpoint? and not minimal? and role in ["web", "all"] do
      [ThunderlineWeb.Endpoint]
    else
      []
    end

    compute_children = if start_compute? and not minimal? and role in ["compute", "all"] do
      [
        Thunderline.Thunderbolt.ThunderCell.Supervisor,
        Thunderline.ThunderBridge
      ]
    else
      []
    end

    extras = [
      # Legacy Bus shim removed (WARHORSE)
      (on?(:enable_ndjson) && {Thunderline.Thunderflow.Observability.NDJSON, [path: System.get_env("NDJSON_PATH") || "log/events.ndjson"]}) || nil,
      (on?(:enable_ups) && Thunderline.Thundergate.UPS) || nil,
      (System.get_env("ENABLE_SIGNAL_STACK") in ["1","true","TRUE"] && Thunderline.Thunderbolt.Signal.Sensor) || nil,
      Thunderline.Thunderblock.Checkpoint
    ] |> Enum.filter(& &1)

    core_db = db_children

  children = phoenix_foundation ++ core_db ++ [
      Thunderline.ThunderMemory,
      Thunderline.Thunderflow.Support.CircuitBreaker,
      Thunderline.Thunderflow.Observability.FanoutAggregator,
      Thunderline.Thunderflow.Observability.FanoutGuard,
  Thunderline.Thunderflow.Observability.QueueDepthCollector,
      Thunderline.Thunderflow.Observability.DriftMetricsProducer,
      # WARHORSE: unified heartbeat + validator integrated via EventBus
      # In minimal test boot, avoid starting Heartbeat to prevent Mnesia usage/errors
      (not minimal? && {Thunderline.Thunderflow.Heartbeat, [interval: 2000]}) || nil,
    (not minimal? and role in ["worker", "all"] && {Thunderline.Thunderflow.Pipelines.EventPipeline, []}) || nil,
    (not minimal? and role in ["worker", "all"] && {Thunderline.Thunderflow.Pipelines.CrossDomainPipeline, []}) || nil,
    (not minimal? and role in ["worker", "all", "realtime"] && {Thunderline.Thunderflow.Pipelines.RealTimePipeline, []}) || nil,
  # Market/EDGAR ingest pipelines removed
  # Demo realtime emitter (dev/demo only)
  (on?(:demo_realtime_emitter) and not minimal? && Thunderline.Thunderflow.DemoRealtimeEmitter) || nil,
  (on?(:tocp) and not minimal? && Thunderline.Thunderlink.Transport.Supervisor) || nil,
      (on?(:cerebros_bridge) and not minimal? &&
         {Task.Supervisor, name: Thunderline.TaskSupervisor, restart: :transient}) || nil,
      (on?(:cerebros_bridge) and not minimal? && Thunderline.Thunderbolt.CerebrosBridge.Cache) || nil,
  # In minimal test boot, avoid starting DashboardMetrics (queries Mnesia/node state)
  (not minimal? && Thunderline.DashboardMetrics) || nil,
      {Thunderline.Thunderflow.Observability.RingBuffer, name: Thunderline.NoiseBuffer, limit: 500},
  Thunderline.Thunderflow.Blackboard,
  {Thunderline.Thunderflow.Telemetry.LegacyBlackboardWatch, []},
  # Thundergrid authoritative zone API (WARHORSE Week1 skeleton)
  Thunderline.Thundergrid.API,
      {Thunderline.Thunderflow.EventBuffer, [limit: 750]},
      Thundergate.Thunderwatch.Supervisor,
      (on?(:enable_voice_media) and not minimal? && {Registry, keys: :unique, name: Thunderline.Thunderlink.Voice.Registry}) || nil,
      (on?(:enable_voice_media) and not minimal? && Thunderline.Thunderlink.Voice.Supervisor) || nil,
      (on?(:ca_viz) and not minimal? && Thunderline.Thunderbolt.CA.Registry) || nil,
      (on?(:ca_viz) and not minimal? && Thunderline.Thunderbolt.CA.RunnerSupervisor) || nil,
      (on?(:thundervine_lineage) and not minimal? && {Thunderline.Thundervine.WorkflowCompactor, []}) || nil,
      (not minimal? && Thunderline.Thundergate.SelfTest) || nil
    ] ++ compute_children ++ endpoint_child ++ extras
      |> Enum.filter(& &1)

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]

    Thunderline.Thunderflow.Observability.FanoutAggregator.attach()
    Thunderline.Thunderflow.Telemetry.Oban.attach()

    # OpenTelemetry instrumentation (no-op if OTEL_DISABLED=1)
    if System.get_env("OTEL_DISABLED") not in ["1", "true", "TRUE"] do
      # Phoenix spans (router, endpoint, liveview)
      :ok = OpentelemetryPhoenix.setup()

      # Ecto spans (if Repo is started later, handlers still capture events)
      try do
        :ok = OpentelemetryEcto.setup(Thunderline.Repo, [])
      rescue
        _ -> :ok
      end
    end

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThunderlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Private helper to configure AshOban with proper error handling
  defp oban_config do
    try do
      ash_domains = Application.fetch_env!(:thunderline, :ash_domains)
      oban_config = Application.fetch_env!(:thunderline, Oban)

      AshOban.config(ash_domains, oban_config)
    rescue
      error ->
        Logger.error("Failed to configure AshOban: #{inspect(error)}")
        # Fallback to basic Oban config without Ash integration
        Application.fetch_env!(:thunderline, Oban)
    end
  end

  defp on?(flag), do: flag in Application.get_env(:thunderline, :features, [])
end
