defmodule Thunderline.Thundergate.Resources.AuditLog do
  @moduledoc """
  AuditLog Resource - Migrated from Thundervault

  System Audit Trail & Change Tracking for observability and compliance.
  Now properly located in Thundereye for system monitoring and diagnostics.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban]

  import Ash.Resource.Change.Builtins

  postgres do
    table "thundereye_audit_logs"
    repo Thunderline.Repo

    custom_indexes do
      index [:target_resource_type, :target_resource_id], name: "audit_logs_target_idx"
      index [:actor_id, :action_type], name: "audit_logs_actor_idx"
      index [:inserted_at], name: "audit_logs_time_idx"
    end
  end

  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end
  #
  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  code_interface do
    define :log_action
    define :by_user, args: [:user_id]
    define :by_resource, args: [:resource_type, :resource_id]
    define :archive_old_logs, action: :archive_old_logs
  end

  actions do
    defaults [:read]

    create :log_action do
      description "Create audit log entry"

      accept [
        :action_type,
        :target_resource_type,
        :target_resource_id,
        :actor_id,
        :actor_type,
        :changes,
        :metadata
      ]
    end

    read :by_user do
      description "Get audit logs for specific user"
      argument :user_id, :uuid, allow_nil?: false
      filter expr(actor_id == ^arg(:user_id))
    end

    read :by_resource do
      description "Get audit logs for specific resource"
      argument :resource_type, :atom, allow_nil?: false
      argument :resource_id, :uuid, allow_nil?: false

      filter expr(
               target_resource_type == ^arg(:resource_type) and
                 target_resource_id == ^arg(:resource_id)
             )
    end

    destroy :archive_old_logs do
      description "Archive old audit logs"
      filter expr(inserted_at < ago(365, :day))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action_type, :atom do
      allow_nil? false
      description "Type of action performed"
      constraints one_of: [:create, :read, :update, :delete, :login, :logout, :permission_change]
    end

    attribute :target_resource_type, :atom do
      allow_nil? false
      description "Type of resource affected"
      constraints one_of: [:memory_record, :embedding_vector, :knowledge_node, :user, :user_token]
    end

    attribute :target_resource_id, :uuid do
      allow_nil? true
      description "ID of the affected resource"
    end

    attribute :actor_id, :uuid do
      allow_nil? true
      description "ID of the user/system performing the action"
    end

    attribute :actor_type, :atom do
      allow_nil? false
      description "Type of actor"
      default :user
      constraints one_of: [:user, :system, :api, :automated]
    end

    attribute :changes, :map do
      allow_nil? false
      description "Details of changes made"
      default %{}
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional audit metadata"
      default %{}
    end

    create_timestamp :inserted_at
  end
end
