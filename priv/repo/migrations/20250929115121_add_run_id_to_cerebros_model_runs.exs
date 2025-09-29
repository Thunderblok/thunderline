defmodule Thunderline.Repo.Migrations.AddRunIdToCerebrosModelRuns do
  use Ecto.Migration

  def change do
    alter table(:cerebros_model_runs) do
      add :run_id, :text
      add :bridge_payload, :map, default: %{}
      add :bridge_result, :map, default: %{}
    end

    execute(
      "UPDATE cerebros_model_runs SET run_id = gen_random_uuid()::text WHERE run_id IS NULL"
    )

    execute(
      "UPDATE cerebros_model_runs SET bridge_payload = '{}'::jsonb WHERE bridge_payload IS NULL"
    )

    execute(
      "UPDATE cerebros_model_runs SET bridge_result = '{}'::jsonb WHERE bridge_result IS NULL"
    )

    alter table(:cerebros_model_runs) do
      modify :run_id, :text, null: false
      modify :bridge_payload, :map, default: %{}, null: false
      modify :bridge_result, :map, default: %{}, null: false
    end

    create unique_index(:cerebros_model_runs, [:run_id])
  end
end
