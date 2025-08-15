defmodule Thunderline.Thundergate.Resources.AlertRule do
  @moduledoc """
  Configurable alerting rules and thresholds for proactive system monitoring.

  Defines conditions that trigger alerts, notification channels, escalation
  policies, and alert suppression logic. Enables intelligent alerting that
  reduces noise while ensuring critical issues are never missed.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  import Ash.Resource.Change.Builtins

  postgres do
    table "alert_rules"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_rule do
      accept [
        :name,
        :description,
        :domain,
        :component,
        :metric_name,
        :condition,
        :threshold_value,
        :threshold_count,
        :time_window_minutes,
        :severity,
        :notification_channels,
        :escalation_minutes,
        :suppression_minutes,
        :expression,
        :tags,
        :metadata
      ]
    end

    update :enable do
      change set_attribute(:enabled, true)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :disable do
      change set_attribute(:enabled, false)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    action :trigger_alert, :map do
      argument :current_value, :decimal, allow_nil?: false
      argument :context, :map, default: %{}

      run fn input, _context ->
        rule = input.resource
        current_value = Ash.Changeset.get_argument(input, :current_value)
        alert_context = Ash.Changeset.get_argument(input, :context)

        # Evaluate if rule should trigger
        should_trigger =
          case rule.condition do
            :greater_than -> current_value > rule.threshold_value
            :less_than -> current_value < rule.threshold_value
            :equals -> current_value == rule.threshold_value
            :not_equals -> current_value != rule.threshold_value
            _ -> false
          end

        if should_trigger and rule.enabled do
          alert_data = %{
            rule_id: rule.id,
            rule_name: rule.name,
            severity: rule.severity,
            domain: rule.domain,
            component: rule.component,
            metric_name: rule.metric_name,
            current_value: current_value,
            threshold_value: rule.threshold_value,
            context: alert_context,
            triggered_at: DateTime.utc_now()
          }

          # Emit alert via PubSub
          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "thundereye:alerts:triggered",
            {:alert_triggered, alert_data}
          )

          {:ok, alert_data}
        else
          {:ok, %{triggered: false, reason: "condition_not_met"}}
        end
      end
    end

    read :active_rules do
      filter expr(enabled == true)
    end

    read :by_domain do
      argument :domain_name, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain_name))
    end

    read :by_severity do
      argument :severity_level, :atom, allow_nil?: false
      filter expr(severity == ^arg(:severity_level))
    end

    read :critical_rules do
      filter expr(severity == :critical and enabled == true)
    end
  end

  preparations do
    prepare build(sort: [severity: :desc, created_at: :desc])
  end

  #   notifiers do
  #     module Thunderline.PubSub
  #     prefix "thundereye:alerts"
  #     
  #     publish :create, ["alert:rule_created", :name]
  #     publish :update, ["alert:rule_updated", :name]
  #     publish :destroy, "alert:rule_deleted"
  #   end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :domain, :string
    attribute :component, :string
    attribute :metric_name, :string

    attribute :condition, :atom,
      constraints: [
        one_of: [:greater_than, :less_than, :equals, :not_equals, :contains, :missing]
      ]

    attribute :threshold_value, :decimal
    attribute :threshold_count, :integer, default: 1
    attribute :time_window_minutes, :integer, default: 5
    attribute :severity, :atom, constraints: [one_of: [:info, :warning, :error, :critical]]
    attribute :notification_channels, {:array, :string}, default: []
    attribute :escalation_minutes, :integer, default: 60
    attribute :suppression_minutes, :integer, default: 15
    attribute :enabled, :boolean, default: true

    # For complex conditions
    attribute :expression, :string
    attribute :tags, :map, default: %{}
    attribute :metadata, :map, default: %{}
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :is_complex, :boolean, expr(not is_nil(expression))

    calculate :effectiveness_score,
              :integer,
              expr(
                # Placeholder calculation - would be based on alert history
                cond do
                  severity == :critical -> 95
                  severity == :error -> 85
                  severity == :warning -> 75
                  true -> 65
                end
              )

    calculate :next_evaluation,
              :utc_datetime,
              expr(fragment("? + INTERVAL '? minutes'", updated_at, time_window_minutes))
  end

  identities do
    identity :unique_rule_name, [:name]
    identity :unique_metric_rule, [:domain, :component, :metric_name, :condition]
  end
end
