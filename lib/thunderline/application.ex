defmodule Thunderline.Application do
  @moduledoc """
  OTP application supervisor for the Thunderline platform.

  Responsibilities:
    * Start shared infrastructure (Repo, Vault, PubSub, Presence)
    * Wire telemetry, Oban, and the Phoenix Endpoint
    * Respect runtime feature flags (e.g. SKIP_ASH_SETUP) when starting children
  """

  use Application
  alias Thunderline.Feature

  @impl Application
  def start(_type, _args) do
    Thunderline.Thunderblock.Telemetry.Retention.attach()
    attach_reward_handler()

    # CRITICAL: Children are started sequentially in the order listed.
    # Repo MUST be before Oban to avoid ETS registry races.
    # Do NOT use Supervisor.start_child or other dynamic approaches.
    children = build_children_list()

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_children_list do
    # Core infrastructure - these start first
    core = [
      ThunderlineWeb.Telemetry,
      maybe_vault_child(),
      {Phoenix.PubSub, name: Thunderline.PubSub},
      {Task.Supervisor, name: Thunderline.TaskSupervisor}
    ]

    # Database layer - MUST be before Oban and tick system
    database = [maybe_repo_child()]

    # Tick system - starts AFTER database, BEFORE domains
    # DomainRegistry MUST start before TickGenerator
    tick_system = [
      Thunderline.Thunderblock.DomainRegistry,
      Thunderline.Thunderlink.TickGenerator
    ]

    # Domain-specific children that may need DB (excluding Cerebros - starts after Oban)
    domains =
      saga_children() ++
        rag_children() ++
        upm_children() ++
        ml_pipeline_children()

    # Infrastructure that does NOT need DB access - safe to start early
    # NOTE: All domain supervisors use tick-based activation (Phase 3+: OPERATION BLAZING VINE EXTENDED)
    infrastructure_early = [
      # Tick 1: Core flow & state
      Thunderline.Thunderflow.Supervisor,
      # Tick 2: Authentication & presence
      Thunderline.Thundergate.Supervisor,
      Thunderline.Thunderlink.Supervisor,
      # Tick 3: Orchestration engine
      Thunderline.Thunderbolt.Supervisor,
      # Tick 4: AI sovereignty
      Thunderline.Thundercrown.Supervisor,
      # Tick 5: DAG persistence
      Thundervine.Supervisor,
      # Tick 6: Spatial & GraphQL
      Thunderline.Thundergrid.Supervisor,
      # Tick 7: Visual intelligence
      Thunderline.Thunderprism.Supervisor,
      # Non-domain infrastructure
      ThunderlineWeb.Presence
    ]

    # Background job processor - MUST be after Repo
    jobs = [maybe_oban_child()]

    # Infrastructure that DOES need DB access - start after Oban
    # NOTE: HealthMonitor now started by Thundergate.Supervisor
    # Cerebros needs Repo for metrics/checkpoints - start after Oban
    infrastructure_late = cerebros_children()

    # Web endpoint - starts last
    web = [ThunderlineWeb.Endpoint]

    # Combine in correct order: core -> database -> tick_system -> domains -> early infra -> jobs -> late infra -> web
    (core ++ database ++ tick_system ++ domains ++ infrastructure_early ++ jobs ++ infrastructure_late ++ web)
    |> Enum.reject(&is_nil/1)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    ThunderlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_repo_child do
    if System.get_env("SKIP_ASH_SETUP") in ["1", "true", "TRUE"] do
      nil
    else
      Thunderline.Repo
    end
  end

  defp maybe_oban_child do
    # Skip Oban if repo is skipped - Oban needs DB access
    if System.get_env("SKIP_ASH_SETUP") in ["1", "true", "TRUE"] do
      nil
    else
      case Application.get_env(:thunderline, Oban) do
        nil -> nil
        false -> nil
        config -> {Oban, config}
      end
    end
  end

  defp maybe_vault_child do
    case Application.get_env(:thunderline, Thunderline.Vault) do
      nil -> nil
      _config -> Thunderline.Vault
    end
  end

  defp cerebros_children do
    if cerebros_enabled?() do
      [
        Thunderline.Thunderbolt.Cerebros.EventPublisher,
        Thunderline.Thunderbolt.Cerebros.Metrics,
        Thunderline.Thunderbolt.CerebrosBridge.Cache,
        Thunderline.Thunderbolt.AutoMLDriver
      ]
    else
      []
    end
  end

  defp cerebros_enabled? do
    Feature.enabled?(:ml_nas, default: false) and
      bridge_enabled?(Application.get_env(:thunderline, :cerebros_bridge, []))
  end

  defp bridge_enabled?(config) do
    case Keyword.get(config, :enabled, false) do
      val when val in [true, "true", "TRUE", 1, "1"] -> true
      _ -> false
    end
  end

  defp saga_children do
    if Feature.enabled?(:reactor_sagas, default: true) do
      [
        Thunderline.Thunderbolt.Sagas.Registry,
        Thunderline.Thunderbolt.Sagas.Supervisor
      ]
    else
      []
    end
  end

  defp rag_children do
    if Feature.enabled?(:rag_enabled, default: true) do
      [Thunderline.Thunderbolt.RAG.Serving]
    else
      []
    end
  end

  defp upm_children do
    if Feature.enabled?(:unified_model, default: false) do
      [Thunderline.Thunderbolt.UPM.Supervisor]
    else
      []
    end
  end

  defp ml_pipeline_children do
    if Feature.enabled?(:ml_pipeline, default: true) do
      [
        # ML Controller for adaptive model selection
        {Thunderline.Thunderbolt.ML.Controller, ml_controller_config()},
        # Model selection consumer (requires Controller to be started first)
        {Thunderline.Thunderbolt.ML.ModelSelectionConsumer, controller_pid: :ml_controller},
        # File classification consumer
        Thunderline.Thunderflow.Consumers.Classifier
      ]
    else
      []
    end
  end

  defp ml_controller_config do
    [
      name: :ml_controller,
      # TODO: Load from config
      models: [:model_a, :model_b],
      distance_metric: :js_divergence,
      window_size: 50,
      sla_params: %{
        learning_rate: 0.01,
        penalty_factor: 0.1
      }
    ]
  end

  defp attach_reward_handler do
    if Feature.enabled?(:reward_signal, default: false) do
      Thunderline.Thunderblock.Telemetry.RewardHandler.init()

      :telemetry.attach(
        "thunderline-reward-handler",
        [:thunderline, :flow, :probe, :reward],
        &Thunderline.Thunderblock.Telemetry.RewardHandler.handle_event/4,
        nil
      )
    end
  end
end
