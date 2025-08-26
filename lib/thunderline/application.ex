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

    db_children = if skip_db? do
      []
    else
      [
    Thunderline.Repo,
    Thunderline.MigrationRunner,
    {Oban, oban_config()},
    Thunderline.Thunderflow.Telemetry.ObanHealth,
    Thunderline.Thunderflow.Telemetry.ObanDiagnostics,
        {AshAuthentication.Supervisor, [otp_app: :thunderline]}
      ]
    end

    compute_children = if start_compute? do
      [
        Thunderline.Thunderbolt.ThunderCell.Supervisor,
        Thunderline.ErlangBridge,
        Thunderline.NeuralBridge,
        Thunderline.ThunderBridge
      ]
    else
      Logger.warning("[Thunderline.Application] START_COMPUTE disabled - skipping ThunderCell/ErlangBridge/NeuralBridge/ThunderBridge")
      []
    end

    endpoint_child = if start_endpoint? do
      [ThunderlineWeb.Endpoint]
    else
      Logger.warning("[Thunderline.Application] START_ENDPOINT disabled - skipping Phoenix Endpoint")
      []
    end

    extras = [
      {Task, fn -> try do Thunderline.Bus.init_tables() rescue _ -> :ok end end},
      # NDJSON logger and UPS watcher now gated by feature helper (HC-10)
  (Thunderline.Feature.enabled?(:enable_ndjson) && {Thunderline.Thunderflow.Observability.NDJSON, [path: System.get_env("NDJSON_PATH") || "log/events.ndjson"]}) || nil,
  (Thunderline.Feature.enabled?(:enable_ups) && Thunderline.Thundergate.UPS) || nil,
      # Signal-processing stack (legacy env flag until migrated to unified registry)
  (System.get_env("ENABLE_SIGNAL_STACK") in ["1","true","TRUE"] && Thunderline.Thunderbolt.Signal.Sensor) || nil,
  Thunderline.Thunderblock.Checkpoint
    ] |> Enum.filter(& &1)

  # IMPORTANT: Start DB + migrations BEFORE any pipelines or processes that might query the DB.
  # Previously Repo/migrations were appended at the end, causing early connection attempts while
  # Postgres might still be coming up (especially in containerized/dev environments).
  core_db = db_children

  children = phoenix_foundation ++ core_db ++ [
      # ⚡🧱 THUNDERBLOCK - Storage & Memory Services
  Thunderline.ThunderMemory,

      # ⚡💧 THUNDERFLOW - Event Stream Processing
  Thunderline.Thunderflow.Support.CircuitBreaker,
      Thunderline.Thunderflow.Observability.FanoutAggregator,
      Thunderline.Thunderflow.Observability.FanoutGuard,
      Thunderline.Thunderflow.Observability.QueueDepthCollector,
  Thunderline.Thunderflow.Observability.DriftMetricsProducer,
      {Thunderline.Thunderflow.Pipelines.EventPipeline, []},
      {Thunderline.Thunderflow.Pipelines.CrossDomainPipeline, []},
      {Thunderline.Thunderflow.Pipelines.RealTimePipeline, []},
  # Phase 0 market & EDGAR ingestion skeletons
  {Thunderline.Thunderflow.Pipelines.MarketIngest, []},
  {Thunderline.Thunderflow.Pipelines.EDGARIngest, []},

  # ⚡🔥 THUNDERBOLT - Compute Acceleration Services (conditionally started)

  # (Conditional DB/Ash/Oban children appended below)

      # ⚡🌐 THUNDERGATE - Gateway Services
      Thundergate.ThunderBridge,

      # ⚡🔗 THUNDERLINK - Communication Services
  Thunderlink.ThunderWebsocketClient,
  Thunderline.DashboardMetrics,
  # ThunderBridge implementation lives under ThunderLink domain (see thunderlink/thunder_bridge.ex)
  {Thunderline.Thunderflow.Observability.RingBuffer, name: Thunderline.NoiseBuffer, limit: 500},
  # ⚡🧠 AUTOMATA - Shared knowledge space (canonical under Thunderbolt)
  Thunderline.Thunderbolt.Automata.Blackboard,
  # Dashboard Event Buffer (ETS ring for streaming events)
  {Thunderline.Thunderflow.EventBuffer, [limit: 750]},
  # Internal file observer (Thunderwatch) – optional, privacy-preserving alternative to Watchman
  Thunderline.Thunderwatch.Supervisor,
  # Voice / WebRTC MVP infrastructure (dynamic Membrane pipelines per room)
  {Registry, keys: :unique, name: Thunderline.Thundercom.Voice.Registry},
  Thunderline.Thundercom.Voice.Supervisor,

      # ⚡👑 THUNDERCROWN - Orchestration Services
      # (MCP Bus and AI orchestration services will be added here)

      # ⚡⚔️ THUNDERGUARD - Security Services
      # (Authentication and authorization services will be added here)

      # Phoenix Web Server (conditionally started after core observability)
  ] ++ compute_children ++ endpoint_child ++ extras

  opts = [strategy: :one_for_one, name: Thunderline.Supervisor]

  # Attach observability telemetry handlers
  Thunderline.Thunderflow.Observability.FanoutAggregator.attach()
      Thunderline.Thunderflow.Telemetry.Oban.attach()
  if skip_db?, do: Logger.warning("[Thunderline.Application] Starting with SKIP_ASH_SETUP - DB/Oban/AshAuth supervision children disabled for lightweight tests")

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
end
