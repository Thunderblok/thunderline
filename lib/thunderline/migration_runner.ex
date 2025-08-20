defmodule Thunderline.MigrationRunner do
  @moduledoc """
  Synchronous startup migration runner placed before Oban so that
  `oban_jobs` and any Ash resource tables exist before Oban queues boot.

  Returns :ignore so it is a one-shot step and not supervised after completion.
  """
  require Logger

  # Provide an explicit child_spec so Supervisor can accept this module directly
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      type: :worker,
      restart: :transient,
      shutdown: 30_000
    }
  end

  def start_link(_arg) do
    # Run synchronously; return :ignore so it's not supervised further.
    run()
    :ignore
  end

  def run do
    if System.get_env("DISABLE_BOOT_MIGRATIONS") in ["1", "true"] do
      Logger.warning("[MigrationRunner] Boot migrations disabled via DISABLE_BOOT_MIGRATIONS — skipping.")
      :ok
    else
      path = Application.app_dir(:thunderline, "priv/repo/migrations")
      attempts = System.get_env("MIGRATION_MAX_ATTEMPTS", "5") |> String.to_integer()
      base_backoff = System.get_env("MIGRATION_BACKOFF_MS", "1500") |> String.to_integer()
      Logger.info("[MigrationRunner] Running pending migrations (max_attempts=#{attempts}) ...")
      run_migrations(path, attempts, base_backoff, 1)
    end
  rescue
    exception ->
      Logger.error("[MigrationRunner] Migration failure: #{Exception.message(exception)}")
      reraise(exception, __STACKTRACE__)
  end

  defp run_migrations(_path, 0, _base_backoff, attempt) do
    raise "[MigrationRunner] Exhausted migration attempts at attempt #{attempt}"
  end

  defp run_migrations(path, remaining, base_backoff, attempt) do
    # Ensure Repo is started (it should already be a child before this runner) but guard just in case
    ensure_repo_started(5)

    try do
      Ecto.Migrator.with_repo(Thunderline.Repo, fn repo ->
        Ecto.Migrator.run(repo, path, :up, all: true)
      end)
      Logger.info("[MigrationRunner] Migrations complete (attempt #{attempt}).")
      :ok
    rescue
      error in [DBConnection.ConnectionError, Postgrex.Error] ->
        # If this is a duplicate column / already applied artifact, treat as success (idempotent safety)
        msg = Exception.message(error)
        if String.contains?(msg, "duplicate") or String.contains?(msg, "already exists") do
          Logger.warning("[MigrationRunner] Treating duplicate/exists error as success: #{msg}")
          :ok
        else
        if remaining - 1 > 0 do
          backoff = min(round(base_backoff * :math.pow(2, attempt - 1)), 10_000) + :rand.uniform(250)
          Logger.warning("[MigrationRunner] Migration attempt #{attempt} failed (#{inspect(error.__struct__)}). Retrying in #{backoff}ms (#{remaining - 1} attempts left)...")
          Process.sleep(backoff)
          run_migrations(path, remaining - 1, base_backoff, attempt + 1)
        else
          Logger.error("[MigrationRunner] Final migration attempt failed: #{Exception.message(error)}")
          reraise(error, __STACKTRACE__)
        end
        end
      other ->
        # Non-connection error: re-raise immediately
        reraise(other, __STACKTRACE__)
    end
  end
  # Retry helper for starting Repo with exponential backoff (attempts left)
  defp ensure_repo_started(0), do: raise "[MigrationRunner] Repo failed to start after retries"
  defp ensure_repo_started(attempts) do
    case Process.whereis(Thunderline.Repo) do
      nil ->
        case Thunderline.Repo.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} ->
            delay = (:math.pow(2, 6 - attempts) * 100) |> trunc()
            Logger.warning("[MigrationRunner] Repo start attempt failed (#{inspect(reason)}); retrying in #{delay}ms (#{attempts-1} attempts left)")
            Process.sleep(delay)
            ensure_repo_started(attempts - 1)
        end
      _pid -> :ok
    end
  end
end
