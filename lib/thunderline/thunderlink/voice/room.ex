defmodule Thunderline.Thunderlink.Voice.Room do
  @moduledoc """
  Voice Room Resource (Thunderlink) – migrated from Thundercom.

  DEPRECATION: `Thunderline.Thundercom.Resources.VoiceRoom` will be removed after grace cycle.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "voice_rooms"
    repo Thunderline.Repo
  end

  # Link domain policy purged (WARHORSE) – governance moves to Crown

  code_interface do
    define :create_room
    define :close
    define :kick
    define :read
  end

  actions do
    defaults [:read]

    create :create_room do
      accept [:title, :community_id, :block_id, :created_by_id, :metadata]
      change &validate_scope!/2
      change &ensure_metadata_map/2
      change after_action(&broadcast_created/3)
    end

    update :close do
      accept []
      require_atomic? false
      change fn changeset, _ -> Ash.Changeset.change_attribute(changeset, :status, :closed) end
      change after_action(&broadcast_closed/3)
    end

    action :kick, :map do
      argument :participant_id, :uuid, allow_nil?: false
      run &do_kick/2
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :community_id, :uuid, allow_nil?: true, description: "Optional community scope"

    attribute :block_id, :uuid,
      allow_nil?: true,
      description: "Optional infrastructure block scope"

    attribute :status, :atom,
      allow_nil?: false,
      default: :open,
      constraints: [one_of: [:open, :closed]]

    attribute :created_by_id, :uuid, allow_nil?: false
    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :participants, Thunderline.Thunderlink.Voice.Participant do
      destination_attribute :room_id
    end
  end

  calculations do
    calculate :host_participant_id,
              :uuid,
              Thunderline.Thunderlink.Voice.Calculations.HostParticipantId
  end

  aggregates do
    count :active_participant_count, :participants
  end

  defp validate_scope!(changeset, _ctx) do
    if Ash.Changeset.get_attribute(changeset, :community_id) ||
         Ash.Changeset.get_attribute(changeset, :block_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :community_id,
        message: "either community_id or block_id must be provided"
      )
    end
  end

  defp ensure_metadata_map(changeset, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :metadata) do
      %{} -> changeset
      _ -> Ash.Changeset.change_attribute(changeset, :metadata, %{})
    end
  end

  defp do_kick(room, %{arguments: %{participant_id: participant_id}}) do
    case Thunderline.Thunderlink.Voice.Participant
         |> Ash.Query.for_read(:read, %{filter: [id: participant_id, room_id: room.id]})
         |> Ash.read_one(domain: Thunderline.Thunderlink.Domain) do
      {:ok, participant} ->
        _ = Ash.destroy(participant, action: :leave, domain: Thunderline.Thunderlink.Domain)

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          voice_topic(room.id),
          {:voice_participant_kicked, room.id, participant_id}
        )

        {:ok, %{kicked: participant_id}}

      {:error, _} ->
        {:ok, %{kicked: nil, reason: :not_found}}

      nil ->
        {:ok, %{kicked: nil, reason: :not_found}}
    end
  end

  defp voice_topic(room_id), do: "voice:#{room_id}"

  defp broadcast_created(_changeset, room, _ctx) do
    case Thunderline.Thunderlink.Voice.Supervisor.ensure_room(room.id) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        require Logger

        Logger.warning(
          "[VoiceRoom] failed to auto-start RoomPipeline for room=#{room.id} reason=#{inspect(reason)}"
        )
    end

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      voice_topic(room.id),
      {:voice_room_created, room}
    )

    {:ok, room}
  end

  defp broadcast_closed(_changeset, room, _ctx) do
    _ = Thunderline.Thunderlink.Voice.Supervisor.stop_room(room.id)

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      voice_topic(room.id),
      {:voice_room_closed, room.id}
    )

    {:ok, room}
  end
end
