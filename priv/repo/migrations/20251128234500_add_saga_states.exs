defmodule Thunderline.Repo.Migrations.AddSagaStates do
  @moduledoc """
  Migration for saga_states table used by SagaWorker for state persistence.
  """

  use Ecto.Migration

  def up do
    create table(:saga_states, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :saga_module, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :inputs, :map, default: %{}
      add :output, :text
      add :checkpoint, :text
      add :error, :text
      add :attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, default: 3
      add :last_attempt_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :timeout_ms, :integer, default: 60_000
      add :meta, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Index for querying by saga module and status
    create index(:saga_states, [:saga_module, :status])

    # Index for querying stale running sagas
    create index(:saga_states, [:status, :last_attempt_at])

    # Index for time-based queries
    create index(:saga_states, [:inserted_at])
  end

  def down do
    drop table(:saga_states)
  end
end
