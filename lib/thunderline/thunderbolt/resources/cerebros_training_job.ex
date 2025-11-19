defmodule Thunderline.Thunderbolt.Resources.CerebrosTrainingJob do
  @moduledoc """
  Cerebros Training Job - Tracks training runs sent to Cerebros service.

  Flow:
  1. Dataset frozen → Job queued
  2. CSVs generated and sent to Cerebros
  3. Cerebros returns checkpoints (Phase 1-4)
  4. Checkpoints loaded into Bumblebee
  5. Model ready for serving
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cerebros_training_jobs"
    repo Thunderline.Repo

    references do
      reference :training_dataset, on_delete: :nilify, on_update: :update
    end
  end

  json_api do
    type "cerebros_training_job"

    routes do
      base("/cerebros_training_jobs")
      get(:read)
      index :read
      post(:create)
      patch(:update)
    end
  end

  graphql do
    type :cerebros_training_job

    queries do
      get :get_cerebros_training_job, :read
      list :list_cerebros_training_jobs, :read
    end

    mutations do
      create :create_cerebros_training_job, :create
      update :update_cerebros_training_job, :update
    end
  end

  code_interface do
    define :create
    define :read
    define :update
    define :start
    define :complete, args: [:checkpoint_urls, :metrics]
    define :fail, args: [:error_message]
    define :update_checkpoint, args: [:phase, :checkpoint_url]

    # No required args - model_format has default
    define :mark_model_loaded
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:training_dataset_id, :model_id, :hyperparameters, :metadata]

      change set_attribute(:status, :queued)
    end

    update :update do
      primary? true

      accept [
        :cerebros_job_id,
        :status,
        :phase,
        :checkpoint_urls,
        :current_checkpoint_url,
        :metrics,
        :error_message,
        :started_at,
        :completed_at,
        :model_loaded,
        :model_format,
        :metadata
      ]
    end

    update :start do
      accept []

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:fine_tuned_model, :checkpoint_urls, :metrics]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :update_checkpoint do
      argument :phase, :integer, allow_nil?: false
      argument :checkpoint_url, :string, allow_nil?: false

      change fn changeset, _context ->
        phase = Ash.Changeset.get_argument(changeset, :phase)
        checkpoint_url = Ash.Changeset.get_argument(changeset, :checkpoint_url)
        current_urls = Ash.Changeset.get_attribute(changeset, :checkpoint_urls) || []

        changeset
        |> Ash.Changeset.force_change_attribute(:phase, phase)
        |> Ash.Changeset.force_change_attribute(
          :checkpoint_urls,
          current_urls ++ [checkpoint_url]
        )
        |> Ash.Changeset.force_change_attribute(:current_checkpoint_url, checkpoint_url)
      end
    end

    update :update_fine_tuned_model do
      accept [:fine_tuned_model]
    end

    update :mark_model_loaded do
      argument :model_format, :string, allow_nil?: true, default: "safetensors"

      change fn changeset, _context ->
        model_format = Ash.Changeset.get_argument(changeset, :model_format)

        changeset
        |> Ash.Changeset.force_change_attribute(:model_loaded, true)
        |> Ash.Changeset.force_change_attribute(:model_loaded_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:model_format, model_format)
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :cerebros_job_id, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :queued
      public? true
      constraints one_of: [:queued, :running, :completed, :failed, :cancelled]
    end

    attribute :phase, :integer do
      default 0
      public? true
      constraints min: 0, max: 4
    end

    attribute :checkpoint_urls, {:array, :string} do
      default []
      public? true
    end

    attribute :current_checkpoint_url, :string do
      public? true
    end

    attribute :metrics, :map do
      default %{}
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :model_loaded, :boolean do
      default false
      public? true
    end

    attribute :model_loaded_at, :utc_datetime_usec do
      public? true
      description "When the fine-tuned model was loaded into Bumblebee"
    end

    attribute :model_format, :string do
      public? true
    end

    attribute :model_id, :string do
      public? true
      description "Base model to fine-tune (e.g., 'gpt-4o-mini')"
    end

    attribute :hyperparameters, :map do
      default %{}
      public? true
      description "Training hyperparameters (n_epochs, learning_rate_multiplier, batch_size)"
    end

    attribute :fine_tuned_model, :string do
      public? true
      description "ID of the resulting fine-tuned model"
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :training_dataset, Thunderline.Thunderbolt.Resources.TrainingDataset do
      allow_nil? false
      attribute_writable? true
    end
  end
end
