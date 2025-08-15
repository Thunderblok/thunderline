defmodule Thunderline.Thundergrid.Resources.ZoneEvent do
  @moduledoc """
  ZoneEvent Resource - Migrated from Thundervault

  Tracking events and activities within zones for analysis and coordination.
  Now properly located in Thundergrid for spatial coordinate management.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "zone_events"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      allow_nil? false
      constraints [one_of: [:agent_enter, :agent_exit, :entropy_change, :energy_fluctuation,
                           :agent_action, :zone_activation, :zone_deactivation, :system_event]]
      description "Type of event that occurred"
    end

    attribute :description, :string do
      allow_nil? false
      constraints max_length: 500
      description "Human-readable event description"
    end

    attribute :event_data, :map do
      allow_nil? false
      default %{}
      description "Structured event data and context"
    end

    attribute :severity, :atom do
      allow_nil? false
      default :info
      constraints [one_of: [:debug, :info, :warning, :error, :critical]]
      description "Event severity level"
    end

    attribute :coordinates, :map do
      allow_nil? false
      description "Zone coordinates where event occurred"
    end

    attribute :impact_radius, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Radius of zones affected by this event"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      constraints min: 0
      description "Event duration in milliseconds"
    end

    attribute :was_predicted, :boolean do
      allow_nil? false
      default false
      description "Whether this event was predicted by the system"
    end

    attribute :prediction_accuracy, :decimal do
      allow_nil? true
      constraints min: 0, max: 1
      description "Accuracy of prediction if event was predicted"
    end

    timestamps()
  end

  relationships do
    belongs_to :zone, Thunderline.Thundergrid.Resources.Zone do
      allow_nil? false
      attribute_writable? true
      description "Zone where event occurred"
    end

    belongs_to :agent, Thunderline.Thunderbolt.Resources.CoreAgent do
      allow_nil? true
      attribute_writable? true
      description "Agent involved in the event (if applicable)"
    end

    belongs_to :triggered_by_action, Thunderline.Thunderblock.Resources.VaultAction do
      allow_nil? true
      attribute_writable? true
      description "Action that triggered this event (if applicable)"
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :log_event do
      accept [:zone_id, :event_type, :description, :event_data, :severity,
              :coordinates, :impact_radius, :duration_ms, :agent_id, :triggered_by_action_id]

      change set_attribute(:was_predicted, false)
    end

    create :log_predicted_event do
      accept [:zone_id, :event_type, :description, :event_data, :severity,
              :coordinates, :impact_radius, :duration_ms, :agent_id, :triggered_by_action_id,
              :prediction_accuracy]

      change set_attribute(:was_predicted, true)
    end

    update :update_duration do
      argument :duration_ms, :integer, allow_nil?: false
      require_atomic? false

      change set_attribute(:duration_ms, arg(:duration_ms))
    end

    update :escalate_severity do
      argument :new_severity, :atom, allow_nil?: false
      require_atomic? false

      change set_attribute(:severity, arg(:new_severity))

      validate fn changeset, context ->
        severity = context.arguments.new_severity
        if severity in [:debug, :info, :warning, :error, :critical] do
          :ok
        else
          {:error, "Invalid severity level"}
        end
      end
    end

    read :by_zone do
      argument :zone_id, :uuid, allow_nil?: false
      filter expr(zone_id == ^arg(:zone_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_event_type do
      argument :event_type, :atom, allow_nil?: false
      filter expr(event_type == ^arg(:event_type))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_severity do
      argument :severity, :atom, allow_nil?: false
      filter expr(severity == ^arg(:severity))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent_events do
      argument :hours, :integer, default: 24
      filter expr(inserted_at > ago(^arg(:hours), :hour))
      prepare build(sort: [inserted_at: :desc])
    end

    read :critical_events do
      filter expr(severity in [:error, :critical])
      prepare build(sort: [inserted_at: :desc])
    end

    read :predicted_events do
      filter expr(was_predicted == true)
      prepare build(sort: [prediction_accuracy: :desc, inserted_at: :desc])
    end

    read :high_impact_events do
      argument :min_radius, :integer, default: 2
      filter expr(impact_radius >= ^arg(:min_radius))
      prepare build(sort: [impact_radius: :desc, inserted_at: :desc])
    end

    read :in_coordinate_range do
      argument :center_q, :integer, allow_nil?: false
      argument :center_r, :integer, allow_nil?: false
      argument :radius, :integer, allow_nil?: false, default: 1

      # Filter events within hexagonal distance
      filter expr(
        max(
          abs(fragment("(?->>'q')::int", coordinates) - ^arg(:center_q)),
          abs(fragment("(?->>'r')::int", coordinates) - ^arg(:center_r)),
          abs((fragment("(?->>'q')::int", coordinates) + fragment("(?->>'r')::int", coordinates)) -
              (^arg(:center_q) + ^arg(:center_r)))
        ) <= ^arg(:radius)
      )
      prepare build(sort: [inserted_at: :desc])
    end
  end

  preparations do
    prepare build(load: [:zone, :agent])
  end

  aggregates do
    # TODO: Fix group_by syntax for events_by_type aggregate
    # count :events_by_type, [] do
    #   group_by :event_type
    #   authorize? false
    # end

    avg :average_prediction_accuracy, [], :prediction_accuracy do
      filter expr(was_predicted == true)
      authorize? false
    end
  end

  calculations do
    calculate :is_recent, :boolean, expr(inserted_at > ago(1, :hour)) do
      description "Whether event occurred in the last hour"
    end

    calculate :event_age_hours, :decimal,
      expr(fragment("EXTRACT(EPOCH FROM ? - ?) / 3600", now(), inserted_at)) do
      description "Age of event in hours"
    end

    calculate :has_duration, :boolean, expr(not is_nil(duration_ms))

    calculate :involves_agent, :boolean, expr(not is_nil(agent_id))

    calculate :severity_level, :integer, expr(
      cond do
        severity == :debug -> 1
        severity == :info -> 2
        severity == :warning -> 3
        severity == :error -> 4
        severity == :critical -> 5
        true -> 0
      end
    ) do
      description "Numeric severity level for sorting"
    end
  end

  validations do
    validate present([:zone_id, :event_type, :description, :coordinates])
    validate string_length(:description, min: 1, max: 500)
    validate numericality(:impact_radius, greater_than_or_equal_to: 0)
    validate numericality(:duration_ms, greater_than_or_equal_to: 0) do
      where present(:duration_ms)
    end
    validate numericality(:prediction_accuracy, greater_than_or_equal_to: 0, less_than_or_equal_to: 1) do
      where present(:prediction_accuracy)
    end

    # Validate coordinates structure
    validate fn changeset, _context ->
      coordinates = Ash.Changeset.get_attribute(changeset, :coordinates)
      if coordinates && is_map(coordinates) do
        if Map.has_key?(coordinates, "q") && Map.has_key?(coordinates, "r") do
          :ok
        else
          {:error, "Coordinates must contain 'q' and 'r' keys"}
        end
      else
        {:error, "Coordinates must be a map"}
      end
    end
  end

  # TODO: Re-enable policies once AshAuthentication is properly configured
  # policies do
  #   policy action_type(:read) do
  #     authorize_if always()
  #   end

  #   policy action_type([:create, :update]) do
  #     authorize_if actor_present()
  #   end

  #   policy action_type(:destroy) do
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
