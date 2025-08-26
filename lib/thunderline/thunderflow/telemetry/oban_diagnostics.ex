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
    repo_up = Process.whereis(Thunderline.Repo) |> alive?()
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
      check_tables()
      if oban_up, do: log_queue_overview(), else: attempt_demo_job_insert()
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

  defp check_tables do
    for table <- ["oban_jobs", "oban_peers"] do
      case Thunderline.Repo.query("SELECT to_regclass($1)", [table]) do
        {:ok, %{rows: [[nil]]}} -> Logger.error("[ObanDiagnostics] MISSING table #{table} – migration not applied")
        {:ok, %{rows: [[present]]}} when not is_nil(present) -> if verbose?(), do: Logger.debug("[ObanDiagnostics] table_present=#{table} regclass=#{inspect(present)}")
        {:error, err} -> Logger.error("[ObanDiagnostics] table_check_error=#{table} error=#{inspect(err)}")
      end
    end
  end

  defp log_queue_overview do
    Application.get_env(:thunderline, Oban, [])
    |> Keyword.get(:queues, [])
    |> Enum.each(fn {queue, _concurrency} ->
      case Thunderline.Repo.query("SELECT count(*) FROM oban_jobs WHERE queue=$1 AND state='available'", [to_string(queue)]) do
        {:ok, %{rows: [[count]]}} -> if verbose?(), do: Logger.debug("[ObanDiagnostics] queue=#{queue} available=#{count}")
        {:error, err} -> Logger.warning("[ObanDiagnostics] queue_stat_error queue=#{queue} error=#{inspect(err)}")
      end
    end)
  end

  defp attempt_demo_job_insert do
    args = %{"probe" => true, "at" => DateTime.utc_now()}
  case Code.ensure_loaded?(Thunderline.Thunderflow.Jobs.DemoJob) do
      true ->
  job = Thunderline.Thunderflow.Jobs.DemoJob.new(args)
        case Oban.insert(job) do
          {:ok, _job} -> Logger.info("[ObanDiagnostics] Inserted demo job (Oban not yet supervising – will run once supervisor alive)")
          {:error, changeset} -> Logger.error("[ObanDiagnostics] Failed to insert demo job: #{inspect(changeset.errors)}")
        end
      false -> if verbose?(), do: Logger.debug("[ObanDiagnostics] DemoJob module not loaded; skipping test insert")
    end
  end

  defp verbose?, do: System.get_env("OBAN_DIAGNOSTICS_VERBOSE") in ["1", "true", "TRUE", "yes", "Y"]
end
