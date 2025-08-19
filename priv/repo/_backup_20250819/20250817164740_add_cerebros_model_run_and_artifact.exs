defmodule Thunderline.Repo.Migrations.AddCerebrosModelRunAndArtifact do
  use Ecto.Migration

  def change do
    create table(:cerebros_model_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :string, null: false
      add :search_space_version, :integer, null: false, default: 1
      add :max_params, :bigint, null: false, default: 2_000_000
      add :requested_trials, :integer, null: false, default: 3
      add :completed_trials, :integer, null: false, default: 0
      add :best_metric, :float
      add :error_message, :text
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create table(:cerebros_model_artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :model_run_id, references(:cerebros_model_runs, type: :uuid, on_delete: :delete_all), null: false
      add :trial_index, :integer, null: false
      add :metric, :float, null: false
      add :params, :bigint, null: false
      add :spec, :map, null: false, default: %{}
      add :path, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:cerebros_model_artifacts, [:model_run_id])
    create index(:cerebros_model_artifacts, [:metric])
    create index(:cerebros_model_runs, [:status])
    create index(:cerebros_model_runs, [:inserted_at])
  end
end
