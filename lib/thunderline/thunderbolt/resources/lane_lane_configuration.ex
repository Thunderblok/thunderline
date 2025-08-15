defmodule Thunderline.Thunderbolt.Resources.LaneConfiguration do
  @moduledoc """
  Configuration resource for individual processing lanes in the multi-scale self-organization engine.

  Each lane represents a processing slice that can run CA rules, Ising consensus, or other
  computational patterns. Lanes are organized into X/Y/Z orthogonal families with α-gain coupling.

  ## Lane Types
  - `:ca` - Cellular Automata processing lane
  - `:ising` - Ising model consensus lane
  - `:majority` - Simple majority voting lane
  - `:neural` - Neural network processing lane

  ## State Machine
  - `:initializing` - Lane is being configured
  - `:active` - Lane is actively processing
  - `:paused` - Lane is temporarily suspended
  - `:maintenance` - Lane is under maintenance
  - `:terminated` - Lane has been shut down
  """

  use Ash.Resource,
    extensions: [AshJsonApi.Resource, AshStateMachine],
    authorizers: [Ash.Policy.Authorizer],
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  json_api do
    type "lane_configurations"
  end

  state_machine do
    initial_states([:initializing])
    default_initial_state(:initializing)

    transitions do
      transition(:activate, from: [:initializing, :paused], to: :active)
      transition(:pause, from: :active, to: :paused)
      transition(:resume, from: :paused, to: :active)
      transition(:start_maintenance, from: [:active, :paused], to: :maintenance)
      transition(:end_maintenance, from: :maintenance, to: :active)
      transition(:terminate, from: [:active, :paused, :maintenance], to: :terminated)
    end
  end

  postgres do
    table "lane_configurations"
    repo Thunderline.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :activate
    define :pause
    define :resume
    define :start_maintenance
    define :end_maintenance
    define :terminate
    define :adjust_parameters
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :name,
        :lane_type,
        :lane_family,
        :rule_parameters,
        :performance_target,
        :max_concurrent_tasks,
        :priority_weight,
        :adaptive_bounds,
        :metadata
      ]
    end

    update :update do
      accept [
        :name,
        :rule_parameters,
        :performance_target,
        :max_concurrent_tasks,
        :priority_weight,
        :adaptive_bounds,
        :metadata
      ]
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :pause do
      accept []
      change transition_state(:paused)
    end

    update :resume do
      accept []
      change transition_state(:active)
    end

    update :start_maintenance do
      accept []
      change transition_state(:maintenance)
    end

    update :end_maintenance do
      accept []
      change transition_state(:active)
    end

    update :terminate do
      accept []
      change transition_state(:terminated)
    end

    update :adjust_parameters do
      accept [:rule_parameters, :performance_target, :priority_weight, :adaptive_bounds]
    end
  end

  policies do
    # Default policy - allow all for now, will implement proper authorization later
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Human-readable lane name"
      allow_nil? false
      constraints min_length: 1, max_length: 100
    end

    attribute :lane_type, :atom do
      description "Type of processing lane"
      allow_nil? false
      constraints one_of: [:ca, :ising, :majority, :neural]
      default :ca
    end

    attribute :lane_family, :atom do
      description "Lane family (X, Y, or Z orthogonal slice)"
      allow_nil? false
      constraints one_of: [:x_slice, :y_slice, :z_slice]
    end

    attribute :rule_parameters, :map do
      description "Configuration parameters for the lane's computational rules"
      default %{}
    end

    attribute :performance_target, :decimal do
      description "Target performance metric for this lane"
      default Decimal.new("0.85")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :max_concurrent_tasks, :integer do
      description "Maximum number of concurrent tasks this lane can handle"
      default 10
      constraints min: 1, max: 1000
    end

    attribute :priority_weight, :decimal do
      description "Weight factor for task routing priority"
      default Decimal.new("1.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("10.0")
    end

    attribute :adaptive_bounds, :map do
      description "Bounds for adaptive parameter adjustment"
      default %{min: 0.0, max: 1.0, step: 0.01}
    end

    attribute :metadata, :map do
      description "Additional lane metadata and configuration"
      default %{}
    end

    attribute :rule_oracle_id, :uuid do
      description "Current active rule oracle for this lane"
      allow_nil? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :consensus_runs, Thunderline.Thunderbolt.Resources.ConsensusRun do
      description "Consensus runs executed by this lane"
    end

    has_many :performance_metrics, Thunderline.Thunderbolt.Resources.PerformanceMetric do
      description "Performance metrics for this lane"
    end

    has_many :rule_sets, Thunderline.Thunderbolt.Resources.RuleSet do
      description "Rule sets available for this lane"
    end

    belongs_to :rule_oracle, Thunderline.Thunderbolt.Resources.RuleOracle do
      description "Current active rule oracle for this lane"
      allow_nil? true
    end
  end

  calculations do
    calculate :current_load,
              :decimal,
              expr(
                fragment(
                  "COALESCE((SELECT COUNT(*) FROM consensus_runs WHERE lane_configuration_id = ? AND status = 'running'), 0)::decimal / ?",
                  id,
                  max_concurrent_tasks
                )
              ) do
      description "Current processing load as percentage of capacity"
    end

    calculate :success_rate,
              :decimal,
              expr(
                fragment(
                  """
                    COALESCE(
                      (SELECT
                        COUNT(CASE WHEN success = true THEN 1 END)::decimal /
                        NULLIF(COUNT(*), 0)
                      FROM consensus_runs
                      WHERE lane_configuration_id = ?
                      AND created_at > NOW() - INTERVAL '24 hours'),
                      0.0
                    )
                  """,
                  id
                )
              ) do
      description "Success rate over the last 24 hours"
    end
  end
end
