defmodule Thunderline.Thunderblock.Resources.ActiveDomainRegistry do
  @moduledoc """
  Persistent record of domain activations and deactivations.
  Complements the in-memory ETS registry with durable storage.

  ## Purpose

  While `Thunderline.Thunderblock.DomainRegistry` provides fast in-memory tracking
  via ETS, this resource provides:
  - Persistent history across server restarts
  - Audit trail of domain lifecycle events
  - Historical analysis of domain health
  - Long-term activation patterns

  ## Status Values

  - `:active` - Domain successfully activated and running
  - `:inactive` - Domain cleanly deactivated
  - `:crashed` - Domain terminated unexpectedly
  - `:restarting` - Domain in restart cycle

  ## Usage

      # Record domain activation
      ActiveDomainRegistry.record_activation!("thunderflow", 1, %{reason: "first_tick"})

      # Update domain status
      ActiveDomainRegistry.update_status!(domain_record, :crashed, %{error: "timeout"})

      # Query active domains
      ActiveDomainRegistry.list_active!()
  """
  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "active_domain_registry"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :domain_name, :string do
      allow_nil? false
      constraints max_length: 100
      description "Name of the domain (e.g., 'thunderflow', 'thunderbolt')"
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :inactive, :crashed, :restarting]
      default :active
      description "Current status of the domain"
    end

    attribute :tick_count, :integer do
      allow_nil? false
      description "Tick count when this status was recorded"
    end

    attribute :metadata, :map do
      default %{}
      description "Additional context about activation/deactivation"
    end

    create_timestamp :activated_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :record_activation do
      description "Record a new domain activation"
      accept [:domain_name, :status, :tick_count, :metadata]

      argument :domain_name, :string do
        allow_nil? false
      end

      argument :tick_count, :integer do
        allow_nil? false
      end

      argument :metadata, :map do
        default %{}
      end

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :status, :active)
      end
    end

    update :update_status do
      description "Update domain status"
      accept [:status, :tick_count, :metadata]

      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:active, :inactive, :crashed, :restarting]
      end

      argument :tick_count, :integer
      argument :metadata, :map
    end

    read :list_active do
      description "List all currently active domains"
      filter expr(status == :active)
    end

    read :by_domain_name do
      description "Get latest record for a specific domain"
      get? true

      argument :domain_name, :string do
        allow_nil? false
      end

      filter expr(domain_name == ^arg(:domain_name))

      prepare fn query, _context ->
        Ash.Query.sort(query, updated_at: :desc)
        |> Ash.Query.limit(1)
      end
    end

    read :activation_history do
      description "Get activation history ordered by time"

      prepare fn query, _context ->
        Ash.Query.sort(query, activated_at: :desc)
      end
    end
  end

  code_interface do
    define :record_activation, args: [:domain_name, :tick_count], action: :record_activation
    define :update_status, args: [:status], action: :update_status
    define :list_active, action: :list_active
    define :by_domain_name, args: [:domain_name], action: :by_domain_name
    define :activation_history, action: :activation_history
  end

  identities do
    identity :unique_domain_name, [:domain_name], eager_check?: true
  end

  preparations do
    prepare build(load: [:activated_at, :updated_at])
  end
end
