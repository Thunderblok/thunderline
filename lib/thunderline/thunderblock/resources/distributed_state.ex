defmodule Thunderline.Thunderblock.Resources.DistributedState do
  @moduledoc """
  Distributed state synchronization resource
  Provides persistent, queryable alternative to Memento tables
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "thunderblock_distributed_state"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :set_state do
      description "Set distributed state value"
      primary? true
      accept [:state_key, :state_scope, :state_value, :last_updated_by, :ttl_expires_at]
    end

    update :update_state do
      description "Update existing state with version check"
      accept [:state_value, :last_updated_by, :ttl_expires_at]
      change increment(:version, amount: 1)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    read :get_by_key do
      description "Get state by key and scope"
      argument :state_key, :string, allow_nil?: false
      argument :state_scope, :string, default: "global"
      filter expr(state_key == ^arg(:state_key) and state_scope == ^arg(:state_scope))
    end

    read :get_by_scope do
      description "Get all state in a scope"
      argument :state_scope, :string, allow_nil?: false
      filter expr(state_scope == ^arg(:state_scope))
    end

    read :get_expired_states do
      description "Get all expired states for cleanup"
      filter expr(not is_nil(ttl_expires_at) and ttl_expires_at < ^DateTime.utc_now())
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state_key, :string do
      description "Unique state identifier"
      allow_nil? false
    end

    attribute :state_scope, :string do
      description "Scope/namespace for the state"
      default "global"
    end

    attribute :state_value, :map do
      description "State data payload"
      allow_nil? false
    end

    attribute :version, :integer do
      description "State version for conflict resolution"
      default 1
    end

    attribute :last_updated_by, :string do
      description "Node that last updated this state"
    end

    attribute :ttl_expires_at, :utc_datetime_usec do
      description "TTL expiration timestamp"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :is_expired,
              :boolean,
              expr(not is_nil(ttl_expires_at) and ttl_expires_at < ^DateTime.utc_now())
  end

  identities do
    identity :unique_state_key_scope, [:state_key, :state_scope]
  end
end
