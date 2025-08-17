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
    # Allowed starting states, with a default
    initial_states([:initialized])
    default_initial_state(:initialized)

    transitions do
  transition(:start, from: [:initialized], to: [:running])
  transition(:complete, from: [:running], to: [:succeeded])
  transition(:fail, from: [:running], to: [:failed])
  transition(:cancel, from: [:running], to: [:cancelled])
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
      change set_attribute(:state, :initialized)
    end

    update :start do
      accept []
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:best_metric, :completed_trials]
      change transition_state(:succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change transition_state(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
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

    # State attribute managed by AshStateMachine transitions.
    attribute :state, :atom do
      description "Current lifecycle state"
      allow_nil? false
      default :initialized
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
      # Point to the foreign key defined by the belongs_to in ModelArtifact
      destination_attribute :model_run_id
    end
  end
end
