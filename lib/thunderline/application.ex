defmodule Thunderline.Application do
  @moduledoc """
  OTP application supervisor for the Thunderline platform.

  Responsibilities:
    * Start shared infrastructure (Repo, Vault, PubSub, Presence)
    * Wire telemetry, Oban, and the Phoenix Endpoint
    * Respect runtime feature flags (e.g. SKIP_ASH_SETUP) when starting children
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      [
    ThunderlineWeb.Telemetry,
    maybe_repo_child(),
    maybe_vault_child(),
    {Phoenix.PubSub, name: Thunderline.PubSub},
    {Task.Supervisor, name: Thunderline.TaskSupervisor},
  Thunderline.Thunderbolt.Cerebros.Metrics,
    Thunderline.Thunderbolt.CerebrosBridge.Cache,
    Thunderline.Thunderflow.EventBuffer,
    Thunderline.Thunderflow.Blackboard,
    ThunderlineWeb.Presence,
    maybe_oban_child(),
    ThunderlineWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]
    Supervisor.start_link(children, opts)
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
      config -> {Oban, config}
    end
  end

  defp maybe_vault_child do
    case Application.get_env(:thunderline, Thunderline.Vault) do
      nil -> nil
      _config -> Thunderline.Vault
    end
  end
end
