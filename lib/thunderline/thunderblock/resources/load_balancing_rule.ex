defmodule Thunderline.Thunderblock.Resources.LoadBalancingRule do
  @moduledoc """
  Load balancing rules and policies for distributed coordination
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "thunderblock_load_balancing_rules"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :define_rule do
      description "Define new load balancing rule"
      primary? true
      accept [:rule_name, :target_service, :algorithm, :weights, :health_check_path]
    end

    update :activate do
      description "Activate load balancing rule"
      accept []
      change set_attribute(:is_active, true)
    end

    update :deactivate do
      description "Deactivate load balancing rule"
      accept []
      change set_attribute(:is_active, false)
    end

    read :active_rules do
      description "Get all active load balancing rules"
      filter expr(is_active == true)
    end

    read :rules_for_service do
      description "Get rules for specific service"
      argument :service, :string, allow_nil?: false
      filter expr(target_service == ^arg(:service) and is_active == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :rule_name, :string do
      description "Load balancing rule identifier"
      allow_nil? false
    end

    attribute :target_service, :string do
      description "Service/domain this rule applies to"
      allow_nil? false
    end

    attribute :algorithm, :atom do
      description "Load balancing algorithm"
      default :round_robin
    end

    attribute :weights, :map do
      description "Node weights for weighted algorithms"
      default %{}
    end

    attribute :health_check_path, :string do
      description "Health check endpoint for nodes"
    end

    attribute :is_active, :boolean do
      description "Whether rule is currently active"
      default true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_rule_service, [:rule_name, :target_service]
  end
end
