defmodule Thunderline.Thundergate.Resources.RealmIdentity do
  @moduledoc """
  RealmIdentity Resource - Cryptographic Identity Management

  Manages cryptographic identities, key exchange, and verification
  for secure cross-realm federation in the Thunderline ecosystem.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  import Ash.Resource.Change.Builtins

  postgres do
    table "thundercom_realm_identities"
    repo Thunderline.Repo

    custom_indexes do
      index [:realm_id]
      index [:fingerprint], unique: true
      index [:verification_status]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:realm_id, :public_key, :key_algorithm, :fingerprint]
    end

    update :verify_identity do
      accept [:verification_status, :verified_at]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :verified_at, DateTime.utc_now())
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :realm_id, :uuid do
      allow_nil? false
      description "Associated federated realm"
    end

    attribute :public_key, :string do
      allow_nil? false
      description "Public key for verification"
      constraints max_length: 4096
    end

    attribute :key_algorithm, :string do
      allow_nil? false
      description "Cryptographic algorithm used"
      default "Ed25519"
      constraints max_length: 16
    end

    attribute :fingerprint, :string do
      allow_nil? false
      description "Key fingerprint for quick verification"
      constraints max_length: 128
    end

    attribute :verification_status, :atom do
      allow_nil? false
      description "Identity verification status"
      default :unverified
    end

    attribute :verified_at, :utc_datetime do
      allow_nil? true
      description "Timestamp of verification"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :federated_realm, Thunderline.Thundergate.Resources.FederatedRealm do
      source_attribute :realm_id
      destination_attribute :id
    end
  end
end
