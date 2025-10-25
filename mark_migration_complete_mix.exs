# Mark migration 20251024185845 as completed
# Run with: mix run mark_migration_complete_mix.exs

alias Thunderline.Repo

query = """
INSERT INTO schema_migrations (version, inserted_at)
VALUES ($1, NOW())
ON CONFLICT (version) DO NOTHING
RETURNING version
"""

case Repo.query(query, [20251024185845]) do
  {:ok, %{rows: [[version]]}} ->
    IO.puts("\n✅ SUCCESS: Migration #{version} marked as completed\n")
  {:ok, %{num_rows: 0}} ->
    IO.puts("\nℹ️  Migration 20251024185845 was already marked as completed\n")
  {:error, error} ->
    IO.puts("\n❌ ERROR: #{inspect(error)}\n")
    System.halt(1)
end
