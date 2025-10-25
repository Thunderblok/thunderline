# Create tokens table manually
# Run with: mix run create_tokens_table.exs

alias Thunderline.Repo

# SQL extracted from migration file line 169
create_tokens_sql = """
CREATE TABLE IF NOT EXISTS tokens (
  jti TEXT NOT NULL PRIMARY KEY,
  subject TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  purpose TEXT NOT NULL,
  extra_data JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
)
"""

IO.puts("\n🔧 Creating tokens table...")

case Repo.query(create_tokens_sql, []) do
  {:ok, _result} ->
    IO.puts("✅ SUCCESS: tokens table created\n")
    
    # Verify table exists by querying its structure
    case Repo.query("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'tokens' ORDER BY ordinal_position", []) do
      {:ok, %{rows: columns}} ->
        IO.puts("📋 Table structure:")
        Enum.each(columns, fn [col_name, data_type] ->
          IO.puts("  - #{col_name} (#{data_type})")
        end)
        IO.puts("")
      {:error, error} ->
        IO.puts("⚠️  Could not verify table structure: #{inspect(error)}\n")
    end
    
  {:error, error} ->
    IO.puts("❌ ERROR: #{inspect(error)}\n")
    System.halt(1)
end
