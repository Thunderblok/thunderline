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

    compute_children = if start_compute? and not minimal? do
      [
        Thunderline.Thunderbolt.ThunderCell.Supervisor,
        Thunderline.ErlangBridge,
        Thunderline.NeuralBridge,
        Thunderline.ThunderBridge
      ]
    else
      []
    end

    endpoint_child = if start_endpoint? and not minimal? do
      [ThunderlineWeb.Endpoint]
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
  {Thunderline.Thunderflow.Heartbeat, [interval: 2000]},
      (not minimal? && {Thunderline.Thunderflow.Pipelines.EventPipeline, []}) || nil,
      (not minimal? && {Thunderline.Thunderflow.Pipelines.CrossDomainPipeline, []}) || nil,
      (not minimal? && {Thunderline.Thunderflow.Pipelines.RealTimePipeline, []}) || nil,
      (not minimal? && {Thunderline.Thunderflow.Pipelines.MarketIngest, []}) || nil,
      (not minimal? && {Thunderline.Thunderflow.Pipelines.EDGARIngest, []}) || nil,
      (on?(:tocp) and not minimal? && Thunderline.TOCP.Supervisor) || nil,
      (on?(:cerebros_bridge) and not minimal? && Thunderline.Thunderbolt.CerebrosBridge.Cache) || nil,
      Thunderline.DashboardMetrics,
      {Thunderline.Thunderflow.Observability.RingBuffer, name: Thunderline.NoiseBuffer, limit: 500},
  Thunderline.Thunderflow.Blackboard,
  # Thundergrid authoritative zone API (WARHORSE Week1 skeleton)
  Thunderline.Thundergrid.API,
      {Thunderline.Thunderflow.EventBuffer, [limit: 750]},
      Thundergate.Thunderwatch.Supervisor,
      (on?(:enable_voice_media) and not minimal? && {Registry, keys: :unique, name: Thunderline.Thunderlink.Voice.Registry}) || nil,
      (on?(:enable_voice_media) and not minimal? && Thunderline.Thunderlink.Voice.Supervisor) || nil,
      (on?(:ca_viz) and not minimal? && Thunderline.Thunderbolt.CA.Registry) || nil,
      (on?(:ca_viz) and not minimal? && Thunderline.Thunderbolt.CA.RunnerSupervisor) || nil,
      (on?(:thundervine_lineage) and not minimal? && {Thunderline.Thundervine.WorkflowCompactor, []}) || nil
    ] ++ compute_children ++ endpoint_child ++ extras
      |> Enum.filter(& &1)

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]

    Thunderline.Thunderflow.Observability.FanoutAggregator.attach()
  Thunderline.Thunderflow.Telemetry.Oban.attach()

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
