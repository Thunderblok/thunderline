defmodule Thunderline.Thunderbolt.ML.ConsentRecord do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ml_consent_records"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :grant do
      accept [:user_id, :tenant_id, :purpose, :expires_at]
      change set_attribute(:granted_at, DateTime.utc_now())
    end

    update :revoke do
      change set_attribute(:revoked_at, DateTime.utc_now())
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false
    attribute :tenant_id, :string, allow_nil?: false
    attribute :purpose, :atom, constraints: [one_of: [:train, :eval]], allow_nil?: false
    attribute :granted_at, :utc_datetime_usec
    attribute :revoked_at, :utc_datetime_usec
    attribute :expires_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_consent, [:user_id, :tenant_id, :purpose]
  end
end
