defmodule Thunderline.Thunderbolt.MLflow.Experiment do
  @moduledoc """
  Represents an MLflow experiment that groups related runs.

  An experiment corresponds to a ModelRun in Thunderline, providing
  bidirectional linkage between Thunderline trials and MLflow tracking.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "mlflow_experiments"
    repo Thunderline.Repo
  end

  code_interface do
    define :create, action: :create
    define :get_by_id, action: :by_mlflow_id, args: [:mlflow_experiment_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :mlflow_experiment_id,
        :name,
        :artifact_location,
        :lifecycle_stage,
        :tags,
        :model_run_id
      ]

      change set_attribute(:synced_at, &DateTime.utc_now/0)
    end

    update :update_metadata do
      accept [:name, :artifact_location, :lifecycle_stage, :tags]
      change set_attribute(:synced_at, &DateTime.utc_now/0)
    end

    read :by_mlflow_id do
      argument :mlflow_experiment_id, :string, allow_nil?: false
      filter expr(mlflow_experiment_id == ^arg(:mlflow_experiment_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mlflow_experiment_id, :string do
      allow_nil? false
      constraints [match: ~r/^[0-9]+$/]
    end

    attribute :name, :string, allow_nil?: false
    attribute :artifact_location, :string

    attribute :lifecycle_stage, :atom,
      constraints: [one_of: [:active, :deleted]],
      default: :active

    attribute :tags, :map, default: %{}

    # Linkage to Thunderline ModelRun
    attribute :model_run_id, :uuid

    attribute :synced_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun,
      source_attribute: :model_run_id

    has_many :runs, Thunderline.Thunderbolt.MLflow.Run,
      destination_attribute: :mlflow_experiment_id,
      relationship_context: %{data_layer: %{table: "mlflow_runs"}}
  end

  identities do
    identity :unique_mlflow_experiment_id, [:mlflow_experiment_id]
  end
end
