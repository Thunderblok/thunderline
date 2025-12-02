defmodule Thunderline.Thundergate.Resources.FederatedRealm do
  @moduledoc """
  FederatedRealm Resource - Sovereign Community Federation

  Represents federated realms in the Thunderline ecosystem, managing
  cross-realm connections, trust relationships, and federation protocols.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban]

  # Removed unused import Ash.Resource.Change.Builtins to silence compile warning

  postgres do
    table "thundercom_federated_realms"
    repo Thunderline.Repo

    custom_indexes do
      index [:realm_name], unique: true
      index [:trust_level]
      index [:connection_status]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:realm_name, :federation_url, :trust_level, :protocol_versions, :metadata]
    end

    update :establish_connection do
      accept [:connection_status, :trust_level]
    end

    read :by_trust_level do
      argument :trust_level, :atom, allow_nil?: false
      filter expr(trust_level == ^arg(:trust_level))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :realm_name, :string do
      allow_nil? false
      description "Unique realm identifier"
      constraints max_length: 100
    end

    attribute :federation_url, :string do
      allow_nil? false
      description "Primary federation endpoint URL"
      constraints max_length: 500
    end

    attribute :trust_level, :atom do
      allow_nil? false
      description "Trust level for this realm"
      default :untrusted
    end

    attribute :protocol_versions, {:array, :string} do
      allow_nil? false
      description "Supported federation protocol versions"
      default ["thundercom/1.0", "activitypub/1.0"]
    end

    attribute :connection_status, :atom do
      allow_nil? false
      description "Current connection status"
      default :disconnected
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Realm metadata and capabilities"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
