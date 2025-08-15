defmodule Thunderline.Thunderbolt.Resources.RuleOracle do
  @moduledoc """
  Rule Oracle resource tracking ML rule inference engines.

  Democratizes neural rule systems - making advanced ML inference
  accessible without institutional-scale budgets.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlane_rule_oracles"
    repo Thunderline.Repo
  end

  state_machine do
    initial_states([:initializing])
    default_initial_state(:initializing)

    transitions do
      transition(:start, from: :initializing, to: :active)
      transition(:begin_training, from: :active, to: :training)
      transition(:finish_training, from: :training, to: :active)
      transition(:encounter_error, from: [:active, :training], to: :error)
      transition(:stop, from: [:active, :training, :error], to: :stopped)
      transition(:restart, from: [:error, :stopped], to: :initializing)
    end
  end

  json_api do
    type "rule_oracles"
  end

  code_interface do
    define :create
    define :read
    define :start
    define :begin_training
    define :finish_training
    define :encounter_error
    define :stop
    define :restart
    define :record_inference
    define :update_rules
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :name,
        :implementation,
        :description,
        :input_size,
        :hidden_size,
        :batch_size,
        :temperature,
        :rule_parameters
      ]
    end

    update :start do
      require_atomic? false
      change transition_state(:active)
    end

    update :begin_training do
      require_atomic? false
      change transition_state(:training)
    end

    update :finish_training do
      require_atomic? false
      change transition_state(:active)
      accept [:model_version, :training_examples, :model_size_bytes, :rule_parameters]
    end

    update :encounter_error do
      require_atomic? false
      change transition_state(:error)
    end

    update :stop do
      require_atomic? false
      change transition_state(:stopped)
    end

    update :restart do
      require_atomic? false
      change transition_state(:initializing)
    end

    update :record_inference do
      accept [
        :total_inferences,
        :avg_latency_us,
        :error_rate,
        :last_inference_at,
        :performance_metrics
      ]
    end

    update :update_rules do
      accept [:rule_parameters, :model_version]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Human-readable oracle name"
      allow_nil? false
      constraints min_length: 1, max_length: 100
    end

    attribute :implementation, :atom do
      description "Backend implementation type"
      allow_nil? false
      constraints one_of: [:LocalNx, :CerebrosPy, :EXLA, :Torchx]
    end

    attribute :description, :string do
      description "Description of the oracle's purpose and capabilities"
    end

    # Configuration
    attribute :input_size, :integer do
      description "Input layer size for neural network"
      default 16
      constraints min: 1, max: 10000
    end

    attribute :hidden_size, :integer do
      description "Hidden layer size for neural network"
      default 32
      constraints min: 1, max: 10000
    end

    attribute :batch_size, :integer do
      description "Training batch size"
      default 32
      constraints min: 1, max: 1000
    end

    attribute :temperature, :float do
      description "Temperature parameter for sampling"
      default 1.0
      constraints min: 0.1, max: 10.0
    end

    # Performance metrics
    attribute :total_inferences, :integer do
      description "Total number of inferences performed"
      default 0
    end

    attribute :avg_latency_us, :float do
      description "Average inference latency in microseconds"
    end

    attribute :error_rate, :float do
      description "Error rate (0.0 to 1.0)"
      default 0.0
      constraints min: 0.0, max: 1.0
    end

    attribute :last_inference_at, :utc_datetime do
      description "Timestamp of last inference"
    end

    # Model metadata
    attribute :model_version, :string do
      description "Current model version identifier"
    end

    attribute :training_examples, :integer do
      description "Number of training examples used"
      default 0
    end

    attribute :model_size_bytes, :integer do
      description "Model size in bytes"
    end

    attribute :rule_parameters, :map do
      description "CA/Ising rule parameters"
      default %{}
    end

    attribute :performance_metrics, :map do
      description "Detailed performance metrics"
      default %{}
    end

    timestamps()
  end

  relationships do
    has_many :lane_configurations, Thunderline.Thunderbolt.Resources.LaneConfiguration do
      description "Lane configurations using this oracle"
    end

    has_many :consensus_runs, Thunderline.Thunderbolt.Resources.ConsensusRun do
      description "Consensus runs that used this oracle's rules"
    end
  end

  calculations do
    calculate :inference_rate,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? > 0 THEN ?::float / ? ELSE 0.0 END",
                  total_inferences,
                  total_inferences,
                  fragment("EXTRACT(EPOCH FROM (NOW() - ?))", inserted_at)
                )
              ) do
      description "Inferences per second since creation"
    end

    calculate :accuracy,
              :decimal,
              expr(
                fragment(
                  "CASE WHEN ? > 0 THEN (1.0 - ?)::decimal ELSE 0.0 END",
                  total_inferences,
                  error_rate
                )
              ) do
      description "Accuracy rate (1.0 - error_rate)"
    end
  end
end
