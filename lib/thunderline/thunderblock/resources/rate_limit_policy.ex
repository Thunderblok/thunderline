defmodule Thunderblock.Resources.RateLimitPolicy do
  @moduledoc """
  Rate limiting policies for system protection
  Integrates with Hammer for distributed rate limiting
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thunderblock_rate_limit_policies"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :policy_name, :string do
      description "Rate limit policy identifier"
      allow_nil? false
    end
    
    attribute :target_pattern, :string do
      description "Pattern/scope this policy applies to"
      allow_nil? false
    end
    
    attribute :limit_count, :integer do
      description "Maximum allowed requests"
      allow_nil? false
    end
    
    attribute :limit_window_ms, :integer do
      description "Time window in milliseconds"
      allow_nil? false
    end
    
    attribute :violation_action, :atom do
      description "Action to take on limit violation"
      default :block
    end
    
    attribute :is_active, :boolean do
      description "Whether policy is currently active"
      default true
    end
    
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]
    
    create :define_policy do
      description "Define new rate limit policy"
      primary? true
      accept [:policy_name, :target_pattern, :limit_count, :limit_window_ms, :violation_action]
    end
    
    update :activate do
      description "Activate rate limit policy"
      accept []
      change set_attribute(:is_active, true)
    end
    
    update :deactivate do
      description "Deactivate rate limit policy"
      accept []
      change set_attribute(:is_active, false)
    end
    
    read :active_policies do
      description "Get all active rate limit policies"
      filter expr(is_active == true)
    end
  end

  identities do
    identity :unique_policy_name, [:policy_name]
  end
end
