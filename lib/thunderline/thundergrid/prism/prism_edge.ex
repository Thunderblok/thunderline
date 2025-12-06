defmodule Thunderline.Thundergrid.Prism.PrismEdge do
  @moduledoc """
  PrismEdge — Connection between PrismNodes in the DAG scratchpad.

  Consolidated from Thunderprism.PrismEdge into Thundergrid.Prism.

  Edges represent relationships between ML decision points:
  - Sequential decisions (next iteration)
  - Model transitions (switching between models)
  - Causality chains (decisions that led to other decisions)

  Default relation_type is "sequential" for sequential ML iterations.
  """
  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "prism_edges"
    repo Thunderline.Repo
  end

  graphql do
    type :prism_edge

    queries do
      list :list_prism_edges, :read
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:from_id, :to_id, :relation_type, :meta]
    end

    update :update do
      accept [:meta]
    end

    read :by_node do
      argument :node_id, :uuid, allow_nil?: false
      filter expr(from_id == ^arg(:node_id) or to_id == ^arg(:node_id))
    end

    read :by_relation do
      argument :relation_type, :string, allow_nil?: false
      filter expr(relation_type == ^arg(:relation_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_id, :uuid do
      allow_nil? false
      public? true
      description "Source node UUID"
    end

    attribute :to_id, :uuid do
      allow_nil? false
      public? true
      description "Target node UUID"
    end

    attribute :relation_type, :string do
      allow_nil? false
      default "sequential"
      public? true
      description "Type of relationship (sequential, transition, causality)"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Additional edge metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :from_node, Thunderline.Thundergrid.Prism.PrismNode do
      source_attribute :from_id
      public? true
    end

    belongs_to :to_node, Thunderline.Thundergrid.Prism.PrismNode do
      source_attribute :to_id
      public? true
    end
  end
end
