defmodule Thunderline.Repo.Migrations.CreateReplayCheckpoints do
  use Ecto.Migration

  def change do
    create table(:replay_checkpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      # market | edgar
      add :stream, :text, null: false
      add :last_ts, :bigint
      add :last_vendor_seq, :bigint
      add :note, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:replay_checkpoints, [:stream])
  end
end
