defmodule Thunderline.Thundergate.Resources.HealthCheck do
  @moduledoc """
  System health monitoring and status coordination across Thunderline domains.

  Orchestrates health checks for all domains, services, and infrastructure
  components. Provides real-time health status and historical health trends
  for operational visibility and alerting.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  postgres do
    table "health_checks"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :perform_check do
      accept [
        :component,
        :domain,
        :status,
        :response_time_ms,
        :message,
        :details,
        :node_name,
        :endpoint_url,
        :check_type,
        :timeout_ms,
        :expected_status_code,
        :metadata
      ]

      change set_attribute(:checked_at, &DateTime.utc_now/0)
    end

    create :quick_ping do
      accept [:component, :domain, :status, :response_time_ms]
      change set_attribute(:check_type, :heartbeat)
      change set_attribute(:checked_at, &DateTime.utc_now/0)
    end

    read :current_status do
      # Get the most recent health check for each component

      # 5 minutes
      filter expr(checked_at > ago(300, :second))
    end

    read :by_domain do
      argument :domain_name, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain_name))
    end

    read :by_status do
      argument :health_status, :atom, allow_nil?: false
      filter expr(status == ^arg(:health_status))
    end

    read :unhealthy_components do
      filter expr(status in [:degraded, :unhealthy] and checked_at > ago(300, :second))
    end

    read :slow_responses do
      argument :threshold_ms, :integer, default: 1000
      filter expr(response_time_ms > ^arg(:threshold_ms))
    end

    read :component_history do
      argument :component_name, :string, allow_nil?: false
      argument :hours, :integer, default: 24
      filter expr(component == ^arg(:component_name) and checked_at > ago(^arg(:hours), :hour))
    end
  end

  preparations do
    prepare build(sort: [checked_at: :desc])
  end

  #   notifiers do
  #     module Thunderline.PubSub
  #     prefix "thundereye:health"
  #
  #     publish :create, ["health:checked", :component]
  #     publish :update, ["health:status_changed", :component, :status]
  #   end

  attributes do
    uuid_primary_key :id
    attribute :component, :string, allow_nil?: false
    attribute :domain, :string, allow_nil?: false
    attribute :status, :atom, constraints: [one_of: [:healthy, :degraded, :unhealthy, :unknown]]
    attribute :response_time_ms, :integer
    attribute :message, :string
    attribute :details, :map, default: %{}
    attribute :node_name, :string
    attribute :endpoint_url, :string

    attribute :check_type, :atom,
      constraints: [one_of: [:heartbeat, :deep, :dependency, :resource]]

    attribute :timeout_ms, :integer, default: 30_000
    attribute :expected_status_code, :integer
    attribute :metadata, :map, default: %{}
    create_timestamp :checked_at
  end

  calculations do
    calculate :is_recent, :boolean, expr(checked_at > ago(300, :second))

    calculate :health_score,
              :integer,
              expr(
                cond do
                  status == :healthy and response_time_ms < 500 -> 100
                  status == :healthy and response_time_ms < 1000 -> 90
                  status == :healthy -> 80
                  status == :degraded -> 60
                  status == :unhealthy -> 20
                  true -> 0
                end
              )

    calculate :availability_24h,
              :decimal,
              expr(
                fragment(
                  """
                  (SELECT COALESCE(
                    (COUNT(CASE WHEN status = 'healthy' THEN 1 END) * 100.0) /
                    NULLIF(COUNT(*), 0), 0
                  ) FROM health_checks hc2
                  WHERE hc2.component = ?
                  AND hc2.checked_at > ?)
                  """,
                  component,
                  ago(24, :hour)
                )
              )

    calculate :last_healthy,
              :utc_datetime,
              expr(
                fragment(
                  """
                  (SELECT MAX(checked_at) FROM health_checks hc2
                   WHERE hc2.component = ?
                   AND hc2.status = 'healthy')
                  """,
                  component
                )
              )
  end

  aggregates do
    # Commented out - aggregate on same resource needs different syntax in Ash 3.x
    # avg :avg_response_time, :response_time_ms do
    #   filter expr(checked_at > ago(1, :hour))
    # end

    # Commented out - count on same resource needs different syntax in Ash 3.x
    # count :check_count_24h, :id do
    #   filter expr(checked_at > ago(24, :hour))
    # end
  end

  identities do
    identity :unique_check, [:component, :domain, :checked_at]
  end
end
