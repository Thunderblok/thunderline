defmodule Thunderline.Thunderchief.Resources.PlanTree do
  @moduledoc """
  PlanTree Ash Resource - Persistent storage for hierarchical plans (HC-81).

  A PlanTree represents a complete orchestration plan with:
  - Goal description and metadata
  - Status lifecycle (pending → running → completed/failed/cancelled)
  - Root node reference and child node relationships
  - Domain context for Chief routing

  ## Hybrid Architecture

  This Ash resource provides **persistence** while the struct-based
  `Thunderline.Thunderchief.PlanTree` module provides **fast in-memory execution**.

  Use the adapters to convert between:
  ```elixir
  # Ash → Struct (for execution)
  {:ok, struct_tree} = PlanTree.to_struct(ash_tree)

  # Struct → Ash (for persistence)
  {:ok, ash_tree} = PlanTree.from_struct(struct_tree)
  ```

  ## Plan Lifecycle

  1. `:pending` - Plan created, not yet started
  2. `:running` - Plan actively executing
  3. `:completed` - All nodes finished successfully
  4. `:failed` - Critical node failed, plan aborted
  5. `:cancelled` - Plan cancelled externally

  ## Example

  ```elixir
  # Create a plan
  {:ok, plan} = Thunderline.Thunderchief.create_plan!("Deploy v2.0", %{
    domain: :vine,
    metadata: %{priority: :high}
  })

  # Start execution
  {:ok, plan} = Thunderline.Thunderchief.start_plan!(plan.id)

  # Check completion
  plan = Thunderline.Thunderchief.get_plan_tree!(plan.id, load: [:nodes])
  ```
  """

  use Ash.Resource,
    domain: Thunderline.Thunderchief.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  alias Thunderline.Thunderchief.PlanTree, as: PlanTreeStruct

  postgres do
    table "chief_plan_trees"
    repo Thunderline.Repo

    references do
      reference :root_node, on_delete: :nilify
    end
  end

  graphql do
    type :plan_tree
  end

  actions do
    defaults [:read, :destroy]

    read :running do
      filter expr(status == :running)
    end

    read :by_domain do
      argument :domain, :atom, allow_nil?: false
      filter expr(domain == ^arg(:domain))
    end

    create :create_plan do
      accept [:goal, :domain, :metadata]

      change fn changeset, _ctx ->
        Ash.Changeset.change_attribute(changeset, :status, :pending)
      end
    end

    update :start do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :set_root_node do
      accept [:root_node_id]
    end

    update :update_metadata do
      accept [:metadata]
    end
  end

  policies do
    # Admin bypass
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # System actors can do everything
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Authenticated users can create plans
    policy action(:create_plan) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Authenticated users can manage plans
    policy action([:start, :complete, :fail, :cancel, :set_root_node, :update_metadata]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Read access for authenticated users
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Public read for completed plans
    policy action_type(:read) do
      authorize_if expr(status == :completed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :goal, :string do
      allow_nil? false
      public? true
      description "Human-readable goal/purpose of this plan"
    end

    attribute :domain, :atom do
      allow_nil? true
      public? true
      default :bit
      description "Domain context for Chief routing (bit, vine, crown, ui, plan)"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
      description "Current lifecycle status"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Arbitrary metadata (priority, tags, context)"
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
      description "Error description if status is :failed"
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When plan execution started"
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When plan reached terminal state"
    end

    timestamps()
  end

  relationships do
    belongs_to :root_node, Thunderline.Thunderchief.Resources.PlanNode do
      allow_nil? true
      public? true
      description "Root node of the plan tree"
    end

    has_many :nodes, Thunderline.Thunderchief.Resources.PlanNode do
      public? true
      description "All nodes belonging to this plan"
    end
  end

  calculations do
    calculate :duration_ms, :integer, expr(
      if(not is_nil(started_at) and not is_nil(completed_at),
        fragment("EXTRACT(EPOCH FROM (? - ?)) * 1000", completed_at, started_at),
        nil
      )
    ) do
      public? true
      description "Execution duration in milliseconds"
    end

    calculate :is_terminal?, :boolean, expr(
      status in [:completed, :failed, :cancelled]
    ) do
      public? true
      description "Whether plan has reached a terminal state"
    end
  end

  aggregates do
    count :node_count, :nodes do
      public? true
      description "Total number of nodes in this plan"
    end

    count :pending_node_count, :nodes do
      filter expr(status == :pending)
      public? true
    end

    count :running_node_count, :nodes do
      filter expr(status == :running)
      public? true
    end

    count :completed_node_count, :nodes do
      filter expr(status in [:done, :skipped])
      public? true
    end

    count :failed_node_count, :nodes do
      filter expr(status == :failed)
      public? true
    end
  end

  identities do
    identity :unique_goal_domain, [:goal, :domain] do
      pre_check_with Thunderline.Thunderchief.Domain
    end
  end

  # ============================================================================
  # Struct Adapters (Hybrid Architecture)
  # ============================================================================

  @doc """
  Convert this Ash resource to the in-memory PlanTree struct for fast execution.

  Loads all nodes and reconstructs the rose tree structure.
  """
  @spec to_struct(map()) :: {:ok, PlanTreeStruct.t()} | {:error, term()}
  def to_struct(ash_tree) when is_struct(ash_tree) do
    # Ensure nodes are loaded
    ash_tree = Ash.load!(ash_tree, [:nodes])

    # Convert to struct format
    struct_tree = %{
      id: ash_tree.id,
      goal: ash_tree.goal,
      status: ash_tree.status,
      metadata: %{
        domain: ash_tree.domain,
        started_at: ash_tree.started_at,
        completed_at: ash_tree.completed_at
      },
      tree: build_rose_tree_from_nodes(ash_tree.nodes, ash_tree.root_node_id)
    }

    {:ok, struct(PlanTreeStruct, struct_tree)}
  rescue
    e -> {:error, {:struct_conversion_failed, Exception.message(e)}}
  end

  @doc """
  Persist an in-memory PlanTree struct to this Ash resource.

  Creates or updates the plan tree and all its nodes.
  """
  @spec from_struct(PlanTreeStruct.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_struct(%PlanTreeStruct{} = struct_tree, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    # Create or update the plan tree
    attrs = %{
      goal: struct_tree.goal || struct_tree.id,
      domain: get_in(struct_tree.metadata, [:domain]) || :bit,
      status: struct_tree.status || :pending,
      metadata: Map.drop(struct_tree.metadata || %{}, [:domain, :started_at, :completed_at]),
      started_at: get_in(struct_tree.metadata, [:started_at]),
      completed_at: get_in(struct_tree.metadata, [:completed_at])
    }

    case struct_tree.id do
      nil ->
        # New plan
        __MODULE__
        |> Ash.Changeset.for_create(:create_plan, attrs, actor: actor)
        |> Ash.create()

      existing_id ->
        # Update existing
        case Ash.get(__MODULE__, existing_id) do
          {:ok, existing} ->
            existing
            |> Ash.Changeset.for_update(:update_metadata, %{metadata: attrs.metadata}, actor: actor)
            |> Ash.update()

          {:error, _} ->
            # Doesn't exist, create with ID
            __MODULE__
            |> Ash.Changeset.for_create(:create_plan, attrs, actor: actor)
            |> Ash.create()
        end
    end
  end

  # Build rose tree from flat node list
  defp build_rose_tree_from_nodes([], _root_id), do: nil

  defp build_rose_tree_from_nodes(nodes, root_id) do
    nodes_by_id = Map.new(nodes, fn n -> {n.id, n} end)
    nodes_by_parent = Enum.group_by(nodes, & &1.parent_id)

    build_subtree(root_id, nodes_by_id, nodes_by_parent)
  end

  defp build_subtree(nil, _by_id, _by_parent), do: nil

  defp build_subtree(node_id, nodes_by_id, nodes_by_parent) do
    case Map.get(nodes_by_id, node_id) do
      nil ->
        nil

      node ->
        children = Map.get(nodes_by_parent, node_id, [])

        child_trees =
          children
          |> Enum.sort_by(& &1.order)
          |> Enum.map(&build_subtree(&1.id, nodes_by_id, nodes_by_parent))
          |> Enum.reject(&is_nil/1)

        Thunderline.RoseTree.new(node_id, %{
          label: node.label,
          node_type: node.node_type,
          status: node.status,
          payload: node.payload,
          result: node.result
        })
        |> then(fn tree ->
          Enum.reduce(child_trees, tree, &Thunderline.RoseTree.add_subtree(&2, &1))
        end)
    end
  end
end
