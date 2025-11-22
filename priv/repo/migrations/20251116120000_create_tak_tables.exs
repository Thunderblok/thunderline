defmodule Thunderline.Repo.Migrations.CreateTakTables do
  @moduledoc """
  Creates TAK (Totalistic Automata Kernel) persistence tables for Thundervine.

  ## Tables
  - tak_chunk_events: Records cellular automaton evolution events per chunk
  - tak_chunk_states: Stores complete chunk state snapshots
  """
  use Ecto.Migration

  def up do
    create table(:tak_chunk_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :zone_id, :text, null: false
      add :chunk_coords, {:array, :integer}, null: false
      add :tick_id, :bigint, null: false
      add :diffs, :jsonb, null: false
      add :rule_hash, :text, null: false
      add :meta, :jsonb

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:tak_chunk_events, [:zone_id, :chunk_coords, :tick_id],
             name: :tak_chunk_events_by_zone_tick_index
           )

    create index(:tak_chunk_events, [:zone_id])
    create index(:tak_chunk_events, [:tick_id])
    create index(:tak_chunk_events, [:rule_hash])

    create table(:tak_chunk_states, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :zone_id, :text, null: false
      add :chunk_coords, {:array, :integer}, null: false
      add :tick_id, :bigint, null: false
      add :state_snapshot, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tak_chunk_states, [:zone_id, :chunk_coords],
             name: :tak_chunk_states_by_zone_chunk_index
           )

    create index(:tak_chunk_states, [:zone_id])
  end

  def down do
    drop table(:tak_chunk_states)
    drop table(:tak_chunk_events)
  end
end
