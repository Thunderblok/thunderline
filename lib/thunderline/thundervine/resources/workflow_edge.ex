defmodule Thunderline.Thundervine.Resources.WorkflowEdge do
  @moduledoc """
  WorkflowEdge - Causal link between two nodes within a workflow.

  Defines dependencies in the workflow DAG:
  - from_node_id: Source node (dependency)
  - to_node_id: Target node (dependent)
  - edge_type: Nature of dependency (:causal, :follows, :child)

  Edges enable:
  - Workflow replay in dependency order
  - Lineage analysis and impact tracking
  - Distributed system causality reasoning
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "dag_edges"
    repo Thunderline.Repo
  end

  graphql do
    # Renamed from workflow_edge to avoid GraphQL edge type collision
    type :workflow_link
  end

  actions do
    defaults [:create, :read]
  end

  policies do
    # Admin and system bypass
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Authenticated users can create workflow edges
    policy action_type(:create) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Read access for authenticated users
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workflow_id, :uuid, allow_nil?: false
    attribute :from_node_id, :uuid, allow_nil?: false
    attribute :to_node_id, :uuid, allow_nil?: false

    attribute :edge_type, :atom,
      allow_nil?: false,
      default: :causal,
      constraints: [one_of: [:causal, :follows, :child]]

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workflow, Thunderline.Thundervine.Resources.Workflow do
      source_attribute :workflow_id
      destination_attribute :id
    end
  end

  identities do
    identity :unique_edge, [:workflow_id, :from_node_id, :to_node_id, :edge_type]
  end
end
