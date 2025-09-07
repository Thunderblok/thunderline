defmodule Thunderline.MoE.DecisionTrace do
  @moduledoc """
  Captures routing & action provenance for a single feature window decision.

  Domain Placement: Thunderbolt (orchestration, routing, optimization) – this is *after*
  feature construction (Thunderflow) and before external action execution.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "decision_traces"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :feature_window_id, :uuid, allow_nil?: false
    attribute :router_version, :string, allow_nil?: false
    attribute :gate_scores, :map, allow_nil?: false, default: %{}
    attribute :selected_experts, :map, allow_nil?: false, default: %{}
    attribute :actions, :map, allow_nil?: false, default: %{}
    attribute :blended_action, :map
    attribute :pnl_snapshot, :map
    attribute :risk_flags, :map, allow_nil?: false, default: %{}
    attribute :behavior_embedding, :binary
    attribute :hash, :binary, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
    create :record do
      accept [:tenant_id, :feature_window_id, :router_version, :gate_scores, :selected_experts, :actions, :blended_action, :pnl_snapshot, :risk_flags, :behavior_embedding, :hash]
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  policies do
    # Create-specific: avoid filters on create, use changing_attributes
    policy [action(:record), action_type(:create)] do
      authorize_if changing_attributes(tenant_id: [equals_actor: :tenant_id])
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end

    # Reads: enforce tenant match via filter expr
    policy action(:read) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end
  end

  code_interface do
    define :record
    define :read
  end
end
