defmodule Thunderline.Thunderprism.PrismNode do
  @moduledoc """
  PrismNode - Individual ML decision point in the DAG scratchpad.

  Each node captures:
  - Which PAC (Parzen Adaptive Controller) made the decision
  - Which iteration of the learning process
  - Which model was chosen
  - Model selection probabilities and distances
  - Arbitrary metadata for extensions

  Nodes form a graph through PrismEdge connections, creating a visualization
  of the ML decision-making process over time.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderprism.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_nodes"
    repo Thunderline.Repo
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
  end

  attributes do
    uuid_primary_key :id

    attribute :pac_id, :string do
      allow_nil? false
      public? true
    end

    attribute :iteration, :integer do
      allow_nil? false
      public? true
    end

    attribute :chosen_model, :string do
      allow_nil? false
      public? true
    end

    # JSON blobs so we don't over-model early
    attribute :model_probabilities, :map do
      default %{}
      public? true
    end

    attribute :model_distances, :map do
      default %{}
      public? true
    end

    attribute :meta, :map do
      default %{}
      public? true
    end

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :out_edges, Thunderline.Thunderprism.PrismEdge do
      destination_attribute :from_id
      public? true
    end

    has_many :in_edges, Thunderline.Thunderprism.PrismEdge do
      destination_attribute :to_id
      public? true
    end
  end
end
