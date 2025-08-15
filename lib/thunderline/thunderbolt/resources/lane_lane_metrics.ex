defmodule Thunderline.Thunderbolt.Resources.LaneMetrics do
  @moduledoc """
  LaneMetrics Resource - Performance and operational metrics for lane processing.

  This resource captures time-series metrics for lane coordination, coupling
  performance, and system health monitoring.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource, AshEvents.Events]

  postgres do
    table "thunderlane_lane_metrics"
    repo Thunderline.Repo
  end

  # ============================================================================
  # JSON API
  # ============================================================================

  json_api do
    type "lane_metrics"

    routes do
      base("/metrics")
      get(:read)
      index :read
      post(:create)
      post(:capture_performance, route: "/capture/performance")
      post(:capture_coupling, route: "/capture/coupling")
      post(:capture_health, route: "/capture/health")
      post(:capture_optimization, route: "/capture/optimization")
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  graphql do
    type :lane_metrics

    queries do
      get :get_metrics, :read
      list :list_metrics, :read
      list :recent_metrics, :recent_metrics
      list :performance_alerts, :performance_alerts
      list :trending_metrics, :trending_metrics
    end

    mutations do
      create :create_metrics, :create
      create :capture_performance_metrics, :capture_performance
      create :capture_coupling_metrics, :capture_coupling
      create :capture_health_metrics, :capture_health
      create :capture_optimization_metrics, :capture_optimization
    end
  end

  # ============================================================================
  # EVENTS
  # ============================================================================

  events do
    event_log(Thunderline.Thunderflow.Events.Event)
    current_action_versions(create: 1, update: 1, destroy: 1)
  end

  # ============================================================================
  # ACTIONS
  # ============================================================================

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :metric_type,
        :source_type,
        :source_id,
        :timestamp,
        :measurement_window_ms,
        :sequence_number,
        :lane_dimension,
        :updates_per_second,
        :coordination_latency_ms,
        :cells_processed,
        :events_processed,
        :queue_depth,
        :coupling_strength,
        :coupling_latency_ms,
        :mutual_information,
        :phase_coherence,
        :energy_transfer,
        :alpha_effectiveness,
        :throughput,
        :latency_p50_ms,
        :latency_p95_ms,
        :latency_p99_ms,
        :error_rate,
        :success_rate,
        :cpu_usage_percent,
        :memory_usage_mb,
        :memory_usage_percent,
        :network_io_mbps,
        :disk_io_mbps,
        :stability_score,
        :health_score,
        :anomaly_score,
        :optimization_target,
        :optimization_score,
        :improvement_factor,
        :convergence_rate,
        :pathflow_accuracy,
        :pattern_recognition_rate,
        :emergence_detection_count,
        :computation_efficiency,
        :raw_metrics,
        :aggregated_metrics,
        :trend_indicators,
        :tags,
        :metadata,
        :measurement_confidence,
        :data_quality_score,
        :coordinator_id,
        :coupling_id,
        :topology_id,
        :ruleset_id
      ]

      change fn changeset, _ ->
        timestamp = Ash.Changeset.get_attribute(changeset, :timestamp) || DateTime.utc_now()
        Ash.Changeset.change_attribute(changeset, :timestamp, timestamp)
      end

      change after_action(&emit_metrics_event/2)
    end

    update :update do
      accept [
        :measurement_window_ms,
        :sequence_number,
        :updates_per_second,
        :coordination_latency_ms,
        :cells_processed,
        :events_processed,
        :queue_depth,
        :coupling_strength,
        :coupling_latency_ms,
        :mutual_information,
        :phase_coherence,
        :energy_transfer,
        :alpha_effectiveness,
        :throughput,
        :latency_p50_ms,
        :latency_p95_ms,
        :latency_p99_ms,
        :error_rate,
        :success_rate,
        :cpu_usage_percent,
        :memory_usage_mb,
        :memory_usage_percent,
        :network_io_mbps,
        :disk_io_mbps,
        :stability_score,
        :health_score,
        :anomaly_score,
        :optimization_score,
        :improvement_factor,
        :convergence_rate,
        :pathflow_accuracy,
        :pattern_recognition_rate,
        :emergence_detection_count,
        :computation_efficiency,
        :raw_metrics,
        :aggregated_metrics,
        :trend_indicators,
        :tags,
        :metadata,
        :measurement_confidence,
        :data_quality_score
      ]
    end

    create :capture_performance do
      accept [
        :source_type,
        :source_id,
        :lane_dimension,
        :updates_per_second,
        :coordination_latency_ms,
        :cells_processed,
        :events_processed,
        :queue_depth,
        :throughput,
        :latency_p50_ms,
        :latency_p95_ms,
        :latency_p99_ms,
        :error_rate,
        :success_rate,
        :cpu_usage_percent,
        :memory_usage_mb,
        :memory_usage_percent,
        :raw_metrics,
        :tags,
        :coordinator_id,
        :coupling_id,
        :topology_id,
        :ruleset_id
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:metric_type, :lane_performance)
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
      end
    end

    create :capture_coupling do
      accept [
        :source_id,
        :lane_dimension,
        :coupling_strength,
        :coupling_latency_ms,
        :mutual_information,
        :phase_coherence,
        :energy_transfer,
        :alpha_effectiveness,
        :raw_metrics,
        :tags,
        :coupling_id
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:metric_type, :coupling_performance)
        |> Ash.Changeset.change_attribute(:source_type, :coupling)
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
      end
    end

    create :capture_health do
      accept [
        :source_type,
        :source_id,
        :stability_score,
        :health_score,
        :anomaly_score,
        :error_rate,
        :success_rate,
        :raw_metrics,
        :tags,
        :coordinator_id,
        :coupling_id,
        :topology_id,
        :ruleset_id
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:metric_type, :system_health)
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
      end
    end

    create :capture_optimization do
      accept [
        :source_type,
        :source_id,
        :optimization_target,
        :optimization_score,
        :improvement_factor,
        :convergence_rate,
        :raw_metrics,
        :tags,
        :coordinator_id,
        :coupling_id,
        :topology_id,
        :ruleset_id
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:metric_type, :optimization_result)
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
      end
    end

    read :recent_metrics do
      argument :minutes_ago, :integer, default: 60

      prepare fn query, %{arguments: %{minutes_ago: minutes_ago}} ->
        cutoff = DateTime.utc_now() |> DateTime.add(-minutes_ago, :minute)
        Ash.Query.filter(query, expr(timestamp >= ^cutoff))
      end
    end

    read :by_source do
      argument :source_type, :atom, allow_nil?: false
      argument :source_id, :uuid, allow_nil?: false
      filter expr(source_type == ^arg(:source_type) and source_id == ^arg(:source_id))
    end

    read :by_metric_type do
      argument :metric_type, :atom, allow_nil?: false
      filter expr(metric_type == ^arg(:metric_type))
    end

    read :by_lane do
      argument :lane_dimension, :atom, allow_nil?: false
      filter expr(lane_dimension == ^arg(:lane_dimension))
    end

    read :performance_alerts do
      filter expr(health_score < 0.7 or anomaly_score > 0.3 or error_rate > 0.1)
    end

    read :trending_metrics do
      argument :hours, :integer, default: 24

      prepare fn query, %{arguments: %{hours: hours}} ->
        cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

        query
        |> Ash.Query.filter(expr(timestamp >= ^cutoff))
        |> Ash.Query.sort(timestamp: :desc)
      end
    end
  end

  # ============================================================================
  # ATTRIBUTES
  # ============================================================================

  attributes do
    uuid_primary_key :id

    # Core Identity
    attribute :metric_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [
          :lane_performance,
          :coupling_performance,
          :topology_health,
          :rule_effectiveness,
          :system_health,
          :optimization_result
        ]
      ]

    attribute :source_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:coordinator, :coupling, :topology, :ruleset, :system]]

    attribute :source_id, :uuid, public?: true

    # Foreign Keys for Relationships
    attribute :lane_coordinator_id, :uuid, public?: true
    attribute :cross_lane_coupling_id, :uuid, public?: true
    attribute :rule_set_id, :uuid, public?: true
    attribute :cell_topology_id, :uuid, public?: true

    # Temporal Information
    attribute :timestamp, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :measurement_window_ms, :integer, public?: true
    attribute :sequence_number, :integer, public?: true

    # Lane-Specific Metrics
    attribute :lane_dimension, :atom,
      public?: true,
      constraints: [one_of: [:x, :y, :z, :all]]

    attribute :updates_per_second, :float, public?: true
    attribute :coordination_latency_ms, :float, public?: true
    attribute :cells_processed, :integer, public?: true
    attribute :events_processed, :integer, public?: true
    attribute :queue_depth, :integer, public?: true

    # Coupling Metrics
    attribute :coupling_strength, :float, public?: true
    attribute :coupling_latency_ms, :float, public?: true
    attribute :mutual_information, :float, public?: true
    attribute :phase_coherence, :float, public?: true
    attribute :energy_transfer, :float, public?: true
    attribute :alpha_effectiveness, :float, public?: true

    # Performance Metrics
    attribute :throughput, :float, public?: true
    attribute :latency_p50_ms, :float, public?: true
    attribute :latency_p95_ms, :float, public?: true
    attribute :latency_p99_ms, :float, public?: true
    attribute :error_rate, :float, public?: true
    attribute :success_rate, :float, public?: true

    # Resource Utilization
    attribute :cpu_usage_percent, :float, public?: true
    attribute :memory_usage_mb, :float, public?: true
    attribute :memory_usage_percent, :float, public?: true
    attribute :network_io_mbps, :float, public?: true
    attribute :disk_io_mbps, :float, public?: true

    # Health and Stability
    attribute :stability_score, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    attribute :health_score, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    attribute :anomaly_score, :float,
      public?: true,
      default: 0.0,
      constraints: [min: 0.0, max: 1.0]

    # Optimization Metrics
    attribute :optimization_target, :string, public?: true
    attribute :optimization_score, :float, public?: true
    attribute :improvement_factor, :float, public?: true
    attribute :convergence_rate, :float, public?: true

    # Business/Application Metrics
    attribute :pathflow_accuracy, :float, public?: true
    attribute :pattern_recognition_rate, :float, public?: true
    attribute :emergence_detection_count, :integer, public?: true
    attribute :computation_efficiency, :float, public?: true

    # Raw Metric Data
    attribute :raw_metrics, :map, public?: true, default: %{}
    attribute :aggregated_metrics, :map, public?: true, default: %{}
    attribute :trend_indicators, :map, public?: true, default: %{}

    # Metadata
    attribute :tags, :map, public?: true, default: %{}
    attribute :metadata, :map, public?: true, default: %{}

    # Quality and Confidence
    attribute :measurement_confidence, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    attribute :data_quality_score, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    # Timestamps
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # ============================================================================
  # RELATIONSHIPS
  # ============================================================================

  relationships do
    belongs_to :coordinator, Thunderline.Thunderbolt.Resources.LaneCoordinator do
      attribute_writable? true
      public? true
    end

    belongs_to :coupling, Thunderline.Thunderbolt.Resources.CrossLaneCoupling do
      attribute_writable? true
      public? true
    end

    belongs_to :topology, Thunderline.Thunderbolt.Resources.CellTopology do
      attribute_writable? true
      public? true
    end

    belongs_to :ruleset, Thunderline.Thunderbolt.Resources.RuleSet do
      attribute_writable? true
      public? true
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp emit_metrics_event(_changeset, metrics) do
    # Emit real-time metrics update
    Thunderline.EventBus.emit_realtime(:metrics_captured, %{
      metric_id: metrics.id,
      metric_type: metrics.metric_type,
      source_type: metrics.source_type,
      source_id: metrics.source_id,
      timestamp: metrics.timestamp,
      key_metrics: extract_key_metrics(metrics)
    })

    # Check for alerts
    check_and_emit_alerts(metrics)

    {:ok, metrics}
  end

  defp extract_key_metrics(metrics) do
    %{
      health_score: metrics.health_score,
      throughput: metrics.throughput,
      latency_p95_ms: metrics.latency_p95_ms,
      error_rate: metrics.error_rate,
      anomaly_score: metrics.anomaly_score
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Map.new()
  end

  defp check_and_emit_alerts(metrics) do
    alerts = []

    alerts =
      if metrics.health_score && metrics.health_score < 0.7 do
        [%{type: :health_degraded, value: metrics.health_score, threshold: 0.7} | alerts]
      else
        alerts
      end

    alerts =
      if metrics.anomaly_score && metrics.anomaly_score > 0.3 do
        [%{type: :anomaly_detected, value: metrics.anomaly_score, threshold: 0.3} | alerts]
      else
        alerts
      end

    alerts =
      if metrics.error_rate && metrics.error_rate > 0.1 do
        [%{type: :high_error_rate, value: metrics.error_rate, threshold: 0.1} | alerts]
      else
        alerts
      end

    alerts =
      if metrics.latency_p95_ms && metrics.latency_p95_ms > 100.0 do
        [%{type: :high_latency, value: metrics.latency_p95_ms, threshold: 100.0} | alerts]
      else
        alerts
      end

    if not Enum.empty?(alerts) do
      Thunderline.EventBus.emit_realtime(:metrics_alerts, %{
        metric_id: metrics.id,
        source_type: metrics.source_type,
        source_id: metrics.source_id,
        alerts: alerts,
        timestamp: metrics.timestamp
      })
    end
  end
end
