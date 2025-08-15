defmodule Thunderline.Thundergate.Resources.PerformanceTrace do
  @moduledoc """
  Request/response timing and bottleneck detection.

  Tracks performance traces across all system operations to identify
  bottlenecks, slow queries, and optimization opportunities.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "performance_traces"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :trace_id, :string, allow_nil?: false
    attribute :span_name, :string, allow_nil?: false
    attribute :duration_ms, :integer, allow_nil?: false
    attribute :status, :atom, constraints: [one_of: [:success, :error, :timeout]]
    attribute :domain, :string
    attribute :operation, :string
    attribute :metadata, :map, default: %{}
    attribute :parent_span_id, :string
    attribute :node_name, :string
    create_timestamp :started_at
    update_timestamp :completed_at
  end

  actions do
    defaults [:read]

    create :start_trace do
      accept [:trace_id, :span_name, :domain, :operation, :metadata, :parent_span_id, :node_name]
    end

    update :complete_trace do
      accept [:duration_ms, :status, :metadata]
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :slow_operations do
      argument :threshold_ms, :integer, default: 1000
      filter expr(duration_ms > ^arg(:threshold_ms))
    end

    read :by_trace_id do
      argument :trace_id, :string, allow_nil?: false
      filter expr(trace_id == ^arg(:trace_id))
    end

    read :active_traces do
      filter expr(is_nil(completed_at))
    end
  end

  calculations do
    calculate :is_slow, :boolean, expr(duration_ms > 1000)
    calculate :performance_grade, :atom, expr(
      cond do
        duration_ms < 100 -> :excellent
        duration_ms < 500 -> :good
        duration_ms < 1000 -> :acceptable
        true -> :slow
      end
    )
  end

  identities do
    identity :unique_span, [:trace_id, :span_name]
  end

  preparations do
    prepare build(sort: [started_at: :desc])
  end
end
