defmodule Thunderline.Repo.Migrations.DropMarketAndEdgarRawTables do
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS raw_market_ticks CASCADE")
    execute("DROP TABLE IF EXISTS raw_edgar_docs CASCADE")
  end

  def down do
    # No-op: intentionally not recreating legacy tables
    :ok
  end
end
