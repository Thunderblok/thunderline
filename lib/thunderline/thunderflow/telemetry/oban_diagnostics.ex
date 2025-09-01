defmodule Thunderline.Thunderflow.Telemetry.ObanDiagnostics do
  @moduledoc """
  Canonical Oban diagnostics & boot probe (migrated from Thunderchief.ObanDiagnostics).

  Periodically logs repository availability, Oban supervisor status, table presence,
  and (optionally) inserts a demo job to validate writes.
  """
  use GenServer
  require Logger

  @interval 15_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if diagnostics_enabled?() do
      Logger.notice("[ObanDiagnostics] Enabled – collecting Oban boot diagnostics...")
      send(self(), :boot_diagnostics)
      schedule()
      {:ok, %{last_pid: nil, attempts: 0}}
    else
      Logger.debug("[ObanDiagnostics] Disabled (set OBAN_DIAGNOSTICS=1 to enable)")
      :ignore
    end
  end

  @impl true
  def handle_info(:boot_diagnostics, state) do
    run_diagnostics(:boot)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    run_diagnostics(:periodic)
    schedule()
    {:noreply, state}
  end

  # -- internals ---------------------------------------------------------------
  defp diagnostics_enabled? do
    System.get_env("OBAN_DIAGNOSTICS") in [nil, "", "1", "true", "TRUE", "yes"]
  end
  defp schedule, do: Process.send_after(self(), :tick, @interval)

  defp run_diagnostics(stage) do
  repo_up = Thunderline.Thunderblock.ObanIntrospection.repo_alive?()
    oban_name = oban_instance_name()
    oban_pid = Oban.whereis(oban_name)
    oban_up = alive?(oban_pid)

    log_level =
      cond do
        oban_up -> if verbose?(), do: :info, else: :debug
        true -> :warning
      end

    Logger.log(log_level,
      "[ObanDiagnostics] stage=#{stage} repo_up=#{repo_up} oban_up=#{oban_up} name=#{inspect(oban_name)}"
    )

    with true <- repo_up do
  Thunderline.Thunderblock.ObanIntrospection.check_tables(verbose?())
  if oban_up, do: Thunderline.Thunderblock.ObanIntrospection.log_queue_overview(verbose?()), else: Thunderline.Thunderblock.ObanIntrospection.attempt_demo_job_insert(verbose?())
    else
      _ -> Logger.warning("[ObanDiagnostics] Repo not up yet; skipping table & job checks")
    end
  rescue
    error -> Logger.error("[ObanDiagnostics] diagnostics error: #{Exception.message(error)}")
  end

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(_), do: false

  defp oban_instance_name do
    Application.get_env(:thunderline, Oban, []) |> Keyword.get(:name, Oban)
  end

  defp verbose?, do: System.get_env("OBAN_DIAGNOSTICS_VERBOSE") in ["1", "true", "TRUE", "yes", "Y"]
end
