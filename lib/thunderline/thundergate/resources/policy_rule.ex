defmodule Thunderline.Thundergate.Resources.PolicyRule do
  @moduledoc """
  PolicyRule Resource - Basic policy evaluation rules

  Minimal policy rule storage and evaluation for authorization decisions.
  Used by other domains to check permissions and validate actions.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins



  postgres do
    table "policy_rules"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints [max_length: 200]
      description "Human-readable policy rule name"
    end

    attribute :rule_type, :atom do
      allow_nil? false
      constraints [one_of: [:allow, :deny, :conditional]]
      description "Type of policy rule"
    end

    attribute :scope, :string do
      allow_nil? false
      constraints [max_length: 100]
      description "Domain or resource scope this rule applies to"
    end

    attribute :condition_expression, :string do
      description "Expression to evaluate for conditional rules"
    end

    attribute :priority, :integer do
      default 100
      constraints [min: 1, max: 1000]
      description "Rule priority (lower numbers = higher priority)"
    end

    attribute :active, :boolean do
      default true
      description "Whether this rule is currently active"
    end

    attribute :metadata, :map do
      default %{}
      description "Additional rule metadata"
    end

    timestamps()
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :list do
      primary? true
      pagination offset?: true, countable: true
    end

    create :create_policy do
      description "Create a new policy rule"
      accept [:name, :rule_type, :scope, :condition_expression, :priority, :active, :metadata]
    end

    update :activate do
      description "Activate a policy rule"
      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate a policy rule"
      change set_attribute(:active, false)
    end
  end

  policies do
    # Simple policy - allow all for now, can be refined later
    policy always() do
      authorize_if always()
    end
  end

  identities do
    identity :unique_name_per_scope, [:name, :scope] do
      description "Policy rule names must be unique within a scope"
    end
  end

  validations do
    validate match(:name, ~r/^[a-zA-Z0-9_\-\s]+$/) do
      message "Policy name can only contain alphanumeric characters, spaces, hyphens, and underscores"
    end

    validate match(:scope, ~r/^[a-zA-Z0-9_\-\.]+$/) do
      message "Scope must be a valid domain/resource identifier"
    end
  end
end
