defmodule Thunderline.Thundergate.Resources.User do
  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    strategies do
      magic_link :magic_link do
        identity_field :email
        sender Thunderline.Thundergate.Authentication.MagicLinkSender
      end
    end

    tokens do
      enabled? true
      token_resource Thunderline.Thundergate.Resources.Token
      signing_secret Thunderline.Secrets
      store_all_tokens? true
    end
  end

  postgres do
    table "users"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
      constraints match: ~r/.+@.+/i
    end

    # Virtual password field for input only
    attribute :password, :string do
      allow_nil? true
      sensitive? true
      public? false
      writable? true
    end

    # Legacy hashed password field (retained for existing rows, unused by magic link)
    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
      public? false
      writable? false
    end

    attribute :confirmed_at, :utc_datetime do
      public? true
      allow_nil? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
  end
end
