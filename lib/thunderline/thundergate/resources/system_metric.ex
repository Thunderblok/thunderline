defmodule Thunderline.Thundergate.Resources.SystemMetric do
  @moduledoc """
  Telemetry aggregation and storage for system-wide metrics.

  Collects performance data, throughput metrics, and system utilization
  across all Thunderline domains for real-time monitoring and analysis.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "system_metrics"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :domain, :string, allow_nil?: false
    attribute :metric_name, :string, allow_nil?: false
    attribute :value, :decimal, allow_nil?: false
    attribute :unit, :string
    attribute :tags, :map, default: %{}
    attribute :node_name, :string
    create_timestamp :collected_at
  end

  actions do
    defaults [:read]

    create :collect do
      accept [:domain, :metric_name, :value, :unit, :tags, :node_name]
    end

    update :aggregate do
      accept [:value]
    end

    read :recent do
      argument :time_window, :integer, default: 300 # 5 minutes
      filter expr(collected_at > ago(^arg(:time_window), :second))
    end

    read :by_domain do
      argument :domain_name, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain_name))
    end
  end

  identities do
    identity :unique_metric_point, [:domain, :metric_name, :collected_at, :node_name]
  end

  preparations do
    prepare build(sort: [collected_at: :desc])
  end
end
