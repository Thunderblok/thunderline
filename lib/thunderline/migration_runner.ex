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
      Logger.info("[MigrationRunner] Running pending migrations...")
      path = Application.app_dir(:thunderline, "priv/repo/migrations")

      # Ensure Repo is started (it should already be a child before this runner) but guard just in case
      unless Process.whereis(Thunderline.Repo) do
        {:ok, _} = Thunderline.Repo.start_link()
      end

      Ecto.Migrator.with_repo(Thunderline.Repo, fn repo ->
        Ecto.Migrator.run(repo, path, :up, all: true)
      end)

      Logger.info("[MigrationRunner] Migrations complete.")
      :ok
    end
  rescue
    exception ->
      Logger.error("[MigrationRunner] Migration failure: #{Exception.message(exception)}")
      reraise(exception, __STACKTRACE__)
  end
end
