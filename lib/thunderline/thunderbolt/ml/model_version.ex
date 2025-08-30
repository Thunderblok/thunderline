defmodule Thunderline.Thunderbolt.ML.ModelVersion do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ml_model_versions"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:spec_id, :artifact_id, :dataset_id, :metrics, :notes]
      change set_attribute(:version_id, Thunderline.UUID.v7())
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :version_id, :string, allow_nil?: false
    attribute :spec_id, :uuid, allow_nil?: false
    attribute :artifact_id, :uuid, allow_nil?: false
    attribute :dataset_id, :uuid, allow_nil?: false
    attribute :metrics, :map, default: %{}
    attribute :notes, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :spec, Thunderline.Thunderbolt.ML.ModelSpec, source_attribute: :spec_id
    belongs_to :artifact, Thunderline.Thunderbolt.ML.ModelArtifact, source_attribute: :artifact_id
    belongs_to :dataset, Thunderline.Thunderbolt.ML.TrainingDataset, source_attribute: :dataset_id
  end
end
