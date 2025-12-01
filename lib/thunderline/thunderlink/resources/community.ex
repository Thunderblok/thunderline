defmodule Thunderline.Thunderlink.Resources.Community do
  @moduledoc """
  Community Resource - Federation Realm & Discord-Style Server

  Represents a federated community realm within the Thunderblock execution container.
  Each Community functions as a sovereign Discord-style server with PAC autonomy,
  smart contract capabilities, and swarm coordination.

  ## Core Responsibilities
  - Community governance and member management
  - Channel orchestration and message coordination
  - Role-based permissions and moderation systems
  - PAC home provisioning for community members
  - Federation socket management for cross-realm communication
  - Resource allocation and execution container provisioning

  ## Architecture Philosophy
  "Discord Server + Kubernetes Cluster + Smart Contract = Federation Realm"

  Each Community is a self-governing enclave with:
  - Execution layer for PAC agents and LiveView apps
  - Community coordination for channels, messages, roles
  - Federation bridge for cross-community interaction
  - Sovereign policy enforcement and resource management
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource],
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  import Ash.Expr

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_communities"
    repo Thunderline.Repo

    references do
      reference :cluster_node, on_delete: :delete, on_update: :update
      reference :zone_container, on_delete: :nilify, on_update: :update
      reference :channels, on_delete: :delete, on_update: :update
      reference :pac_homes, on_delete: :delete, on_update: :update
      reference :community_roles, on_delete: :delete, on_update: :update
      reference :federation_socket, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:community_slug], unique: true, name: "communities_slug_idx"
      index [:owner_id, :status], name: "communities_owner_idx"
      index [:status, :member_count], name: "communities_activity_idx"
      index [:community_type, :governance_model], name: "communities_type_idx"
      index "USING GIN (member_ids)", name: "communities_members_idx"
      index "USING GIN (moderator_ids)", name: "communities_moderators_idx"
      index "USING GIN (tags)", name: "communities_tags_idx"
      index "USING GIN (federation_config)", name: "communities_federation_idx"
      index "USING GIN (community_metrics)", name: "communities_metrics_idx"
    end

    check_constraints do
      check_constraint :valid_member_count, "member_count >= 0"
      check_constraint :valid_channel_count, "channel_count >= 0"
      check_constraint :valid_pac_home_count, "pac_home_count >= 0"
      check_constraint :owner_is_member, "owner_id = ANY(member_ids)"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "community"

    routes do
      base("/communities")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # Community management endpoints
      route(:post, "/:id/activate", :activate)
      route(:post, "/:id/add_member", :add_member)
      route(:post, "/:id/remove_member", :remove_member)
      route(:patch, "/:id/update_metrics", :update_metrics)
      route(:post, "/:id/suspend", :suspend)

      # Query endpoints removed - :read actions cannot use explicit routes
      # These actions are available through the code interface but not as REST endpoints
    end
  end

  # ===== AUTHORIZATION =====
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
    define :activate, args: []
    define :add_member, action: :add_member, args: [:id, :user_id, :role]
    define :remove_member, action: :remove_member, args: [:id, :user_id]
    define :update_metrics, args: [:id, :community_metrics, :channel_count, :pac_home_count]
    define :suspend, args: [:id]
    define :by_owner, args: [:owner_id]
    define :by_member, args: [:user_id]
    define :active_communities, action: :active_communities
    define :public_discovery, action: :public_discovery
    define :federation_enabled, action: :federation_enabled
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new community realm"

      accept [
        :community_name,
        :community_slug,
        :community_type,
        :governance_model,
        :federation_config,
        :community_config,
        :resource_limits,
        :owner_id,
        :invitation_config,
        :community_policies,
        :tags,
        :metadata,
        :cluster_node_id
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :initializing)
        |> Ash.Changeset.change_attribute(:member_ids, [
          Ash.Changeset.get_attribute(changeset, :owner_id)
        ])
        |> Ash.Changeset.change_attribute(:member_count, 1)
      end

      change after_action(fn _changeset, community, _context ->
               # Provision execution zone for community
               provision_community_zone(community)

               # Create default channels
               create_default_channels(community)

               # Initialize federation socket
               initialize_federation_socket(community)

               # Broadcast community creation
               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 Thunderline.Thunderlink.Topics.community_channels(community.id),
                 {:community_created,
                  %{
                    community_id: community.id,
                    community_slug: community.community_slug,
                    owner_id: community.owner_id
                  }}
               )

               {:ok, community}
             end)
    end

    update :update do
      description "Update community configuration"

      accept [
        :community_name,
        :community_type,
        :governance_model,
        :federation_config,
        :community_config,
        :resource_limits,
        :invitation_config,
        :community_policies,
        :tags,
        :metadata
      ]
    end

    action :activate, :struct do
      description "Activate community realm"
      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        community =
          Ash.get!(Thunderline.Thunderblock.Resources.ExecutionTenant, input.arguments.id)

        community
        |> Ash.Changeset.for_update(:internal_activate)
        |> Thunderline.Thunderblock.Domain.update!()

        # Start community services
        start_community_services(community)

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          Thunderline.Thunderlink.Topics.community_channels(community.id),
          {:community_activated,
           %{community_id: community.id, community_slug: community.community_slug}}
        )

        {:ok, community}
      end
    end

    update :internal_activate do
      description "Internal update for activate action"
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :active)
      end
    end

    action :add_member, :struct do
      description "Add member to community"

      argument :id, :uuid do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :role, :atom do
        default :member
      end

      run fn input, _context ->
        case Thunderline.Thunderblock.Domain
             |> Ash.get(Thunderline.Thunderblock.Resources.ExecutionTenant, input.arguments.id) do
          {:ok, community} ->
            {:ok, updated_community} =
              community
              |> Ash.Changeset.for_update(:_internal_add_member, %{
                user_id: input.arguments.user_id,
                role: input.arguments.role
              })
              |> Thunderline.Thunderblock.Domain.update()

            # Provision PAC home for new member
            provision_pac_home(community, input.arguments.user_id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              Thunderline.Thunderlink.Topics.community_channels(community.id),
              {:member_added, %{user_id: input.arguments.user_id, community_id: community.id}}
            )

            {:ok, updated_community}

          error ->
            error
        end
      end
    end

    update :_internal_add_member do
      description "Internal update action for adding member to community"
      accept [:member_ids, :member_count]

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :role, :atom do
        default :member
      end

      change fn changeset, context ->
        user_id = context.arguments.user_id
        role = context.arguments.role

        current_members = Ash.Changeset.get_attribute(changeset, :member_ids) || []
        current_moderators = Ash.Changeset.get_attribute(changeset, :moderator_ids) || []

        # Add to members if not already present
        updated_members =
          if user_id in current_members do
            current_members
          else
            [user_id | current_members]
          end

        # Add to moderators if role requires it
        updated_moderators =
          if role in [:moderator, :admin] and user_id not in current_moderators do
            [user_id | current_moderators]
          else
            current_moderators
          end

        changeset
        |> Ash.Changeset.change_attribute(:member_ids, updated_members)
        |> Ash.Changeset.change_attribute(:moderator_ids, updated_moderators)
        |> Ash.Changeset.change_attribute(:member_count, length(updated_members))
      end
    end

    action :remove_member, :struct do
      description "Remove member from community"

      argument :id, :uuid do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        case Thunderline.Thunderblock.Domain
             |> Ash.get(Thunderline.Thunderblock.Resources.ExecutionTenant, input.arguments.id) do
          {:ok, community} ->
            {:ok, updated_community} =
              community
              |> Ash.Changeset.for_update(:_internal_remove_member, %{
                user_id: input.arguments.user_id
              })
              |> Thunderline.Thunderblock.Domain.update()

            # Cleanup PAC home and resources
            cleanup_member_resources(community, input.arguments.user_id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              Thunderline.Thunderlink.Topics.community_channels(community.id),
              {:member_removed, %{user_id: input.arguments.user_id, community_id: community.id}}
            )

            {:ok, updated_community}

          error ->
            error
        end
      end
    end

    update :_internal_remove_member do
      description "Internal update action for removing member from community"
      accept [:member_ids, :moderator_ids, :member_count]

      argument :user_id, :uuid do
        allow_nil? false
      end

      change fn changeset, context ->
        user_id = context.arguments.user_id

        current_members = Ash.Changeset.get_attribute(changeset, :member_ids) || []
        current_moderators = Ash.Changeset.get_attribute(changeset, :moderator_ids) || []

        updated_members = List.delete(current_members, user_id)
        updated_moderators = List.delete(current_moderators, user_id)

        changeset
        |> Ash.Changeset.change_attribute(:member_ids, updated_members)
        |> Ash.Changeset.change_attribute(:moderator_ids, updated_moderators)
        |> Ash.Changeset.change_attribute(:member_count, length(updated_members))
      end
    end

    action :update_metrics do
      description "Update community activity metrics"
      argument :id, :uuid, allow_nil?: false
      argument :community_metrics, :map
      argument :channel_count, :integer
      argument :pac_home_count, :integer

      returns :struct

      run fn input, _context ->
        case Thunderline.Thunderblock.Domain
             |> Ash.get(Thunderline.Thunderblock.Resources.ExecutionTenant, input.arguments.id) do
          {:ok, community} ->
            # Calculate health score based on activity
            metrics = input.arguments.community_metrics || %{}
            health_score = calculate_community_health(metrics)

            updated_metrics = Map.put(metrics, "health_score", health_score)

            updated_community =
              community
              |> Ash.Changeset.for_update(:_update_metrics_internal, %{
                community_metrics: updated_metrics,
                channel_count: input.arguments.channel_count,
                pac_home_count: input.arguments.pac_home_count
              })
              |> Thunderline.Thunderblock.Domain.update!()

            {:ok, updated_community}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :_update_metrics_internal do
      description "Internal action to update metrics"
      accept [:community_metrics, :channel_count, :pac_home_count]
    end

    action :suspend do
      description "Suspend community operations"
      argument :id, :uuid, allow_nil?: false

      returns :struct

      run fn input, _context ->
        case Thunderline.Thunderblock.Domain
             |> Ash.get(Thunderline.Thunderblock.Resources.ExecutionTenant, input.arguments.id) do
          {:ok, community} ->
            updated_community =
              community
              |> Ash.Changeset.for_update(:_suspend_internal, %{})
              |> Thunderline.Thunderblock.Domain.update!()

            # Suspend community services
            suspend_community_services(updated_community)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              Thunderline.Thunderlink.Topics.community_channels(updated_community.id),
              {:community_suspended,
               %{
                 community_id: updated_community.id,
                 community_slug: updated_community.community_slug
               }}
            )

            {:ok, updated_community}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :_suspend_internal do
      description "Internal action to suspend community"
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :suspended)
      end
    end

    # Query actions
    read :by_owner do
      description "Get communities owned by user"

      argument :owner_id, :uuid do
        allow_nil? false
      end

      filter expr(owner_id == ^arg(:owner_id))
      prepare build(sort: :community_name)
    end

    read :by_member do
      description "Get communities where user is a member"

      argument :user_id, :uuid do
        allow_nil? false
      end

      filter expr(^arg(:user_id) in member_ids)
      prepare build(sort: :community_name)
    end

    read :active_communities do
      description "Get active communities"

      filter expr(status == :active)
      prepare build(sort: [member_count: :desc])
    end

    read :public_discovery do
      description "Get communities available for public discovery"

      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
      # prepare fn query, _context ->
      #   Ash.Query.filter(query,
      #     status == :active and
      #     fragment("(?->>'public_discovery')::boolean = true", invitation_config)
      #   )
      # end
      prepare build(sort: [])

      prepare build(sort: [member_count: :desc])
    end

    read :federation_enabled do
      description "Get communities with federation enabled"

      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
      # prepare fn query, _context ->
      #   Ash.Query.filter(query,
      #     status == :active and
      #     fragment("(?->>'federation_enabled')::boolean = true", federation_config)
      #   )
      # end
      prepare build(sort: [])

      prepare build(sort: :community_name)
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(
              load: [:cluster_node, :zone_container, :channels, :pac_homes, :federation_socket]
            )
  end

  # ===== VALIDATIONS =====
  validations do
    validate present([:community_name, :community_slug, :owner_id])
    validate {Thunderline.Thunderblock.Validations.ValidSlug, field: :community_slug}
    validate Thunderline.Thunderblock.Validations.ValidResourceLimits
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :community_name, :string do
      allow_nil? false
      description "Human-readable community name"
      constraints min_length: 1, max_length: 100
    end

    attribute :community_slug, :string do
      allow_nil? false
      description "URL-safe community identifier"
      constraints min_length: 1, max_length: 50, match: ~r/^[a-z0-9\-_]+$/
    end

    attribute :community_type, :atom do
      allow_nil? false
      description "Type of community realm"
      default :standard
    end

    attribute :governance_model, :atom do
      allow_nil? false
      description "Community governance structure"
      default :hierarchical
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current community status"
      default :initializing
    end

    attribute :federation_config, :map do
      allow_nil? false
      description "Federation settings and cross-realm policies"

      default %{
        federation_enabled: true,
        cross_realm_messaging: true,
        agent_migration: false,
        resource_sharing: false,
        trust_level: "basic"
      }
    end

    attribute :community_config, :map do
      allow_nil? false
      description "Community-specific configuration and settings"

      default %{
        max_members: 1000,
        max_channels: 50,
        max_pac_homes: 100,
        message_retention_days: 30,
        enable_voice: true,
        enable_ai_agents: true
      }
    end

    attribute :resource_limits, :map do
      allow_nil? false
      description "Execution container resource limits"

      default %{
        max_cpu_cores: 4,
        max_memory_gb: 8,
        max_storage_gb: 100,
        max_pac_processes: 50,
        max_concurrent_users: 200
      }
    end

    attribute :member_count, :integer do
      allow_nil? false
      description "Current number of community members"
      default 0
      constraints min: 0
    end

    attribute :channel_count, :integer do
      allow_nil? false
      description "Number of channels in this community"
      default 0
      constraints min: 0
    end

    attribute :pac_home_count, :integer do
      allow_nil? false
      description "Number of PAC homes provisioned"
      default 0
      constraints min: 0
    end

    attribute :owner_id, :uuid do
      allow_nil? false
      description "ID of the community owner/creator"
    end

    attribute :moderator_ids, {:array, :uuid} do
      allow_nil? false
      description "List of community moderator IDs"
      default []
    end

    attribute :member_ids, {:array, :uuid} do
      allow_nil? false
      description "List of community member IDs"
      default []
    end

    attribute :invitation_config, :map do
      allow_nil? false
      description "Community invitation and access control settings"

      default %{
        invite_required: true,
        public_discovery: false,
        approval_required: false,
        max_invites_per_member: 5
      }
    end

    attribute :community_policies, :map do
      allow_nil? false
      description "Community governance policies and rules"

      default %{
        content_moderation: "moderate",
        pac_permissions: "member_only",
        resource_sharing: "restricted",
        federation_rules: []
      }
    end

    attribute :vault_mount_id, :uuid do
      allow_nil? true
      description "Associated Thundervault mount for persistent storage"
    end

    attribute :execution_zone_id, :uuid do
      allow_nil? true
      description "Primary execution zone for this community"
    end

    attribute :federation_socket_id, :uuid do
      allow_nil? true
      description "Federation socket for cross-realm communication"
    end

    attribute :community_metrics, :map do
      allow_nil? false
      description "Community activity and health metrics"

      default %{
        daily_active_users: 0,
        weekly_message_count: 0,
        pac_activity_score: 0.0,
        health_score: 1.0
      }
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Community categorization tags"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional community metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    belongs_to :cluster_node, Thunderline.Thunderblock.Resources.ClusterNode do
      source_attribute :cluster_node_id
      destination_attribute :id
    end

    belongs_to :zone_container, Thunderline.Thunderblock.Resources.ZoneContainer do
      source_attribute :execution_zone_id
      destination_attribute :id
    end

    has_many :channels, Thunderline.Thunderlink.Resources.Channel do
      destination_attribute :community_id
    end

    has_many :pac_homes, Thunderline.Thunderblock.Resources.PACHome do
      destination_attribute :community_id
    end

    has_many :community_roles, Thunderline.Thunderlink.Resources.Role do
      destination_attribute :community_id
    end

    has_one :federation_socket, Thunderline.Thunderlink.Resources.FederationSocket do
      destination_attribute :community_id
    end

    has_many :system_events, Thunderline.Thunderblock.Resources.SystemEvent do
      destination_attribute :target_resource_id
      filter expr(target_resource_type == :community)
    end
  end

  # ===== OBAN CONFIGURATION =====
  # oban do
  #   # Community health monitoring
  #   trigger :community_health_check do
  #     action :update_metrics
  #     schedule "*/300 * * * * *"  # Every 5 minutes
  #     where expr(status == :active)
  #   end

  #   # Member activity tracking
  #   trigger :activity_tracking do
  #     action :active_communities
  #     schedule "0 */6 * * *"  # Every 6 hours
  #   end
  # end

  # ===== IDENTITIES =====
  identities do
    identity :unique_community_slug, [:community_slug]
  end

  # ===== PRIVATE FUNCTIONS =====
  defp provision_community_zone(community) do
    # Create dedicated execution zone for community
    {:ok, zone} =
      Thunderline.Thunderblock.Resources.ZoneContainer.create(%{
        zone_name: "community_#{community.community_slug}",
        zone_type: :community,
        cluster_node_id: community.cluster_node_id,
        capacity_config: community.resource_limits
      })

    # Update community with zone reference
    Thunderline.Thunderlink.Resources.Community
    |> Ash.Changeset.for_update(:update, community, %{execution_zone_id: zone.id})
    |> Thunderline.Thunderlink.Domain.update()
  end

  defp create_default_channels(_community) do
    # Create default #general and #announcements channels
    # Implementation would go here
    :ok
  end

  defp initialize_federation_socket(_community) do
    # Create federation socket for cross-realm communication
    # Implementation would go here
    :ok
  end

  defp start_community_services(_community) do
    # Start community-specific services and processes
    :ok
  end

  defp suspend_community_services(_community) do
    # Suspend community services while preserving state
    :ok
  end

  defp provision_pac_home(_community, _user_id) do
    # Provision PAC home for new community member
    :ok
  end

  defp cleanup_member_resources(_community, _user_id) do
    # Clean up PAC home and other member resources
    :ok
  end

  defp calculate_community_health(metrics) do
    # Calculate community health score based on activity metrics
    daily_users = Map.get(metrics, "daily_active_users", 0)
    message_count = Map.get(metrics, "weekly_message_count", 0)
    pac_activity = Map.get(metrics, "pac_activity_score", 0.0)

    # Simple health calculation - can be made more sophisticated
    base_health = 0.5
    user_factor = min(0.3, daily_users / 100.0)
    message_factor = min(0.2, message_count / 1000.0)

    base_health + user_factor + message_factor + pac_activity * 0.1
  end
end
