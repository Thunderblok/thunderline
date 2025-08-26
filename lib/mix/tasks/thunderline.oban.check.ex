defmodule Mix.Tasks.Thunderline.Oban.Check do
  @shortdoc "Deep diagnostic of Oban + AshOban trigger state"
  @moduledoc """
  Provides a point‑in‑time diagnostic readout of:

  * Repo status & migration status for Oban tables
  * Presence of required Oban tables
  * Loaded Oban queues & plugins
  * Ash domains registered & whether AshOban configured them
  * Pending AshOban trigger-derived jobs (next 25 scheduled)
  * A quick sample enqueue of a DemoJob (optional --sample)

  Usage:

      mix thunderline.oban.check
      mix thunderline.oban.check --sample

  """
  use Mix.Task
  require Logger

  @switches [sample: :boolean]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    repo = Thunderline.Repo

    IO.puts("\n== ⚙️  Repo / DB Status ==")
    repo_started? = Process.whereis(repo) != nil
    IO.puts("Repo started?: #{repo_started?}")

    check_table(repo, "oban_jobs")
    check_table(repo, "oban_peers")

    IO.puts("\n== 🧬 Ash Domains / AshOban ==")
    domains = Application.get_env(:thunderline, :ash_domains, [])
    Enum.each(domains, fn d ->
      has? = function_exported?(d, :__ash_oban_info__, 0)
      IO.puts("#{inspect(d)} ash_oban_extension?: #{has?}")
    end)

    IO.puts("\n== 📦 Oban Instance ==")
  case Oban.whereis(Oban) do
      nil -> IO.puts("Oban root supervisor NOT running (nil from Oban.whereis/0)")
      pid -> IO.puts("Oban root supervisor PID: #{inspect(pid)}")
    end

    IO.puts("\n== 🎛️ Queues ==")
    for {queue, conf} <- Oban.config().queues do
      IO.puts(" - #{queue}: #{conf[:limit] || conf}")
    end

    IO.puts("\n== ⏱️ Plugins ==")
    for plugin <- Oban.config().plugins do
      IO.puts(" - #{inspect(plugin)}")
    end

    IO.puts("\n== 🗓️  Upcoming Scheduled Jobs (next 25 by scheduled_at) ==")
    upcoming(repo)

    if opts[:sample] do
      IO.puts("\n== 🧪 Enqueue Sample DemoJob ==")
  {:ok, job} = Oban.insert(Thunderline.Thunderflow.Jobs.DemoJob.new(%{"source" => "mix_check"}))
      IO.puts("Inserted job id=#{job.id} state=#{job.state}")
    end

    IO.puts("\nDone.\n")
  end

  defp check_table(repo, table) do
    case repo.query("select to_regclass($1)", [table]) do
      {:ok, %{rows: [[nil]]}} -> IO.puts("Missing table: #{table}")
      {:ok, %{rows: [[_]]}} -> IO.puts("Found table: #{table}")
      {:error, err} -> IO.puts("Error checking table #{table}: #{inspect(err)}")
    end
  end

  defp upcoming(repo) do
    # Only select minimal columns
    case repo.query("""
      select id, queue, state, scheduled_at, attempt, worker
      from oban_jobs
      where state in ('scheduled','available')
      order by scheduled_at asc
      limit 25
    """) do
      {:ok, %{rows: rows}} when rows == [] -> IO.puts("(none)")
      {:ok, %{rows: rows}} ->
        Enum.each(rows, fn [id, queue, state, sch_at, attempt, worker] ->
          IO.puts("id=#{id} queue=#{queue} state=#{state} at=#{format_ts(sch_at)} attempt=#{attempt} worker=#{worker}")
        end)
      {:error, err} -> IO.puts("Failed to query oban_jobs: #{inspect(err)}")
    end
  end

  defp format_ts(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_ts(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_ts(other), do: inspect(other)
end
