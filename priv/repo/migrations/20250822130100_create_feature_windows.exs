defmodule Thunderline.Repo.Migrations.CreateFeatureWindows do
  use Ecto.Migration

  def change do
    create table(:feature_windows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :kind, :string, null: false # market | edgar
      add :key, :text, null: false # symbol or cik
      add :window_start, :utc_datetime, null: false
      add :window_end, :utc_datetime, null: false
      add :status, :string, null: false, default: "open"
      add :features, :map, null: false, default: %{}
      add :label_spec, :map, null: false, default: %{}
      add :labels, :map
      add :feature_schema_version, :integer, null: false
      add :provenance, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:feature_windows, [:tenant_id, :kind, :key, :window_start])
    create index(:feature_windows, [:tenant_id, :feature_schema_version, :inserted_at])
  end
end
