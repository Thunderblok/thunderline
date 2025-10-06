defmodule Thunderline.Repo.Migrations.AddSpectralNormToModelTrials do
  @moduledoc """
  Phase 1: Create ModelTrial table and add spectral normalization tracking fields.

  Creates cerebros_model_trials table with:
  - Core trial fields (trial_id, status, metrics, parameters, etc.)
  - spectral_norm (boolean): Flag indicating if spectral norm constraint was applied
  - mlflow_run_id (string): Cross-reference to MLflow experiment tracking
  """

  use Ecto.Migration

  def up do
    create_if_not_exists table(:cerebros_model_trials, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :trial_id, :text, null: false
      add :status, :text, null: false, default: "succeeded"
      add :metrics, :map, default: %{}
      add :parameters, :map, default: %{}
      add :spectral_norm, :boolean, null: false, default: false
      add :mlflow_run_id, :text
      add :artifact_uri, :text
      add :duration_ms, :bigint
      add :rank, :bigint
      add :warnings, {:array, :text}, default: []
      add :candidate_id, :text
      add :pulse_id, :text
      add :bridge_payload, :map, default: %{}

      add :model_run_id, references(:cerebros_model_runs, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:cerebros_model_trials, [:model_run_id])
    create_if_not_exists index(:cerebros_model_trials, [:trial_id])
    create_if_not_exists index(:cerebros_model_trials, [:status])
    create_if_not_exists index(:cerebros_model_trials, [:spectral_norm])
    create_if_not_exists index(:cerebros_model_trials, [:mlflow_run_id])
  end

  def down do
    drop_if_exists index(:cerebros_model_trials, [:mlflow_run_id])
    drop_if_exists index(:cerebros_model_trials, [:spectral_norm])
    drop_if_exists index(:cerebros_model_trials, [:status])
    drop_if_exists index(:cerebros_model_trials, [:trial_id])
    drop_if_exists index(:cerebros_model_trials, [:model_run_id])

    drop_if_exists table(:cerebros_model_trials)
  end
end
