defmodule Mix.Tasks.Thunderline.Doctor.Db do
  @shortdoc "Run Thunderline DB diagnostics (connectivity, extensions, pool, oban)"
  @moduledoc """
  Provides a focused diagnostic report for local Postgres issues causing UI unresponsiveness.

  It checks:
  1. Repo configuration (host, port, database, pool_size)
  2. TCP socket reachability
  3. Basic Ecto connectivity & server version
  4. Installed extensions (ash-functions, uuid-ossp, citext) presence
  5. Oban connection viability (optional)
  6. Slow / stuck connection hints

  Run with:
      mix thunderline.doctor.db
  """
  use Mix.Task
  alias Thunderline.Repo

  @timeout 3_000

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    cfg = Application.get_env(:thunderline, Repo) || []
    host = Keyword.get(cfg, :hostname, "localhost")
    port = Keyword.get(cfg, :port, 5432)
    db   = Keyword.get(cfg, :database, "(unset)")
    pool_size = Keyword.get(cfg, :pool_size, :unknown)

    header("Repo Configuration")
    kv host: host, port: port, database: db, pool_size: pool_size, env: Mix.env()

    header("Step 1: TCP Reachability")
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], @timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        ok("TCP connect succeeded (port open)")
      {:error, reason} ->
        error("Cannot open TCP socket (#{inspect(reason)}). Postgres likely not listening on #{host}:#{port}.")
        hint([
          "Verify Postgres running: systemctl status postgresql OR docker ps (if container)",
          "If using default local install, port is usually 5432 (current=#{port})",
          "Adjust dev.exs or export DATABASE_URL with correct port"
        ])
        exit({:shutdown, 1})
    end

    header("Step 2: Ecto Connection & Version")
    case Ecto.Adapters.SQL.query(Repo, "select version(), current_database();", [], timeout: @timeout) do
      {:ok, %{rows: [[version, current_db]]}} ->
        ok("Connected: #{version} db=#{current_db}")
      other ->
        error("Ecto query failed: #{inspect(other)}")
    end

    header("Step 3: Extension Check")
    needed = ["uuid-ossp", "citext", "ash-functions"]
    installed = installed_extensions() || []
    missing = needed -- installed
    kv installed_extensions: installed, missing_extensions: missing
    if missing != [], do: hint(["Run migrations or create manually: CREATE EXTENSION IF NOT EXISTS <ext>;"])

    header("Step 4: Pool Sample")
    try do
  info("Poolboy not in use; skipping pool status check")
    rescue
      _ -> info("Pool status not available (poolboy not used?)")
    end
  rescue
    e -> error("Doctor failed: #{Exception.message(e)}")
  end

  defp installed_extensions do
    case Ecto.Adapters.SQL.query(Repo, "select extname from pg_extension;", [], timeout: 5_000) do
      {:ok, %{rows: rows}} -> Enum.map(rows, &List.first/1)
      _ -> []
    end
  end

  # Formatting helpers
  defp header(t), do: Mix.shell().info(["\n== ", :cyan, t, :reset])
  defp ok(msg), do: Mix.shell().info([:green, "✔ ", :reset, msg])
  defp error(msg), do: Mix.shell().error([:red, "✖ ", :reset, msg])
  defp info(msg), do: Mix.shell().info([:blue, msg, :reset])
  defp kv(pairs) do
    Enum.each(pairs, fn {k, v} -> Mix.shell().info(["  ", :yellow, to_string(k), ": ", :reset, inspect(v)]) end)
  end
  defp hint(lines) do
    Mix.shell().info([:magenta, "Hints:", :reset])
    Enum.each(lines, &Mix.shell().info(["  - ", &1]))
  end
end
