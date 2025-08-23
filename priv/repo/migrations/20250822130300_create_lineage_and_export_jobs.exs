defmodule Thunderline.Repo.Migrations.CreateLineageAndExportJobs do
  use Ecto.Migration

  def change do
    create table(:lineage_edges, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :from_id, :uuid, null: false
      add :to_id, :uuid, null: false
      add :edge_type, :text, null: false
      add :day_bucket, :date, null: false, default: fragment("CURRENT_DATE")
      timestamps(type: :utc_datetime)
    end
    create index(:lineage_edges, [:from_id])
    create index(:lineage_edges, [:to_id])
    create index(:lineage_edges, [:day_bucket])

    create table(:export_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :slice_spec, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :artifact_uri, :text
      add :error, :text
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end
    create index(:export_jobs, [:tenant_id, :status])
  end
end
