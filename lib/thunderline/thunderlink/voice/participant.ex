defmodule Thunderline.Thunderlink.Voice.Participant do
  @moduledoc """
  Voice Participant Resource (Thunderlink) – migrated from Thundercom. Old module deprecated.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "voice_participants"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :room_id, :uuid, allow_nil?: false
    attribute :principal_id, :uuid, allow_nil?: false, description: "User or PAC id"
    attribute :principal_type, :atom, allow_nil?: false, default: :user, constraints: [one_of: [:user, :pac, :agent]]
    attribute :role, :atom, allow_nil?: false, default: :listener, constraints: [one_of: [:host, :speaker, :listener]]
    attribute :muted, :boolean, allow_nil?: false, default: false
    attribute :speaking, :boolean, allow_nil?: false, default: false
    attribute :last_active_at, :utc_datetime, allow_nil?: true
    create_timestamp :joined_at
  end

  identities do
    identity :unique_room_principal, [:room_id, :principal_id]
  end

  relationships do
    belongs_to :room, Thunderline.Thunderlink.Voice.Room do
      source_attribute :room_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]
    create :join do
      accept [:room_id, :principal_id, :principal_type, :role, :muted, :speaking]
      change &ensure_role/2
      change &touch/2
      change after_action(&broadcast_join/3)
    end
    update :set_muted do
      accept [:muted]
      change &touch/2
      change after_action(&broadcast_muted/3)
    end
    update :set_speaking do
      accept [:speaking]
      change &touch/2
      change after_action(&broadcast_speaking/3)
    end
    update :promote do
      accept [:role]
      change &validate_promotion/2
      change after_action(&broadcast_promote/3)
    end
    destroy :leave do
      description "Leave a voice room"
      change after_action(&broadcast_leave/3)
    end
  end

  # Link domain policy purged (WARHORSE)

  code_interface do
    define :join
    define :set_muted
    define :set_speaking
    define :promote
    define :leave
    define :read
  end

  defp ensure_role(changeset, _ctx) do
    role = Ash.Changeset.get_attribute(changeset, :role)
    if role in [:host, :speaker, :listener], do: changeset, else: Ash.Changeset.change_attribute(changeset, :role, :listener)
  end
  defp validate_promotion(changeset, _ctx) do
    role = Ash.Changeset.get_attribute(changeset, :role)
    if role in [:host, :speaker, :listener], do: changeset, else: Ash.Changeset.add_error(changeset, field: :role, message: "invalid role")
  end
  defp touch(changeset, _ctx), do: Ash.Changeset.change_attribute(changeset, :last_active_at, DateTime.utc_now())
  defp topic(room_id), do: "voice:#{room_id}"
  defp broadcast_join(_changeset, participant, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(participant.room_id), {:voice_participant_joined, participant}); {:ok, participant}
  end
  defp broadcast_leave(_changeset, participant, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(participant.room_id), {:voice_participant_left, participant.id}); {:ok, participant}
  end
  defp broadcast_muted(_changeset, participant, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(participant.room_id), {:voice_participant_muted, participant.id, participant.muted}); {:ok, participant}
  end
  defp broadcast_speaking(_changeset, participant, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(participant.room_id), {:voice_participant_speaking, participant.id, participant.speaking}); {:ok, participant}
  end
  defp broadcast_promote(_changeset, participant, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(participant.room_id), {:voice_participant_role, participant.id, participant.role}); {:ok, participant}
  end
end
