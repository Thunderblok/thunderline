defmodule Thunderline.Thundergate.Resources.ExternalService do
  @moduledoc """
  Third-party API configurations and management.

  Tracks external service endpoints, authentication configurations,
  health status, and integration metadata for seamless interoperability.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "external_services"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :base_url, :string, allow_nil?: false
    attribute :protocol_type, :atom, constraints: [one_of: [:rest, :graphql, :grpc, :webhook, :legacy]]
    attribute :auth_config, :map, sensitive?: true
    attribute :rate_limits, :map, default: %{}
    attribute :timeout_ms, :integer, default: 30_000
    attribute :retry_config, :map, default: %{max_attempts: 3, backoff_ms: 1000}
    attribute :headers, :map, default: %{}
    attribute :status, :atom, constraints: [one_of: [:active, :inactive, :error, :maintenance]]
    attribute :health_check_url, :string
    attribute :last_health_check, :utc_datetime
    attribute :metadata, :map, default: %{}
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :register do
      accept [:name, :base_url, :protocol_type, :auth_config, :rate_limits, :timeout_ms, :retry_config, :headers, :health_check_url, :metadata]
    end

    update :activate do
      change set_attribute(:status, :active)
      change set_attribute(:last_health_check, &DateTime.utc_now/0)
    end

    update :deactivate do
      change set_attribute(:status, :inactive)
    end

    update :health_check do
      accept [:status, :last_health_check]
    end

    read :active_services do
      filter expr(status == :active)
    end

    read :by_protocol do
      argument :protocol, :atom, allow_nil?: false
      filter expr(protocol_type == ^arg(:protocol))
    end

    read :unhealthy do
      filter expr(status == :error or (not is_nil(last_health_check) and last_health_check < ago(300, :second)))
    end
  end

  calculations do
    calculate :is_healthy, :boolean, expr(
      status == :active and
      (is_nil(last_health_check) or last_health_check > ago(300, :second))
    )

    calculate :uptime_status, :atom, expr(
      cond do
        status == :active and last_health_check > ago(60, :second) -> :excellent
        status == :active and last_health_check > ago(300, :second) -> :good
        status == :active -> :stale
        true -> :down
      end
    )
  end

  identities do
    identity :unique_service_name, [:name]
    identity :unique_service_url, [:base_url]
  end

  preparations do
    prepare build(sort: [name: :asc])
  end
end
