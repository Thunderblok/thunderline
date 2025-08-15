defmodule Thunderblock.Resources.SystemEvent do
  @moduledoc """
  System-wide event tracking and coordination
  Replaces direct cross-domain calls with event-driven patterns
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thunderblock_system_events"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :string do
      description "Type of system event"
      allow_nil? false
    end

    attribute :source_domain, :string do
      description "Domain that generated the event"
      allow_nil? false
    end

    attribute :target_domain, :string do
      description "Intended recipient domain (null for broadcast)"
    end

    attribute :event_data, :map do
      description "Event payload and context"
      default %{}
    end

    attribute :status, :atom do
      description "Event processing status"
      constraints [one_of: [:pending, :processing, :completed, :failed, :expired]]
      default :pending
    end

    attribute :priority, :integer do
      description "Event processing priority (0-9)"
      default 5
    end

    attribute :correlation_id, :string do
      description "For tracking related events"
    end

    attribute :processed_at, :utc_datetime_usec do
      description "When event was processed"
    end

    attribute :expires_at, :utc_datetime_usec do
      description "Event expiration timestamp"
    end

    attribute :target_resource_id, :uuid do
      description "ID of target resource (if event is resource-specific)"
    end

    attribute :target_resource_type, :atom do
      description "Type of target resource (if event is resource-specific)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :emit do
      description "Emit a new system event"
      primary? true
      accept [:event_type, :source_domain, :target_domain, :event_data, :priority, :correlation_id, :expires_at]
    end

    update :mark_processing do
      description "Mark event as being processed"
      accept []
      change set_attribute(:status, :processing)
    end

    update :mark_completed do
      description "Mark event as successfully processed"
      accept []
      change set_attribute(:status, :completed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    update :mark_failed do
      description "Mark event as failed to process"
      accept []
      change set_attribute(:status, :failed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    read :pending_events do
      description "Get all pending events for processing"
      filter expr(status == :pending)
    end

    read :events_for_domain do
      description "Get events targeted for specific domain"
      argument :domain, :string, allow_nil?: false
      filter expr(target_domain == ^arg(:domain) or is_nil(target_domain))
      filter expr(status == :pending)
    end

    read :events_by_correlation do
      description "Get related events by correlation ID"
      argument :correlation_id, :string, allow_nil?: false
      filter expr(correlation_id == ^arg(:correlation_id))
    end
  end

  identities do
    identity :unique_correlation_event, [:correlation_id, :event_type], where: expr(not is_nil(correlation_id))
  end
end
