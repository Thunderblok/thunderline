defmodule Thunderline.Thunderlink.Resources.Message do
  @moduledoc """
  Message Resource - Communication Atoms & Conversation Flow

  Represents individual messages within channels, providing persistent storage,
  threading capabilities, reactions, and specialized message types for different
  communication patterns within Community realms.

  ## Core Responsibilities
  - Message content storage and versioning
  - Thread and reply management
  - Reaction and emoji response tracking
  - Message attachments and media handling
  - AI agent message integration
  - PAC coordination message types
  - Message search and history retrieval

  ## Message Philosophy
  "Every word matters. Every response creates connection."

  Messages are the atoms of community communication - enabling everything
  from casual conversation to AI coordination and PAC orchestration.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource, AshCloak],
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_messages"
    repo Thunderline.Repo

    references do
      reference :channel, on_delete: :delete, on_update: :update
      reference :community, on_delete: :delete, on_update: :update
      reference :reply_to, on_delete: :nilify, on_update: :update
      reference :thread_root, on_delete: :nilify, on_update: :update
      reference :replies, on_delete: :delete, on_update: :update
      reference :thread_messages, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:channel_id, :inserted_at], name: "messages_channel_time_idx"
      index [:sender_id, :inserted_at], name: "messages_sender_time_idx"
      index [:thread_root_id, :inserted_at], name: "messages_thread_idx"
      index [:reply_to_id], name: "messages_reply_idx"
      index [:status, :inserted_at], name: "messages_status_time_idx"
      index [:message_type, :sender_type], name: "messages_type_idx"
      index [:ephemeral_until], name: "messages_ephemeral_idx"
      index "USING GIN (search_vector)", name: "messages_search_idx"
      index "USING GIN (mentions)", name: "messages_mentions_idx"
      index "USING GIN (message_flags)", name: "messages_flags_idx"
      index "USING GIN (tags)", name: "messages_tags_idx"
      index "USING GIN (reactions)", name: "messages_reactions_idx"
    end

    check_constraints do
      check_constraint :valid_thread_counts,
                       "thread_participant_count >= 0 AND thread_message_count >= 0"

      check_constraint :valid_content_length, "char_length(content) > 0"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "message"

    routes do
      base("/messages")
      get(:read)
      index :read
      post(:create)
      patch(:edit)
      delete(:destroy)
    end
  end

  # ===== POLICIES =====
  #   policies do
  #     bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #       authorize_if always()
  #     end

  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :send_ai_response, args: [:content, :sender_id, :ai_metadata, :channel_id]
    define :send_pac_command, args: [:content, :sender_id, :pac_metadata, :channel_id]
    define :send_system_message, args: [:content, :channel_id]
    define :edit, args: [:content]
    define :add_reaction, args: [:emoji, :user_id]
    define :remove_reaction, args: [:emoji, :user_id]
    define :flag, args: []
    define :soft_delete, args: []
    define :pin, args: []
    define :by_channel, args: [:channel_id, :limit]
    define :thread_messages, args: [:thread_root_id]
    define :by_sender, args: [:sender_id]
    define :recent_messages, args: [:hours_back]
    define :search, args: [:search_term, :channel_id]
    define :flagged_messages, action: :flagged_messages
    define :ai_messages, action: :ai_messages
    define :pac_commands, action: :pac_commands
    define :cleanup_ephemeral, action: :cleanup_ephemeral
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new message in channel"

      accept [
        :content,
        :message_type,
        :sender_id,
        :sender_type,
        :reply_to_id,
        :attachments,
        :mentions,
        :channel_mentions,
        :role_mentions,
        :message_flags,
        :ai_metadata,
        :pac_metadata,
        :federation_metadata,
        :ephemeral_until,
        :tags,
        :metadata,
        :channel_id,
        :community_id
      ]

      change fn changeset, _context ->
        content = Ash.Changeset.get_attribute(changeset, :content) || ""

        # Generate search vector for full-text search
        search_vector = generate_search_vector(content)

        # Set thread root if this is a reply
        thread_root_id =
          case Ash.Changeset.get_attribute(changeset, :reply_to_id) do
            nil -> nil
            reply_to_id -> get_thread_root_id(reply_to_id)
          end

        changeset
        |> Ash.Changeset.change_attribute(:search_vector, search_vector)
        |> Ash.Changeset.change_attribute(:thread_root_id, thread_root_id)
        |> Ash.Changeset.change_attribute(:status, :active)
      end

      change after_action(fn _changeset, message, _context ->
               # Update channel message count and last message timestamp
               update_channel_message_stats(message.channel_id)

               # Update thread statistics if this is a reply
               if message.reply_to_id do
                 update_thread_stats(message.thread_root_id || message.reply_to_id)
               end

               # Process mentions and notifications
               process_message_mentions(message)

               # Run content moderation
               moderate_message_content(message)

               # Handle special message types
               handle_special_message_type(message)

               # Broadcast message to channel subscribers
               broadcast_new_message(message)

               {:ok, message}
             end)
    end

    create :send_ai_response do
      description "Send AI-generated response message"
      accept [:content, :sender_id, :reply_to_id, :ai_metadata, :channel_id, :community_id]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:message_type, :ai_response)
        |> Ash.Changeset.change_attribute(:sender_type, :ai_agent)
        |> Ash.Changeset.change_attribute(:message_flags, [:ai_generated])
      end
    end

    create :send_pac_command do
      description "Send PAC coordination command"
      accept [:content, :sender_id, :pac_metadata, :channel_id, :community_id]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:message_type, :pac_command)
        |> Ash.Changeset.change_attribute(:sender_type, :pac_agent)
        |> Ash.Changeset.change_attribute(:message_flags, [:pac_command])
      end
    end

    create :send_system_message do
      description "Send system-generated message"
      accept [:content, :message_flags, :channel_id, :community_id]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:message_type, :system)
        |> Ash.Changeset.change_attribute(:sender_type, :system)

        # System UUID
        |> Ash.Changeset.change_attribute(:sender_id, Ash.UUID.generate())
      end
    end

    update :edit do
      description "Edit message content"
      accept [:content]

      change fn changeset, _context ->
        # Store edit in history
        current_content = Ash.Changeset.get_data(changeset, :content)
        current_history = Ash.Changeset.get_attribute(changeset, :edit_history) || []

        edit_entry = %{
          previous_content: current_content,
          edited_at: DateTime.utc_now(),
          edit_reason: "user_edit"
        }

        # Keep last 10 edits

        updated_history = [edit_entry | current_history] |> Enum.take(10)

        changeset
        |> Ash.Changeset.change_attribute(:status, :edited)
        |> Ash.Changeset.change_attribute(:edit_history, updated_history)
      end

      change after_action(fn _changeset, message, _context ->
               # Broadcast message edit
               broadcast_message_edit(message)
               {:ok, message}
             end)
    end

    update :add_reaction do
      description "Add emoji reaction to message"
      accept [:reactions, :message_metrics]

      argument :emoji, :string do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change fn changeset, context ->
        emoji = context.arguments.emoji
        user_id = context.arguments.user_id

        current_reactions = Ash.Changeset.get_attribute(changeset, :reactions) || %{}
        current_metrics = Ash.Changeset.get_attribute(changeset, :message_metrics) || %{}

        # Add user to emoji reaction list
        emoji_reactions = Map.get(current_reactions, emoji, [])

        updated_reactions =
          if user_id in emoji_reactions do
            # User already reacted with this emoji
            current_reactions
          else
            Map.put(current_reactions, emoji, [user_id | emoji_reactions])
          end

        # Update reaction count
        total_reactions =
          updated_reactions
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        updated_metrics = Map.put(current_metrics, "reaction_count", total_reactions)

        changeset
        |> Ash.Changeset.change_attribute(:reactions, updated_reactions)
        |> Ash.Changeset.change_attribute(:message_metrics, updated_metrics)
      end

      change after_action(fn _changeset, message, context ->
               # Broadcast reaction update
               broadcast_reaction_update(
                 message,
                 context.arguments.emoji,
                 context.arguments.user_id,
                 :added
               )

               {:ok, message}
             end)
    end

    update :remove_reaction do
      description "Remove emoji reaction from message"
      accept [:reactions, :message_metrics]

      argument :emoji, :string do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change fn changeset, context ->
        emoji = context.arguments.emoji
        user_id = context.arguments.user_id

        current_reactions = Ash.Changeset.get_attribute(changeset, :reactions) || %{}
        current_metrics = Ash.Changeset.get_attribute(changeset, :message_metrics) || %{}

        # Remove user from emoji reaction list
        emoji_reactions = Map.get(current_reactions, emoji, [])
        updated_emoji_reactions = List.delete(emoji_reactions, user_id)

        updated_reactions =
          if updated_emoji_reactions == [] do
            # Remove emoji entirely if no reactions
            Map.delete(current_reactions, emoji)
          else
            Map.put(current_reactions, emoji, updated_emoji_reactions)
          end

        # Update reaction count
        total_reactions =
          updated_reactions
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        updated_metrics = Map.put(current_metrics, "reaction_count", total_reactions)

        changeset
        |> Ash.Changeset.change_attribute(:reactions, updated_reactions)
        |> Ash.Changeset.change_attribute(:message_metrics, updated_metrics)
      end

      change after_action(fn _changeset, message, context ->
               # Broadcast reaction update
               broadcast_reaction_update(
                 message,
                 context.arguments.emoji,
                 context.arguments.user_id,
                 :removed
               )

               {:ok, message}
             end)
    end

    update :flag do
      description "Flag message for moderation"
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :flagged)
      end

      change after_action(fn _changeset, message, _context ->
               # Notify moderation team
               notify_moderation_team(message)
               {:ok, message}
             end)
    end

    update :soft_delete do
      description "Soft delete message (mark as deleted but preserve)"
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :deleted)
      end

      change after_action(fn _changeset, message, _context ->
               # Broadcast message deletion
               broadcast_message_deletion(message)
               {:ok, message}
             end)
    end

    update :pin do
      description "Pin message in channel"
      accept [:message_flags]
      require_atomic? false

      change fn changeset, _context ->
        current_flags = Ash.Changeset.get_attribute(changeset, :message_flags) || []

        updated_flags =
          if :pinned in current_flags do
            current_flags
          else
            [:pinned | current_flags]
          end

        Ash.Changeset.change_attribute(changeset, :message_flags, updated_flags)
      end

      change after_action(fn _changeset, message, _context ->
               # Load channel and invoke pin action via correct resource module
               channel = Ash.get!(Thunderline.Thunderlink.Resources.Channel, message.channel_id)
               Thunderline.Thunderlink.Resources.Channel.pin_message(channel, message.id)
               {:ok, message}
             end)
    end

    # Query actions
    read :by_channel do
      description "Get messages in channel"

      argument :channel_id, :uuid do
        allow_nil? false
      end

      argument :limit, :integer, default: 50

      filter expr(channel_id == ^arg(:channel_id) and status in [:active, :edited])
      prepare build(sort: [inserted_at: :desc])

      prepare fn query, context ->
        limit = context.arguments.limit
        Ash.Query.limit(query, limit)
      end
    end

    read :thread_messages do
      description "Get messages in thread"

      argument :thread_root_id, :uuid do
        allow_nil? false
      end

      filter expr(thread_root_id == ^arg(:thread_root_id) and status in [:active, :edited])
      prepare build(sort: [:inserted_at])
    end

    read :by_sender do
      description "Get messages by sender"

      argument :sender_id, :uuid do
        allow_nil? false
      end

      filter expr(sender_id == ^arg(:sender_id) and status in [:active, :edited])
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent_messages do
      description "Get recent messages across channels"

      argument :hours_back, :integer, default: 24

      # TODO: Fix fragment expression variable reference issues
      # prepare fn query, context ->
      #   hours = context.arguments.hours_back
      #   Ash.Query.filter(query,
      #     inserted_at > ago(^(hours * 3600), :second) and
      #     status in [:active, :edited]
      #   )
      # end

      prepare build(sort: [inserted_at: :desc])
    end

    read :search do
      description "Full-text search messages"

      argument :search_term, :string do
        allow_nil? false
      end

      argument :channel_id, :uuid, allow_nil?: true

      # TODO: Fix fragment expression variable reference issues
      # prepare fn query, context ->
      #   search_term = context.arguments.search_term
      #   channel_id = context.arguments.channel_id

      #   # Use PostgreSQL full-text search
      #   query = Ash.Query.filter(query,
      #     fragment("? @@ plainto_tsquery(?)", search_vector, ^search_term) and
      #     status in [:active, :edited]
      #   )

      #   if channel_id do
      #     Ash.Query.filter(query, channel_id == ^channel_id)
      #   else
      #     query
      #   end
      # end

      prepare build(sort: [inserted_at: :desc])
    end

    read :flagged_messages do
      description "Get flagged messages for moderation"

      filter expr(status == :flagged)
      prepare build(sort: [inserted_at: :desc])
    end

    read :ai_messages do
      description "Get AI-generated messages"

      filter expr(sender_type == :ai_agent and status in [:active, :edited])
      prepare build(sort: [inserted_at: :desc])
    end

    read :pac_commands do
      description "Get PAC coordination commands"

      filter expr(message_type == :pac_command and status in [:active, :edited])
      prepare build(sort: [inserted_at: :desc])
    end

    # Cleanup action for ephemeral messages
    destroy :cleanup_ephemeral do
      description "Remove expired ephemeral messages"
      require_atomic? false

      filter expr(not is_nil(ephemeral_until) and ephemeral_until < now())

      change after_action(fn _changeset, messages, _context ->
               # Broadcast ephemeral message cleanup
               for message <- messages do
                 broadcast_message_deletion(message)
               end

               {:ok, messages}
             end)
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(load: [:channel, :community, :reply_to, :thread_root])
  end

  # ===== OBAN CONFIGURATION =====
  # TODO: Fix AshOban extension loading issue
  # oban do
  #   # Cleanup ephemeral messages
  #   trigger :cleanup_ephemeral_messages do
  #     action :cleanup_ephemeral
  #     schedule "*/300 * * * * *"  # Every 5 minutes
  #   end

  #   # Content moderation batch processing
  #   trigger :moderate_flagged_messages do
  #     action :flagged_messages
  #     schedule "*/60 * * * * *"  # Every minute
  #   end
  # end

  # ===== VALIDATIONS =====
  validations do
    validate present([:content, :sender_id, :channel_id])
    # TODO: Fix validation syntax - :edit is not valid in Ash 3.x
    # validate {Thunderblock.Validations, :message_content_appropriate}, on: [:create, :edit]
    # TODO: Fix validation syntax for Ash 3.x
    # validate {Thunderblock.Validations, :valid_attachments}, on: [:create, :update]
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      allow_nil? false
      description "The message content text"
      constraints min_length: 1, max_length: 4000
    end

    attribute :message_type, :atom do
      allow_nil? false
      description "Type of message"
      default :text
    end

    attribute :sender_id, :uuid do
      allow_nil? false
      description "ID of the message sender (user or AI agent)"
    end

    attribute :sender_type, :atom do
      allow_nil? false
      description "Type of sender"
      default :user
    end

    attribute :status, :atom do
      allow_nil? false
      description "Message status"
      default :active
    end

    attribute :reply_to_id, :uuid do
      allow_nil? true
      description "ID of message this is replying to (for threading)"
    end

    attribute :thread_root_id, :uuid do
      allow_nil? true
      description "ID of the root message in thread chain"
    end

    attribute :attachments, {:array, :map} do
      allow_nil? false
      description "File attachments and media content"
      default []
    end

    attribute :reactions, :map do
      allow_nil? false
      description "Emoji reactions and their counts"
      default %{}
    end

    attribute :mentions, {:array, :uuid} do
      allow_nil? false
      description "User IDs mentioned in message"
      default []
    end

    attribute :channel_mentions, {:array, :uuid} do
      allow_nil? false
      description "Channel IDs mentioned in message"
      default []
    end

    attribute :role_mentions, {:array, :uuid} do
      allow_nil? false
      description "Role IDs mentioned in message"
      default []
    end

    attribute :message_flags, {:array, :atom} do
      allow_nil? false
      description "Message flags and special properties"
      default []
      # Possible flags: :pinned, :announcement, :urgent, :ai_generated, :pac_command, :federated
    end

    attribute :edit_history, {:array, :map} do
      allow_nil? false
      description "History of message edits"
      default []
    end

    attribute :ai_metadata, :map do
      allow_nil? false
      description "AI-specific message metadata"

      default %{
        model_used: nil,
        confidence_score: nil,
        processing_time_ms: nil,
        token_count: nil
      }
    end

    attribute :pac_metadata, :map do
      allow_nil? false
      description "PAC coordination metadata"

      default %{
        command_type: nil,
        execution_status: nil,
        target_agents: [],
        result_data: nil
      }
    end

    attribute :federation_metadata, :map do
      allow_nil? false
      description "Cross-realm federation metadata"

      default %{
        origin_realm: nil,
        origin_user: nil,
        federation_signature: nil,
        relay_path: []
      }
    end

    attribute :search_vector, :string do
      allow_nil? true
      description "Full-text search vector (tsvector)"
    end

    attribute :thread_participant_count, :integer do
      allow_nil? false
      description "Number of unique participants in thread"
      default 0
      constraints min: 0
    end

    attribute :thread_message_count, :integer do
      allow_nil? false
      description "Number of messages in thread (if root message)"
      default 0
      constraints min: 0
    end

    attribute :last_thread_activity, :utc_datetime do
      allow_nil? true
      description "Timestamp of last activity in thread"
    end

    attribute :moderation_data, :map do
      allow_nil? false
      description "Content moderation analysis results"

      default %{
        toxicity_score: 0.0,
        spam_score: 0.0,
        flags: [],
        auto_actions: []
      }
    end

    attribute :message_metrics, :map do
      allow_nil? false
      description "Message engagement and interaction metrics"

      default %{
        view_count: 0,
        reaction_count: 0,
        reply_count: 0,
        share_count: 0
      }
    end

    attribute :ephemeral_until, :utc_datetime do
      allow_nil? true
      description "Timestamp when ephemeral message expires"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Message categorization tags"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional message metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    belongs_to :channel, Thunderline.Thunderlink.Resources.Channel do
      attribute_writable? true
      source_attribute :channel_id
      destination_attribute :id
    end

    belongs_to :community, Thunderline.Thunderlink.Resources.Community do
      source_attribute :community_id
      destination_attribute :id
    end

    belongs_to :reply_to, Thunderline.Thunderlink.Resources.Message do
      source_attribute :reply_to_id
      destination_attribute :id
    end

    belongs_to :thread_root, Thunderline.Thunderlink.Resources.Message do
      source_attribute :thread_root_id
      destination_attribute :id
    end

    has_many :replies, Thunderline.Thunderlink.Resources.Message do
      destination_attribute :reply_to_id
    end

    has_many :thread_messages, Thunderline.Thunderlink.Resources.Message do
      destination_attribute :thread_root_id
    end
  end

  # ===== PRIVATE FUNCTIONS =====
  defp generate_search_vector(content) do
    # Generate PostgreSQL tsvector for full-text search
    # This would be implemented to create proper search vectors
    content
  end

  defp get_thread_root_id(reply_to_id) do
    # Get the root message ID for threading
    # This would query the replied-to message to find its thread root
    reply_to_id
  end

  defp update_channel_message_stats(channel_id) do
    # Update channel's message count and last message timestamp
    :ok
  end

  defp update_thread_stats(thread_root_id) do
    # Update thread statistics
    :ok
  end

  defp process_message_mentions(message) do
    # Process @mentions and send notifications
    for user_id <- message.mentions do
      send_mention_notification(user_id, message)
    end
  end

  defp moderate_message_content(message) do
    # Run content moderation checks
    :ok
  end

  defp handle_special_message_type(message) do
    case message.message_type do
      :pac_command -> process_pac_command(message)
      :ai_response -> process_ai_response(message)
      :federation -> process_federation_message(message)
      _ -> :ok
    end
  end

  defp broadcast_new_message(message) do
    alias Thunderline.Thunderlink.Topics

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      Topics.channel_messages(message.channel_id),
      {:new_message, message}
    )

    if message.community_id do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        Topics.community_messages(message.community_id),
        {:new_message, message}
      )
    end
  end

  defp broadcast_message_edit(message) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      Thunderline.Thunderlink.Topics.channel_messages(message.channel_id),
      {:message_edited, message}
    )
  end

  defp broadcast_reaction_update(message, emoji, user_id, action) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      Thunderline.Thunderlink.Topics.channel_reactions(message.channel_id),
      {:reaction_update,
       %{
         message_id: message.id,
         emoji: emoji,
         user_id: user_id,
         action: action
       }}
    )
  end

  defp broadcast_message_deletion(message) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      Thunderline.Thunderlink.Topics.channel_messages(message.channel_id),
      {:message_deleted, %{message_id: message.id}}
    )
  end

  defp notify_moderation_team(message) do
    # Notify moderation team of flagged message
    :ok
  end

  defp send_mention_notification(user_id, message) do
    # Send notification to mentioned user
    :ok
  end

  defp process_pac_command(message) do
    # Process PAC coordination command
    :ok
  end

  defp process_ai_response(message) do
    # Process AI-generated response
    :ok
  end

  defp process_federation_message(message) do
    # Process federated message from another realm
    :ok
  end
end
