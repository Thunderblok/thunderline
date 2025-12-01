defmodule Thunderline.Thundervine.Resources.BehaviorGraph do
  @moduledoc """
  BehaviorGraph - Persistent storage for composable behavior DAGs.

  Unlike Workflow (which tracks event lineage), BehaviorGraph stores
  reusable workflow definitions that can be instantiated and executed.

  ## Usage

      # Create a behavior graph from a Graph struct
      {:ok, record} = BehaviorGraph.create_from_graph(graph)

      # Load and hydrate back to a Graph struct
      {:ok, graph} = BehaviorGraph.to_graph(record)
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  alias Thunderline.Thundervine.Graph

  postgres do
    table "behavior_graphs"
    repo Thunderline.Repo
  end

  graphql do
    type :behavior_graph
  end

  actions do
    defaults [:read, :destroy]

    read :by_name do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
    end

    read :active do
      filter expr(status == :active)
    end

    create :create do
      accept [:name, :description, :graph_data, :metadata, :version]

      change fn cs, _ctx ->
        cs
        |> Ash.Changeset.change_attribute(:status, :active)
      end
    end

    create :create_from_struct do
      argument :graph, :map, allow_nil?: false

      change fn cs, _ctx ->
        graph_map = Ash.Changeset.get_argument(cs, :graph)

        cs
        |> Ash.Changeset.change_attribute(:name, graph_map[:name] || graph_map["name"])
        |> Ash.Changeset.change_attribute(:description, graph_map[:description] || graph_map["description"])
        |> Ash.Changeset.change_attribute(:graph_data, graph_map)
        |> Ash.Changeset.change_attribute(:metadata, graph_map[:metadata] || graph_map["metadata"] || %{})
        |> Ash.Changeset.change_attribute(:status, :active)
      end
    end

    update :update do
      accept [:description, :graph_data, :metadata]

      change fn cs, _ctx ->
        # Increment version on updates
        current = Ash.Changeset.get_data(cs, :version) || 0
        Ash.Changeset.change_attribute(cs, :version, current + 1)
      end
    end

    update :archive do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :archived)
      end
    end

    update :activate do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :active)
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action(:create_from_struct) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action([:update, :archive, :activate, :destroy]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      description "Human-readable name for the behavior graph"
    end

    attribute :description, :string do
      allow_nil? true
    end

    attribute :graph_data, :map do
      allow_nil? false
      default %{}
      description "Serialized Graph struct data (nodes, edges, entry/exit nodes)"
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :archived, :draft]
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :executions, Thunderline.Thundervine.Resources.GraphExecution do
      destination_attribute :behavior_graph_id
    end
  end

  identities do
    identity :unique_name_version, [:name, :version]
  end

  calculations do
    calculate :node_count, :integer do
      calculation fn records, _ctx ->
        Enum.map(records, fn record ->
          nodes = get_in(record.graph_data, ["nodes"]) || get_in(record.graph_data, [:nodes]) || %{}
          map_size(nodes)
        end)
      end
    end
  end

  @doc """
  Converts a Graph struct to a map suitable for persistence.
  """
  def serialize_graph(%Graph{} = graph) do
    Graph.to_map(graph)
  end

  @doc """
  Hydrates a BehaviorGraph record back to a Graph struct.
  """
  def to_graph(record) when is_struct(record) and is_map(record.graph_data) do
    {:ok, Graph.from_map(record.graph_data)}
  end

  def to_graph(_), do: {:error, :invalid_graph_data}
end
