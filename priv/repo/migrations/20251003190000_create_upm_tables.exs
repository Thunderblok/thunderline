defmodule Thunderline.Repo.Migrations.CreateUpmTables do
  use Ecto.Migration

  def change do
    create table(:upm_trainers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :tenant_id, :uuid
      add :mode, :text, null: false, default: "shadow"
      add :status, :text, null: false, default: "idle"
      add :last_window_id, :uuid
      add :last_window_fetched_at, :utc_datetime_usec
      add :last_loss, :float
      add :drift_score, :float, null: false, default: 0.0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:upm_trainers, [:name, :tenant_id])

    create table(:upm_snapshots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :version, :text, null: false
      add :tenant_id, :uuid
      add :mode, :text, null: false, default: "shadow"
      add :status, :text, null: false, default: "created"
      add :checksum, :text
      add :size_bytes, :bigint
      add :storage_path, :text
      add :activated_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :trainer_id, references(:upm_trainers, type: :uuid, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:upm_snapshots, [:trainer_id, :version])
    create index(:upm_snapshots, [:trainer_id])
    create index(:upm_snapshots, [:status])

    create table(:upm_adapters, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :adapter_key, :text, null: false
      add :tenant_id, :uuid
      add :mode, :text, null: false, default: "shadow"
      add :status, :text, null: false, default: "pending"
      add :last_synced_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      add :snapshot_id, references(:upm_snapshots, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:upm_adapters, [:adapter_key, :tenant_id])
    create index(:upm_adapters, [:snapshot_id])
    create index(:upm_adapters, [:status])

    create table(:upm_drift_windows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid
      add :status, :text, null: false, default: "open"
      add :score_p95, :float, null: false, default: 0.0
      add :threshold, :float, null: false, default: 0.2
      add :sample_count, :bigint, null: false, default: 0
      add :window_started_at, :utc_datetime_usec
      add :window_closed_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      add :snapshot_id, references(:upm_snapshots, type: :uuid, on_delete: :delete_all),
        null: false

      add :trainer_id, references(:upm_trainers, type: :uuid, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:upm_drift_windows, [:snapshot_id])
    create index(:upm_drift_windows, [:trainer_id])
    create index(:upm_drift_windows, [:status])
  end
end
