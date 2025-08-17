defmodule Thunderline.Thunderbolt.Resources.ModelArtifact do
  @moduledoc """
  Cerebros Model Artifact - persisted output of a model run trial or final selection.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cerebros_model_artifacts"
    repo Thunderline.Repo
  end

  json_api do
    type "model_artifacts"
  end

  code_interface do
    define :create
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [:model_run_id, :trial_index, :metric, :params, :spec, :path, :metadata]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :trial_index, :integer do
      allow_nil? false
    end

    attribute :metric, :float do
      allow_nil? false
    end

    attribute :params, :integer do
      allow_nil? false
    end

    attribute :spec, :map do
      allow_nil? false
      default %{}
    end

    attribute :path, :string do
      description "Filesystem path or opaque storage reference"
    end

    attribute :metadata, :map do
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun do
      allow_nil? false
      attribute_writable? true
    end
  end
end
