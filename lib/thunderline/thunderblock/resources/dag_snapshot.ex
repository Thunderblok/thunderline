defmodule Thunderline.Thunderblock.Resources.DAGSnapshot do
  @moduledoc """
  DAG Snapshot - Immutable serialized representation of a sealed workflow for replay.
  Stores ordered node payloads and edge list.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dag_snapshots"
    repo Thunderline.Repo
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

  attributes do
    uuid_primary_key :id
    attribute :workflow_id, :uuid, allow_nil?: false
    attribute :version, :integer, allow_nil?: false, default: 1
    attribute :node_order, {:array, :uuid}, allow_nil?: false, default: []
    attribute :nodes_payload, :map, allow_nil?: false, default: %{}
    attribute :edges, {:array, :map}, allow_nil?: false, default: []

    attribute :embedding_vector, {:array, :float},
      allow_nil?: true,
      description: "Optional pgvector embedding"

    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workflow, Thunderline.Thunderblock.Resources.DAGWorkflow do
      source_attribute :workflow_id
      destination_attribute :id
    end
  end
end
