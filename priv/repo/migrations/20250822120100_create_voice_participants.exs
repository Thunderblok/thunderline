defmodule Thunderline.Repo.Migrations.CreateVoiceParticipants do
  use Ecto.Migration

  def change do
    create table(:voice_participants, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:voice_rooms, type: :uuid, on_delete: :delete_all), null: false
      add :principal_id, :uuid, null: false
      add :principal_type, :string, null: false, default: "user"
      add :role, :string, null: false, default: "listener"
      add :muted, :boolean, null: false, default: false
      add :speaking, :boolean, null: false, default: false
      add :last_active_at, :utc_datetime
      add :joined_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:voice_participants, [:room_id, :principal_id],
             name: :voice_participants_unique_room_principal
           )

    create index(:voice_participants, [:principal_id])
  end
end
