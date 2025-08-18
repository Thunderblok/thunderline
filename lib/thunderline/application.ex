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
  optional_db? = System.get_env("OPTIONAL_DB") in ["1", "true"]
  skip_db? = if !skip_db? and optional_db? and not db_preflight?(), do: true, else: skip_db?

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
        # Oban with AshOban integration - must start after repo
        {Oban, oban_config()},
        {AshAuthentication.Supervisor, [otp_app: :thunderline]}
      ]
    end

    children = phoenix_foundation ++ [

      # ⚡🧱 THUNDERBLOCK - Storage & Memory Services
      Thunderline.ThunderMemory,

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
  # ⚡🧠 AUTOMATA - Shared knowledge space
  # Updated namespace for Automata Blackboard after refactor to Thunderbolt domain
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
  if skip_db? do
  reason = Process.get(:thunderline_db_preflight_reason)
  Logger.warning("[Thunderline.Application] Starting without DB/Oban (skip flag/OPTIONAL_DB) reason=#{inspect(reason)}")
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

  defp db_preflight? do
    cfg = Application.get_env(:thunderline, Thunderline.Repo) || []
    host = cfg[:hostname] || "127.0.0.1"
    port = cfg[:port] || 5432
    username = cfg[:username] || System.get_env("PGUSER") || "postgres"
    password = cfg[:password] || System.get_env("PGPASSWORD") || "postgres"
    database = cfg[:database] || System.get_env("PGDATABASE") || "postgres"

    # First quick TCP reachability check
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 400) do
      {:ok, socket} -> :gen_tcp.close(socket)
      _ ->
        return_false("port_unreachable")
    end

    # Attempt a lightweight direct Postgrex connection to the *target* database so that
    # OPTIONAL_DB mode can gracefully skip when the database itself is absent (3D000).
    # We keep timeouts short so it doesn't stall boot.
    opts = [
      hostname: host,
      port: port,
      username: username,
      password: password,
      database: database,
      connect_timeout: 800,
      timeout: 800,
      pool: DBConnection.ConnectionPool
    ]

    case Postgrex.start_link(opts) do
      {:ok, pid} ->
        Process.exit(pid, :normal)
        true
      {:error, %Postgrex.Error{postgres: %{code: :invalid_catalog_name}}} ->
        return_false("db_missing")
      {:error, %Postgrex.Error{} = err} ->
        Logger.debug("[db_preflight] Postgrex error: #{inspect(err)} - treating as unreachable for OPTIONAL_DB")
        return_false("pg_error")
      {:error, other} ->
        Logger.debug("[db_preflight] Other error: #{inspect(other)} - treating as unreachable for OPTIONAL_DB")
        return_false("other_error")
    end
  end

  defp return_false(reason) do
    Process.put(:thunderline_db_preflight_reason, reason)
    false
  end
end
