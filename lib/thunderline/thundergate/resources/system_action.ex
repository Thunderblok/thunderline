defmodule Thunderline.Thundergate.Resources.SystemAction do
  @moduledoc """
  SystemAction Resource - Migrated from Thundervault

  System Operation Tracking for monitoring and debugging purposes.
  Now properly located in ThunderGate for security monitoring and access control.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  postgres do
    table "thundereye_system_actions"
    repo Thunderline.Repo

    custom_indexes do
      index [:domain, :status], name: "system_actions_domain_status_idx"
      index [:action_name, :inserted_at], name: "system_actions_name_time_idx"
      index [:status, :inserted_at], name: "system_actions_status_time_idx"
    end
  end

  code_interface do
    define :record
    define :complete, args: [:result_data, :duration_ms]
    define :fail, args: [:error_data, :duration_ms]
    define :archive_old_actions, action: :archive_old_actions
  end

  actions do
    defaults [:read]

    create :record do
      description "Record a system action"
      accept [:action_name, :domain, :status, :result_data, :error_data, :duration_ms, :metadata]
    end

    update :complete do
      # Complete a system action with results
      accept [:status, :result_data, :duration_ms]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :completed)
      end
    end

    update :fail do
      description "Mark action as failed"
      accept [:status, :error_data, :duration_ms]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :failed)
      end
    end

    destroy :archive_old_actions do
      description "Archive old system actions"
      filter expr(inserted_at < ago(30, :day))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action_name, :string do
      allow_nil? false
      description "Name of the system action"
      constraints max_length: 200
    end

    attribute :domain, :string do
      allow_nil? false
      description "Thunderline domain executing the action"
      constraints min_length: 1, max_length: 50
    end

    attribute :status, :atom do
      allow_nil? false
      description "Action execution status"
      default :running
      constraints one_of: [:pending, :running, :completed, :failed, :timeout]
    end

    attribute :result_data, :map do
      allow_nil? false
      description "Action execution results"
      default %{}
    end

    attribute :error_data, :map do
      allow_nil? true
      description "Error information if action failed"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      description "Action execution duration in milliseconds"
      constraints min: 0
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional action metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
