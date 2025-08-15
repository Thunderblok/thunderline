defmodule Thunderline.Thunderbolt.Resources.TelemetrySnapshot do
  @moduledoc """
  Telemetry snapshots for CTRW-aware event-wave monitoring.

  Implements exponential tail latency tracking and anti-bunching
  analysis based on continuous-time random walk mathematics.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlane_telemetry_snapshots"
    repo Thunderline.Repo
  end

  json_api do
    type "telemetry_snapshots"
  end

  code_interface do
    define :create
    define :read
    define :capture_window_snapshot
    define :capture_burst_snapshot
    define :capture_anomaly_snapshot
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :coordinator_id,
        :snapshot_type,
        :window_start_ms,
        :window_end_ms,
        :window_duration_ms,
        :total_events,
        :event_rate_per_second,
        :burst_count,
        :anti_bunching_effectiveness,
        :displacement_mean,
        :displacement_variance,
        :tail_exponent,
        :tail_fit_quality,
        :latency_mean_us,
        :latency_median_us,
        :latency_p90_us,
        :latency_p95_us,
        :latency_p99_us,
        :latency_p999_us,
        :latency_max_us,
        :queue_depth_mean,
        :queue_depth_max,
        :backpressure_events,
        :dropped_events,
        :cpu_usage_mean,
        :memory_usage_mean_mb,
        :memory_usage_max_mb,
        :gc_count,
        :gc_total_time_ms,
        :network_bytes_in,
        :network_bytes_out,
        :coordination_messages,
        :coordination_latency_us,
        :error_count,
        :anomaly_score,
        :anomaly_features,
        :lane_configuration_id,
        :rule_oracle_id,
        :metadata
      ]
    end

    create :capture_window_snapshot do
      accept [
        :coordinator_id,
        :window_start_ms,
        :window_end_ms,
        :total_events,
        :latency_mean_us,
        :latency_p99_us,
        :cpu_usage_mean,
        :lane_configuration_id
      ]

      change set_attribute(:snapshot_type, "window")
    end

    create :capture_burst_snapshot do
      accept [
        :coordinator_id,
        :burst_count,
        :anti_bunching_effectiveness,
        :displacement_mean,
        :tail_exponent,
        :rule_oracle_id
      ]

      change set_attribute(:snapshot_type, "burst")
    end

    create :capture_anomaly_snapshot do
      accept [
        :coordinator_id,
        :anomaly_score,
        :anomaly_features,
        :error_count,
        :latency_max_us,
        :queue_depth_max
      ]

      change set_attribute(:snapshot_type, "anomaly")
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
      description "Coordinator instance that generated this snapshot"
      allow_nil? false
    end

    attribute :snapshot_type, :atom do
      description "Type of telemetry snapshot"
      allow_nil? false
      constraints one_of: [:window, :burst, :anomaly, :baseline]
    end

    attribute :window_start_ms, :integer do
      description "Start of measurement window in milliseconds"
    end

    attribute :window_end_ms, :integer do
      description "End of measurement window in milliseconds"
    end

    attribute :window_duration_ms, :integer do
      description "Duration of measurement window in milliseconds"
    end

    # Event statistics
    attribute :total_events, :integer do
      description "Total number of events in this window"
      default 0
    end

    attribute :event_rate_per_second, :float do
      description "Events per second during this window"
    end

    attribute :burst_count, :integer do
      description "Number of burst events detected"
      default 0
    end

    attribute :anti_bunching_effectiveness, :float do
      description "Effectiveness of anti-bunching measures (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    # CTRW tail statistics
    attribute :displacement_mean, :float do
      description "Mean displacement in continuous-time random walk"
    end

    attribute :displacement_variance, :float do
      description "Variance in displacement measurements"
    end

    attribute :tail_exponent, :float do
      description "Tail exponent for exponential tail fitting"
    end

    attribute :tail_fit_quality, :float do
      description "R-squared value for exponential tail fit quality"
      constraints min: 0.0, max: 1.0
    end

    # Latency distribution
    attribute :latency_mean_us, :float do
      description "Mean latency in microseconds"
    end

    attribute :latency_median_us, :float do
      description "Median latency in microseconds"
    end

    attribute :latency_p90_us, :integer do
      description "90th percentile latency in microseconds"
    end

    attribute :latency_p95_us, :integer do
      description "95th percentile latency in microseconds"
    end

    attribute :latency_p99_us, :integer do
      description "99th percentile latency in microseconds"
    end

    attribute :latency_p999_us, :integer do
      description "99.9th percentile latency in microseconds"
    end

    attribute :latency_max_us, :integer do
      description "Maximum latency observed in microseconds"
    end

    # Queue and backpressure metrics
    attribute :queue_depth_mean, :float do
      description "Mean queue depth during window"
    end

    attribute :queue_depth_max, :integer do
      description "Maximum queue depth observed"
    end

    attribute :backpressure_events, :integer do
      description "Number of backpressure events"
      default 0
    end

    attribute :dropped_events, :integer do
      description "Number of dropped events due to overload"
      default 0
    end

    # System resource metrics
    attribute :cpu_usage_mean, :float do
      description "Mean CPU usage percentage during window"
      constraints min: 0.0, max: 100.0
    end

    attribute :memory_usage_mean_mb, :integer do
      description "Mean memory usage in megabytes"
    end

    attribute :memory_usage_max_mb, :integer do
      description "Peak memory usage in megabytes"
    end

    attribute :gc_count, :integer do
      description "Number of garbage collection events"
      default 0
    end

    attribute :gc_total_time_ms, :integer do
      description "Total time spent in garbage collection (ms)"
      default 0
    end

    # Network and coordination metrics
    attribute :network_bytes_in, :integer do
      description "Network bytes received during window"
      default 0
    end

    attribute :network_bytes_out, :integer do
      description "Network bytes sent during window"
      default 0
    end

    attribute :coordination_messages, :integer do
      description "Inter-coordinator messages exchanged"
      default 0
    end

    attribute :coordination_latency_us, :integer do
      description "Average coordination message latency"
    end

    # Error and anomaly tracking
    attribute :error_count, :integer do
      description "Number of errors during window"
      default 0
    end

    attribute :anomaly_score, :float do
      description "Anomaly detection score (higher = more anomalous)"
      default 0.0
    end

    attribute :anomaly_features, :map do
      description "Features that contributed to anomaly detection"
      default %{}
    end

    # Metadata
    attribute :lane_configuration_id, :uuid do
      description "Associated lane configuration"
    end

    attribute :rule_oracle_id, :uuid do
      description "Associated rule oracle"
    end

    attribute :metadata, :map do
      description "Additional telemetry metadata"
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :lane_configuration, Thunderline.Thunderbolt.Resources.LaneConfiguration do
      description "Lane configuration this telemetry relates to"
    end

    belongs_to :rule_oracle, Thunderline.Thunderbolt.Resources.RuleOracle do
      description "Rule oracle this telemetry relates to"
    end

    has_many :performance_metrics, Thunderline.Thunderbolt.Resources.PerformanceMetric do
      description "Performance metrics captured during this window"
    end
  end

  calculations do
    calculate :throughput_score,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? > 0 THEN ?::float / ? ELSE 0.0 END",
                  window_duration_ms,
                  total_events,
                  window_duration_ms
                )
              ) do
      description "Events processed per millisecond"
    end

    calculate :latency_stability,
              :float,
              expr(
                fragment(
                  """
                    CASE
                      WHEN ? > 0 AND ? > 0 THEN
                        1.0 - (?::float - ?) / ?
                      ELSE 0.0
                    END
                  """,
                  latency_mean_us,
                  latency_median_us,
                  latency_p99_us,
                  latency_median_us,
                  latency_mean_us
                )
              ) do
      description "Stability score based on latency distribution"
    end

    calculate :system_health_score,
              :float,
              expr(
                fragment(
                  """
                    LEAST(1.0,
                      (1.0 - ?::float / 100.0) * 0.4 +  -- CPU component
                      (1.0 - ?::float / 100.0) * 0.3 +  -- Anti-bunching component
                      (1.0 - ?::float / 1000.0) * 0.3   -- Error rate component
                    )
                  """,
                  cpu_usage_mean,
                  fragment("100.0 - ? * 100.0", anti_bunching_effectiveness),
                  error_count
                )
              ) do
      description "Overall system health score (0.0 to 1.0)"
    end
  end
end
