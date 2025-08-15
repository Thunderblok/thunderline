defmodule Thunderline.Thunderbolt.Resources.CoreTimingEvent do
  @moduledoc """
  System timing and synchronization events
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thundercore_timing_events"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :event_name, :string do
      description "Timing event identifier"
      allow_nil? false
    end
    
    attribute :event_type, :atom do
      description "Type of timing event"
      allow_nil? false
    end
    
    attribute :scheduled_at, :utc_datetime_usec do
      description "When event is scheduled to occur"
      allow_nil? false
    end
    
    attribute :executed_at, :utc_datetime_usec do
      description "When event was actually executed"
    end
    
    attribute :status, :atom do
      description "Event execution status"
      default :scheduled
    end
    
    attribute :metadata, :map do
      description "Event metadata and context"
      default %{}
    end
    
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]
    
    create :schedule do
      description "Schedule new timing event"
      primary? true
      accept [:event_name, :event_type, :scheduled_at, :metadata]
    end
    
    update :mark_executed do
      description "Mark event as executed"
      accept []
      change set_attribute(:status, :completed)
      change set_attribute(:executed_at, &DateTime.utc_now/0)
    end
    
    read :due_events do
      description "Get events due for execution"
      filter expr(status == :scheduled and scheduled_at <= ^DateTime.utc_now())
    end
  end
end
