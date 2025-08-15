defmodule Thunderline.Thundergate.Resources.DecisionFramework do
  @moduledoc """
  DecisionFramework Resource - Decision-making templates and logic

  Provides structured decision-making frameworks that can be referenced
  by other domains for consistent decision processing.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins



  postgres do
    table "decision_frameworks"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints [max_length: 200]
      description "Framework name"
    end

    attribute :description, :string do
      description "Detailed description of the decision framework"
    end

    attribute :framework_type, :atom do
      allow_nil? false
      constraints [one_of: [:rule_based, :weighted_scoring, :threshold, :consensus]]
      description "Type of decision framework"
    end

    attribute :configuration, :map do
      default %{}
      description "Framework-specific configuration parameters"
    end

    attribute :active, :boolean do
      default true
      description "Whether this framework is currently active"
    end

    attribute :version, :string do
      default "1.0.0"
      description "Framework version for evolution tracking"
    end

    timestamps()
  end

  relationships do
    # Future: Add relationships as needed
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :list do
      primary? true
      pagination offset?: true, countable: true
    end

    create :create_framework do
      description "Create a new decision framework"
      accept [:name, :description, :framework_type, :configuration, :active, :version]
    end

    update :activate do
      description "Activate a decision framework"
      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate a decision framework"
      change set_attribute(:active, false)
    end

    update :update_version do
      description "Update framework version"
      accept [:version, :configuration]
    end
  end

  calculations do
    # Future: Add calculations as needed
  end

  policies do
    # Simple policy - allow all for now, can be refined later
    policy always() do
      authorize_if always()
    end
  end

  identities do
    identity :unique_name, [:name] do
      description "Framework names must be unique"
    end
  end

  validations do
    validate match(:name, ~r/^[a-zA-Z0-9_\-\s]+$/) do
      message "Framework name can only contain alphanumeric characters, spaces, hyphens, and underscores"
    end

    validate match(:version, ~r/^\d+\.\d+\.\d+$/) do
      message "Version must follow semantic versioning (e.g., 1.0.0)"
    end
  end
end
