defmodule Thunderline.Thunderblock.Resources.VaultUser do
  @moduledoc """
  User Resource - Migrated from lib/thunderline/accounts/resources/user

  Core user accounts and authentication (historical: consolidated from legacy Thundervault -> ThunderBlock Vault).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEvents.Events]

  import Ash.Resource.Change.Builtins

  postgres do
    table "users"
    repo Thunderline.Repo
  end

  events do
    event_log(Thunderline.Thunderflow.Events.Event)
    current_action_versions(create: 1, update: 1, destroy: 1)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:email, :hashed_password, :first_name, :last_name, :avatar_url, :role]
    end

    update :update do
      primary? true
      accept [:first_name, :last_name, :avatar_url]
    end

    create :register do
      accept [:email, :hashed_password, :first_name, :last_name]

      change fn changeset, _context ->
        case changeset.arguments[:password] do
          password when is_binary(password) ->
            hashed = Bcrypt.hash_pwd_salt(password)
            Ash.Changeset.change_attribute(changeset, :hashed_password, hashed)

          _ ->
            changeset
        end
      end
    end

    update :confirm_email do
      accept []
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end

    update :record_login do
      accept []
      change set_attribute(:last_login_at, &DateTime.utc_now/0)
      change increment(:login_count)
    end
  end

  policies do
    # Allow unauthenticated user creation (registration flow)
    policy action_type(:create) do
      authorize_if always()
    end

    # Allow unauthenticated reads (for auth preparation, email lookup)
    policy action_type(:read) do
      authorize_if always()
    end

    # Updates require actor to be the user themselves or an admin
    policy action_type(:update) do
      authorize_if expr(id == ^actor(:id))
      authorize_if expr(^actor(:role) == :admin)
    end

    # Deletes require actor to be the user themselves or an admin
    policy action_type(:destroy) do
      authorize_if expr(id == ^actor(:id))
      authorize_if expr(^actor(:role) == :admin)
    end
  end

  validations do
    validate match(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)

    validate string_length(:first_name, min: 1) do
      where present(:first_name)
    end

    validate string_length(:last_name, min: 1) do
      where present(:last_name)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      constraints max_length: 160
      description "User email address"
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
      description "Bcrypt hashed password"
    end

    attribute :confirmed_at, :utc_datetime do
      allow_nil? true
      description "Email confirmation timestamp"
    end

    attribute :first_name, :string do
      allow_nil? true
      constraints max_length: 80
      description "User first name"
    end

    attribute :last_name, :string do
      allow_nil? true
      constraints max_length: 80
      description "User last name"
    end

    attribute :avatar_url, :string do
      allow_nil? true
      description "User avatar image URL"
    end

    attribute :role, :atom do
      allow_nil? false
      default :user
      description "User role and permissions level"
    end

    attribute :last_login_at, :utc_datetime do
      allow_nil? true
      description "Last successful login timestamp"
    end

    attribute :login_count, :integer do
      allow_nil? false
      default 0
      description "Total number of successful logins"
    end

    timestamps()
  end

  relationships do
    has_many :user_tokens, Thunderline.Thunderblock.Resources.VaultUserToken do
      destination_attribute :user_id
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
