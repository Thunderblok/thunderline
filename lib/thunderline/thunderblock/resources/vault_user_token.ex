defmodule Thunderline.Thunderblock.Resources.VaultUserToken do
  @moduledoc """
  User Token Resource - Migrated from lib/thunderline/accounts/resources/user_token

  Authentication tokens for password resets, email confirmations, and sessions.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "user_tokens"
    repo Thunderline.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :build_email_token do
      accept [:user_id, :context, :sent_to]

      change fn changeset, _context ->
        token = :crypto.strong_rand_bytes(32)

        # 24 hours

        expires_at = DateTime.add(DateTime.utc_now(), 60 * 60 * 24, :second)

        changeset
        |> Ash.Changeset.change_attribute(:token, token)
        |> Ash.Changeset.change_attribute(:expires_at, expires_at)
      end
    end

    create :build_session_token do
      accept [:user_id]

      change fn changeset, _context ->
        token = :crypto.strong_rand_bytes(32)

        # 30 days

        expires_at = DateTime.add(DateTime.utc_now(), 60 * 60 * 24 * 30, :second)

        changeset
        |> Ash.Changeset.change_attribute(:token, token)
        |> Ash.Changeset.change_attribute(:context, :session)
        |> Ash.Changeset.change_attribute(:expires_at, expires_at)
      end
    end

    update :mark_as_used do
      accept []
      change set_attribute(:used_at, &DateTime.utc_now/0)
    end

    read :valid_tokens do
      filter expr(is_nil(used_at) and expires_at > now())
    end

    read :by_user_and_token do
      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :token, :binary do
        allow_nil? false
      end

      filter expr(user_id == ^arg(:user_id) and token == ^arg(:token))
    end
  end

  preparations do
    prepare build(load: [:user])
  end

  validations do
    validate present([:token, :context, :expires_at])

    validate compare(:expires_at, greater_than: &DateTime.utc_now/0) do
      on [:create, :update]
      message "Token expiration must be in the future"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token, :binary do
      allow_nil? false
      sensitive? true
      description "Cryptographic token value"
    end

    attribute :context, :atom do
      allow_nil? false
      description "Token usage context"
    end

    attribute :sent_to, :string do
      allow_nil? true
      description "Email address token was sent to"
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      description "Token expiration timestamp"
    end

    attribute :used_at, :utc_datetime do
      allow_nil? true
      description "Timestamp when token was consumed"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Thunderline.Thunderblock.Resources.VaultUser do
      allow_nil? false
      attribute_writable? true
    end
  end

  # TODO: Re-enable policies once AshAuthentication is properly configured
  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end

  #   policy action_type(:create) do
  #     authorize_if always()
  #   end

  #   policy action_type(:read) do
  #     authorize_if relates_to_actor_via(:user)
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end

  #   policy action_type(:update) do
  #     authorize_if relates_to_actor_via(:user)
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end

  #   policy action_type(:destroy) do
  #     authorize_if relates_to_actor_via(:user)
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
