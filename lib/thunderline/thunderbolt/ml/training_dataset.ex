defmodule Thunderline.Thunderbolt.ML.TrainingDataset do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query
  alias Thunderline.Thunderbolt.ML.Types

  postgres do
    table "ml_training_datasets"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :purpose, :tenant_id, :description]
      change set_attribute(:dataset_id, Types.uuid_v7())
      change set_attribute(:version, 1)
      change set_attribute(:status, :draft)
    end

    update :bump_version do
      change increment(:version, amount: 1)
      change set_attribute(:status, :draft)
    end

    update :seal do
      argument :bytes, :integer, allow_nil?: false
      argument :records, :integer, allow_nil?: false
      argument :checksum, :string, allow_nil?: false
      change set_attribute(:status, :sealed)
      change set_attribute(:bytes, arg(:bytes))
      change set_attribute(:records, arg(:records))
      change set_attribute(:checksum, arg(:checksum))
      change set_attribute(:sealed_at, Types.now_utc())
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :dataset_id, :string, allow_nil?: false
    attribute :tenant_id, :string, allow_nil?: false
    attribute :name, :string, allow_nil?: false
    attribute :purpose, :atom, constraints: [one_of: [:train, :eval]], allow_nil?: false
    attribute :description, :string
    attribute :version, :integer, default: 1
    attribute :status, :atom, constraints: [one_of: [:draft, :sealed]], default: :draft
    attribute :bytes, :integer
    attribute :records, :integer
    attribute :checksum, :string
    attribute :sealed_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :feature_views, Thunderline.Thunderbolt.ML.FeatureView, destination_attribute: :dataset_id
    has_many :runs, Thunderline.Thunderbolt.ML.TrainingRun, destination_attribute: :dataset_id
  end

  policies do
    policy action(:*) do
      authorize_if expr(^actor(:tenant_id) == tenant_id)
    end
  end

  code_interface do
    define :read
    define :create
    define :seal
  end
end
