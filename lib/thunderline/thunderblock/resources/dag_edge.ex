defmodule Thunderline.Thunderblock.Resources.DAGEdge do
  @moduledoc """
  DAG Edge - Causal link between two node ids within a workflow.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dag_edges"
    repo Thunderline.Repo
  end

  actions do
    defaults [:create, :read]
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
    belongs_to :workflow, Thunderline.Thunderblock.Resources.DAGWorkflow do
      source_attribute :workflow_id
      destination_attribute :id
    end
  end

  identities do
    identity :unique_edge, [:workflow_id, :from_node_id, :to_node_id, :edge_type]
  end
end
