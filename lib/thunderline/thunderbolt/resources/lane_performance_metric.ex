defmodule Thunderline.Thunderbolt.Resources.PerformanceMetric do
  @moduledoc """
  Performance metrics for ThunderLane multi-scale coordination.

  Tracks the real-time performance of our democratized optimization
  system - proving that open-source can outperform institutional systems.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlane_performance_metrics"
    repo Thunderline.Repo
  end

  json_api do
    type "performance_metrics"
  end

  code_interface do
    define :create
    define :read
    define :record_micro_metric
    define :record_meso_metric
    define :record_macro_metric
    define :record_system_metric
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :coordinator_id,
        :metric_type,
        :step_number,
        :micro_latency_us,
        :meso_latency_us,
        :macro_latency_us,
        :total_latency_us,
        :patches_processed,
        :consensus_bursts,
        :fusion_operations,
        :system_energy,
        :energy_drift,
        :stability_score,
        :convergence_rate,
        :lane_x_energy,
        :lane_y_energy,
        :lane_z_energy,
        :alpha_xy,
        :alpha_xz,
        :alpha_yz,
        :oracle_batch_size,
        :oracle_success_rate,
        :oracle_latency_us,
        :cpu_usage_percent,
        :memory_usage_mb,
        :gpu_usage_percent,
        :lane_configuration_id,
        :rule_oracle_id,
        :metadata
      ]
    end

    create :record_micro_metric do
      accept [
        :coordinator_id,
        :step_number,
        :micro_latency_us,
        :patches_processed,
        :lane_configuration_id,
        :metadata
      ]

      change set_attribute(:metric_type, "micro")
    end

    create :record_meso_metric do
      accept [
        :coordinator_id,
        :step_number,
        :meso_latency_us,
        :consensus_bursts,
        :system_energy,
        :stability_score,
        :rule_oracle_id,
        :metadata
      ]

      change set_attribute(:metric_type, "meso")
    end

    create :record_macro_metric do
      accept [
        :coordinator_id,
        :step_number,
        :macro_latency_us,
        :fusion_operations,
        :lane_x_energy,
        :lane_y_energy,
        :lane_z_energy,
        :alpha_xy,
        :alpha_xz,
        :alpha_yz,
        :metadata
      ]

      change set_attribute(:metric_type, "macro")
    end

    create :record_system_metric do
      accept [
        :coordinator_id,
        :step_number,
        :total_latency_us,
        :cpu_usage_percent,
        :memory_usage_mb,
        :gpu_usage_percent,
        :metadata
      ]

      change set_attribute(:metric_type, "system")
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :coordinator_id, :string do
      description "Which coordinator instance generated this metric"
    end

    attribute :metric_type, :atom do
      description "Type of metric (micro, meso, macro, fusion)"
      allow_nil? false
      constraints one_of: [:micro, :meso, :macro, :fusion, :system]
    end

    attribute :step_number, :integer do
      description "Processing step number"
      allow_nil? false
      constraints min: 0
    end

    # Timing metrics (all in microseconds)
    attribute :micro_latency_us, :integer do
      description "Micro-level processing latency in microseconds"
    end

    attribute :meso_latency_us, :integer do
      description "Meso-level processing latency in microseconds"
    end

    attribute :macro_latency_us, :integer do
      description "Macro-level processing latency in microseconds"
    end

    attribute :total_latency_us, :integer do
      description "Total processing latency in microseconds"
    end

    # Throughput metrics
    attribute :patches_processed, :integer do
      description "Number of CA patches processed"
      default 0
    end

    attribute :consensus_bursts, :integer do
      description "Number of consensus bursts completed"
      default 0
    end

    attribute :fusion_operations, :integer do
      description "Number of lane fusion operations"
      default 0
    end

    # Energy and stability metrics
    attribute :system_energy, :float do
      description "Total system energy level"
    end

    attribute :energy_drift, :float do
      description "Energy drift from expected baseline"
    end

    attribute :stability_score, :float do
      description "System stability score (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :convergence_rate, :float do
      description "Rate of convergence to optimal solution"
    end

    # Lane-specific metrics
    attribute :lane_x_energy, :float do
      description "X-slice lane energy level"
    end

    attribute :lane_y_energy, :float do
      description "Y-slice lane energy level"
    end

    attribute :lane_z_energy, :float do
      description "Z-slice lane energy level"
    end

    attribute :alpha_xy, :float do
      description "α-coupling strength between X and Y lanes"
    end

    attribute :alpha_xz, :float do
      description "α-coupling strength between X and Z lanes"
    end

    attribute :alpha_yz, :float do
      description "α-coupling strength between Y and Z lanes"
    end

    # Oracle performance
    attribute :oracle_batch_size, :integer do
      description "Batch size used by rule oracle"
    end

    attribute :oracle_success_rate, :float do
      description "Oracle inference success rate"
      constraints min: 0.0, max: 1.0
    end

    attribute :oracle_latency_us, :integer do
      description "Oracle inference latency in microseconds"
    end

    # Resource utilization
    attribute :cpu_usage_percent, :float do
      description "CPU utilization percentage"
      constraints min: 0.0, max: 100.0
    end

    attribute :memory_usage_mb, :integer do
      description "Memory usage in megabytes"
    end

    attribute :gpu_usage_percent, :float do
      description "GPU utilization percentage"
      constraints min: 0.0, max: 100.0
    end

    # Metadata
    attribute :lane_configuration_id, :uuid do
      description "Associated lane configuration"
    end

    attribute :rule_oracle_id, :uuid do
      description "Associated rule oracle"
    end

    attribute :telemetry_snapshot_id, :uuid do
      description "Associated telemetry snapshot"
      allow_nil? true
    end

    attribute :metadata, :map do
      description "Additional metric metadata"
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :lane_configuration, Thunderline.Thunderbolt.Resources.LaneConfiguration do
      description "Lane configuration this metric relates to"
    end

    belongs_to :rule_oracle, Thunderline.Thunderbolt.Resources.RuleOracle do
      description "Rule oracle this metric relates to"
    end

    belongs_to :telemetry_snapshot, Thunderline.Thunderbolt.Resources.TelemetrySnapshot do
      description "Telemetry snapshot this metric relates to"
    end
  end

  calculations do
    calculate :efficiency_score,
              :float,
              expr(
                fragment(
                  """
                    CASE
                      WHEN ? > 0 AND ? > 0 THEN
                        (? + ? + ?)::float / (3.0 * ?)
                      ELSE 0.0
                    END
                  """,
                  patches_processed,
                  total_latency_us,
                  patches_processed,
                  consensus_bursts,
                  fusion_operations,
                  total_latency_us
                )
              ) do
      description "Overall efficiency score combining throughput and latency"
    end

    calculate :lane_balance_score,
              :float,
              expr(
                fragment(
                  """
                    CASE
                      WHEN ? IS NOT NULL AND ? IS NOT NULL AND ? IS NOT NULL THEN
                        1.0 - (ABS(? - ?) + ABS(? - ?) + ABS(? - ?)) / 3.0
                      ELSE 0.0
                    END
                  """,
                  lane_x_energy,
                  lane_y_energy,
                  lane_z_energy,
                  lane_x_energy,
                  lane_y_energy,
                  lane_y_energy,
                  lane_z_energy,
                  lane_x_energy,
                  lane_z_energy
                )
              ) do
      description "How balanced the energy is across X/Y/Z lanes"
    end
  end
end
