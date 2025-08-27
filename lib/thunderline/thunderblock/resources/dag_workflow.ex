defmodule Thunderline.Thunderblock.Resources.DAGWorkflow do
  @moduledoc """
  Thundervine DAG Workflow root instance.

  Represents a durable, immutable workflow lineage capturing a successful domain
  resource action chain. Child nodes and edges form the execution graph.
  Snapshots provide replay packages.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "dag_workflows"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :source_domain, :atom, allow_nil?: false, description: "Originating domain of root action"
    attribute :root_event_name, :string, allow_nil?: false
    attribute :correlation_id, :string, allow_nil?: false
    attribute :causation_id, :string, allow_nil?: true
    attribute :status, :atom, allow_nil?: false, default: :building, constraints: [one_of: [:building, :sealed]]
    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :nodes, Thunderline.Thunderblock.Resources.DAGNode do
      destination_attribute :workflow_id
    end
    has_many :edges, Thunderline.Thunderblock.Resources.DAGEdge do
      destination_attribute :workflow_id
    end
    has_many :snapshots, Thunderline.Thunderblock.Resources.DAGSnapshot do
      destination_attribute :workflow_id
    end
  end

  identities do
    identity :unique_correlation, [:correlation_id]
  end

  actions do
    defaults [:read]

    create :start do
      accept [:source_domain, :root_event_name, :correlation_id, :causation_id, :metadata]
    end

    update :seal do
      accept []
      change fn cs, _ -> Ash.Changeset.change_attribute(cs, :status, :sealed) end
    end
  end

  policies do
    policy action([:start, :seal]) do
      authorize_if expr(not is_nil(actor(:id)))
    end
    policy action(:read) do
      authorize_if expr(true)
    end
  end
end
