defmodule Thunderline.Thunderchief.Resources.PlanNode do
  @moduledoc """
  PlanNode Ash Resource - Individual nodes within a PlanTree (HC-81).

  A PlanNode represents a single step in a hierarchical plan:
  - **:goal** - High-level objective (decomposed into strategies)
  - **:strategy** - Approach to achieve a goal (decomposed into actions)
  - **:action** - Concrete executable step

  ## Node Lifecycle

  1. `:pending` - Node created, waiting for dependencies
  2. `:ready` - All dependencies satisfied, can be scheduled
  3. `:running` - Currently executing
  4. `:done` - Completed successfully
  5. `:failed` - Execution failed
  6. `:skipped` - Skipped (dependency failed, cancelled, etc.)

  ## Frontier Computation

  The "frontier" consists of all `:ready` nodes - those whose dependencies
  (parent nodes) have completed. Use the `frontier` read action to get these:

  ```elixir
  {:ok, frontier} = Thunderline.Thunderchief.Domain.read(
    Thunderline.Thunderchief.Resources.PlanNode,
    :frontier,
    %{plan_tree_id: plan_id}
  )
  ```

  ## Example

  ```elixir
  # Attach a goal node to a plan
  {:ok, goal} = Thunderline.Thunderchief.attach_node!(plan_id, nil, %{
    label: "Deploy application",
    node_type: :goal
  })

  # Attach strategy under goal
  {:ok, strategy} = Thunderline.Thunderchief.attach_node!(plan_id, goal.id, %{
    label: "Blue-green deployment",
    node_type: :strategy
  })

  # Attach action under strategy
  {:ok, action} = Thunderline.Thunderchief.attach_node!(plan_id, strategy.id, %{
    label: "Build container image",
    node_type: :action,
    payload: %{dockerfile: "./Dockerfile"}
  })
  ```
  """

  use Ash.Resource,
    domain: Thunderline.Thunderchief.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "chief_plan_nodes"
    repo Thunderline.Repo

    references do
      reference :plan_tree, on_delete: :delete
      reference :parent, on_delete: :nilify
    end
  end

  graphql do
    type :plan_node
  end

  actions do
    defaults [:read, :destroy]

    read :frontier do
      argument :plan_tree_id, :uuid, allow_nil?: false

      filter expr(
        plan_tree_id == ^arg(:plan_tree_id) and
          status == :ready
      )
    end

    read :by_status do
      argument :plan_tree_id, :uuid, allow_nil?: false
      argument :status, :atom, allow_nil?: false

      filter expr(
        plan_tree_id == ^arg(:plan_tree_id) and
          status == ^arg(:status)
      )
    end

    read :children_of do
      argument :parent_id, :uuid, allow_nil?: false

      filter expr(parent_id == ^arg(:parent_id))
      prepare build(sort: [:order])
    end

    create :attach do
      accept [:label, :node_type, :payload, :order]

      argument :plan_tree_id, :uuid, allow_nil?: false
      argument :parent_id, :uuid, allow_nil?: true

      change manage_relationship(:plan_tree_id, :plan_tree, type: :append)
      change manage_relationship(:parent_id, :parent, type: :append)

      change fn changeset, _ctx ->
        # Set initial status based on parent
        parent_id = Ash.Changeset.get_argument(changeset, :parent_id)

        status =
          if is_nil(parent_id) do
            # Root node starts as ready
            :ready
          else
            # Child nodes start as pending
            :pending
          end

        Ash.Changeset.change_attribute(changeset, :status, status)
      end

      change fn changeset, _ctx ->
        # Auto-assign order if not provided
        case Ash.Changeset.get_attribute(changeset, :order) do
          nil ->
            parent_id = Ash.Changeset.get_argument(changeset, :parent_id)
            plan_tree_id = Ash.Changeset.get_argument(changeset, :plan_tree_id)

            # Count existing siblings
            require Ash.Query

            sibling_count =
              __MODULE__
              |> Ash.Query.filter(plan_tree_id == ^plan_tree_id and parent_id == ^parent_id)
              |> Ash.count!()

            Ash.Changeset.change_attribute(changeset, :order, sibling_count)

          _order ->
            changeset
        end
      end
    end

    update :start do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:result]
      change set_attribute(:status, :done)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      # Mark children as ready
      change after_action(fn changeset, node, _ctx ->
        promote_children_to_ready(node)
        {:ok, node}
      end)
    end

    update :fail do
      accept [:error]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :skip do
      change set_attribute(:status, :skipped)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :mark_ready do
      change set_attribute(:status, :ready)
    end

    update :update_payload do
      accept [:payload]
    end

    update :update_result do
      accept [:result]
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

    # Authenticated users can attach nodes
    policy action(:attach) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Authenticated users can manage nodes
    policy action([:start, :complete, :fail, :skip, :mark_ready, :update_payload, :update_result]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Read access for authenticated users
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      allow_nil? false
      public? true
      description "Human-readable label for this node"
    end

    attribute :node_type, :atom do
      allow_nil? false
      public? true
      default :action
      constraints one_of: [:goal, :strategy, :action]
      description "Node type: goal (high-level), strategy (approach), action (executable)"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :ready, :running, :done, :failed, :skipped]
      description "Current lifecycle status"
    end

    attribute :order, :integer do
      allow_nil? false
      public? true
      default 0
      description "Execution order among siblings (lower = earlier)"
    end

    attribute :payload, :map do
      allow_nil? true
      public? true
      default %{}
      description "Input parameters for this node's execution"
    end

    attribute :result, :map do
      allow_nil? true
      public? true
      description "Output/result from successful execution"
    end

    attribute :error, :map do
      allow_nil? true
      public? true
      description "Error details if status is :failed"
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When node execution started"
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When node reached terminal state"
    end

    timestamps()
  end

  relationships do
    belongs_to :plan_tree, Thunderline.Thunderchief.Resources.PlanTree do
      allow_nil? false
      public? true
      description "Parent plan this node belongs to"
    end

    belongs_to :parent, __MODULE__ do
      allow_nil? true
      public? true
      description "Parent node (nil for root nodes)"
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
      public? true
      description "Child nodes under this node"
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
      status in [:done, :failed, :skipped]
    ) do
      public? true
      description "Whether node has reached a terminal state"
    end

    calculate :is_leaf?, :boolean, expr(
      count(children) == 0
    ) do
      public? true
      description "Whether this is a leaf node (no children)"
    end

    calculate :depth, :integer, expr(
      fragment(
        "WITH RECURSIVE node_depth AS (
          SELECT id, parent_id, 0 as depth FROM chief_plan_nodes WHERE id = ?
          UNION ALL
          SELECT n.id, n.parent_id, nd.depth + 1
          FROM chief_plan_nodes n
          JOIN node_depth nd ON n.id = nd.parent_id
        )
        SELECT MAX(depth) FROM node_depth",
        id
      )
    ) do
      public? true
      description "Depth in tree (root = 0)"
    end
  end

  aggregates do
    count :child_count, :children do
      public? true
      description "Number of direct children"
    end

    count :completed_child_count, :children do
      filter expr(status in [:done, :skipped])
      public? true
    end

    count :pending_child_count, :children do
      filter expr(status == :pending)
      public? true
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc false
  def promote_children_to_ready(node) when is_struct(node) do
    parent_id = node.id
    # Find all pending children of this node and mark them ready
    require Ash.Query

    __MODULE__
    |> Ash.Query.filter(parent_id == ^parent_id and status == :pending)
    |> Ash.read!()
    |> Enum.each(fn child ->
      child
      |> Ash.Changeset.for_update(:mark_ready, %{})
      |> Ash.update!()
    end)
  end

  @doc """
  Convert this node to a map suitable for the in-memory PlanTree struct.
  """
  @spec to_node_map(map()) :: map()
  def to_node_map(node) when is_struct(node) do
    %{
      id: node.id,
      label: node.label,
      node_type: node.node_type,
      status: node.status,
      order: node.order,
      payload: node.payload,
      result: node.result,
      error: node.error,
      parent_id: node.parent_id
    }
  end

  @doc """
  Create a node from a map (used when persisting from in-memory struct).
  """
  @spec from_node_map(map(), Ecto.UUID.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, t()} | {:error, term()}
  def from_node_map(node_map, plan_tree_id, parent_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    attrs = %{
      label: node_map[:label] || node_map["label"] || "Unnamed",
      node_type: node_map[:node_type] || node_map["node_type"] || :action,
      payload: node_map[:payload] || node_map["payload"] || %{},
      order: node_map[:order] || node_map["order"] || 0,
      plan_tree_id: plan_tree_id,
      parent_id: parent_id
    }

    __MODULE__
    |> Ash.Changeset.for_create(:attach, attrs, actor: actor)
    |> Ash.create()
  end
end
