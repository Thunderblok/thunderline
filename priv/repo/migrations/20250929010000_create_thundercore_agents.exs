defmodule Thunderline.Repo.Migrations.CreateThundercoreAgents do
  use Ecto.Migration

  def change do
    create table(:thundercore_agents, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :agent_name, :text, null: false
      add :agent_type, :text, null: false
      add :status, :text, null: false, default: "starting"
      add :capabilities, :map, null: false, default: %{}
      add :current_task, :text
      add :last_heartbeat, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:thundercore_agents, [:agent_name], name: :thundercore_agents_unique_agent_name_index)
  end
end
