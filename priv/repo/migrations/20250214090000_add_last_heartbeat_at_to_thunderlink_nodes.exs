defmodule Thunderline.Repo.Migrations.AddLastHeartbeatAtToThunderlinkNodes do
  use Ecto.Migration

  def up do
    alter table(:thunderlink_nodes) do
      add :last_heartbeat_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:thunderlink_nodes) do
      remove :last_heartbeat_at
    end
  end
end
