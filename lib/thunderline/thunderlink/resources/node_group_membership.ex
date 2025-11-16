defmodule Thunderline.Thunderlink.Resources.NodeGroupMembership do
  @moduledoc """
  NodeGroupMembership - join resource for many-to-many Node <-> NodeGroup.

  Tracks which nodes belong to which groups.
  A node can belong to multiple groups (e.g., zone=us-west-2a, role=worker, project=ml-platform).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_node_group_memberships"
    repo Thunderline.Repo

    references do
      reference :node, on_delete: :delete
      reference :group, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :node_id, :uuid do
      allow_nil? false
      primary_key? true
      public? true
    end

    attribute :group_id, :uuid do
      allow_nil? false
      primary_key? true
      public? true
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Membership metadata: weight, priority, etc."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :node, Thunderline.Thunderlink.Resources.Node do
      allow_nil? false
      primary_key? true
      public? true
    end

    belongs_to :group, Thunderline.Thunderlink.Resources.NodeGroup do
      allow_nil? false
      primary_key? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :add do
      description "Add node to group"
      accept [:node_id, :group_id, :meta]
    end

    update :update do
      description "Update membership metadata"
      accept [:meta]
    end
  end

  identities do
    identity :unique_membership, [:node_id, :group_id]
  end

  validations do
    validate present([:node_id, :group_id])
  end

  policies do
    # Allow internal system access
    bypass always() do
      authorize_if always()
    end
  end

  code_interface do
    define :add, args: [:node_id, :group_id]
    define :update
  end
end
