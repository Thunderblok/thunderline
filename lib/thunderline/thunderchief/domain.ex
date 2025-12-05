defmodule Thunderline.Thunderchief.Domain do
  @moduledoc """
  ThunderChief Ash Domain - Hierarchical Plan Orchestration & Chief Management

  **Boundary**: "If it orchestrates, it's Chief" - Plan trees, domain chiefs, action execution

  Core responsibilities:
  - Persistent plan tree storage for long-running orchestration
  - Plan node lifecycle management (pending → running → done/failed)
  - Chief coordination and domain delegation
  - Trajectory logging for Cerebros RL training

  ## Architecture

  Thunderchief implements a hybrid approach:
  - **In-memory**: Fast `Thunderline.Thunderchief.PlanTree` struct for ephemeral execution
  - **Persistent**: `PlanTree` and `PlanNode` Ash resources for long-running/archival plans

  The Ash resources serialize to/from the struct-based PlanTree via adapters,
  enabling both speed (in-memory) and durability (PostgreSQL).

  ## Plan Lifecycle (HC-82)

  1. **Create Plan**: `create_plan` action creates root + initial structure
  2. **Expand Nodes**: Chiefs call `expand_node` to decompose goals into strategies/actions
  3. **Execute Frontier**: `compute_frontier` finds ready nodes, dispatched via Oban
  4. **Complete/Fail**: Node results update via `complete_node` or `fail_node`
  5. **Archive**: Completed plans can be archived for analysis

  ## Code Interfaces

  ```elixir
  # Create a new plan
  {:ok, plan} = Thunderchief.create_plan!("Deploy feature X")

  # Add child nodes
  {:ok, node} = Thunderchief.attach_node!(plan.id, parent_id, %{label: "Build", node_type: :strategy})

  # Get ready-to-execute frontier
  frontier = Thunderchief.get_frontier!(plan.id)

  # Complete a node
  {:ok, _} = Thunderchief.complete_node!(node_id, %{output: "success"})
  ```
  """

  use Ash.Domain,
    otp_app: :thunderline,
    extensions: [AshAdmin.Domain, AshGraphql.Domain]

  admin do
    show? true
  end

  graphql do
    authorize? true

    queries do
      # PlanTree queries
      get Thunderline.Thunderchief.Resources.PlanTree, :plan_tree, :read
      list Thunderline.Thunderchief.Resources.PlanTree, :plan_trees, :read
      list Thunderline.Thunderchief.Resources.PlanTree, :running_plan_trees, :running

      # PlanNode queries
      get Thunderline.Thunderchief.Resources.PlanNode, :plan_node, :read
      list Thunderline.Thunderchief.Resources.PlanNode, :plan_nodes, :read
      list Thunderline.Thunderchief.Resources.PlanNode, :frontier_nodes, :frontier
    end

    mutations do
      # PlanTree mutations
      create Thunderline.Thunderchief.Resources.PlanTree, :create_plan, :create_plan
      update Thunderline.Thunderchief.Resources.PlanTree, :start_plan, :start
      update Thunderline.Thunderchief.Resources.PlanTree, :complete_plan, :complete
      update Thunderline.Thunderchief.Resources.PlanTree, :fail_plan, :fail
      update Thunderline.Thunderchief.Resources.PlanTree, :cancel_plan, :cancel

      # PlanNode mutations
      create Thunderline.Thunderchief.Resources.PlanNode, :attach_node, :attach
      update Thunderline.Thunderchief.Resources.PlanNode, :start_node, :start
      update Thunderline.Thunderchief.Resources.PlanNode, :complete_node, :complete
      update Thunderline.Thunderchief.Resources.PlanNode, :fail_node, :fail
      update Thunderline.Thunderchief.Resources.PlanNode, :skip_node, :skip
    end
  end

  resources do
    resource Thunderline.Thunderchief.Resources.PlanTree do
      define :create_plan, action: :create_plan, args: [:goal]
      define :get_plan_tree, action: :read, get_by: [:id]
      define :list_plan_trees, action: :read
      define :list_running_plans, action: :running
      define :list_plans_by_domain, action: :by_domain, args: [:domain]
      define :start_plan, action: :start
      define :complete_plan, action: :complete
      define :fail_plan, action: :fail
      define :cancel_plan, action: :cancel
      define :set_root_node, action: :set_root_node
    end

    resource Thunderline.Thunderchief.Resources.PlanNode do
      define :attach_node, action: :attach, args: [:plan_tree_id, :parent_id]
      define :get_node, action: :read, get_by: [:id]
      define :list_nodes, action: :read
      define :get_frontier, action: :frontier, args: [:plan_tree_id]
      define :list_children, action: :children_of, args: [:parent_id]
      define :start_node, action: :start
      define :complete_node, action: :complete
      define :fail_node, action: :fail
      define :skip_node, action: :skip
      define :mark_node_ready, action: :mark_ready
    end
  end
end
