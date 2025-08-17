defmodule Thunderline.Thunderbolt.Resources.ModelRun do
  @moduledoc """
  Cerebros Model Run - tracks a search/training execution lifecycle.

  State machine (draft):
    :initialized -> :running -> (:succeeded | :failed | :cancelled)
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cerebros_model_runs"
    repo Thunderline.Repo
  end

  json_api do
    type "model_runs"
  end

  state_machine do
    initial_states [:initialized]
    default_initial_state :initialized

    states [:initialized, :running, :succeeded, :failed, :cancelled]

    transitions do
      transition :initialized, :running
      transition :running, :succeeded
      transition :running, :failed
      transition :running, :cancelled
    end
  end

  code_interface do
    define :create
    define :start
    define :complete
    define :fail
    define :cancel
  end

  actions do
    defaults [:read]

    create :create do
      accept [:search_space_version, :max_params, :requested_trials, :metadata]
      change set_attribute(:status, :initialized)
    end

    update :start do
      accept []
      change AshStateMachine.Transition.transition(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:best_metric, :completed_trials]
      change AshStateMachine.Transition.transition(:succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change AshStateMachine.Transition.transition(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change AshStateMachine.Transition.transition(:cancelled)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      description "Current lifecycle status"
      allow_nil? false
      constraints one_of: [:initialized, :running, :succeeded, :failed, :cancelled]
    end

    attribute :search_space_version, :integer do
      allow_nil? false
      default 1
    end

    attribute :max_params, :integer do
      allow_nil? false
      default 2_000_000
    end

    attribute :requested_trials, :integer do
      allow_nil? false
      default 3
    end

    attribute :completed_trials, :integer do
      default 0
    end

    attribute :best_metric, :float do
      description "Best metric achieved"
    end

    attribute :error_message, :string do
      description "Failure reason if failed"
    end

    attribute :metadata, :map do
      default %{}
    end

    attribute :started_at, :utc_datetime_usec
    attribute :finished_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    has_many :artifacts, Thunderline.Thunderbolt.Resources.ModelArtifact do
      destination_field :model_run_id
    end
  end
end
