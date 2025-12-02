defmodule Thunderline.Thunderlink.Resources.Channel do
  @moduledoc """
  Channel Resource - Communication Conduits & Message Streams

  Represents communication channels within Community realms. Channels provide
  structured messaging, voice coordination, and specialized communication flows
  for different community needs and access patterns.

  ## Core Responsibilities
  - Text messaging and conversation threading
  - Voice channel coordination and audio streaming
  - Specialized channel types (announcements, AI agents, PAC coordination)
  - Message persistence and history management
  - Channel-specific permissions and access control
  - Real-time message broadcasting and synchronization

  ## Channel Philosophy
  "Every conversation has its place. Every voice has its conduit."

  Channels are the nervous system of Communities - enabling structured
  communication while maintaining sovereignty and federation capabilities.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  import Ash.Expr
  alias Thunderline.Thunderlink.Presence.Enforcer
  # import Ash.Resource.Change  # unused currently

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_channels"
    repo Thunderline.Repo

    references do
      reference :community, on_delete: :delete, on_update: :update
      reference :messages, on_delete: :delete, on_update: :update
      reference :channel_participants, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:channel_slug, :community_id], unique: true, name: "channels_slug_community_idx"
      index [:community_id, :channel_type], name: "channels_community_type_idx"
      index [:community_id, :position], name: "channels_community_position_idx"
      index [:channel_type, :status], name: "channels_type_status_idx"
      index [:status, :last_message_at], name: "channels_activity_idx"
      index [:visibility, :status], name: "channels_visibility_idx"
      index "USING GIN (pinned_message_ids)", name: "channels_pinned_messages_idx"
      index "USING GIN (tags)", name: "channels_tags_idx"
      index "USING GIN (channel_metrics)", name: "channels_metrics_idx"
    end

    check_constraints do
      check_constraint :valid_message_count, "message_count >= 0"
      check_constraint :valid_active_participants, "active_participants >= 0"
      check_constraint :valid_position, "position >= 0"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "channel"

    routes do
      base("/channels")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # Custom action endpoints (only :action type actions can use routes)
      route(:post, "/:id/send_message", :send_message)
      route(:post, "/:id/join", :join_channel)
      route(:post, "/:id/leave", :leave_channel)
      route(:post, "/:id/pin_message", :pin_message)
      route(:post, "/:id/archive", :archive)
      route(:post, "/:id/lock", :lock)
      route(:post, "/:id/unlock", :unlock)
      route(:post, "/:id/update_metrics", :update_metrics)
    end
  end

  # ===== POLICIES =====
  # ===== POLICIES =====
  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end

  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :update
    define :send_message, args: [:message_content, :sender_id, :message_type]
    define :join_channel, args: [:user_id]
    define :leave_channel, args: [:user_id]
    define :pin_message, args: [:message_id]
    define :archive, args: []
    define :lock, args: []
    define :unlock, args: []
    define :update_metrics, args: [:channel_metrics], action: :update_metrics
    define :by_community, args: [:community_id], action: :by_community
    define :by_type, args: [:channel_type], action: :by_type
    define :active_channels, action: :active_channels
    define :voice_channels, action: :voice_channels
    define :by_category, args: [:category], action: :by_category
    define :high_activity, action: :high_activity
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new channel in community"

      accept [
        :channel_name,
        :channel_slug,
        :channel_type,
        :channel_category,
        :visibility,
        :topic,
        :channel_config,
        :voice_config,
        :permissions_override,
        :created_by,
        :channel_integrations,
        :moderation_config,
        :position,
        :tags,
        :metadata,
        :community_id
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :active)
      end

      change after_action(fn _changeset, channel, _context ->
               # Update community channel count
               update_community_channel_count(channel.community_id, 1)

               # Initialize channel services
               initialize_channel_services(channel)

               # Create default channel permissions
               create_default_channel_permissions(channel)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 Thunderline.Thunderlink.Topics.community_channels(channel.community_id),
                 {:channel_created,
                  %{
                    channel_id: channel.id,
                    channel_name: channel.channel_name,
                    channel_type: channel.channel_type
                  }}
               )

               {:ok, channel}
             end)
    end

    update :update do
      description "Update channel configuration"

      accept [
        :channel_name,
        :channel_type,
        :channel_category,
        :visibility,
        :topic,
        :channel_config,
        :voice_config,
        :permissions_override,
        :channel_integrations,
        :moderation_config,
        :position,
        :tags,
        :metadata
      ]
    end

    action :send_message, :struct do
      constraints instance_of: __MODULE__
      description "Send message to channel and update metrics"

      argument :message_content, :string do
        allow_nil? false
      end

      argument :sender_id, :uuid do
        allow_nil? false
      end

      argument :message_type, :atom do
        default :text
        constraints one_of: [:text, :voice, :media, :system, :ai_response]
      end

      run fn input, context ->
        # Presence policy check (deny-by-default enforcement)
        channel = input.resource
        actor_ctx = Map.get(context, :actor_ctx)
        _ = Enforcer.with_presence(:send, {:channel, channel.id}, actor_ctx)

        current_count = channel.message_count || 0
        current_metrics = channel.channel_metrics || %{}

        # Update message count and timestamp
        updated_metrics =
          current_metrics
          |> Map.put("daily_messages", Map.get(current_metrics, "daily_messages", 0) + 1)
          |> calculate_engagement_score()

        # Update the channel
        updated_channel =
          channel
          |> Ash.Changeset.for_update(:internal_update_message_metrics, %{
            message_count: current_count + 1,
            last_message_at: DateTime.utc_now(),
            channel_metrics: updated_metrics
          })
          |> Thunderline.Thunderblock.Domain.update!()

        # Create message record
        create_channel_message(updated_channel, input.arguments)

        # Broadcast message to channel subscribers
        broadcast_channel_message(updated_channel, input.arguments)

        {:ok, updated_channel}
      end
    end

    update :internal_update_message_metrics do
      description "Internal update for message metrics"
      accept [:message_count, :last_message_at, :channel_metrics]
    end

    action :join_channel do
      description "User joins channel (for voice or tracked participation)"

      argument :user_id, :uuid do
        allow_nil? false
        description "ID of user joining channel"
      end

      argument :join_type, :string do
        allow_nil? false
        description "Type of join: voice, text, or full"
      end

      run fn input, context ->
        channel = input.resource
        actor_ctx = Map.get(context, :actor_ctx)

        Enforcer.with_presence :join, {:channel, channel.id}, actor_ctx do
          Ash.Changeset.for_update(channel, :internal_update_metrics, %{
            participant_count: channel.participant_count + 1
          })
          |> Ash.update()
        end
      end
    end

    action :leave_channel do
      description "User leaves channel"

      argument :user_id, :uuid do
        allow_nil? false
      end

      run fn input, context ->
        user_id = context.arguments.user_id
        channel = input.resource

        # Update active participants count
        updated_channel =
          Ash.Changeset.for_update(channel, :internal_update_metrics, %{
            active_participants: max(0, (channel.active_participants || 0) - 1)
          })
          |> Ash.update()

        case updated_channel do
          {:ok, channel} ->
            # Track channel participation
            track_channel_participation(channel, user_id, :left)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              Thunderline.Thunderlink.Topics.channel_base(channel.id),
              {:user_left, %{user_id: user_id, channel_id: channel.id}}
            )

            {:ok, channel}

          error ->
            error
        end
      end
    end

    action :pin_message do
      description "Pin message in channel"

      argument :message_id, :uuid do
        allow_nil? false
      end

      run fn input, context ->
        message_id = context.arguments.message_id
        channel = input.resource
        current_pinned = channel.pinned_message_ids || []

        # Add to pinned if not already present, limit to 10 pinned messages
        updated_pinned =
          if message_id in current_pinned do
            current_pinned
          else
            [message_id | current_pinned] |> Enum.take(10)
          end

        Ash.Changeset.for_update(channel, :internal_update_metadata, %{
          pinned_message_ids: updated_pinned
        })
        |> Ash.update()
      end
    end

    action :archive do
      description "Archive channel (preserve but make read-only)"

      run fn input, _context ->
        input.resource
        |> Ash.Changeset.for_update(:internal_update_metadata, %{status: :archived})
        |> Ash.update()
        |> case do
          {:ok, channel} ->
            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              Thunderline.Thunderlink.Topics.community_channels(channel.community_id),
              {:channel_archived, %{channel_id: channel.id, channel_name: channel.channel_name}}
            )

            {:ok, channel}

          error ->
            error
        end
      end
    end

    action :lock do
      description "Lock channel (prevent new messages)"

      run fn input, _context ->
        input.resource
        |> Ash.Changeset.for_update(:internal_update_metadata, %{is_locked: true})
        |> Ash.update()
      end
    end

    action :unlock do
      description "Unlock channel"

      run fn input, _context ->
        input.resource
        |> Ash.Changeset.for_update(:internal_update_metadata, %{is_locked: false})
        |> Ash.update()
      end
    end

    # Convert update_metrics to action type for JSON API route
    action :update_metrics do
      description "Update channel activity metrics"

      argument :channel_metrics, :map do
        allow_nil? false
      end

      run fn input, _context ->
        channel = input.resource
        metrics = input.arguments.channel_metrics || %{}
        health_score = calculate_channel_health(metrics)
        updated_metrics = Map.put(metrics, "health_score", health_score)

        result =
          Ash.update!(channel, :_internal_update_metrics, %{channel_metrics: updated_metrics})

        {:ok, result}
      end
    end

    # Internal update action for update_metrics
    update :_internal_update_metrics do
      description "Internal update for update_metrics operation"
      accept [:channel_metrics]
    end

    # Query actions
    action :by_community, :struct do
      constraints instance_of: __MODULE__
      description "Get channels for a community"

      argument :community_id, :uuid do
        allow_nil? false
      end

      filter expr(community_id == ^arg(:community_id))
    end

    read :by_type do
      description "Get channels by type"

      argument :channel_type, :atom do
        allow_nil? false
      end

      filter expr(channel_type == ^arg(:channel_type))
    end

    read :active_channels do
      description "Get active channels"

      filter expr(status == :active)
    end

    read :voice_channels do
      description "Get voice channels"

      filter expr(channel_type == :voice and status == :active)
    end

    read :by_category do
      description "Get channels in specific category"

      argument :category, :string do
        allow_nil? false
      end

      filter expr(channel_category == ^arg(:category))
      prepare build(sort: [:position, :channel_name])
    end

    read :high_activity do
      description "Get channels with high activity"

      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
      prepare build(sort: [])
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(load: [:community, :messages])
  end

  # ===== VALIDATIONS =====
  validations do
    validate present([:channel_name, :channel_slug, :community_id, :created_by])
    validate {Thunderline.Thunderblock.Validations.ValidSlug, field: :channel_slug}
    validate Thunderline.Thunderblock.Validations.ValidChannelPermissions
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :channel_name, :string do
      allow_nil? false
      description "Human-readable channel name"
      constraints min_length: 1, max_length: 100
    end

    attribute :channel_slug, :string do
      allow_nil? false
      description "URL-safe channel identifier"
      constraints min_length: 1, max_length: 50, match: ~r/^[a-z0-9\-_]+$/
    end

    attribute :channel_type, :atom do
      allow_nil? false
      description "Type of channel functionality"
      default :text

      constraints one_of: [
                    :text,
                    :voice,
                    :announcement,
                    :ai_agent,
                    :pac_coordination,
                    :media,
                    :forum
                  ]
    end

    attribute :channel_category, :string do
      allow_nil? true
      description "Optional channel category for organization"
      constraints max_length: 50
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current channel status"
      default :active
      constraints one_of: [:active, :archived, :locked, :maintenance, :deleted]
    end

    attribute :visibility, :atom do
      allow_nil? false
      description "Channel visibility and access level"
      default :public
      constraints one_of: [:public, :private, :restricted, :moderator_only, :admin_only]
    end

    attribute :topic, :string do
      allow_nil? true
      description "Channel topic or description"
      constraints max_length: 500
    end

    attribute :channel_config, :map do
      allow_nil? false
      description "Channel-specific configuration and settings"

      default %{
        message_retention_days: 30,
        allow_attachments: true,
        allow_reactions: true,
        allow_threads: true,
        max_message_length: 2000,
        rate_limit_per_minute: 10
      }
    end

    attribute :voice_config, :map do
      allow_nil? false
      description "Voice channel specific configuration"

      default %{
        max_participants: 10,
        quality: "standard",
        auto_record: false,
        push_to_talk: false,
        noise_suppression: true
      }
    end

    attribute :permissions_override, :map do
      allow_nil? false
      description "Channel-specific permission overrides"
      default %{}
    end

    attribute :message_count, :integer do
      allow_nil? false
      description "Total number of messages in channel"
      default 0
      constraints min: 0
    end

    attribute :active_participants, :integer do
      allow_nil? false
      description "Currently active participants in channel"
      default 0
      constraints min: 0
    end

    attribute :last_message_at, :utc_datetime do
      allow_nil? true
      description "Timestamp of last message in channel"
    end

    attribute :created_by, :uuid do
      allow_nil? false
      description "ID of user who created the channel"
    end

    attribute :pinned_message_ids, {:array, :uuid} do
      allow_nil? false
      description "List of pinned message IDs"
      default []
    end

    attribute :channel_integrations, :map do
      allow_nil? false
      description "External integrations and bot configurations"

      default %{
        ai_agents_enabled: false,
        pac_integration: false,
        federation_bridge: false,
        webhooks: []
      }
    end

    attribute :moderation_config, :map do
      allow_nil? false
      description "Channel moderation settings"

      default %{
        automod_enabled: true,
        spam_protection: true,
        profanity_filter: "moderate",
        link_protection: false,
        require_approval: false
      }
    end

    attribute :channel_metrics, :map do
      allow_nil? false
      description "Channel activity and engagement metrics"

      default %{
        daily_messages: 0,
        weekly_active_participants: 0,
        engagement_score: 0.0,
        health_score: 1.0
      }
    end

    attribute :position, :integer do
      allow_nil? false
      description "Channel display position within category"
      default 0
      constraints min: 0
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Channel categorization and search tags"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional channel metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    belongs_to :community, Thunderline.Thunderlink.Resources.Community do
      attribute_writable? true
      source_attribute :community_id
      destination_attribute :id
    end

    has_many :messages, Thunderline.Thunderlink.Resources.Message do
      destination_attribute :channel_id
    end

    has_many :channel_participants, Thunderline.Thunderblock.Resources.ChannelParticipant do
      destination_attribute :channel_id
    end

    has_many :system_events, Thunderline.Thunderblock.Resources.SystemEvent do
      destination_attribute :target_resource_id
      filter expr(target_resource_type == :channel)
    end
  end

  # ===== OBAN CONFIGURATION =====
  # oban do
  #   # Channel metrics update
  #   trigger :channel_metrics_update do
  #     action :update_metrics
  #     schedule "*/300 * * * * *"  # Every 5 minutes
  #     where expr(status == :active)
  #   end

  #   # Archive inactive channels
  #   trigger :archive_inactive_channels do
  #     action :active_channels
  #     schedule "0 2 * * *"  # Daily at 2 AM
  #     where expr(
  #       status == :active and
  #       (last_message_at < ago(30, :day) or is_nil(last_message_at))
  #     )
  #   end
  # end

  # ===== IDENTITIES =====
  identities do
    identity :unique_channel_in_community, [:channel_slug, :community_id]
  end

  # ===== PRIVATE FUNCTIONS =====
  defp update_community_channel_count(_community_id, _increment) do
    # Update the community's channel count
    # This would be implemented to update the community resource
    :ok
  end

  defp initialize_channel_services(channel) do
    # Initialize channel-specific services (voice, streaming, etc.)
    case channel.channel_type do
      :voice -> initialize_voice_channel(channel)
      :ai_agent -> initialize_ai_integration(channel)
      :pac_coordination -> initialize_pac_bridge(channel)
      _ -> :ok
    end
  end

  defp create_default_channel_permissions(_channel) do
    # Create default permission set for channel based on visibility
    :ok
  end

  defp create_channel_message(_channel, _message_args) do
    # Create message record in the messages table
    # This would interface with the Message resource
    :ok
  end

  defp broadcast_channel_message(channel, message_args) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      Thunderline.Thunderlink.Topics.channel_messages(channel.id),
      {:new_message,
       %{
         channel_id: channel.id,
         sender_id: message_args.sender_id,
         content: message_args.message_content,
         message_type: message_args.message_type,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp track_channel_participation(_channel, _user_id, _action) do
    # Track user participation for analytics
    :ok
  end

  defp calculate_engagement_score(metrics) do
    # Calculate engagement score based on activity
    daily_messages = Map.get(metrics, "daily_messages", 0)
    weekly_participants = Map.get(metrics, "weekly_active_participants", 0)

    engagement = daily_messages * 0.3 + weekly_participants * 0.7
    Map.put(metrics, "engagement_score", min(100.0, engagement))
  end

  defp calculate_channel_health(metrics) do
    # Calculate channel health score
    engagement = Map.get(metrics, "engagement_score", 0.0)
    daily_messages = Map.get(metrics, "daily_messages", 0)

    # Health based on consistent activity
    cond do
      daily_messages > 20 && engagement > 50 -> 1.0
      daily_messages > 10 && engagement > 25 -> 0.8
      daily_messages > 5 && engagement > 10 -> 0.6
      daily_messages > 0 -> 0.4
      true -> 0.2
    end
  end

  # Channel service initialization helpers
  defp initialize_voice_channel(_channel), do: :ok
  defp initialize_ai_integration(_channel), do: :ok
  defp initialize_pac_bridge(_channel), do: :ok

  # ===== PRESENCE POLICY INTEGRATION HELPERS =====
  # Deprecated helper removed to avoid direct Policy usage in Link domain.
  # Use Thunderline.Thunderlink.Presence.Enforcer macros instead.
end
