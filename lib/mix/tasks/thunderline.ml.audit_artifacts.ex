defmodule Mix.Tasks.Thunderline.Ml.AuditArtifacts do
  use Mix.Task
  @shortdoc "Audit ML artifact tables and export legacy rows (read-only)"

  @moduledoc """
  Audits legacy and current ML artifact tables and optionally exports legacy rows
  to JSONL for review.

  Options:
    --export=PATH   Export legacy rows to PATH (JSONL). Read-only; no deletes.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [export: :string])
    repo = Thunderline.Repo

    legacy = count(repo, "cerebros_model_artifacts")
    current = count(repo, "ml_model_artifacts")

    IO.puts("Legacy cerebros_model_artifacts: #{legacy}")
    IO.puts("Current ml_model_artifacts:     #{current}")

    if path = Keyword.get(opts, :export) do
      rows = fetch_all(repo, "cerebros_model_artifacts")
      {:ok, dev} = File.open(path, [:write])

      Enum.each(rows, fn row ->
        IO.write(dev, Jason.encode!(row))
        IO.write(dev, "\n")
      end)

      File.close(dev)
      IO.puts("Exported #{length(rows)} legacy rows to #{path}")
    end
  end

  defp count(repo, table) do
    %{rows: [[n]]} = Ecto.Adapters.SQL.query!(repo, "SELECT COUNT(*) FROM #{table}")
    n
  end

  defp fetch_all(repo, table) do
    %{columns: cols, rows: rows} =
      Ecto.Adapters.SQL.query!(repo, "SELECT * FROM #{table} ORDER BY inserted_at")

    Enum.map(rows, fn row -> Enum.zip(cols, row) |> Map.new() end)
  end
end
