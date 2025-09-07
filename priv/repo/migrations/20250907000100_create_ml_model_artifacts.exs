defmodule Thunderline.Repo.Migrations.CreateMlModelArtifacts do
  use Ecto.Migration

  def change do
    create table(:ml_model_artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :spec_id, :uuid, null: false
      add :model_run_id, references(:cerebros_model_runs, type: :uuid, on_delete: :nilify_all)
      add :uri, :text, null: false
      add :checksum, :string, null: false
      add :bytes, :bigint, null: false
      add :status, :string, null: false, default: "created"
      add :promoted, :boolean, null: false, default: false
      add :semver, :string, null: false, default: "0.1.0"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ml_model_artifacts, [:spec_id])
    create index(:ml_model_artifacts, [:model_run_id])
    create index(:ml_model_artifacts, [:checksum])
    create index(:ml_model_artifacts, [:uri])
  end
end
