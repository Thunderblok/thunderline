defmodule Thunderline.Thunderbolt.Resources.ChunkHealth do
  @moduledoc """
  ChunkHealth Resource - Health monitoring for 144-bit meshes

  Tracks health metrics, resource usage, performance indicators, and diagnostic
  information for each Thunderbolt chunk. Provides health data and triggers
  for automated remediation.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshOban, AshGraphql.Resource],
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  # IN-MEMORY CONFIGURATION (sqlite removed)
  # Using :embedded data layer

  json_api do
    type "chunk_health"

    routes do
      base("/chunk-health")
      get(:read)
      index :read
      post(:create)
      get :health_report, route: "/:id/report"
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :record_health_check do
      accept [
        :status,
        :health_score,
        :cpu_usage_percent,
        :memory_usage_mb,
        :network_throughput_kbps,
        :response_time_ms,
        :throughput_ops_per_second,
        :error_rate_percent,
        :active_bit_count,
        :dormant_bit_count,
        :activation_failures,
        :signal_routing_errors,
        :warnings,
        :errors,
        :thundercore_pulse_health,
        :neighbor_connectivity
      ]

      # The last_check will be automatically set by create_timestamp
    end

    update :update_status do
      accept [:status, :health_score, :warnings, :errors]
      # The last_check field is now a create_timestamp, so it doesn't need manual updates
    end

    read :health_report do
      get? true
      # Simplified version without complex build function
    end

    read :critical_chunks do
      filter expr(is_critical == true)
    end

    read :degraded_chunks do
      filter expr(status in [:degraded, :critical])
    end

    read :recent_health_checks do
      argument :hours_ago, :integer, default: 24

      filter expr(last_check > ago(^arg(:hours_ago), :hour))
    end
  end

  # oban do
  #   triggers do
  #     trigger :health_degradation_alert do
  #       action :update_status
  #       scheduler_cron "*/1 * * * *"  # Every minute
  #       where expr(status in [:critical, :degraded])
  #     end
  #   end
  # end

  pub_sub do
    module Thunderline.PubSub
    prefix "thunderbolt:health"

    publish :create, ["health:created", :chunk_id]
    publish :update, ["health:updated", :chunk_id]
    # Custom events for health state changes
    # publish :health_critical, ["health:critical", :chunk_id]
    # publish :health_recovered, ["health:recovered", :chunk_id]
  end

  attributes do
    uuid_primary_key :id

    # Health status and metrics
    attribute :status, :atom,
      constraints: [
        one_of: [:healthy, :degraded, :critical, :recovering, :offline]
      ],
      default: :healthy

    attribute :health_score, :decimal, default: Decimal.new("1.0")
    create_timestamp :last_check

    # Resource Usage Metrics
    attribute :cpu_usage_percent, :decimal, default: Decimal.new("0.0")
    attribute :memory_usage_mb, :integer, default: 0
    attribute :memory_limit_mb, :integer, default: 1024
    attribute :network_throughput_kbps, :decimal, default: Decimal.new("0.0")

    # Performance metrics
    attribute :response_time_ms, :decimal, default: Decimal.new("0.0")
    attribute :throughput_ops_per_second, :decimal, default: Decimal.new("0.0")
    attribute :error_rate_percent, :decimal, default: Decimal.new("0.0")

    # Thunderbit-specific metrics
    attribute :active_bit_count, :integer, default: 0
    attribute :dormant_bit_count, :integer, default: 0
    attribute :activation_failures, :integer, default: 0
    attribute :signal_routing_errors, :integer, default: 0

    # Diagnostic information
    attribute :warnings, {:array, :string}, default: []
    attribute :errors, {:array, :string}, default: []
    attribute :recovery_actions, {:array, :string}, default: []

    # Environmental factors
    attribute :cluster_node, :string, default: nil
    attribute :thundercore_pulse_health, :boolean, default: true
    attribute :neighbor_connectivity, :map, default: %{}

    timestamps()
  end

  relationships do
    belongs_to :chunk, Thunderline.Thunderbolt.Resources.Chunk do
      attribute_writable? true
    end
  end

  calculations do
    calculate :memory_usage_percent, :decimal, expr(memory_usage_mb / memory_limit_mb * 100)

    calculate :overall_health_score,
              :decimal,
              expr(
                (health_score +
                   (100 - cpu_usage_percent) / 100 +
                   (100 - memory_usage_percent) / 100 +
                   (100 - error_rate_percent) / 100) / 4
              )

    calculate :is_critical,
              :boolean,
              expr(
                status in [:critical, :offline] or
                  cpu_usage_percent > 90 or
                  memory_usage_percent > 90 or
                  error_rate_percent > 50
              )
  end

  # Private action implementations
  defp evaluate_health_thresholds(_changeset, health_record) do
    # TODO: Implement ML-based health threshold evaluation
    # For now, use simple thresholds
    cond do
      health_record.cpu_usage_percent |> Decimal.gt?(90) or
          health_record.error_rate_percent |> Decimal.gt?(50) ->
        {:ok, %{health_record | status: :critical}}

      health_record.cpu_usage_percent |> Decimal.gt?(70) or
          health_record.error_rate_percent |> Decimal.gt?(20) ->
        {:ok, %{health_record | status: :degraded}}

      true ->
        {:ok, %{health_record | status: :healthy}}
    end
  end

  defp trigger_remediation_if_needed(_changeset, health_record) do
    if health_record.status in [:critical, :degraded] do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "thunderbolt:remediation",
        {:remediation_needed, health_record}
      )
    end

    {:ok, health_record}
  end

  defp broadcast_health_change(_changeset, health_record) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:health:#{health_record.chunk_id}",
      {:health_changed, health_record}
    )

    {:ok, health_record}
  end
end
