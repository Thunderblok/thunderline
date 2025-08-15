defmodule Thunderline.Thundergate.Resources.ErrorLog do
  @moduledoc """
  Error tracking and diagnostic logging across all Thunderline domains.

  Captures and categorizes errors, exceptions, and anomalies for debugging
  and system health analysis. Provides real-time error monitoring and
  trend analysis capabilities.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins



  postgres do
    table "error_logs"
    repo Thunderline.Repo
  end

#   notifiers do
#     module Thunderline.PubSub
#     prefix "thundereye:errors"
#
#     publish :create, ["error:logged", :severity]
#     publish :update, ["error:updated", :id]
#   end

  attributes do
    uuid_primary_key :id
    attribute :domain, :string, allow_nil?: false
    attribute :error_type, :string, allow_nil?: false
    attribute :message, :string, allow_nil?: false
    attribute :severity, :atom, constraints: [one_of: [:debug, :info, :warning, :error, :critical]]
    attribute :stack_trace, :string
    attribute :context, :map, default: %{}
    attribute :node_name, :string
    attribute :process_id, :string
    attribute :user_id, :uuid
    attribute :request_id, :string
    attribute :metadata, :map, default: %{}
    attribute :resolved, :boolean, default: false
    attribute :resolution_notes, :string
    create_timestamp :occurred_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :log_error do
      accept [:domain, :error_type, :message, :severity, :stack_trace, :context,
              :node_name, :process_id, :user_id, :request_id, :metadata]

      change set_attribute(:occurred_at, &DateTime.utc_now/0)
    end

    update :resolve do
      accept [:resolution_notes]
      change set_attribute(:resolved, true)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :escalate do
      change set_attribute(:severity, :critical)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    read :recent do
      argument :hours, :integer, default: 24
      filter expr(occurred_at > ago(^arg(:hours), :hour))
    end

    read :by_domain do
      argument :domain_name, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain_name))
    end

    read :by_severity do
      argument :severity_level, :atom, allow_nil?: false
      filter expr(severity == ^arg(:severity_level))
    end

    read :unresolved do
      filter expr(resolved == false)
    end

    read :critical_errors do
      filter expr(severity == :critical and resolved == false)
    end
  end

  calculations do
    calculate :age_minutes, :integer, expr(
      fragment("EXTRACT(EPOCH FROM (? - ?))/60", now(), occurred_at)
    )

    calculate :is_stale, :boolean, expr(
      occurred_at < ago(24, :hour) and resolved == false
    )

    calculate :error_frequency, :integer, expr(
      fragment("""
      (SELECT COUNT(*) FROM error_logs el2
       WHERE el2.error_type = ?
       AND el2.occurred_at > ?)
      """, error_type, ago(1, :hour))
    )
  end

  identities do
    identity :unique_error_occurrence, [:domain, :error_type, :message, :occurred_at]
  end

  preparations do
    prepare build(sort: [occurred_at: :desc])
  end
end
