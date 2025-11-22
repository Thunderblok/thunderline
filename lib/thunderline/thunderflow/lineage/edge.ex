defmodule Thunderline.Lineage.Edge do
  @moduledoc """
  Directed provenance edge between artifacts (raw→feature→decision→label).

  Domain Placement: Thunderflow (provenance & dataflow graph) providing cross-stage
  traceability while avoiding orchestration coupling in Thunderbolt.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lineage_edges"
    repo Thunderline.Repo
  end

  code_interface do
    define :connect
    define :read
  end

  actions do
    defaults [:read]

    create :connect do
      accept [:from_id, :to_id, :edge_type, :day_bucket]
    end
  end

  policies do
    # Create-specific: Tenant isolation enforced
    policy [action(:connect), action_type(:create)] do
      authorize_if expr(not is_nil(^actor(:tenant_id)))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end

    # Read: Tenant isolation enforced
    policy action(:read) do
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

    attribute :tenant_id, :uuid,
      allow_nil?: false,
      description: "Owning tenant for both from/to artifacts"

    attribute :from_id, :uuid, allow_nil?: false
    attribute :to_id, :uuid, allow_nil?: false
    attribute :edge_type, :string, allow_nil?: false
    attribute :day_bucket, :date, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
