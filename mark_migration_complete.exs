#!/usr/bin/env elixir

# Mark migration 20251024185845 as completed
# This migration tried to create tables that already exist

# Start the app
Mix.install([])
Application.ensure_all_started(:postgrex)

{:ok, pid} = Postgrex.start_link(
  hostname: "localhost",
  username: "postgres",
  password: "postgres",
  database: "thunderline_dev"
)

# Insert the migration record
query = """
INSERT INTO schema_migrations (version, inserted_at)
VALUES (20251024185845, NOW())
ON CONFLICT (version) DO NOTHING
RETURNING version
"""

case Postgrex.query(pid, query, []) do
  {:ok, %{rows: [[version]]}} ->
    IO.puts("✅ Migration #{version} marked as completed")
  {:ok, %{num_rows: 0}} ->
    IO.puts("ℹ️  Migration 20251024185845 was already marked as completed")
  {:error, error} ->
    IO.puts("❌ Error: #{inspect(error)}")
    System.halt(1)
end

GenServer.stop(pid)
