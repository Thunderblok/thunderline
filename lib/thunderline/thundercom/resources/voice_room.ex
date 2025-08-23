defmodule Thunderline.Thundercom.Resources.VoiceRoom do
  @moduledoc """
  VoiceRoom Resource - Represents a real-time audio room for human + agent interaction.

  MVP Scope:
  - Create/Open room inside a community or block context
  - Track status (:open | :closed)
  - Basic moderation via host/creator ownership
  - Policy surface prepared for enrichment

  Future (not in MVP but anticipated):
  - Recording linkage (session manifest resource)
  - Transcription stream association
  - AI Co-host / Agent participants
  - Persistence of aggregate metrics (talk time, active speaker count)
  """
  use Ash.Resource,
    domain: Thunderline.Thundercom.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "voice_rooms"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :community_id, :uuid, allow_nil?: true, description: "Optional community scope"
    attribute :block_id, :uuid, allow_nil?: true, description: "Optional infrastructure block scope"
    attribute :status, :atom, allow_nil?: false, default: :open, constraints: [one_of: [:open, :closed]]
    attribute :created_by_id, :uuid, allow_nil?: false
    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
  has_many :participants, Thunderline.Thundercom.Resources.VoiceParticipant do
      destination_attribute :room_id
    end
  end

  aggregates do
    # Count active participants (exclude those destroyed by leave)
    count :active_participant_count, :participants
  end

  calculations do
    calculate :host_participant_id, :uuid, Thunderline.Thundercom.Calculations.HostParticipantId
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

    # Host moderation: remove a participant from the room (soft abstraction; actually destroys participant row)
    action :kick, :map do
      argument :participant_id, :uuid, allow_nil?: false
      run &do_kick/2
    end
  end

  policies do
    # Creating a room requires an actor and at least one scope; host becomes creator.
    policy action(:create_room) do
      authorize_if expr(not is_nil(actor(:id)))
    end

    # Read open rooms; creator can read closed as well.
    policy action(:read) do
      authorize_if expr(status == :open)
      authorize_if expr(created_by_id == actor(:id))
    end

    # Only creator can close or kick for now (future: allow moderators/roles)
    policy action([:close, :kick]) do
      authorize_if expr(created_by_id == actor(:id))
    end

    # Fallback deny (implicit) if nothing matched
  end

  code_interface do
    define :create_room
    define :close
    define :kick
    define :read
  end

  # --- Internal helpers --------------------------------------------------
  defp validate_scope!(changeset, _ctx) do
    community_id = Ash.Changeset.get_attribute(changeset, :community_id)
    block_id = Ash.Changeset.get_attribute(changeset, :block_id)
    if is_nil(community_id) and is_nil(block_id) do
      Ash.Changeset.add_error(changeset, field: :community_id, message: "either community_id or block_id must be provided")
    else
      changeset
    end
  end

  defp ensure_metadata_map(changeset, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :metadata) do
      %{} -> changeset
      _ -> Ash.Changeset.change_attribute(changeset, :metadata, %{})
    end
  end

  defp do_kick(room, %{arguments: %{participant_id: participant_id}}) do
    # We do a best-effort delete; ignore if already gone.
    case Thunderline.Thundercom.Resources.VoiceParticipant
         |> Ash.Query.for_read(:read, %{filter: [id: participant_id, room_id: room.id]})
         |> Thunderline.Thundercom.Domain.read_one() do
      {:ok, participant} ->
        _ = Ash.destroy(participant, action: :leave, domain: Thunderline.Thundercom.Domain)
        Phoenix.PubSub.broadcast(Thunderline.PubSub, voice_topic(room.id), {:voice_participant_kicked, room.id, participant_id})
        {:ok, %{kicked: participant_id}}
      {:error, _} -> {:ok, %{kicked: nil, reason: :not_found}}
      nil -> {:ok, %{kicked: nil, reason: :not_found}}
    end
  end

  # --- Broadcast helpers -------------------------------------------------
  defp voice_topic(room_id), do: "voice:#{room_id}"

  defp broadcast_created(_changeset, room, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, voice_topic(room.id), {:voice_room_created, room})
    {:ok, room}
  end

  defp broadcast_closed(_changeset, room, _ctx) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, voice_topic(room.id), {:voice_room_closed, room.id})
    {:ok, room}
  end
end
