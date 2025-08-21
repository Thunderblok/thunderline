defmodule Thunderline.Repo.Migrations.CreateObanTables do
  use Ecto.Migration

  @disable_ddl_transaction true

  # Use Oban's recommended canonical schema (kept minimal here). Avoid redefining :id primary key manually.
  def up do
    create table(:oban_jobs) do
      add :state, :text, null: false
      add :queue, :text, null: false
      add :worker, :text, null: false
      add :args, :map, null: false, default: %{}
      add :errors, {:array, :map}, null: false, default: []
      add :attempt, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 20
      add :priority, :integer, null: false, default: 0
      add :attempted_by, {:array, :text}, null: false, default: []
      add :meta, :map, null: false, default: %{}
      add :tags, {:array, :text}, null: false, default: []
      add :scheduled_at, :utc_datetime_usec
      add :attempted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :discarded_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :conflict?, :boolean, null: false, default: false
      timestamps(updated_at: false)
    end

    create index(:oban_jobs, [:queue, :state])
    create index(:oban_jobs, [:scheduled_at])
    create index(:oban_jobs, [:attempted_at])

    create table(:oban_peers, primary_key: false) do
      add :name, :text, primary_key: true
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create index(:oban_peers, [:expires_at])
  end

  def down do
    drop table(:oban_peers)
    drop table(:oban_jobs)
  end
end
