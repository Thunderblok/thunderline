defmodule Thunderline.Repo.Migrations.AddCerebrosModelTracking do
  use Ecto.Migration

  def change do
    alter table(:cerebros_training_jobs) do
      add :model_id, :text
      add :hyperparameters, :jsonb
      add :fine_tuned_model, :text
      add :model_loaded_at, :timestamptz
    end
  end
end
