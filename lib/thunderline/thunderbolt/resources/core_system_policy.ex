defmodule Thunderline.Thunderbolt.Resources.CoreSystemPolicy do
  @moduledoc """
  System-wide policy definitions and enforcement
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "thundercore_system_policies"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :define do
      description "Define new system policy"
      primary? true
      accept [:policy_name, :policy_type, :rule_definition, :enforcement_level]
    end

    update :record_violation do
      description "Record policy violation"
      accept []
      change increment(:violation_count, amount: 1)
    end

    read :active_policies do
      description "Get all active policies by type"
      argument :policy_type, :atom
      filter expr(is_active == true)

      filter expr(
               if not is_nil(^arg(:policy_type)),
                 do: policy_type == ^arg(:policy_type),
                 else: true
             )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :policy_name, :string do
      description "System policy identifier"
      allow_nil? false
    end

    attribute :policy_type, :atom do
      description "Type of system policy"
      allow_nil? false
    end

    attribute :rule_definition, :map do
      description "Policy rule logic and conditions"
      allow_nil? false
    end

    attribute :enforcement_level, :atom do
      description "How strictly to enforce this policy"
      default :warning
    end

    attribute :is_active, :boolean do
      description "Whether policy is currently active"
      default true
    end

    attribute :violation_count, :integer do
      description "Number of policy violations detected"
      default 0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_policy_name, [:policy_name]
  end
end
