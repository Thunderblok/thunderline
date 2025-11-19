defmodule Thunderline.ServiceRegistry.Service do
  @moduledoc """
  Resource representing a registered service in the Thunderline ecosystem.

  Services register themselves with Thunderline on startup and send periodic heartbeats.
  This enables service discovery, health monitoring, and coordination.
  """
  use Ash.Resource,
    domain: Thunderline.ServiceRegistry,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "services"
    repo Thunderline.Repo
  end

  graphql do
    type :service
  end

  code_interface do
    define :register, action: :register
    define :heartbeat, action: :heartbeat
    define :mark_unhealthy, action: :mark_unhealthy
    define :mark_healthy, action: :mark_healthy
    define :list_by_type, action: :list_by_type, args: [:service_type]
    define :list_healthy, action: :list_healthy
    define :find_by_service_id, action: :find_by_service_id, args: [:service_id]
    define :list, action: :read
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description "Register a new service"

      accept [
        :service_id,
        :service_type,
        :name,
        :host,
        :port,
        :capabilities,
        :metadata
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :starting)
        |> Ash.Changeset.change_attribute(:last_heartbeat_at, DateTime.utc_now())
      end

      change fn changeset, _context ->
        # Compute URL from host and port
        host = Ash.Changeset.get_attribute(changeset, :host)
        port = Ash.Changeset.get_attribute(changeset, :port)

        url =
          if host && port do
            "http://#{host}:#{port}"
          else
            nil
          end

        Ash.Changeset.change_attribute(changeset, :url, url)
      end
    end

    update :heartbeat do
      description "Update service heartbeat (called periodically by service)"
      accept [:status, :capabilities, :metadata]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_heartbeat_at, DateTime.utc_now())
      end
    end

    update :mark_unhealthy do
      description "Mark service as unhealthy (called by health check)"
      accept []

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :unhealthy)
      end
    end

    update :mark_healthy do
      description "Mark service as healthy"
      accept []

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :healthy)
        |> Ash.Changeset.change_attribute(:last_heartbeat_at, DateTime.utc_now())
      end
    end

    read :list_by_type do
      description "List services by type"
      argument :service_type, :atom, allow_nil?: false

      filter expr(service_type == ^arg(:service_type))
    end

    read :list_healthy do
      description "List all healthy services"
      filter expr(status == :healthy)
    end

    read :find_by_service_id do
      description "Find service by service_id"
      argument :service_id, :string, allow_nil?: false

      get? true
      filter expr(service_id == ^arg(:service_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :service_id, :string do
      allow_nil? false
      description "Unique identifier for the service (e.g., 'cerebros-1', 'mlflow-main')"
    end

    attribute :service_type, :atom do
      allow_nil? false
      description "Type of service (e.g., :cerebros, :mlflow)"
      constraints one_of: [:cerebros, :mlflow, :custom]
    end

    attribute :name, :string do
      allow_nil? false
      description "Human-readable name for the service"
    end

    attribute :host, :string do
      allow_nil? false
      description "Hostname or IP address where the service is running"
      default "localhost"
    end

    attribute :port, :integer do
      allow_nil? false
      description "Port number the service is listening on"
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current status of the service"
      constraints one_of: [:starting, :healthy, :unhealthy, :stopped]
      default :starting
    end

    attribute :capabilities, :map do
      description "Service capabilities and metadata (e.g., supported models, GPU availability)"
      default %{}
    end

    attribute :metadata, :map do
      description "Additional service metadata"
      default %{}
    end

    attribute :last_heartbeat_at, :utc_datetime_usec do
      description "Timestamp of last heartbeat received from service"
    end

    attribute :url, :string do
      description "Full URL to the service (computed from host + port)"
    end

    create_timestamp :registered_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_service_id, [:service_id]
  end
end
