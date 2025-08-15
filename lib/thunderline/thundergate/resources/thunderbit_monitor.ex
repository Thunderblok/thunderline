defmodule Thunderline.Thundergate.Resources.ThunderbitMonitor do
  @moduledoc """
  Real-time monitoring and state tracking for Thunderbit agents.

  Provides comprehensive observability into the Thunderbit agent ecosystem,
  tracking agent lifecycle, performance, behavior patterns, and spatial
  coordination within the ECSx framework.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins



  postgres do
    table "thunderbit_monitors"
    repo Thunderline.Repo
  end

  pub_sub do
    module Thunderline.PubSub
    prefix "thundereye:thunderbit"

    publish :track_agent, ["thunderbit:spawned", :agent_id]
    publish :update_status, ["thunderbit:state_changed", :agent_id, :status]
    # publish_all :energy_alert, "thunderbit:energy_critical"  # Invalid type, commented out
  end

  attributes do
    uuid_primary_key :id
    attribute :agent_id, :uuid, allow_nil?: false
    attribute :agent_name, :string
    attribute :status, :atom, constraints: [one_of: [:active, :idle, :processing, :error, :terminated]]
    attribute :behavior_type, :string
    attribute :energy_level, :integer, default: 100
    attribute :position_x, :float
    attribute :position_y, :float
    attribute :position_z, :float
    attribute :velocity, :map, default: %{}
    attribute :last_tick, :utc_datetime
    attribute :tick_count, :integer, default: 0
    attribute :processing_queue_size, :integer, default: 0
    attribute :memory_usage_mb, :float
    attribute :cpu_usage_percent, :float
    attribute :error_count, :integer, default: 0
    attribute :last_error, :string
    attribute :interactions_count, :integer, default: 0
    attribute :performance_score, :float
    attribute :node_name, :string
    attribute :metadata, :map, default: %{}
    create_timestamp :monitored_since
    update_timestamp :last_updated
  end

  actions do
    defaults [:read]

    create :track_agent do
      accept [:agent_id, :agent_name, :status, :behavior_type, :energy_level,
              :position_x, :position_y, :position_z, :node_name, :metadata]

      change set_attribute(:monitored_since, &DateTime.utc_now/0)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :update_status do
      accept [:status, :energy_level, :position_x, :position_y, :position_z,
              :velocity, :processing_queue_size, :memory_usage_mb, :cpu_usage_percent,
              :performance_score]

      change set_attribute(:last_tick, &DateTime.utc_now/0)
      change increment(:tick_count)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :record_error do
      accept [:last_error]
      change increment(:error_count)
      change set_attribute(:status, :error)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :record_interaction do
      change increment(:interactions_count)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    action :energy_alert do
      argument :threshold, :integer, default: 20

      run fn input, _context ->
        agent = input.resource
        threshold = Ash.Changeset.get_argument(input, :threshold)

        if agent.energy_level <= threshold do
          alert_data = %{
            agent_id: agent.agent_id,
            agent_name: agent.agent_name,
            energy_level: agent.energy_level,
            threshold: threshold,
            position: %{x: agent.position_x, y: agent.position_y, z: agent.position_z},
            alerted_at: DateTime.utc_now()
          }

          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "thundereye:thunderbit:energy_critical",
            {:energy_critical, alert_data}
          )

          {:ok, alert_data}
        else
          {:ok, %{alert_triggered: false}}
        end
      end
    end

    read :active_agents do
      filter expr(status in [:active, :processing] and last_tick > ago(60, :second))
    end

    read :by_behavior do
      argument :behavior_type, :string, allow_nil?: false
      filter expr(behavior_type == ^arg(:behavior_type))
    end

    read :low_energy do
      argument :threshold, :integer, default: 30
      filter expr(energy_level <= ^arg(:threshold))
    end

    read :error_agents do
      filter expr(status == :error or error_count > 0)
    end

    read :high_performers do
      filter expr(performance_score > 80.0)
    end

    read :spatial_region do
      argument :min_x, :float, allow_nil?: false
      argument :max_x, :float, allow_nil?: false
      argument :min_y, :float, allow_nil?: false
      argument :max_y, :float, allow_nil?: false

      filter expr(
        position_x >= ^arg(:min_x) and position_x <= ^arg(:max_x) and
        position_y >= ^arg(:min_y) and position_y <= ^arg(:max_y)
      )
    end

    read :stale_agents do
      filter expr(last_tick < ago(300, :second)) # 5 minutes
    end
  end

  calculations do
    calculate :is_active, :boolean, expr(
      status in [:active, :processing] and last_tick > ago(60, :second)
    )

    calculate :uptime_minutes, :integer, expr(
      fragment("EXTRACT(EPOCH FROM (? - ?))/60", last_updated, monitored_since)
    )

    calculate :ticks_per_minute, :float, expr(
      fragment("? / GREATEST(EXTRACT(EPOCH FROM (? - ?))/60, 1)",
        tick_count, last_updated, monitored_since)
    )

    calculate :error_rate, :float, expr(
      fragment("CASE WHEN ? > 0 THEN (?::float / ?::float) * 100 ELSE 0 END",
        tick_count, error_count, tick_count)
    )

    calculate :distance_from_origin, :float, expr(
      fragment("SQRT(POWER(COALESCE(?, 0), 2) + POWER(COALESCE(?, 0), 2) + POWER(COALESCE(?, 0), 2))",
        position_x, position_y, position_z)
    )

    calculate :health_score, :integer, expr(
      cond do
        status == :active and energy_level > 70 and error_count == 0 -> 100
        status == :active and energy_level > 50 and error_count < 3 -> 80
        status == :active and energy_level > 30 -> 60
        status == :error or energy_level <= 10 -> 20
        true -> 40
      end
    )
  end

  # Removed aggregates - they were not properly defined for cross-record aggregation
  # If needed, these should be implemented as calculations or proper relationship aggregates

  identities do
    identity :unique_agent_monitor, [:agent_id]
  end

  preparations do
    prepare build(sort: [last_updated: :desc])
  end
end
