defmodule Thunderline.Repo.Migrations.EnsureCerebrosModelRunBridgeColumns do
  use Ecto.Migration

  @run_id_index "cerebros_model_runs_run_id_index"

  def up do
    execute("ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS run_id text")

    execute(
      "UPDATE cerebros_model_runs SET run_id = gen_random_uuid()::text WHERE run_id IS NULL"
    )

    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN run_id SET NOT NULL")

    execute("ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS bridge_payload jsonb")

    execute(
      "UPDATE cerebros_model_runs SET bridge_payload = '{}'::jsonb WHERE bridge_payload IS NULL"
    )

    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN bridge_payload SET NOT NULL")
    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN bridge_payload SET DEFAULT '{}'::jsonb")

    execute("ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS bridge_result jsonb")

    execute(
      "UPDATE cerebros_model_runs SET bridge_result = '{}'::jsonb WHERE bridge_result IS NULL"
    )

    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN bridge_result SET NOT NULL")
    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN bridge_result SET DEFAULT '{}'::jsonb")

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS #{@run_id_index} ON cerebros_model_runs (run_id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS #{@run_id_index}")
    execute("ALTER TABLE cerebros_model_runs DROP COLUMN IF EXISTS bridge_result")
    execute("ALTER TABLE cerebros_model_runs DROP COLUMN IF EXISTS bridge_payload")
    execute("ALTER TABLE cerebros_model_runs ALTER COLUMN run_id DROP NOT NULL")
    execute("ALTER TABLE cerebros_model_runs DROP COLUMN IF EXISTS run_id")
  end
end
