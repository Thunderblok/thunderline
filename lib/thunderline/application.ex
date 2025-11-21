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

    children =
      ([
         ThunderlineWeb.Telemetry,
         maybe_repo_child(),
         maybe_vault_child(),
         {Phoenix.PubSub, name: Thunderline.PubSub},
         {Task.Supervisor, name: Thunderline.TaskSupervisor}
       ] ++
         cerebros_children() ++
         saga_children() ++
         rag_children() ++
         upm_children() ++
         ml_pipeline_children() ++
         [
           Thunderline.Thunderflow.EventBuffer,
           Thunderline.Thunderflow.Blackboard,
           Thunderline.Thunderlink.Registry,
           Thunderline.ServiceRegistry.HealthMonitor,
           Thundervine.Supervisor,
           ThunderlineWeb.Presence,
           maybe_oban_child(),
           ThunderlineWeb.Endpoint
         ])
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # When Oban is in testing: :manual mode, we need to explicitly start queues
      # This happens after the supervisor tree is up, avoiding the race condition
      # where Oban tries to query Repo before it's fully initialized
      maybe_start_oban_queues()
      {:ok, pid}
    end
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
    case Application.get_env(:thunderline, Oban) do
      nil -> nil
      false -> nil
      config -> {Oban, config}
    end
  end

  defp maybe_start_oban_queues do
    # Only start queues if Oban is configured and in manual testing mode
    case Application.get_env(:thunderline, Oban) do
      config when is_list(config) ->
        case Keyword.get(config, :testing) do
          :manual ->
            # Give Repo a moment to fully initialize ETS tables
            Process.sleep(100)
            # Start Oban's queue system manually
            Oban.start_queue(queue: :default)
            Oban.start_queue(queue: :ml)
            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
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
