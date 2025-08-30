defmodule Thunderline.Thunderbolt.ML.TrainingRun do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ml_training_runs"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :queue do
      accept [:tenant_id, :dataset_id, :spec_id, :params]
      change set_attribute(:run_id, Thunderline.UUID.v7())
      change set_attribute(:status, :queued)
      change after_action(fn _changeset, result ->
        %{run_id: result.run_id}
        |> Thunderline.Thunderbolt.ML.Trainer.RunWorker.new(queue: :ml)
        |> Oban.insert()
        {:ok, result}
      end)
    end

    update :mark_started do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, DateTime.utc_now())
    end

    update :mark_completed do
      argument :artifact_id, :uuid, allow_nil?: false
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, DateTime.utc_now())
      change set_attribute(:artifact_id, arg(:artifact_id))
    end

    update :mark_failed do
      argument :error, :string, allow_nil?: false
      change set_attribute(:status, :failed)
      change set_attribute(:error, arg(:error))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :run_id, :string, allow_nil?: false
    attribute :tenant_id, :string, allow_nil?: false
    attribute :dataset_id, :uuid, allow_nil?: false
    attribute :spec_id, :uuid, allow_nil?: false
    attribute :artifact_id, :uuid
    attribute :params, :map, default: %{}
    attribute :status, :atom, constraints: [one_of: [:queued, :running, :completed, :failed]], default: :queued
    attribute :error, :string
    attribute :started_at, :utc_datetime_usec
    attribute :completed_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :dataset, Thunderline.Thunderbolt.ML.TrainingDataset, source_attribute: :dataset_id
    belongs_to :spec, Thunderline.Thunderbolt.ML.ModelSpec, source_attribute: :spec_id
    belongs_to :artifact, Thunderline.Thunderbolt.ML.ModelArtifact, source_attribute: :artifact_id
  end
end
