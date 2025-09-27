defmodule Thunderline.Thunderblock.MigrationRunner do
  @moduledoc """
  (Relocated) Synchronous startup migration runner.

  Moved under Thunderblock to comply with RepoOnly doctrine (only Block touches Repo).
  """
  require Logger

  def child_spec(arg),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      type: :worker,
      restart: :transient,
      shutdown: 30_000
    }

  def start_link(_arg) do
    run()
    :ignore
  end

  def run do
    if System.get_env("DISABLE_BOOT_MIGRATIONS") in ["1", "true"] do
      Logger.warning(
        "[MigrationRunner] Boot migrations disabled via DISABLE_BOOT_MIGRATIONS — skipping."
      )

      :ok
    else
      path = Application.app_dir(:thunderline, "priv/repo/migrations")
      attempts = System.get_env("MIGRATION_MAX_ATTEMPTS", "5") |> String.to_integer()
      base_backoff = System.get_env("MIGRATION_BACKOFF_MS", "1500") |> String.to_integer()
      Logger.info("[MigrationRunner] Running pending migrations (max_attempts=#{attempts}) ...")
      ensure_database_exists()
      run_migrations(path, attempts, base_backoff, 1)
    end
  rescue
    exception ->
      Logger.error("[MigrationRunner] Migration failure: #{Exception.message(exception)}")
      reraise(exception, __STACKTRACE__)
  end

  defp run_migrations(_path, 0, _base_backoff, attempt),
    do: raise("[MigrationRunner] Exhausted migration attempts at attempt #{attempt}")

  defp run_migrations(path, remaining, base_backoff, attempt) do
    ensure_repo_started(5)

    try do
      Ecto.Migrator.with_repo(Thunderline.Repo, fn repo ->
        Ecto.Migrator.run(repo, path, :up, all: true)
      end)

      Logger.info("[MigrationRunner] Migrations complete (attempt #{attempt}).")
      :ok
    rescue
      error in [DBConnection.ConnectionError, Postgrex.Error] ->
        msg = Exception.message(error)

        if String.contains?(msg, "duplicate") or String.contains?(msg, "already exists") do
          Logger.warning("[MigrationRunner] Treating duplicate/exists error as success: #{msg}")
          :ok
        else
          if remaining - 1 > 0 do
            backoff =
              min(round(base_backoff * :math.pow(2, attempt - 1)), 10_000) + :rand.uniform(250)

            Logger.warning(
              "[MigrationRunner] Migration attempt #{attempt} failed (#{inspect(error.__struct__)}). Retrying in #{backoff}ms (#{remaining - 1} attempts left)..."
            )

            Process.sleep(backoff)
            run_migrations(path, remaining - 1, base_backoff, attempt + 1)
          else
            Logger.error(
              "[MigrationRunner] Final migration attempt failed: #{Exception.message(error)}"
            )

            reraise(error, __STACKTRACE__)
          end
        end

      other ->
        reraise(other, __STACKTRACE__)
    end
  end

  defp ensure_repo_started(0), do: raise("[MigrationRunner] Repo failed to start after retries")

  defp ensure_repo_started(attempts) do
    case Process.whereis(Thunderline.Repo) do
      nil ->
        case Thunderline.Repo.start_link() do
          {:ok, _} ->
            :ok

          {:error, {:already_started, _}} ->
            :ok

          {:error, reason} ->
            delay = (:math.pow(2, 6 - attempts) * 100) |> trunc()

            Logger.warning(
              "[MigrationRunner] Repo start attempt failed (#{inspect(reason)}); retrying in #{delay}ms (#{attempts - 1} attempts left)"
            )

            Process.sleep(delay)
            ensure_repo_started(attempts - 1)
        end

      _pid ->
        :ok
    end
  end

  defp ensure_database_exists do
    repo_cfg = Application.get_env(:thunderline, Thunderline.Repo, [])
    %{db: db, host: host, port: port, user: user, pass: pass} = parse_repo_conn_info(repo_cfg)

    if db do
      opts = [
        hostname: host,
        port: port,
        username: user,
        password: pass,
        database: "postgres",
        backoff_type: :stop,
        pool_size: 1
      ]

      case Postgrex.start_link(opts) do
        {:ok, conn} ->
          exists? =
            case Postgrex.query(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [db]) do
              {:ok, %{num_rows: n}} when n > 0 -> true
              _ -> false
            end

          unless exists? do
            case Postgrex.query(conn, "CREATE DATABASE \"#{db}\"", []) do
              {:ok, _} ->
                Logger.info("[MigrationRunner] Created missing database #{db}.")

              {:error, err} ->
                Logger.error(
                  "[MigrationRunner] Failed to create database #{db}: #{Exception.message(err)}"
                )
            end
          end

          :ok = GenServer.stop(conn)

        {:error, reason} ->
          Logger.warning(
            "[MigrationRunner] Could not connect to maintenance DB to auto-create #{db}: #{inspect(reason)}"
          )
      end
    end
  catch
    kind, reason ->
      Logger.warning(
        "[MigrationRunner] ensure_database_exists crashed: #{inspect({kind, reason})}"
      )
  end

  defp parse_repo_conn_info(repo_cfg) do
    url = Keyword.get(repo_cfg, :url) || System.get_env("DATABASE_URL")

    if is_binary(url) do
      uri = URI.parse(url)

      {user, pass} =
        case uri.userinfo do
          nil ->
            {Keyword.get(repo_cfg, :username, System.get_env("PGUSER", "postgres")),
             Keyword.get(repo_cfg, :password, System.get_env("PGPASSWORD", "postgres"))}

          ui ->
            case String.split(ui, ":", parts: 2) do
              [u, p] ->
                {u, p}

              [u] ->
                {u, Keyword.get(repo_cfg, :password, System.get_env("PGPASSWORD", "postgres"))}

              _ ->
                {nil, nil}
            end
        end

      db =
        (uri.path || "/")
        |> String.trim_leading("/")
        |> case do
          "" -> Keyword.get(repo_cfg, :database)
          other -> other
        end

      %{
        db: db,
        host: uri.host || Keyword.get(repo_cfg, :hostname, "127.0.0.1"),
        port: uri.port || Keyword.get(repo_cfg, :port, 5432),
        user: user || Keyword.get(repo_cfg, :username, System.get_env("PGUSER", "postgres")),
        pass: pass || Keyword.get(repo_cfg, :password, System.get_env("PGPASSWORD", "postgres"))
      }
    else
      %{
        db: Keyword.get(repo_cfg, :database),
        host: Keyword.get(repo_cfg, :hostname, "127.0.0.1"),
        port: Keyword.get(repo_cfg, :port, 5432),
        user: Keyword.get(repo_cfg, :username, System.get_env("PGUSER", "postgres")),
        pass: Keyword.get(repo_cfg, :password, System.get_env("PGPASSWORD", "postgres"))
      }
    end
  end
end
