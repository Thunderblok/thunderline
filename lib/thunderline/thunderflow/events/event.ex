defmodule Thunderline.Thunderflow.Events.Event do
  @moduledoc """
  Central event log resource for the Thunderline system.

  This resource stores all events across the entire Thunderline ecosystem,
  providing comprehensive audit logging and event sourcing capabilities.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    extensions: [AshEvents.EventLog],
    data_layer: AshPostgres.DataLayer

  event_log do
    # Module that implements clear_records! callback for event replay
    clear_records_for_replay(Thunderline.Thunderflow.Events.ClearAllRecords)

    # Use UUIDv7 for better ordering and performance
    primary_key_type(Ash.Type.UUIDv7)

    # Store UUIDs for record references
    record_id_type(:uuid)

    # Track different types of actors in the system
    persist_actor_primary_key(:user_id, Thunderline.Thunderblock.Resources.VaultUser)
    persist_actor_primary_key(:agent_id, Thunderline.Thunderbolt.Resources.CoreAgent)

    # Advisory lock configuration for concurrency control
    advisory_lock_key_default(2_147_483_647)
  end

  # Optional: Configure replay overrides for version handling
  # This will be expanded as we implement versioning
  replay_overrides do
    # Example placeholder - will add specific overrides as needed
    # replay_override Thunderline.Thundervault.User, :create do
    #   versions [1]
    #   route_to Thunderline.Thundervault.User, :create_v1
    # end
  end

  postgres do
    table "thunderline_events"
    repo Thunderline.Repo
  end

  actions do
    # Default actions are provided by the event_log extension
    defaults [:read]

    # Custom read actions for Thunderline-specific queries
    read :by_domain do
      argument :domain, :string, allow_nil?: false
      filter expr(domain == ^arg(:domain))
    end

    read :by_criticality do
      argument :criticality, :string, allow_nil?: false
      filter expr(criticality == ^arg(:criticality))
    end

    read :replay_required do
      filter expr(replay_required == true)
    end

    read :by_correlation_id do
      argument :correlation_id, :string, allow_nil?: false
      filter expr(correlation_id == ^arg(:correlation_id))
    end
  end

  preparations do
    # Add domain-specific preparations if needed
  end

  attributes do
    # Primary key is automatically added by event_log extension

    # Additional metadata attributes for Thunderline-specific tracking
    attribute :domain, :string do
      description "Thunderline domain (thunderbit, thundervault, etc.)"
      allow_nil? false
    end

    attribute :operation_type, :string do
      description "Type of operation (lifecycle, configuration, execution, communication)"
      allow_nil? true
    end

    attribute :criticality, :string do
      description "Event criticality level (critical, high, medium, low)"
      allow_nil? true
      default "medium"
    end

    attribute :replay_required, :boolean do
      description "Whether this event is required for system replay"
      allow_nil? false
      default false
    end

    attribute :correlation_id, :string do
      description "Correlation ID for tracking related events across domains"
      allow_nil? true
    end
  end

  relationships do
    # These will be added as we implement actor resources
    # belongs_to :user, Thunderline.Thundervault.User do
    #   source_attribute :user_id
    #   destination_attribute :id
    # end

    # belongs_to :agent, Thunderline.Thunderbit.Agent do
    #   source_attribute :agent_id
    #   destination_attribute :id
    # end
  end

  calculations do
    # Add calculated fields for common queries
    calculate :is_critical, :boolean, expr(criticality in ["critical", "high"])

    calculate :age_in_hours, :integer do
      calculation fn records, _context ->
        now = DateTime.utc_now()

        Enum.map(records, fn record ->
          DateTime.diff(now, record.occurred_at, :hour)
        end)
      end
    end
  end

  identities do
    # Ensure efficient querying
    identity :correlation_events, [:correlation_id]
  end
end
