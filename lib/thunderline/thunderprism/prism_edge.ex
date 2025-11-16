defmodule Thunderline.Thunderprism.PrismEdge do
  @moduledoc """
  PrismEdge - Connection between PrismNodes in the DAG scratchpad.
  
  Edges represent relationships between ML decision points:
  - Sequential decisions (next iteration)
  - Model transitions (switching between models)
  - Causality chains (decisions that led to other decisions)
  
  Default relation_type is "next" for sequential ML iterations.
  Custom types can be added for more complex relationships.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderprism.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_edges"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :from_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :to_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :relation_type, :string do
      allow_nil? false
      default "next"
      public? true
    end

    attribute :meta, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :from_node, Thunderline.Thunderprism.PrismNode do
      source_attribute :from_id
      public? true
    end

    belongs_to :to_node, Thunderline.Thunderprism.PrismNode do
      source_attribute :to_id
      public? true
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
  end
end
