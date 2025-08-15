defmodule Thunderline.Thunderbolt.Resources.ConsensusRun do
  @moduledoc """
  Consensus Run resource tracking Ising consensus bursts.

  Monitors the meso-layer oscillator-Ising consensus that provides
  fast NP-hard problem solving for lane coordination.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlane_consensus_runs"
    repo Thunderline.Repo
  end

  json_api do
    type "consensus_runs"
  end

  code_interface do
    define :create
    define :read
    define :complete
    define :mark_failed
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :region_id,
        :trigger_reason,
        :matrix_size,
        :coupling_strength,
        :initial_temperature,
        :final_temperature,
        :max_steps,
        :lane_configuration_id
      ]
    end

    update :complete do
      accept [
        :final_energy,
        :convergence_steps,
        :success,
        :execution_time_ms,
        :spin_configuration,
        :metadata
      ]
    end

    update :mark_failed do
      accept [:metadata]
      change set_attribute(:success, false)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :region_id, :string do
      description "Region that triggered consensus"
    end

    attribute :trigger_reason, :atom do
      description "Reason for consensus trigger"
      constraints one_of: [:scheduled, :energy_spike, :manual, :coupling_event]
    end

    # Input parameters
    attribute :matrix_size, :integer do
      description "Size of the Ising matrix"
      allow_nil? false
      constraints min: 1, max: 10000
    end

    attribute :coupling_strength, :float do
      description "Coupling strength between Ising spins"
      default 1.0
    end

    attribute :initial_temperature, :float do
      description "Initial annealing temperature"
      default 1.5
    end

    attribute :final_temperature, :float do
      description "Final annealing temperature"
      default 0.1
    end

    attribute :max_steps, :integer do
      description "Maximum annealing steps"
      default 50
    end

    # Results
    attribute :final_energy, :float do
      description "Final energy of the Ising system"
    end

    attribute :convergence_steps, :integer do
      description "Number of steps to convergence"
    end

    attribute :success, :boolean do
      description "Whether consensus was successfully reached"
      default false
    end

    attribute :execution_time_ms, :integer do
      description "Execution time in milliseconds"
    end

    attribute :spin_configuration, :map do
      description "Final spin configuration"
      default %{}
    end

    # Metadata
    attribute :lane_configuration_id, :uuid do
      description "Associated lane configuration"
    end

    attribute :rule_oracle_id, :uuid do
      description "Associated rule oracle that guided this run"
    end

    attribute :metadata, :map do
      description "Additional run metadata"
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :lane_configuration, Thunderline.Thunderbolt.Resources.LaneConfiguration do
      description "Lane configuration that executed this consensus run"
    end

    belongs_to :rule_oracle, Thunderline.Thunderbolt.Resources.RuleOracle do
      description "Rule oracle that guided this consensus run"
    end
  end

  calculations do
    calculate :energy_per_step,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? > 0 THEN ?::float / ? ELSE 0.0 END",
                  convergence_steps,
                  final_energy,
                  convergence_steps
                )
              ) do
      description "Average energy reduction per step"
    end

    calculate :efficiency_score,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? > 0 AND ? = true THEN (? - ?)::float / ? ELSE 0.0 END",
                  max_steps,
                  success,
                  max_steps,
                  convergence_steps,
                  max_steps
                )
              ) do
      description "Efficiency score (0.0 to 1.0) based on steps to convergence"
    end
  end
end
