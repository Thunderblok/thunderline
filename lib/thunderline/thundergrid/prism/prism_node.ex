defmodule Thunderline.Thundergrid.Prism.PrismNode do
  @moduledoc """
  PrismNode — ML Decision Point in the DAG scratchpad.

  Consolidated from Thunderprism.PrismNode into Thundergrid.Prism.

  Each node captures:
  - Which PAC (Parzen Adaptive Controller) made the decision
  - Which iteration of the learning process
  - Which model was chosen
  - Model selection probabilities and distances
  - Arbitrary metadata for extensions

  Nodes form a graph through PrismEdge connections, creating a visualization
  of the ML decision-making process over time.

  ## GraphQL

  Exposed via Thundergrid.Domain as `prism_node` type.
  """
  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "prism_nodes"
    repo Thunderline.Repo
  end

  graphql do
    type :prism_node

    queries do
      get :get_prism_node, :read
      list :list_prism_nodes, :read
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :pac_id,
        :iteration,
        :chosen_model,
        :model_probabilities,
        :model_distances,
        :meta,
        :timestamp
      ]
    end

    update :update do
      accept [:meta, :model_probabilities, :model_distances]
    end

    read :by_pac do
      argument :pac_id, :string, allow_nil?: false
      filter expr(pac_id == ^arg(:pac_id))
      prepare build(sort: [iteration: :desc])
    end

    read :recent do
      argument :limit, :integer, default: 50
      prepare build(sort: [timestamp: :desc], limit: arg(:limit))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :pac_id, :string do
      allow_nil? false
      public? true
      description "Identifier for the PAC/controller"
    end

    attribute :iteration, :integer do
      allow_nil? false
      public? true
      description "Iteration number in the learning process"
    end

    attribute :chosen_model, :string do
      allow_nil? false
      public? true
      description "Model that was selected"
    end

    attribute :model_probabilities, :map do
      default %{}
      public? true
      description "Probability distribution over models"
    end

    attribute :model_distances, :map do
      default %{}
      public? true
      description "Distance metrics for each model"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Additional metadata"
    end

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the decision was made"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :out_edges, Thunderline.Thundergrid.Prism.PrismEdge do
      destination_attribute :from_id
      public? true
    end

    has_many :in_edges, Thunderline.Thundergrid.Prism.PrismEdge do
      destination_attribute :to_id
      public? true
    end
  end

  calculations do
    calculate :confidence, :float, expr(
      fragment("COALESCE((model_probabilities->?)::float, 0.0)", chosen_model)
    ) do
      description "Confidence in the chosen model"
    end
  end
end
