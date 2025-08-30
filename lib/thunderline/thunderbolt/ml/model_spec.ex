defmodule Thunderline.Thunderbolt.ML.ModelSpec do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ml_model_specs"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:tenant_id, :base_model, :task, :adapter, :framework, :params]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :string, allow_nil?: false
    attribute :base_model, :string, allow_nil?: false
    attribute :task, :atom, constraints: [one_of: [:classification, :generation, :embedding]], allow_nil?: false
    attribute :adapter, :atom, constraints: [one_of: [:lora, :prefix, :qlora]], allow_nil?: false
    attribute :framework, :atom, constraints: [one_of: [:pytorch, :mlx, :gguf]], allow_nil?: false
    attribute :params, :map, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :artifacts, Thunderline.Thunderbolt.ML.ModelArtifact
    has_many :versions, Thunderline.Thunderbolt.ML.ModelVersion
  end
end
