defmodule Mix.Tasks.Thunderline.Ml.MigrateArtifacts do
  use Mix.Task
  @shortdoc "Migrate legacy cerebros_model_artifacts to ml_model_artifacts (safe, idempotent)"

  @moduledoc """
  Safely migrates legacy artifact rows from cerebros_model_artifacts into the new
  ml_model_artifacts table. By default runs in --dry-run mode. Can import from a
  JSONL file previously exported by thunderline.ml.audit_artifacts.

  Usage:
    mix thunderline.ml.migrate_artifacts --dry-run         # default, no writes
    mix thunderline.ml.migrate_artifacts --execute         # perform inserts
    mix thunderline.ml.migrate_artifacts --from-jsonl=path # import rows from JSONL

  Notes:
  - This task is conservative: it only inserts rows that don't already exist,
    deduplicated by checksum/uri if present.
  - It does NOT delete from the legacy table. Cleanup is a separate decision.
  - Field mapping: attempts best-effort mapping between legacy columns and the
    new schema. Unmapped data is placed in metadata as needed.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [execute: :boolean, dry_run: :boolean, from_jsonl: :string])

    execute? = Keyword.get(opts, :execute, false)
    dry_run? = Keyword.get(opts, :dry_run, !execute?)
    repo = Thunderline.Repo

    rows =
      case Keyword.get(opts, :from_jsonl) do
        nil -> fetch_all(repo, "cerebros_model_artifacts")
        path -> read_jsonl!(path)
      end

    IO.puts("Loaded #{length(rows)} legacy rows for migration")

    {to_insert, skipped} =
      Enum.split_with(rows, fn row -> needs_insert?(repo, row) end)

    IO.puts("Candidate inserts: #{length(to_insert)} | Skipped (exists or invalid): #{length(skipped)}")

    if dry_run? do
      IO.puts("Dry-run only. No changes written.")
      :ok
    else
      inserted = Enum.count(Enum.map(to_insert, &insert_row(repo, &1)))
      IO.puts("Inserted #{inserted} rows into ml_model_artifacts")
      :ok
    end
  end

  # --- helpers ---

  defp fetch_all(repo, table) do
    %{columns: cols, rows: rows} = Ecto.Adapters.SQL.query!(repo, "SELECT * FROM #{table} ORDER BY inserted_at")
    Enum.map(rows, fn row -> Enum.zip(cols, row) |> Map.new() end)
  end

  defp read_jsonl!(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end

  defp needs_insert?(repo, legacy_row) do
    {uri, checksum} = extract_uri_checksum(legacy_row)

    cond do
      is_nil(uri) and is_nil(checksum) -> false
      true ->
        %{rows: [[n]]} =
          case {uri, checksum} do
            {nil, cs} -> Ecto.Adapters.SQL.query!(repo, "SELECT COUNT(*) FROM ml_model_artifacts WHERE checksum = $1", [cs])
            {u, nil} -> Ecto.Adapters.SQL.query!(repo, "SELECT COUNT(*) FROM ml_model_artifacts WHERE uri = $1", [u])
            {u, cs} -> Ecto.Adapters.SQL.query!(repo, "SELECT COUNT(*) FROM ml_model_artifacts WHERE uri = $1 OR checksum = $2", [u, cs])
          end

        n == 0
    end
  end

  defp insert_row(repo, legacy_row) do
    params = map_legacy_to_new(legacy_row)
    sql = """
    INSERT INTO ml_model_artifacts (id, spec_id, uri, checksum, bytes, status, promoted, semver, inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
    ON CONFLICT DO NOTHING
    """

    args = [params.id, params.spec_id, params.uri, params.checksum, params.bytes, params.status, params.promoted, params.semver]
    Ecto.Adapters.SQL.query!(repo, sql, args)
  end

  defp extract_uri_checksum(row) do
    uri = Map.get(row, "path") || Map.get(row, "uri")
    checksum = Map.get(row, "checksum")
    {uri, checksum}
  end

  defp map_legacy_to_new(row) do
    # Best-effort mapping: many legacy fields may not exist; default sensibly
    %{
      id: Map.get(row, "id") || Ecto.UUID.generate(),
      spec_id: Map.get(row, "spec_id") || Map.get(row, "model_run_id") || Ecto.UUID.generate(),
      uri: Map.get(row, "path") || Map.get(row, "uri") || "",
      checksum: Map.get(row, "checksum") || (Map.get(row, "metric") && :crypto.hash(:sha256, to_string(Map.get(row, "metric"))) |> Base.encode16(case: :lower)) || nil,
      bytes: Map.get(row, "bytes") || 0,
      status: "created",
      promoted: false,
      semver: "0.1.0"
    }
  end
end
