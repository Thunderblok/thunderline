defmodule Thunderline.Repo.Migrations.AddChannelParticipants do
  @moduledoc """
  Add thunderblock_channel_participants table for ChannelParticipant resource.
  """
  use Ecto.Migration

  def up do
    create table(:thunderblock_channel_participants, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "active"
      add :notification_preferences, :map, default: %{}
      add :channel_settings, :map, default: %{}
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :last_active_at, :utc_datetime_usec, null: false

      add :channel_id, references(:thunderblock_channels, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:vault_users, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:thunderblock_channel_participants, [:channel_id, :user_id],
      name: "thunderblock_channel_participants_unique_membership_index"
    )

    create index(:thunderblock_channel_participants, [:channel_id, :status],
      name: "thunderblock_channel_participants_channel_active_index"
    )

    create index(:thunderblock_channel_participants, [:user_id, :status],
      name: "thunderblock_channel_participants_user_active_index"
    )

    create index(:thunderblock_channel_participants, [:status, :last_active_at],
      name: "thunderblock_channel_participants_active_recent_index"
    )
  end

  def down do
    drop_if_exists index(:thunderblock_channel_participants, [:status, :last_active_at],
      name: "thunderblock_channel_participants_active_recent_index"
    )
    drop_if_exists index(:thunderblock_channel_participants, [:user_id, :status],
      name: "thunderblock_channel_participants_user_active_index"
    )
    drop_if_exists index(:thunderblock_channel_participants, [:channel_id, :status],
      name: "thunderblock_channel_participants_channel_active_index"
    )
    drop_if_exists unique_index(:thunderblock_channel_participants, [:channel_id, :user_id],
      name: "thunderblock_channel_participants_unique_membership_index"
    )
    drop table(:thunderblock_channel_participants)
  end
end
