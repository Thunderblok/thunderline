defmodule Thunderline.Repo.Migrations.CreateMarketAndEdgarRawTables do
  use Ecto.Migration

  def change do
    create table(:raw_market_ticks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :symbol, :text, null: false
      # monotonic microsecond timestamp
      add :ts, :bigint, null: false
      add :vendor_seq, :bigint
      add :payload, :map, null: false
    end

    create index(:raw_market_ticks, [:tenant_id, :symbol, :ts])

    create table(:raw_edgar_docs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :cik, :text, null: false
      add :form, :text, null: false
      add :filing_time, :utc_datetime, null: false
      add :period_end, :date
      add :sections, :map, null: false, default: %{}
      add :xbrl, :map, null: false, default: %{}
      add :hash, :binary, null: false
      add :sections_redacted, :boolean, null: false, default: false
      add :xbrl_hash, :binary
    end

    create index(:raw_edgar_docs, [:tenant_id, :cik, :filing_time])

    create unique_index(:raw_edgar_docs, [:cik, :form, :filing_time, :hash],
             name: :raw_edgar_docs_unique_filing
           )
  end
end
