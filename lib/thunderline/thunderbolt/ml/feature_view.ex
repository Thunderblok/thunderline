defmodule Thunderline.Thunderbolt.ML.FeatureView do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  alias Thunderline.Thunderbolt.ML.Types

  postgres do
    table "ml_feature_views"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:dataset_id, :name, :schema_json, :materialization, :version]
      change set_attribute(:feature_view_id, Types.uuid_v7())
      change set_attribute(:version, expr(coalesce(version, 1)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :feature_view_id, :string, allow_nil?: false
    attribute :dataset_id, :uuid, allow_nil?: false
    attribute :name, :string, allow_nil?: false
    attribute :schema_json, :map, allow_nil?: false
    attribute :materialization, :string, allow_nil?: false
    attribute :version, :integer, default: 1
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :dataset, Thunderline.Thunderbolt.ML.TrainingDataset, source_attribute: :dataset_id
  end
end
