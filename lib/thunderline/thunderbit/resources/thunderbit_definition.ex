defmodule Thunderline.Thunderbit.Resources.ThunderbitDefinition do
  @moduledoc """
  Ash Resource for persisting Thunderbit category definitions.

  This resource allows admin-level management of Thunderbit categories,
  storing custom categories beyond the hardcoded defaults.

  ## Attributes

  - `id` - UUID primary key
  - `name` - Display name (e.g., "Sensory")
  - `category_id` - Atom identifier (e.g., :sensory)
  - `ontology_path` - Full ontology path
  - `role` - Computational role
  - `description` - Human-readable description
  - `inputs` - I/O input specifications (JSON)
  - `outputs` - I/O output specifications (JSON)
  - `capabilities` - Allowed capabilities
  - `forbidden` - Forbidden capabilities
  - `can_link_to` - Valid target categories
  - `can_receive_from` - Valid source categories
  - `composition_mode` - How this category composes
  - `required_maxims` - Ethics requirements
  - `forbidden_maxims` - Ethics prohibitions
  - `geometry` - UI geometry hints (JSON)
  - `enabled` - Whether this category is active
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "thunderbit_definitions"
    repo Thunderline.Repo

    migration_types id: :uuid
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :category_id, :atom do
      allow_nil? false
      public? true
    end

    attribute :ontology_path, {:array, :atom} do
      default []
      public? true
    end

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:observer, :transformer, :storage, :actuator, :router, :critic, :analyzer, :controller]
    end

    attribute :description, :string do
      public? true
    end

    attribute :inputs, :map do
      default %{}
      public? true
    end

    attribute :outputs, :map do
      default %{}
      public? true
    end

    attribute :capabilities, {:array, :atom} do
      default []
      public? true
    end

    attribute :forbidden, {:array, :atom} do
      default []
      public? true
    end

    attribute :can_link_to, {:array, :atom} do
      default []
      public? true
    end

    attribute :can_receive_from, {:array, :atom} do
      default []
      public? true
    end

    attribute :composition_mode, :atom do
      default :serial
      public? true
      constraints one_of: [:serial, :parallel, :feedback, :broadcast]
    end

    attribute :required_maxims, {:array, :string} do
      default []
      public? true
    end

    attribute :forbidden_maxims, {:array, :string} do
      default []
      public? true
    end

    attribute :geometry, :map do
      default %{}
      public? true
    end

    attribute :examples, {:array, :string} do
      default []
      public? true
    end

    attribute :enabled, :boolean do
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_category_id, [:category_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :category_id,
        :ontology_path,
        :role,
        :description,
        :inputs,
        :outputs,
        :capabilities,
        :forbidden,
        :can_link_to,
        :can_receive_from,
        :composition_mode,
        :required_maxims,
        :forbidden_maxims,
        :geometry,
        :examples,
        :enabled
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :inputs,
        :outputs,
        :capabilities,
        :forbidden,
        :can_link_to,
        :can_receive_from,
        :composition_mode,
        :required_maxims,
        :forbidden_maxims,
        :geometry,
        :examples,
        :enabled
      ]
    end

    update :enable do
      change set_attribute(:enabled, true)
    end

    update :disable do
      change set_attribute(:enabled, false)
    end

    read :list_enabled do
      filter expr(enabled == true)
    end

    read :by_role do
      argument :role, :atom, allow_nil?: false
      filter expr(role == ^arg(:role))
    end

    read :by_category_id do
      argument :category_id, :atom, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end
  end

  code_interface do
    define :create, args: [:name, :category_id, :role]
    define :read
    define :list_enabled
    define :by_role, args: [:role]
    define :by_category_id, args: [:category_id]
    define :update
    define :enable
    define :disable
    define :destroy
  end
end
