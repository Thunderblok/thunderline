defmodule Thunderline.Repo.Migrations.CreateVoiceRooms do
  use Ecto.Migration

  def change do
    create table(:voice_rooms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :text, null: false
      add :community_id, :uuid
      add :block_id, :uuid
      add :status, :string, null: false, default: "open"
      add :created_by_id, :uuid, null: false
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:voice_rooms, [:community_id])
    create index(:voice_rooms, [:block_id])
    create index(:voice_rooms, [:status])
  end
end
