defmodule Thunderline.Thundervine.Resources.WorkflowSnapshot do
  @moduledoc """
  WorkflowSnapshot - Immutable serialized representation of a sealed workflow.

  Captures complete workflow state for replay and analysis:
  - node_order: Ordered list of node IDs (execution sequence)
  - nodes_payload: Map of node_id → payload data
  - edges: List of edge maps (dependency graph)
  - embedding_vector: Optional pgvector for semantic search
  - metadata: Additional context and tags

  Snapshots enable:
  - Deterministic workflow replay
  - Historical analysis and auditing
  - Semantic similarity search across workflows
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "dag_snapshots"
    repo Thunderline.Repo
  end

  graphql do
    type :workflow_snapshot
  end

  actions do
    defaults [:read]

    create :capture do
      accept [
        :workflow_id,
        :version,
        :node_order,
        :nodes_payload,
        :edges,
        :metadata,
        :embedding_vector
      ]
    end
  end

  policies do
    # Admin and system bypass
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Authenticated users can capture snapshots
    policy action(:capture) do
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
    attribute :version, :integer, allow_nil?: false, default: 1
    attribute :node_order, {:array, :uuid}, allow_nil?: false, default: []
    attribute :nodes_payload, :map, allow_nil?: false, default: %{}
    attribute :edges, {:array, :map}, allow_nil?: false, default: []

    attribute :embedding_vector, {:array, :float},
      allow_nil?: true,
      description: "Optional pgvector embedding for semantic search"

    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workflow, Thunderline.Thundervine.Resources.Workflow do
      source_attribute :workflow_id
      destination_attribute :id
    end
  end
end
