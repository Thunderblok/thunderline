defmodule Thunderline.Thunderbolt.Resources.TrainingDataset do
  @moduledoc """
  Training Dataset - Manages the 4-stage document upload and labeling pipeline.

  Stages:
  1. Reference docs (policies, procedures)
  2. Communication samples (messages, responses)
  3. Instruction & prompt sets
  4. Test case prompts

  Status flow: collecting → chunking → ready → training → frozen
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_datasets"
    repo Thunderline.Repo
  end

  json_api do
    type "training_dataset"

    routes do
      base "/training_datasets"
      get :read
      index :read
      post :create
      patch :update
      delete :destroy
      post :freeze, route: "/:id/freeze"
    end
  end

  graphql do
    type :training_dataset

    queries do
      get :get_training_dataset, :read
      list :list_training_datasets, :read
    end

    mutations do
      create :create_training_dataset, :create
      update :update_training_dataset, :update
      destroy :destroy_training_dataset, :destroy
      update :freeze_training_dataset, :freeze
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :collecting
      public? true
      constraints one_of: [:collecting, :chunking, :ready, :training, :frozen]
    end

    attribute :stage_1_count, :integer do
      default 0
      public? true
    end

    attribute :stage_2_count, :integer do
      default 0
      public? true
    end

    attribute :stage_3_count, :integer do
      default 0
      public? true
    end

    attribute :stage_4_count, :integer do
      default 0
      public? true
    end

    attribute :total_chunks, :integer do
      default 0
      public? true
    end

    attribute :corpus_path, :string do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :document_uploads, Thunderline.Thunderbolt.Resources.DocumentUpload
    has_many :training_jobs, Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :description]
    end

    update :update do
      primary? true
      accept [:name, :description, :status, :metadata, :corpus_path]
    end

    update :freeze do
      accept []

      change set_attribute(:status, :frozen)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :increment_stage do
      # Don't require atomicity - can be called from after_transaction hooks
      require_atomic? false

      argument :stage, :integer do
        allow_nil? false
        constraints min: 1, max: 4
      end

      change fn changeset, _context ->
        stage = Ash.Changeset.get_argument(changeset, :stage)
        field = :"stage_#{stage}_count"
        current = Ash.Changeset.get_attribute(changeset, field) || 0
        Ash.Changeset.force_change_attribute(changeset, field, current + 1)
      end
    end

    update :set_corpus_path do
      accept [:corpus_path]
    end
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :freeze
    define :increment_stage, args: [:stage]
    define :set_corpus_path, args: [:corpus_path]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end
end
