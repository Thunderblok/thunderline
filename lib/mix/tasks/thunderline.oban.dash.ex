defmodule Mix.Tasks.Thunderline.Oban.Dash do
  @shortdoc "Display recent Oban job telemetry and aggregated stats"
  @moduledoc """
  Live snapshot of in-memory Oban job telemetry captured by `Thunderline.Thunderflow.Telemetry.Oban`.

  Shows recent events and aggregates without hitting the database, useful when
  validating AshOban integration or diagnosing queue behavior early in boot.

  Usage:
      mix thunderline.oban.dash            # default 25 events
      mix thunderline.oban.dash --limit 50 # specify number of events
  """
  use Mix.Task

  @switches [limit: :integer]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _argv, _} = OptionParser.parse(args, switches: @switches)
    limit = opts[:limit] || 25

    ensure_attached()
    events = Thunderline.Thunderflow.Telemetry.Oban.recent(limit)
    stats = Thunderline.Thunderflow.Telemetry.Oban.stats()

    IO.puts("\n== Oban Telemetry (last #{limit}) ==")

    Enum.each(events, fn e ->
      IO.puts(format_event(e))
    end)

    IO.puts("\n== Aggregates ==")
    IO.puts("Total events: #{stats.total}")
    IO.puts("By type: #{inspect(stats.by_type)}")
    IO.puts("Queues:  #{inspect(Map.get(stats, :queues, %{}))}")
    IO.puts("Workers: #{inspect(Map.get(stats, :workers, %{}))}")
  end

  defp ensure_attached do
    # Safe to call multiple times
    Thunderline.Thunderflow.Telemetry.Oban.attach()
  catch
    _, _ -> :ok
  end

  defp format_event(%{type: type, queue: q, worker: w, state: s, at: ts}) do
    dt = DateTime.from_unix!(div(ts, 1_000_000), :second) |> DateTime.to_iso8601()
    "#{dt} #{type}|#{s} queue=#{q} worker=#{short_worker(w)}"
  end

  defp format_event(other), do: inspect(other)

  defp short_worker(worker) when is_binary(worker) do
    worker |> String.split(".") |> Enum.take(-2) |> Enum.join(".")
  end

  defp short_worker(worker), do: inspect(worker)
end
