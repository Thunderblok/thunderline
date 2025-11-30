defmodule Thunderline.Thunderpac.Resources.PACRole do
  @moduledoc """
  PAC Role definitions.

  Roles define behavioral templates and capabilities that PACs can assume.
  A PAC can switch roles dynamically based on context or intent.

  ## Role Categories

  - `:assistant` - General-purpose helper
  - `:specialist` - Domain expert (coding, writing, analysis)
  - `:coordinator` - Multi-agent orchestration
  - `:guardian` - Security and monitoring
  - `:explorer` - Discovery and learning

  ## Fields

  - `name` - Role identifier
  - `category` - Role category
  - `capabilities` - Enabled capabilities when role is active
  - `constraints` - Behavioral constraints
  - `persona_overlay` - Personality adjustments for this role
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "thunderpac_roles"
    repo Thunderline.Repo

    custom_indexes do
      index [:category], name: "pac_roles_category_idx"
      index [:is_system], name: "pac_roles_system_idx"
      index "USING GIN (capabilities)", name: "pac_roles_caps_idx"
    end
  end

  admin do
    form do
      field :name
      field :category
      field :description
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Role identifier"
      constraints min_length: 1, max_length: 50
    end

    attribute :category, :atom do
      allow_nil? false
      public? true
      default :assistant
      constraints one_of: [:assistant, :specialist, :coordinator, :guardian, :explorer, :custom]
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Human-readable role description"
      constraints max_length: 500
    end

    attribute :capabilities, {:array, :string} do
      allow_nil? false
      default []
      public? true
      description "Capabilities enabled when this role is active"
    end

    attribute :constraints, :map do
      allow_nil? false
      default %{}
      public? true
      description "Behavioral constraints and limits"
    end

    attribute :persona_overlay, :map do
      allow_nil? false
      default %{}
      public? true
      description "Personality adjustments when this role is active"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 50
      public? true
      description "Role priority (higher = preferred in conflicts)"
    end

    attribute :is_system, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether this is a built-in system role"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new PAC role"
      accept [:name, :category, :description, :capabilities, :constraints, :persona_overlay, :priority, :metadata]
    end

    update :update do
      description "Update a PAC role"
      accept [:description, :capabilities, :constraints, :persona_overlay, :priority, :metadata]
    end

    read :by_category do
      description "Find roles by category"
      argument :category, :atom, allow_nil?: false
      filter expr(category == ^arg(:category))
    end

    read :system_roles do
      description "List system-defined roles"
      filter expr(is_system == true)
    end

    read :custom_roles do
      description "List user-defined roles"
      filter expr(is_system == false)
    end
  end

  code_interface do
    define :create
    define :update
    define :by_category, args: [:category]
    define :system_roles, action: :system_roles
    define :custom_roles, action: :custom_roles
  end
end
