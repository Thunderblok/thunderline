defmodule Thunderline.Thundergate.Resources.ThunderboltMonitor do
  @moduledoc """
  Orchestration and coordination monitoring for Thunderbolt services.

  Tracks distributed infrastructure coordination, load balancing, chunk
  management, and system-wide orchestration health. Provides visibility
  into the coordination layer that manages agent swarms and workload distribution.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  postgres do
    table "thunderbolt_monitors"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :register_service do
      accept [:service_name, :service_type, :region, :node_name, :configuration, :metadata]

      change set_attribute(:status, :online)
      change set_attribute(:registered_at, &DateTime.utc_now/0)
      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :heartbeat do
      accept [
        :load_percentage,
        :active_connections,
        :pending_tasks,
        :completed_tasks,
        :failed_tasks,
        :average_response_time_ms,
        :throughput_per_minute,
        :memory_usage_mb,
        :cpu_usage_percent,
        :disk_usage_percent,
        :network_bandwidth_mbps,
        :chunk_count,
        :chunk_size_mb,
        :health_score
      ]

      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :update_status do
      accept [:status]
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :record_error do
      accept [:last_error]
      change increment(:error_count)
      change set_attribute(:status, :degraded)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :maintenance_mode do
      change set_attribute(:status, :maintenance)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    action :capacity_alert do
      argument :cpu_threshold, :float, default: 85.0
      argument :memory_threshold, :float, default: 80.0
      argument :load_threshold, :float, default: 90.0

      run fn input, _context ->
        service = input.resource
        cpu_threshold = Ash.Changeset.get_argument(input, :cpu_threshold)
        memory_threshold = Ash.Changeset.get_argument(input, :memory_threshold)
        load_threshold = Ash.Changeset.get_argument(input, :load_threshold)

        alerts = []

        alerts =
          if service.cpu_usage_percent > cpu_threshold do
            [%{type: :cpu, value: service.cpu_usage_percent, threshold: cpu_threshold} | alerts]
          else
            alerts
          end

        alerts =
          if service.memory_usage_mb && service.memory_usage_mb > memory_threshold do
            [
              %{type: :memory, value: service.memory_usage_mb, threshold: memory_threshold}
              | alerts
            ]
          else
            alerts
          end

        alerts =
          if service.load_percentage > load_threshold do
            [%{type: :load, value: service.load_percentage, threshold: load_threshold} | alerts]
          else
            alerts
          end

        if length(alerts) > 0 do
          alert_data = %{
            service_name: service.service_name,
            service_type: service.service_type,
            region: service.region,
            node_name: service.node_name,
            alerts: alerts,
            alerted_at: DateTime.utc_now()
          }

          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "thundereye:thunderbolt:capacity_critical",
            {:capacity_critical, alert_data}
          )

          {:ok, alert_data}
        else
          {:ok, %{alerts_triggered: false}}
        end
      end
    end

    read :online_services do
      filter expr(status == :online and last_heartbeat > ago(60, :second))
    end

    read :by_service_type do
      argument :type, :atom, allow_nil?: false
      filter expr(service_type == ^arg(:type))
    end

    read :by_region do
      argument :region_name, :string, allow_nil?: false
      filter expr(region == ^arg(:region_name))
    end

    read :high_load do
      argument :threshold, :float, default: 80.0
      filter expr(load_percentage > ^arg(:threshold))
    end

    read :degraded_services do
      filter expr(status in [:degraded, :offline])
    end

    read :stale_heartbeats do
      # 2 minutes
      filter expr(last_heartbeat < ago(120, :second))
    end

    read :chunk_managers do
      filter expr(service_type == :chunk_manager)
    end

    read :load_balancers do
      filter expr(service_type == :load_balancer)
    end
  end

  pub_sub do
    module Thunderline.PubSub
    prefix "thundereye:thunderbolt"

    publish :register_service, ["thunderbolt:service_registered", :service_name]
    publish :heartbeat, ["thunderbolt:status_changed", :service_name, :status]
    # Removed invalid publish_all with custom type - use standard action types only
    # publish_all :capacity_alert, "thunderbolt:capacity_critical"
  end

  preparations do
    prepare build(sort: [last_heartbeat: :desc])
  end

  attributes do
    uuid_primary_key :id
    attribute :service_name, :string, allow_nil?: false

    attribute :service_type, :atom,
      constraints: [one_of: [:chunk_manager, :load_balancer, :orchestrator, :coordinator]]

    attribute :status, :atom, constraints: [one_of: [:online, :degraded, :offline, :maintenance]]
    attribute :region, :string
    attribute :node_name, :string
    attribute :load_percentage, :float, default: 0.0
    attribute :active_connections, :integer, default: 0
    attribute :pending_tasks, :integer, default: 0
    attribute :completed_tasks, :integer, default: 0
    attribute :failed_tasks, :integer, default: 0
    attribute :average_response_time_ms, :float
    attribute :throughput_per_minute, :float, default: 0.0
    attribute :memory_usage_mb, :float
    attribute :cpu_usage_percent, :float
    attribute :disk_usage_percent, :float
    attribute :network_bandwidth_mbps, :float
    attribute :chunk_count, :integer, default: 0
    attribute :chunk_size_mb, :float, default: 0.0
    attribute :replication_factor, :integer
    attribute :health_score, :float, default: 100.0
    attribute :last_heartbeat, :utc_datetime
    attribute :error_count, :integer, default: 0
    attribute :last_error, :string
    attribute :configuration, :map, default: %{}
    attribute :metadata, :map, default: %{}
    create_timestamp :registered_at
    update_timestamp :last_updated
  end

  calculations do
    calculate :is_healthy,
              :boolean,
              expr(
                status == :online and last_heartbeat > ago(60, :second) and
                  load_percentage < 90.0 and error_count < 10
              )

    calculate :uptime_hours,
              :float,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))/3600", last_updated, registered_at))

    calculate :task_success_rate,
              :float,
              expr(
                fragment(
                  "CASE WHEN (? + ?) > 0 THEN (?::float / (? + ?)::float) * 100 ELSE 100 END",
                  completed_tasks,
                  failed_tasks,
                  completed_tasks,
                  completed_tasks,
                  failed_tasks
                )
              )

    calculate :error_rate,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? > 0 THEN (?::float / ?::float) * 100 ELSE 0 END",
                  completed_tasks,
                  error_count,
                  completed_tasks
                )
              )

    calculate :capacity_utilization,
              :float,
              expr(
                fragment(
                  "(COALESCE(?, 0) + COALESCE(?, 0) + COALESCE(?, 0)) / 3",
                  load_percentage,
                  cpu_usage_percent,
                  memory_usage_mb
                )
              )

    calculate :performance_grade,
              :atom,
              expr(
                cond do
                  health_score > 95 and task_success_rate > 99 -> :excellent
                  health_score > 85 and task_success_rate > 95 -> :good
                  health_score > 70 and task_success_rate > 90 -> :acceptable
                  health_score > 50 -> :poor
                  true -> :critical
                end
              )

    calculate :heartbeat_age_seconds,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))", now(), last_heartbeat))
  end

  # Removed aggregates - they were not properly defined for cross-record aggregation
  # If needed, these should be implemented as calculations or proper relationship aggregates

  identities do
    identity :unique_service, [:service_name, :node_name]
  end
end
