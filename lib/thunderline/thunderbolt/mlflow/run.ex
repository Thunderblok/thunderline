defmodule Thunderline.Thunderbolt.MLflow.Run do
  @moduledoc """
  Represents an MLflow run that tracks a single trial execution.
  
  Links MLflow run IDs to Thunderline ModelTrial records, enabling
  bidirectional navigation and synchronization of metrics, parameters,
  and artifacts between MLflow and Thunderline.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "mlflow_runs"
    repo Thunderline.Repo
  end

  code_interface do
    define :create, action: :create
    define :get_by_id, action: :by_mlflow_id, args: [:mlflow_run_id]
    define :find_by_trial, action: :by_trial_id, args: [:trial_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :mlflow_run_id,
        :mlflow_experiment_id,
        :run_name,
        :status,
        :start_time,
        :end_time,
        :lifecycle_stage,
        :artifact_uri,
        :params,
        :metrics,
        :tags,
        :model_trial_id,
        :model_run_id
      ]

      change set_attribute(:synced_at, &DateTime.utc_now/0)
    end

    update :update_metadata do
      accept [
        :run_name,
        :status,
        :end_time,
        :lifecycle_stage,
        :params,
        :metrics,
        :tags
      ]

      change set_attribute(:synced_at, &DateTime.utc_now/0)
    end

    update :link_trial do
      argument :trial_id, :uuid, allow_nil?: false
      change set_attribute(:model_trial_id, arg(:trial_id))
      change set_attribute(:synced_at, &DateTime.utc_now/0)
    end

    read :by_mlflow_id do
      argument :mlflow_run_id, :string, allow_nil?: false
      filter expr(mlflow_run_id == ^arg(:mlflow_run_id))
    end

    read :by_trial_id do
      argument :trial_id, :uuid, allow_nil?: false
      filter expr(model_trial_id == ^arg(:trial_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mlflow_run_id, :string do
      allow_nil? false
      constraints [match: ~r/^[a-f0-9]{32}$/]
    end

    attribute :mlflow_experiment_id, :string, allow_nil?: false

    attribute :run_name, :string
    
    attribute :status, :atom,
      constraints: [one_of: [:running, :scheduled, :finished, :failed, :killed]],
      default: :running

    attribute :start_time, :integer
    attribute :end_time, :integer
    
    attribute :lifecycle_stage, :atom,
      constraints: [one_of: [:active, :deleted]],
      default: :active

    attribute :artifact_uri, :string
    attribute :params, :map, default: %{}
    attribute :metrics, :map, default: %{}
    attribute :tags, :map, default: %{}

    # Linkage to Thunderline resources
    attribute :model_trial_id, :uuid
    attribute :model_run_id, :uuid

    attribute :synced_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :experiment, Thunderline.Thunderbolt.MLflow.Experiment,
      source_attribute: :mlflow_experiment_id,
      destination_attribute: :mlflow_experiment_id,
      relationship_context: %{data_layer: %{table: "mlflow_experiments"}}

    belongs_to :model_trial, Thunderline.Thunderbolt.Resources.ModelTrial,
      source_attribute: :model_trial_id

    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun,
      source_attribute: :model_run_id
  end

  identities do
    identity :unique_mlflow_run_id, [:mlflow_run_id]
  end
end
