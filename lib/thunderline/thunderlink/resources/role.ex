defmodule Thunderline.Thunderlink.Resources.Role do
  @moduledoc """
  Role Resource - Permissions & Moderation Hierarchy

  Represents roles within Community realms, providing Thunderblock server permission
  hierarchies, moderation capabilities, and access control for channels,
  messages, and community features within the federation realm architecture.

  ## Core Responsibilities
  - Role hierarchy and permission inheritance
  - Channel-specific permission overrides
  - Member role assignment and management
  - Moderation permission delegation
  - Federation role synchronization
  - Permission enforcement and validation

  ## Role Philosophy
  "Every voice has its authority. Every authority has its boundaries."

  Roles define the social and technical boundaries within Community realms,
  enabling self-governance while maintaining federation sovereignty.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban]

  import Ash.Resource.Change.Builtins

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_roles"
    repo Thunderline.Repo

    references do
      reference :community, on_delete: :delete, on_update: :update
      reference :system_events, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:role_slug, :community_id], unique: true, name: "roles_slug_community_idx"
      index [:community_id, :position], name: "roles_community_position_idx"
      index [:community_id, :role_type], name: "roles_community_type_idx"
      index [:position, :role_type], name: "roles_hierarchy_idx"
      index [:auto_assign, :community_id], name: "roles_auto_assign_idx"
      index [:mentionable], name: "roles_mentionable_idx"
      index "USING GIN (member_ids)", name: "roles_members_idx"
      index "USING GIN (permissions)", name: "roles_permissions_idx"
      index "USING GIN (channel_overrides)", name: "roles_overrides_idx"
      index "USING GIN (role_flags)", name: "roles_flags_idx"
      index "USING GIN (tags)", name: "roles_tags_idx"
    end

    check_constraints do
      check_constraint :valid_position, "position >= 0 AND position <= 1000"
      check_constraint :valid_member_count, "member_count >= 0"
      check_constraint :valid_color_format, "color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "role"

    routes do
      base("/roles")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # Role management endpoints
      post(:assign_to_member, route: "/:id/assign")
      post(:remove_from_member, route: "/:id/remove")
      post(:update_permissions, route: "/:id/update_permissions")
      post(:set_channel_override, route: "/:id/channel_override")
      post(:timeout_role, route: "/:id/timeout")
      post(:clear_timeout, route: "/:id/clear_timeout")

      # Query endpoints
      get :by_community, route: "/community/:community_id"
      get :by_type, route: "/type/:role_type"
      get :by_member, route: "/member/:user_id"
      get :with_permission, route: "/permission/:permission"
      get :mentionable_roles, route: "/mentionable"
      get :auto_assign_roles, route: "/auto_assign"
      get :moderation_roles, route: "/moderation"
      get :federation_roles, route: "/federation"
      get :expiring_roles, route: "/expiring/:days_ahead"

      # Cleanup endpoints
      delete(:cleanup_expired, route: "/cleanup_expired")
    end
  end

  # ===== POLICIES =====
  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end
  #
  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :update
    define :assign_to_member, args: [:user_id, :assigned_by]
    define :remove_from_member, args: [:user_id, :removed_by]
    define :update_permissions, args: [:permissions, :updated_by]
    define :set_channel_override, args: [:channel_id, :permission, :value]
    define :timeout_role, args: [:timeout_until, :reason]
    define :clear_timeout, args: []
    define :by_community, args: [:community_id]
    define :by_type, args: [:role_type]
    define :by_member, args: [:user_id]
    define :with_permission, args: [:permission]
    define :mentionable_roles, action: :mentionable_roles
    define :auto_assign_roles, action: :auto_assign_roles
    define :moderation_roles, action: :moderation_roles
    define :federation_roles, action: :federation_roles
    define :expiring_roles, args: [:days_ahead]
    define :cleanup_expired, action: :cleanup_expired
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new role in community"

      accept [
        :role_name,
        :role_slug,
        :role_type,
        :position,
        :color,
        :hoist,
        :mentionable,
        :permissions,
        :channel_overrides,
        :restrictions,
        :auto_assign,
        :requires_approval,
        :created_by,
        :moderation_config,
        :federation_config,
        :role_flags,
        :expiry_config,
        :tags,
        :metadata,
        :community_id
      ]

      change fn changeset, _context ->
        # Ensure role position doesn't conflict
        position = Ash.Changeset.get_attribute(changeset, :position) || 0
        community_id = Ash.Changeset.get_attribute(changeset, :community_id)

        # Auto-adjust position if conflicts exist
        adjusted_position = find_available_position(community_id, position)

        changeset
        |> Ash.Changeset.change_attribute(:position, adjusted_position)
      end

      change after_action(fn _changeset, role, _context ->
               # Create default channel overrides if needed
               initialize_channel_overrides(role)

               # Set up auto-assignment if enabled
               if role.auto_assign do
                 setup_auto_assignment(role)
               end

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 Thunderline.Thunderlink.Topics.community_channels(role.community_id),
                 {:role_created,
                  %{
                    role_id: role.id,
                    role_name: role.role_name,
                    role_type: role.role_type,
                    position: role.position
                  }}
               )

               {:ok, role}
             end)
    end

    update :update do
      description "Update role configuration"

      accept [
        :role_name,
        :role_type,
        :position,
        :color,
        :hoist,
        :mentionable,
        :permissions,
        :channel_overrides,
        :restrictions,
        :moderation_config,
        :federation_config,
        :role_flags,
        :expiry_config,
        :tags,
        :metadata
      ]
    end

    action :assign_to_member, :struct do
      description "Assign role to community member"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :assigned_by, :uuid do
        allow_nil? false
      end

      run fn input, context ->
        role = input
        user_id = input.arguments.user_id
        assigned_by = input.arguments.assigned_by

        current_members = role.member_ids || []

        # Add to members if not already present
        updated_members =
          if user_id in current_members do
            current_members
          else
            [user_id | current_members]
          end

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{
            member_ids: updated_members,
            member_count: length(updated_members)
          })
          |> Ash.update!()

        # Log role assignment
        create_role_assignment_event(updated_role, user_id, assigned_by, :assigned)

        # Apply role permissions to user
        apply_role_permissions(updated_role, user_id)

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          Thunderline.Thunderlink.Topics.community_channels(updated_role.community_id),
          {:role_assigned,
           %{
             role_id: updated_role.id,
             user_id: user_id,
             assigned_by: assigned_by
           }}
        )

        {:ok, updated_role}
      end
    end

    action :remove_from_member, :struct do
      description "Remove role from community member"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :removed_by, :uuid do
        allow_nil? false
      end

      run fn input, context ->
        role = input
        user_id = input.arguments.user_id
        removed_by = input.arguments.removed_by

        current_members = role.member_ids || []
        updated_members = List.delete(current_members, user_id)

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{
            member_ids: updated_members,
            member_count: length(updated_members)
          })
          |> Ash.update!()

        # Log role removal
        create_role_assignment_event(updated_role, user_id, removed_by, :removed)

        # Remove role permissions from user
        remove_role_permissions(updated_role, user_id)

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          Thunderline.Thunderlink.Topics.community_channels(updated_role.community_id),
          {:role_removed,
           %{
             role_id: updated_role.id,
             user_id: user_id,
             removed_by: removed_by
           }}
        )

        {:ok, updated_role}
      end
    end

    action :update_permissions, :struct do
      description "Update role permissions"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      argument :permissions, :map do
        allow_nil? false
      end

      argument :updated_by, :uuid do
        allow_nil? false
      end

      run fn input, context ->
        role = input
        permissions = input.arguments.permissions
        updated_by = input.arguments.updated_by

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{permissions: permissions})
          |> Ash.update!()

        # Log permission changes
        create_permission_change_event(updated_role, updated_by)

        # Re-apply permissions to all role members
        reapply_permissions_to_members(updated_role)

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          Thunderline.Thunderlink.Topics.community_channels(updated_role.community_id),
          {:role_permissions_updated,
           %{
             role_id: updated_role.id,
             updated_by: updated_by
           }}
        )

        {:ok, updated_role}
      end
    end

    action :set_channel_override, :struct do
      description "Set channel-specific permission override"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      argument :channel_id, :uuid do
        allow_nil? false
      end

      argument :permission, :string do
        allow_nil? false
      end

      argument :value, :atom do
        allow_nil? false
        constraints one_of: [:allow, :deny, :inherit]
      end

      run fn input, context ->
        role = input
        channel_id = input.arguments.channel_id
        permission = input.arguments.permission
        value = input.arguments.value

        current_overrides = role.channel_overrides || %{}
        channel_overrides = Map.get(current_overrides, channel_id, %{})

        updated_channel_overrides = Map.put(channel_overrides, permission, value)
        updated_overrides = Map.put(current_overrides, channel_id, updated_channel_overrides)

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{channel_overrides: updated_overrides})
          |> Ash.update!()

        {:ok, updated_role}
      end
    end

    action :timeout_role, :struct do
      description "Apply timeout restrictions to role"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      argument :timeout_until, :utc_datetime do
        allow_nil? false
      end

      argument :reason, :string, allow_nil?: true

      run fn input, context ->
        role = input
        timeout_until = input.arguments.timeout_until
        reason = input.arguments.reason

        current_restrictions = role.restrictions || %{}
        updated_restrictions = Map.put(current_restrictions, "timeout_until", timeout_until)

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{restrictions: updated_restrictions})
          |> Ash.update!()

        # Apply timeout to all role members
        apply_timeout_to_members(updated_role, timeout_until, reason)

        {:ok, updated_role}
      end
    end

    action :clear_timeout, :struct do
      description "Clear timeout restrictions from role"
      constraints instance_of: Thunderline.Thunderlink.Resources.Role

      run fn input, context ->
        role = input
        current_restrictions = role.restrictions || %{}
        updated_restrictions = Map.put(current_restrictions, "timeout_until", nil)

        updated_role =
          role
          |> Ash.Changeset.for_update(:update, %{restrictions: updated_restrictions})
          |> Ash.update!()

        {:ok, updated_role}
      end
    end

    # Query actions
    read :by_community do
      description "Get roles for a community"

      argument :community_id, :uuid do
        allow_nil? false
      end

      filter expr(community_id == ^arg(:community_id))

      # sort [position: :desc, role_name: :asc]  # TODO: Remove sort from filter - not supported in Ash 3.x
    end

    read :by_type do
      description "Get roles by type"

      argument :role_type, :atom do
        allow_nil? false
      end

      filter expr(role_type == ^arg(:role_type))
    end

    read :by_member do
      description "Get roles assigned to a specific member"

      argument :user_id, :uuid do
        allow_nil? false
      end

      filter expr(^arg(:user_id) in member_ids)
    end

    read :with_permission do
      description "Get roles with specific permission"

      argument :permission, :string do
        allow_nil? false
      end

      filter expr(exists(permissions, ^arg(:permission)))
    end

    read :mentionable_roles do
      description "Get roles that can be mentioned"

      filter expr(mentionable == true)
    end

    read :auto_assign_roles do
      description "Get roles that auto-assign to new members"

      filter expr(auto_assign == true)
    end

    read :moderation_roles do
      description "Get roles with moderation permissions"

      # TODO: Fix fragment expression for permissions checking
      # prepare fn query, _context ->
      #   Ash.Query.filter(query,
      #     fragment("(?->>?)::boolean = true OR (?->>?)::boolean = true OR (?->>?)::boolean = true",
      #       permissions, "kick_members",
      #       permissions, "ban_members",
      #       permissions, "manage_messages"
      #     )
      #   )
      # end
    end

    read :federation_roles do
      description "Get roles with federation permissions"

      # TODO: Fix fragment expression for federation_config checking
      prepare fn query, _context ->
        query
        |> Ash.Query.sort(position: :desc)
      end
    end

    read :expiring_roles do
      description "Get roles that are expiring soon"

      argument :days_ahead, :integer, default: 7

      # TODO: Fix fragment expression for expiry_config checking
      prepare fn query, _context ->
        query
        |> Ash.Query.sort([:inserted_at])
      end
    end

    # Cleanup action for expired roles
    destroy :cleanup_expired do
      description "Remove expired roles"

      # TODO: Fix fragment expression for expiry filtering
      # filter expr(
      #   fragment("(?->>?)::boolean = true", expiry_config, "expires") and
      #   fragment("(?->>?)::boolean = false", expiry_config, "auto_renew") and
      #   inserted_at < ago(fragment("(?->>?)::integer", expiry_config, "duration_days"), :day)
      # )

      change after_action(fn _changeset, roles, _context ->
               # Broadcast role expiration cleanup
               for role <- roles do
                 Phoenix.PubSub.broadcast(
                   Thunderline.PubSub,
                   Thunderline.Thunderlink.Topics.community_channels(role.community_id),
                   {:role_expired, %{role_id: role.id, role_name: role.role_name}}
                 )
               end

               {:ok, roles}
             end)
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(load: [:community, :system_events])
  end

  # ===== VALIDATIONS =====
  validations do
    validate present([:role_name, :role_slug, :community_id, :created_by])
    # TODO: Fix validation syntax for Ash 3.x
    # validate {Thunderblock.Validations, :valid_role_slug}, on: [:create, :update]
    # validate {Thunderblock.Validations, :permissions_structure}, on: [:create, :update]
    # validate {Thunderblock.Validations, :channel_overrides_structure}, on: [:create, :update]
    # validate {Thunderblock.Validations, :role_hierarchy_valid}, on: [:create, :update]
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :role_name, :string do
      allow_nil? false
      description "Human-readable role name"
      constraints min_length: 1, max_length: 100
    end

    attribute :role_slug, :string do
      allow_nil? false
      description "URL-safe role identifier"
      constraints min_length: 1, max_length: 50, match: ~r/^[a-z0-9\-_]+$/
    end

    attribute :role_type, :atom do
      allow_nil? false
      description "Type of role functionality"
      default :member
      constraints one_of: [:owner, :admin, :moderator, :member, :guest, :bot, :system]
    end

    attribute :position, :integer do
      allow_nil? false
      description "Role hierarchy position (higher = more authority)"
      default 0
      constraints min: 0, max: 1000
    end

    attribute :color, :string do
      allow_nil? true
      description "Role display color (hex code)"
      constraints match: ~r/^#[0-9A-Fa-f]{6}$/
    end

    attribute :hoist, :boolean do
      allow_nil? false
      description "Display role separately in member list"
      default false
    end

    attribute :mentionable, :boolean do
      allow_nil? false
      description "Allow role to be mentioned (@role)"
      default true
    end

    attribute :permissions, :map do
      allow_nil? false
      description "Base role permissions"

      default %{
        # Community permissions
        "view_community" => true,
        "send_messages" => true,
        "read_message_history" => true,
        "use_voice_activity" => false,
        "priority_speaker" => false,

        # Channel management
        "manage_channels" => false,
        "manage_messages" => false,
        "manage_roles" => false,

        # Member management
        "kick_members" => false,
        "ban_members" => false,
        "manage_members" => false,

        # Community management
        "manage_community" => false,
        "view_audit_log" => false,
        "administrator" => false,

        # AI and PAC permissions
        "use_ai_agents" => true,
        "manage_ai_agents" => false,
        "use_pac_home" => true,
        "manage_pac_homes" => false,

        # Federation permissions
        "federation_messaging" => true,
        "manage_federation" => false
      }
    end

    attribute :channel_overrides, :map do
      allow_nil? false
      description "Channel-specific permission overrides"
      default %{}
      # Format: %{channel_id => %{permission => allow/deny/inherit}}
    end

    attribute :restrictions, :map do
      allow_nil? false
      description "Role restrictions and limitations"

      default %{
        "timeout_until" => nil,
        "rate_limit_factor" => 1.0,
        "max_message_length" => nil,
        "allowed_channels" => [],
        "denied_channels" => []
      }
    end

    attribute :member_count, :integer do
      allow_nil? false
      description "Number of members with this role"
      default 0
      constraints min: 0
    end

    attribute :member_ids, {:array, :uuid} do
      allow_nil? false
      description "List of member IDs with this role"
      default []
    end

    attribute :auto_assign, :boolean do
      allow_nil? false
      description "Automatically assign to new members"
      default false
    end

    attribute :requires_approval, :boolean do
      allow_nil? false
      description "Role assignment requires approval"
      default false
    end

    attribute :created_by, :uuid do
      allow_nil? false
      description "ID of user who created the role"
    end

    attribute :moderation_config, :map do
      allow_nil? false
      description "Moderation-specific configuration"

      default %{
        "can_timeout" => false,
        "can_delete_messages" => false,
        "can_manage_reactions" => false,
        "can_manage_threads" => false,

        # seconds
        "timeout_duration_max" => 3600,
        "bulk_delete_limit" => 0
      }
    end

    attribute :federation_config, :map do
      allow_nil? false
      description "Federation-specific role configuration"

      default %{
        "cross_realm_visibility" => false,
        "external_role_sync" => false,

        # none, basic, elevated, sovereign
        "federation_authority" => "none",
        "trust_level" => "local"
      }
    end

    attribute :role_flags, {:array, :atom} do
      allow_nil? false
      description "Special role flags and properties"
      default []
      # Possible flags: :system, :protected, :everyone, :verified, :premium, :beta_tester
    end

    attribute :expiry_config, :map do
      allow_nil? false
      description "Role expiration and renewal settings"

      default %{
        "expires" => false,
        "duration_days" => nil,
        "auto_renew" => false,
        "renewal_conditions" => []
      }
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Role categorization tags"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional role metadata"
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

    has_many :system_events, Thunderblock.Resources.SystemEvent do
      destination_attribute :target_resource_id
      filter expr(target_resource_type == :role)
    end

    # Note: In a full implementation, would have many-to-many with users
    # many_to_many :users, Thunderbit.Resources.User do
    #   through Thunderblock.Resources.UserRole
    # end
  end

  # ===== OBAN CONFIGURATION =====
  # TODO: Fix trigger syntax for AshOban 3.x
  # oban do
  #   # Cleanup expired roles
  #   trigger :cleanup_expired_roles do
  #     action :cleanup_expired
  #     schedule "0 2 * * *"  # Daily at 2 AM
  #   end
  # end

  # TODO: Fix remaining trigger syntax for AshOban 3.x
  # # Process role assignment queue
  # trigger :process_role_assignments do
  #   action :auto_assign_roles
  #   schedule "*/300 * * * * *"  # Every 5 minutes
  # end

  # # Update role member counts
  # trigger :update_member_counts do
  #   action :by_community
  #   schedule "0 */6 * * *"  # Every 6 hours
  # end

  # ===== IDENTITIES =====
  identities do
    identity :unique_role_in_community, [:role_slug, :community_id]
  end

  # ===== PRIVATE FUNCTIONS =====
  defp find_available_position(_community_id, desired_position) do
    # Find available position in role hierarchy
    # This would query existing roles and find a free position
    desired_position
  end

  defp initialize_channel_overrides(_role) do
    # Set up default channel overrides based on role type
    :ok
  end

  defp setup_auto_assignment(_role) do
    # Configure auto-assignment for new members
    :ok
  end

  defp create_role_assignment_event(_role, _user_id, _actor_id, _action) do
    # Create system event for role assignment/removal
    :ok
  end

  defp apply_role_permissions(_role, _user_id) do
    # Apply role permissions to user's effective permissions
    :ok
  end

  defp remove_role_permissions(_role, _user_id) do
    # Remove role permissions from user's effective permissions
    :ok
  end

  defp create_permission_change_event(_role, _updated_by) do
    # Log permission changes for audit trail
    :ok
  end

  defp reapply_permissions_to_members(role) do
    # Re-apply permissions to all members when role permissions change
    for user_id <- role.member_ids do
      apply_role_permissions(role, user_id)
    end
  end

  defp apply_timeout_to_members(_role, _timeout_until, _reason) do
    # Apply timeout restrictions to all role members
    :ok
  end
end
