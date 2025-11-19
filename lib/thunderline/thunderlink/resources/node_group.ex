defmodule Thunderline.Thunderlink.Resources.NodeGroup do
  @moduledoc """
  NodeGroup resource - logical grouping of nodes.

  Enables:
  - Zone-based grouping (availability zones, data centers)
  - Shard-based grouping (for distributed data)
  - Geographic grouping (regions, continents)
  - Role-based grouping (workers, coordinators, edges)
  - Custom grouping (project, tenant, environment)

  Groups can be nested (e.g., region → zone → rack).
  Many-to-many relationship: nodes can belong to multiple groups.

  Used by Thunderchief for:
  - Placement constraints (affinity/anti-affinity)
  - Failure domain isolation
  - Compliance requirements (data sovereignty)
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_node_groups"
    repo Thunderline.Repo
  end

  code_interface do
    define :create, args: [:name, :group_type]
    define :update
    define :by_type, args: [:group_type]
    define :root_groups
    define :children_of, args: [:parent_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new node group"
      primary? true
      accept [:name, :group_type, :parent_group_id, :meta]
    end

    update :update do
      description "Update group metadata"
      primary? true
      accept [:name, :group_type, :parent_group_id, :meta]
    end

    read :by_type do
      description "Get groups by type"

      argument :group_type, :atom do
        allow_nil? false
        constraints one_of: [:zone, :shard, :region, :role, :project, :custom]
      end

      filter expr(group_type == ^arg(:group_type))
    end

    read :root_groups do
      description "Get top-level groups (no parent)"
      filter expr(is_nil(parent_group_id))
    end

    read :children_of do
      description "Get child groups of a parent"

      argument :parent_id, :uuid do
        allow_nil? false
      end

      filter expr(parent_group_id == ^arg(:parent_id))
    end
  end

  policies do
    # Allow internal system access
    bypass always() do
      authorize_if always()
    end
  end

  validations do
    validate present([:name])
    validate one_of(:group_type, [:zone, :shard, :region, :role, :project, :custom])
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Group name: us-west-2a, shard-001, ml-workers, etc."
    end

    attribute :group_type, :atom do
      allow_nil? false
      default :custom
      public? true
      constraints one_of: [:zone, :shard, :region, :role, :project, :custom]
      description "Type of grouping"
    end

    attribute :parent_group_id, :uuid do
      public? true
      description "Parent group for hierarchical grouping"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Group metadata: capacity, limits, policies, etc."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :parent, Thunderline.Thunderlink.Resources.NodeGroup do
      source_attribute :parent_group_id
      public? true
    end

    has_many :children, Thunderline.Thunderlink.Resources.NodeGroup do
      destination_attribute :parent_group_id
      public? true
    end

    many_to_many :nodes, Thunderline.Thunderlink.Resources.Node do
      through Thunderline.Thunderlink.Resources.NodeGroupMembership
      source_attribute_on_join_resource :group_id
      destination_attribute_on_join_resource :node_id
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
