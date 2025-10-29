defmodule Thunderline.Thunderbolt.Resources.DocumentUpload do
  @moduledoc """
  Document Upload - Tracks individual document uploads in each of the 4 stages.

  Stage semantics:
  - Stage 1: Reference docs (policies, procedures, org docs)
  - Stage 2: Communication samples (user messages, responses)
  - Stage 3: Instruction & prompt sets (examples, instructions)
  - Stage 4: Test case prompts (eval cases, test examples)
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_uploads"
    repo Thunderline.Repo

    references do
      reference :training_dataset, on_delete: :delete, on_update: :update
    end
  end

  json_api do
    type "document_upload"

    routes do
      base "/document_uploads"
      get :read
      index :read
      post :create
      patch :update
      delete :destroy
    end
  end

  graphql do
    type :document_upload

    queries do
      get :get_document_upload, :read
      list :list_document_uploads, :read
    end

    mutations do
      create :create_document_upload, :create
      update :update_document_upload, :update
      destroy :destroy_document_upload, :destroy
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :stage, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 4
    end

    attribute :filename, :string do
      allow_nil? false
      public? true
    end

    attribute :file_url, :string do
      public? true
    end

    attribute :content, :string do
      public? true
    end

    attribute :labels, {:array, :string} do
      default []
      public? true
    end

    attribute :chunk_count, :integer do
      default 0
      public? true
    end

    attribute :processed, :boolean do
      default false
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
    belongs_to :training_dataset, Thunderline.Thunderbolt.Resources.TrainingDataset do
      allow_nil? false
      attribute_writable? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      # Arguments for inputs that need validation
      argument :stage, :integer do
        allow_nil? false
        constraints min: 1, max: 4
      end

      accept [:filename, :file_url, :content, :labels, :training_dataset_id, :metadata]

      # Set stage from argument
      change set_attribute(:stage, arg(:stage))

      # Increment parent dataset's stage counter AFTER transaction completes
      # Use after_transaction instead of after_action to avoid atomicity issues
      change after_transaction(fn changeset, {:ok, record}, _context ->
        dataset = Ash.get!(Thunderline.Thunderbolt.Resources.TrainingDataset, record.training_dataset_id)
        # Use positional argument! args: [:stage] means increment_stage!(dataset, stage_value)
        Thunderline.Thunderbolt.Resources.TrainingDataset.increment_stage!(dataset, record.stage)
        {:ok, record}
      end)
    end

    update :update do
      primary? true
      accept [:filename, :file_url, :content, :labels, :processed, :chunk_count, :metadata]
    end

    update :mark_processed do
      accept []
      change set_attribute(:processed, true)
    end
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :mark_processed
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
