defmodule Thunderline.Thunderblock.Resources.RetentionPolicy do
  @moduledoc """
  Retention and garbage-collection policy definitions for ThunderBlock assets.

  Policies can be scoped globally or to specific tenants/projects/datasets and
  define how long data should be retained, whether older versions should be
  archived, and what action to take when data ages out.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  alias Ash.Changeset
  import Ash.Resource.Change.Builtins

  postgres do
    table "thunderblock_retention_policies"
    repo Thunderline.Repo
  end

  @gc_actions [:delete, :archive, :compact]
  @scope_types [:global, :tenant, :project, :dataset]

  actions do
    defaults [:read, :destroy]

    create :define do
      description "Define or upsert a retention policy"
      primary? true
      accept [:resource, :scope_type, :scope_id, :ttl_seconds, :keep_versions, :action, :grace_seconds, :metadata, :is_active, :notes]
    end

    update :configure do
      description "Update retention policy parameters"
      accept [:ttl_seconds, :keep_versions, :action, :grace_seconds, :metadata, :is_active, :notes]
    end

    read :active do
      description "Fetch active policies"
      filter expr(is_active == true)
    end

    read :for_resource do
      description "Fetch policies for a given resource and scope"
      argument :resource, :atom, allow_nil?: false
      argument :scope_type, :atom, default: :global
      argument :scope_id, :uuid

      filter expr(resource == ^arg(:resource) and scope_type == ^arg(:scope_type) and scope_id == ^arg(:scope_id))
    end
  end

  changes do
    change fn changeset, _context ->
      scope_type = Changeset.get_attribute(changeset, :scope_type) || :global
      scope_id = Changeset.get_attribute(changeset, :scope_id)

      if scope_type != :global and is_nil(scope_id) do
        Changeset.add_error(changeset, field: :scope_id, message: "scope_id required for scoped policies")
      else
        changeset
      end
    end
  end

  validations do
    validate present([:resource])

    validate compare(:ttl_seconds, greater_than: 0) do
      where present(:ttl_seconds)
      message "ttl_seconds must be positive when present"
    end

    validate compare(:grace_seconds, greater_than_or_equal_to: 0) do
      where present(:grace_seconds)
      message "grace_seconds must be zero or positive"
    end

    validate compare(:keep_versions, greater_than_or_equal_to: 0) do
      where present(:keep_versions)
      message "keep_versions cannot be negative"
    end

  end

  attributes do
    uuid_primary_key :id

    attribute :resource, :atom do
      description "Target resource surface (e.g., :event_log, :artifact, :vector, :job)"
      allow_nil? false
    end

    attribute :scope_type, :atom do
      description "Scope of the policy"
      default :global
      constraints one_of: @scope_types
    end

    attribute :scope_id, :uuid do
      description "Scoped identifier (tenant/project/dataset)"
      allow_nil? true
    end

    attribute :ttl_seconds, :integer do
      description "Time-to-live in seconds before policy action triggers"
    end

    attribute :keep_versions, :integer do
      description "How many historical versions to retain (if applicable)"
    end

    attribute :action, :atom do
      description "Retention action to perform"
      constraints one_of: @gc_actions
      default :delete
    end

    attribute :grace_seconds, :integer do
      description "Additional grace period in seconds before executing action"
      default 0
    end

    attribute :metadata, :map do
      description "Free-form metadata for downstream processors"
      default %{}
    end

    attribute :notes, :string do
      description "Operator notes or justification for the policy"
    end

    attribute :is_active, :boolean do
      description "Soft toggle to disable a policy without deleting it"
      default true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :policy_scope, [:resource, :scope_type, :scope_id]
  end
end
