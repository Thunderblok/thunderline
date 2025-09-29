defmodule Thunderline.Repo.Migrations.AddRunIdToCerebrosModelRuns do
  use Ecto.Migration

  def change do
    alter table(:cerebros_model_runs) do
      add :run_id, :text
    end

    execute(
      "UPDATE cerebros_model_runs SET run_id = gen_random_uuid()::text WHERE run_id IS NULL"
    )

    alter table(:cerebros_model_runs) do
      modify :run_id, :text, null: false
    end

    create unique_index(:cerebros_model_runs, [:run_id])
  end
end
