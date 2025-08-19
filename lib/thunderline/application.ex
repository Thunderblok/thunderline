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
        {AshAuthentication.Supervisor, [otp_app: :thunderline]}
      ]
    end

    children = phoenix_foundation ++ [

      # ⚡🧱 THUNDERBLOCK - Storage & Memory Services
      Thunderline.ThunderMemory,
  {Thunderline.Log.RingBuffer, name: Thunderline.NoiseBuffer, limit: 500},

      # ⚡💧 THUNDERFLOW - Event Stream Processing
  Thunderline.Thunderflow.Support.CircuitBreaker,
      Thunderline.Thunderflow.Observability.FanoutAggregator,
      Thunderline.Thunderflow.Observability.FanoutGuard,
      Thunderline.Thunderflow.Observability.QueueDepthCollector,
      {Thunderline.Thunderflow.Pipelines.EventPipeline, []},
      {Thunderline.Thunderflow.Pipelines.CrossDomainPipeline, []},
      {Thunderline.Thunderflow.Pipelines.RealTimePipeline, []},

  # ⚡🔥 THUNDERBOLT - Compute Acceleration Services
      Thunderline.Thunderbolt.ThunderCell.Supervisor,
      Thunderline.ErlangBridge,
      Thunderline.NeuralBridge,

  # (Conditional DB/Ash/Oban children appended below)

      # ⚡🌐 THUNDERGATE - Gateway Services
      Thundergate.ThunderBridge,

      # ⚡🔗 THUNDERLINK - Communication Services
      Thunderlink.ThunderWebsocketClient,
      Thunderline.DashboardMetrics,
      Thunderline.ThunderBridge,
  # ⚡🧠 AUTOMATA - Shared knowledge space (canonical under Thunderbolt)
  Thunderline.Thunderbolt.Automata.Blackboard,

      # ⚡👑 THUNDERCROWN - Orchestration Services
      # (MCP Bus and AI orchestration services will be added here)

      # ⚡⚔️ THUNDERGUARD - Security Services
      # (Authentication and authorization services will be added here)

      # Phoenix Web Server (last to start before optional DB children)
      ThunderlineWeb.Endpoint
    ] ++ db_children

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]

    # Attach observability telemetry handlers
  Thunderline.Thunderflow.Observability.FanoutAggregator.attach()
    Thunderline.Telemetry.Oban.attach()
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
