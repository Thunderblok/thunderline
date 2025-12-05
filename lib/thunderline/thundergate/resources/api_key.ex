defmodule Thunderline.Thundergate.Resources.ApiKey do
  @moduledoc """
  API Key resource for programmatic access to Thunderline APIs.

  API keys are hashed for storage security and support expiration.
  Used for MCP endpoints, JSON API, and external service integrations.

  ## Usage

  Generate a key via mix task:

      mix thunderline.api_key.generate --user-id <uuid> --expires-in 90d

  Or programmatically:

      {:ok, %{api_key: key, resource: api_key}} =
        Thunderline.Thundergate.create_api_key(user, %{expires_in_days: 90})

  The plaintext key is only returned once at creation time.
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :expires_at, :name, :scopes]

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey, prefix: :tl, hash: :api_key_hash}
    end

    read :valid do
      description "Read only valid (non-expired) API keys"
      filter expr(expires_at > now())
    end

    read :by_user do
      description "Get all API keys for a user"
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end

    update :revoke do
      description "Revoke an API key by setting revoked_at"
      accept []
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      description "AshAuthentication can interact with API keys"
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can read their own API keys"
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      description "Users can create API keys for themselves"
      authorize_if relating_to_actor(:user)
    end

    policy action_type(:destroy) do
      description "Users can revoke their own API keys"
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:revoke) do
      description "Users can revoke their own API keys"
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
      public? false
      description "Hashed API key (plaintext never stored)"
    end

    attribute :name, :string do
      allow_nil? true
      public? true
      description "Optional friendly name for the key"
    end

    attribute :scopes, {:array, :string} do
      default []
      public? true
      description "Optional scopes limiting key permissions (e.g., ['mcp:read', 'api:write'])"
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the key expires"
    end

    attribute :revoked_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the key was revoked (nil if active)"
    end

    attribute :last_used_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "Last time the key was used for authentication"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Thunderline.Thundergate.Resources.User do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :valid?, :boolean, expr(expires_at > now() and is_nil(revoked_at)) do
      description "Whether the key is currently valid (not expired and not revoked)"
    end
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end
end
