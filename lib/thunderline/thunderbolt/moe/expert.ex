defmodule Thunderline.MoE.Expert do
  @moduledoc """
  Model expert metadata for MoE routing & lifecycle.

  Domain Placement: Thunderbolt (compute/orchestration). Experts are selectable compute
  units used by DecisionTrace routing logic.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "experts"
    repo Thunderline.Repo
  end

  code_interface do
    define :register
    define :update_metrics
    define :read
  end

  actions do
    defaults [:read]

    create :register do
      # Include :tenant_id to satisfy allow_nil?: false constraint on tenant-scoped resource
      accept [
        :tenant_id,
        :name,
        :version,
        :status,
        :latency_budget_ms,
        :metrics,
        :model_artifact_ref
      ]
    end

    update :update_metrics do
      accept [:metrics, :status]
    end
  end

  policies do
    # Create-specific: avoid filter on creates; rely on multitenancy/inputs & system override
    policy [action(:register), action_type(:create)] do
      authorize_if always()
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end

    # Read/Update: enforce same-tenant
    policy action([:update_metrics, :read]) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false, description: "Owning tenant for isolation"
    attribute :name, :string, allow_nil?: false
    attribute :version, :string, allow_nil?: false

    attribute :status, :atom,
      allow_nil?: false,
      default: :active,
      constraints: [one_of: [:active, :shadow, :retired, :error]]

    attribute :latency_budget_ms, :integer
    attribute :metrics, :map, allow_nil?: false, default: %{}
    attribute :model_artifact_ref, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
