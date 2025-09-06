defmodule Thunderline.Thunderbolt.ML.ModelArtifact do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ml_model_artifacts"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:spec_id, :uri, :checksum, :bytes]
      change set_attribute(:status, :created)
      change set_attribute(:semver, "0.1.0")
    end

    update :promote do
      change set_attribute(:promoted, true)
      change set_attribute(:status, :promoted)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :spec_id, :uuid, allow_nil?: false
    # Preserve linkage to ModelRun for lineage during transition
    attribute :model_run_id, :uuid
    attribute :uri, :string, allow_nil?: false
    attribute :checksum, :string, allow_nil?: false
    attribute :bytes, :integer, allow_nil?: false
    attribute :status, :atom, constraints: [one_of: [:created, :promoted, :archived]], default: :created
    attribute :promoted, :boolean, default: false
    attribute :semver, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :spec, Thunderline.Thunderbolt.ML.ModelSpec, source_attribute: :spec_id
    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun, source_attribute: :model_run_id
  end
end
