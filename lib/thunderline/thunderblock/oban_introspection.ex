defmodule Thunderline.Thunderblock.ObanIntrospection do
  @moduledoc """
  Thunderblock boundary for Oban / DB introspection queries.

  Provides read-only status helpers so non-Block domains (Flow telemetry) do not
  perform direct Repo queries, preserving RepoOnly doctrine.
  """
  require Logger

  def repo_alive? do
    case Process.whereis(Thunderline.Repo) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  def check_tables(verbose?) do
    for table <- ["oban_jobs", "oban_peers"] do
      case Thunderline.Repo.query("SELECT to_regclass($1)", [table]) do
        {:ok, %{rows: [[nil]]}} ->
          Logger.error("[ObanIntrospection] MISSING table #{table} – migration not applied")

        {:ok, %{rows: [[present]]}} when not is_nil(present) ->
          if verbose?,
            do:
              Logger.debug(
                "[ObanIntrospection] table_present=#{table} regclass=#{inspect(present)}"
              )

        {:error, err} ->
          Logger.error("[ObanIntrospection] table_check_error=#{table} error=#{inspect(err)}")
      end
    end
  end

  def log_queue_overview(verbose?) do
    Application.get_env(:thunderline, Oban, [])
    |> Keyword.get(:queues, [])
    |> Enum.each(fn {queue, _concurrency} ->
      case Thunderline.Repo.query(
             "SELECT count(*) FROM oban_jobs WHERE queue=$1 AND state='available'",
             [to_string(queue)]
           ) do
        {:ok, %{rows: [[count]]}} ->
          if verbose?, do: Logger.debug("[ObanIntrospection] queue=#{queue} available=#{count}")

        {:error, err} ->
          Logger.warning(
            "[ObanIntrospection] queue_stat_error queue=#{queue} error=#{inspect(err)}"
          )
      end
    end)
  end

  def attempt_demo_job_insert(verbose?) do
    args = %{"probe" => true, "at" => DateTime.utc_now()}

    case Code.ensure_loaded?(Thunderline.Thunderflow.Jobs.DemoJob) do
      true ->
        job = Thunderline.Thunderflow.Jobs.DemoJob.new(args)

        case Oban.insert(job) do
          {:ok, _job} ->
            Logger.info(
              "[ObanIntrospection] Inserted demo job (Oban not yet supervising – will run once supervisor alive)"
            )

          {:error, changeset} ->
            Logger.error(
              "[ObanIntrospection] Failed to insert demo job: #{inspect(changeset.errors)}"
            )
        end

      false ->
        if verbose?,
          do: Logger.debug("[ObanIntrospection] DemoJob module not loaded; skipping test insert")
    end
  end
end
