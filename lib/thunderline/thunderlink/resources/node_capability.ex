defmodule Thunderline.Thunderlink.Resources.NodeCapability do
  @moduledoc """
  NodeCapability resource - tracks what each node can do.

  Enables capability-based routing and placement decisions:
  - ML inference: {:ml_inference, model_id}
  - GPU compute: {:gpu_available, true}
  - Storage: {:storage_gb, 500}
  - Geographic region: {:region, "us-west-2"}

  Thunderchief queries capabilities to make scheduling decisions.
  Thunderbolt uses ml_inference capabilities for model placement.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_node_capabilities"
    repo Thunderline.Repo

    references do
      reference :node, on_delete: :delete
    end
  end

  code_interface do
    define :create, args: [:node_id, :capability_key, :capability_value]
    define :update
    define :enable
    define :disable
    define :for_node, args: [:node_id]
    define :enabled_for_node, args: [:node_id]
    define :by_capability, args: [:capability_key]
    define :ml_inference_nodes
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a capability to a node"
      primary? true
      accept [:node_id, :capability_key, :capability_value, :enabled, :meta]
    end

    update :update do
      description "Update capability value or metadata"
      primary? true
      accept [:capability_value, :enabled, :meta]
    end

    update :enable do
      description "Enable this capability"

      change set_attribute(:enabled, true)
    end

    update :disable do
      description "Disable this capability"

      change set_attribute(:enabled, false)
    end

    read :for_node do
      description "Get all capabilities for a node"

      argument :node_id, :uuid do
        allow_nil? false
      end

      filter expr(node_id == ^arg(:node_id))
    end

    read :enabled_for_node do
      description "Get enabled capabilities for a node"

      argument :node_id, :uuid do
        allow_nil? false
      end

      filter expr(node_id == ^arg(:node_id) and enabled == true)
    end

    read :by_capability do
      description "Find nodes with a specific capability key/value"
      argument :capability_key, :string, allow_nil?: false
      argument :capability_value, :string

      prepare before_action(fn query, _context ->
                require Ash.Query
                key = query.arguments.capability_key
                query = Ash.Query.filter(query, expr(capability_key == ^key))

                if query.arguments.capability_value do
                  val = query.arguments.capability_value
                  Ash.Query.filter(query, expr(capability_value == ^val))
                else
                  query
                end
              end)
    end

    read :ml_inference_nodes do
      description "Find nodes with ML inference capability"
      filter expr(capability_key == "ml_inference" and enabled == true)
    end
  end

  policies do
    # Allow internal system access
    bypass always() do
      authorize_if always()
    end
  end

  validations do
    validate present([:node_id, :capability_key, :capability_value])
  end

  attributes do
    uuid_primary_key :id

    attribute :node_id, :uuid do
      allow_nil? false
      public? true
      description "Node this capability belongs to"
    end

    attribute :capability_key, :string do
      allow_nil? false
      public? true
      description "Capability key: ml_inference, gpu_available, storage_gb, etc."
    end

    attribute :capability_value, :string do
      allow_nil? false
      public? true
      description "Capability value (stored as string, parse as needed)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
      description "Whether this capability is currently enabled"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Additional metadata about the capability"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :node, Thunderline.Thunderlink.Resources.Node do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_capability_per_node, [:node_id, :capability_key]
  end
end
