defmodule Thunderline.Thunderblock.Resources.ChannelParticipant do
  @moduledoc """
  ChannelParticipant Resource - Channel Membership & Participation Tracking

  Tracks user participation in channels, enabling proper membership management,
  presence tracking, and participation metrics. This is the junction resource
  between channels and users that supports role-based channel access.

  ## Core Responsibilities
  - User-to-channel membership tracking
  - Participant roles and permissions
  - Join/leave timestamps for activity metrics
  - Presence and activity status
  - Channel-specific user settings

  ## Participation Philosophy
  "Every voice matters. Track engagement, respect presence, enable collaboration."

  This resource enables Thunderline to maintain accurate channel membership,
  support real-time presence updates, and calculate participation metrics
  for community health monitoring.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_channel_participants"
    repo Thunderline.Repo

    references do
      reference :channel, on_delete: :delete, on_update: :update
      reference :user, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:channel_id, :user_id], unique: true, name: "channel_participants_unique_idx"
      index [:channel_id, :role], name: "channel_participants_role_idx"
      index [:user_id, :status], name: "channel_participants_user_status_idx"
      index [:channel_id, :joined_at], name: "channel_participants_joined_idx"
      index [:last_active_at], name: "channel_participants_activity_idx"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "channel_participant"

    routes do
      base("/channel_participants")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :update
    define :destroy
    define :join, args: [:channel_id, :user_id]
    define :leave
    define :update_role, args: [:role]
    define :by_channel, args: [:channel_id]
    define :by_user, args: [:user_id]
    define :active_in_channel, args: [:channel_id]
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a participant to a channel"
      primary? true

      accept [
        :channel_id,
        :user_id,
        :role,
        :notification_preferences,
        :channel_settings
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :active)
        |> Ash.Changeset.change_attribute(:joined_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:last_active_at, DateTime.utc_now())
      end
    end

    create :join do
      description "Join a channel (simplified create)"

      argument :channel_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(
          :channel_id,
          Ash.Changeset.get_argument(changeset, :channel_id)
        )
        |> Ash.Changeset.change_attribute(
          :user_id,
          Ash.Changeset.get_argument(changeset, :user_id)
        )
        |> Ash.Changeset.change_attribute(:role, :member)
        |> Ash.Changeset.change_attribute(:status, :active)
        |> Ash.Changeset.change_attribute(:joined_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:last_active_at, DateTime.utc_now())
      end
    end

    update :update do
      description "Update participant settings"
      primary? true

      accept [
        :role,
        :status,
        :notification_preferences,
        :channel_settings
      ]
    end

    update :leave do
      description "Leave a channel (soft delete via status)"

      change set_attribute(:status, :left)
      change set_attribute(:left_at, &DateTime.utc_now/0)
    end

    update :update_role do
      description "Update participant's role in channel"
      require_atomic? false

      argument :role, :atom do
        allow_nil? false
        constraints one_of: [:owner, :admin, :moderator, :member, :guest]
      end

      change fn changeset, _context ->
        role = Ash.Changeset.get_argument(changeset, :role)
        Ash.Changeset.change_attribute(changeset, :role, role)
      end
    end

    update :record_activity do
      description "Record participant activity"

      change set_attribute(:last_active_at, &DateTime.utc_now/0)
    end

    read :by_channel do
      description "Get participants for a channel"

      argument :channel_id, :uuid, allow_nil?: false

      filter expr(channel_id == ^arg(:channel_id) and status == :active)
      prepare build(sort: [joined_at: :asc])
    end

    read :by_user do
      description "Get channels a user participates in"

      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and status == :active)
      prepare build(sort: [last_active_at: :desc])
    end

    read :active_in_channel do
      description "Get active participants in a channel"

      argument :channel_id, :uuid, allow_nil?: false

      filter expr(
               channel_id == ^arg(:channel_id) and
                 status == :active and
                 last_active_at > ago(15, :minute)
             )

      prepare build(sort: [last_active_at: :desc])
    end
  end

  # ===== POLICIES =====
  policies do
    # All actions require authentication
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:owner, :admin, :moderator, :member, :guest]
      default :member
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :muted, :left, :banned]
      default :active
      public? true
    end

    attribute :notification_preferences, :map do
      default %{
        "mentions" => true,
        "all_messages" => false,
        "muted" => false
      }

      public? true
    end

    attribute :channel_settings, :map do
      default %{}
      public? true
    end

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :left_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :last_active_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    belongs_to :channel, Thunderline.Thunderlink.Resources.Channel do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :user, Thunderline.Thunderblock.Resources.VaultUser do
      allow_nil? false
      attribute_writable? true
    end
  end

  # ===== CALCULATIONS =====
  calculations do
    calculate :is_active, :boolean, expr(status == :active)

    calculate :is_online, :boolean, expr(last_active_at > ago(5, :minute) and status == :active)

    calculate :membership_duration_days,
              :integer,
              expr(
                cond do
                  not is_nil(left_at) ->
                    datetime_diff(left_at, joined_at, :day)

                  true ->
                    datetime_diff(now(), joined_at, :day)
                end
              )
  end

  # ===== IDENTITIES =====
  identities do
    identity :unique_channel_user, [:channel_id, :user_id]
  end
end
