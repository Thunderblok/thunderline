defmodule Thunderline.Thunderchief.PlanTree do
  @moduledoc """
  Plan Tree for hierarchical action orchestration.

  A PlanTree represents a hierarchical decomposition of goals into executable
  actions. It uses a rose tree structure where each node can be:

  - **:root** - The top-level goal
  - **:sequence** - Children executed in order
  - **:parallel** - Children executed concurrently
  - **:choice** - One child selected based on conditions
  - **:guard** - Conditional execution
  - **:leaf** - Executable action

  ## Lifecycle

  1. **Creation** - `new/2` creates tree with root node
  2. **Expansion** - `expand/3` decomposes nodes into children via Chief
  3. **Scheduling** - `schedule_ready_nodes/1` identifies executable nodes
  4. **Execution** - External system runs scheduled nodes
  5. **Completion** - `apply_node_result/3` updates node status
  6. **Tick** - `tick/2` advances the tree state

  ## Example

      # Create a plan tree
      {:ok, tree} = PlanTree.new(:my_plan, %{goal: "sync data"})

      # Expand root into children
      {:ok, tree} = PlanTree.expand(tree, :my_plan, [
        {:step1, %{action: :fetch, domain: :thunderblock}},
        {:step2, %{action: :transform, domain: :thundervine}}
      ])

      # Get nodes ready for execution
      ready = PlanTree.schedule_ready_nodes(tree)

      # Mark node as completed
      {:ok, tree} = PlanTree.apply_node_result(tree, :step1, %{
        status: :succeeded,
        output: data
      })

  ## Status Flow

      pending → queued → running → succeeded
                              ↘ failed
                              ↘ cancelled
                              ↘ skipped

  ## Integration Points

  - **DomainProcessor** - Executes scheduled leaf nodes
  - **Thunderheart.RewardTree** - Parallel reward decomposition
  - **Thundervine.DAG** - Node dependencies (future)
  - **Thunderflow.EventBus** - Status change events
  """

  alias Thunderline.RoseTree

  @typedoc "Plan tree structure"
  @type t :: %__MODULE__{
          tree: RoseTree.t(),
          metadata: metadata()
        }

  @typedoc "Plan metadata"
  @type metadata :: %{
          required(:id) => plan_id(),
          required(:created_at) => DateTime.t(),
          required(:status) => plan_status(),
          optional(:pac_id) => binary(),
          optional(:tick) => non_neg_integer(),
          optional(:domain) => atom(),
          optional(:tags) => [atom()]
        }

  @typedoc "Unique plan identifier"
  @type plan_id :: binary()

  @typedoc "Overall plan status"
  @type plan_status :: :pending | :running | :succeeded | :failed | :cancelled

  @typedoc "Node kind"
  @type node_kind :: :root | :sequence | :parallel | :choice | :guard | :leaf

  @typedoc "Node status"
  @type node_status :: :pending | :queued | :running | :succeeded | :failed | :cancelled | :skipped

  @typedoc "Plan node value"
  @type node_value :: %{
          required(:kind) => node_kind(),
          required(:status) => node_status(),
          optional(:action) => atom(),
          optional(:domain) => atom(),
          optional(:params) => map(),
          optional(:output) => term(),
          optional(:error) => term(),
          optional(:started_at) => DateTime.t(),
          optional(:completed_at) => DateTime.t(),
          optional(:metadata) => map()
        }

  @typedoc "Node execution result"
  @type node_result :: %{
          required(:status) => :succeeded | :failed | :skipped,
          optional(:output) => term(),
          optional(:error) => term(),
          optional(:metadata) => map()
        }

  @typedoc "Domain classification"
  @type domain ::
          :thunderbit
          | :thundervine
          | :thunderflow
          | :thunderblock
          | :thundergrid
          | :thundergate
          | :thundercrown
          | :thunderlink
          | :thunderprism
          | :thundercore
          | :system

  defstruct [:tree, :metadata]

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new plan tree with a root node.

  ## Parameters

  - `id` - Unique identifier for the plan
  - `opts` - Options including:
    - `:goal` - Description of the plan goal
    - `:domain` - Primary domain for this plan
    - `:pac_id` - Associated PAC identifier
    - `:tick` - Current tick number
    - `:tags` - List of tags for categorization

  ## Returns

  `{:ok, plan_tree}` on success
  """
  @spec new(plan_id(), keyword()) :: {:ok, t()}
  def new(id, opts \\ []) do
    root_value = %{
      kind: :root,
      status: :pending,
      goal: Keyword.get(opts, :goal),
      domain: Keyword.get(opts, :domain),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    tree = RoseTree.new(id, root_value)

    metadata = %{
      id: id,
      created_at: DateTime.utc_now(),
      status: :pending,
      pac_id: Keyword.get(opts, :pac_id),
      tick: Keyword.get(opts, :tick, 0),
      domain: Keyword.get(opts, :domain),
      tags: Keyword.get(opts, :tags, [])
    }

    {:ok, %__MODULE__{tree: tree, metadata: metadata}}
  end

  # ============================================================================
  # Expansion
  # ============================================================================

  @doc """
  Expands a node into child nodes.

  ## Parameters

  - `plan` - The plan tree
  - `node_id` - ID of the node to expand
  - `children` - List of `{child_id, child_value}` tuples

  ## Returns

  `{:ok, updated_plan}` or `{:error, reason}`
  """
  @spec expand(t(), binary(), [{binary(), node_value()}]) :: {:ok, t()} | {:error, term()}
  def expand(%__MODULE__{tree: tree} = plan, node_id, children) do
    with {:ok, _} <- RoseTree.find(tree, node_id),
         {:ok, updated_tree} <- add_children(tree, node_id, children) do
      {:ok, %{plan | tree: updated_tree}}
    else
      {:error, :not_found} -> {:error, {:node_not_found, node_id}}
      error -> error
    end
  end

  defp add_children(tree, parent_id, children) do
    Enum.reduce_while(children, {:ok, tree}, fn {child_id, child_value}, {:ok, acc_tree} ->
      normalized_value = normalize_node_value(child_value)

      case RoseTree.insert_child(acc_tree, parent_id, child_id, normalized_value) do
        {:ok, new_tree} -> {:cont, {:ok, new_tree}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_node_value(value) do
    value
    |> Map.put_new(:kind, :leaf)
    |> Map.put_new(:status, :pending)
  end

  # ============================================================================
  # Scheduling
  # ============================================================================

  @doc """
  Returns nodes ready for execution.

  A node is ready when:
  - It has status `:pending` or `:queued`
  - It is a `:leaf` node (or `:guard` with condition)
  - All prerequisite nodes are complete (for `:sequence` parents)

  ## Returns

  List of `{node_id, node_value}` tuples ready for execution.
  """
  @spec schedule_ready_nodes(t()) :: [{binary(), node_value()}]
  def schedule_ready_nodes(%__MODULE__{tree: tree}) do
    tree
    |> RoseTree.to_list()
    |> Enum.filter(&ready_for_execution?(&1, tree))
    |> Enum.map(fn node -> {node.id, node.value} end)
  end

  defp ready_for_execution?(node, tree) do
    is_executable_kind?(node.value) and
      is_pending_status?(node.value) and
      prerequisites_complete?(node.id, tree)
  end

  defp is_executable_kind?(%{kind: kind}) when kind in [:leaf, :guard], do: true
  defp is_executable_kind?(_), do: false

  defp is_pending_status?(%{status: status}) when status in [:pending, :queued], do: true
  defp is_pending_status?(_), do: false

  defp prerequisites_complete?(node_id, tree) do
    path = RoseTree.path_to(tree, node_id)

    case find_parent_in_path(path, node_id) do
      nil ->
        true

      parent ->
        if parent.value.kind == :sequence do
          siblings_before_complete?(node_id, tree, parent.id)
        else
          true
        end
    end
  end

  defp find_parent_in_path(path, node_id) do
    path
    |> Enum.reverse()
    |> Enum.drop(1)
    |> List.first()
  end

  defp siblings_before_complete?(node_id, tree, parent_id) do
    case RoseTree.find(tree, parent_id) do
      {:ok, parent_tree} ->
        parent_tree
        |> RoseTree.children()
        |> Enum.map(&RoseTree.root/1)
        |> Enum.take_while(fn sibling -> sibling.id != node_id end)
        |> Enum.all?(fn sibling -> sibling.value.status == :succeeded end)

      _ ->
        true
    end
  end

  # ============================================================================
  # Execution Results
  # ============================================================================

  @doc """
  Applies the result of node execution.

  Updates the node's status and output based on execution result.
  Propagates status changes up the tree when needed.

  ## Parameters

  - `plan` - The plan tree
  - `node_id` - ID of the executed node
  - `result` - Execution result map with `:status`, optional `:output`, `:error`

  ## Returns

  `{:ok, updated_plan}` or `{:error, reason}`
  """
  @spec apply_node_result(t(), binary(), node_result()) :: {:ok, t()} | {:error, term()}
  def apply_node_result(%__MODULE__{tree: tree} = plan, node_id, result) do
    update_fn = fn value ->
      value
      |> Map.put(:status, result.status)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> maybe_put(:output, result[:output])
      |> maybe_put(:error, result[:error])
      |> maybe_put(:metadata, Map.merge(value[:metadata] || %{}, result[:metadata] || %{}))
    end

    case RoseTree.update_value(tree, node_id, update_fn) do
      {:ok, updated_tree} ->
        plan = %{plan | tree: updated_tree}
        {:ok, propagate_status(plan)}

      {:error, :not_found} ->
        {:error, {:node_not_found, node_id}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp propagate_status(%__MODULE__{tree: tree} = plan) do
    # Update non-leaf nodes based on children status
    updated_tree =
      RoseTree.map(tree, fn node ->
        if node.value.kind in [:sequence, :parallel, :choice, :root] do
          case RoseTree.find(tree, node.id) do
            {:ok, subtree} ->
              children = RoseTree.children(subtree)

              if children == [] do
                node
              else
                new_status = compute_parent_status(node.value.kind, children)
                %{node | value: Map.put(node.value, :status, new_status)}
              end

            _ ->
              node
          end
        else
          node
        end
      end)

    # Update plan-level status from root
    root = RoseTree.root(updated_tree)
    plan_status = map_node_status_to_plan_status(root.value.status)

    %{plan | tree: updated_tree, metadata: %{plan.metadata | status: plan_status}}
  end

  defp compute_parent_status(:sequence, children) do
    statuses = Enum.map(children, fn c -> RoseTree.root(c).value.status end)

    cond do
      Enum.any?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 == :cancelled)) -> :cancelled
      Enum.all?(statuses, &(&1 == :succeeded)) -> :succeeded
      Enum.any?(statuses, &(&1 == :running)) -> :running
      Enum.any?(statuses, &(&1 in [:pending, :queued])) -> :running
      true -> :pending
    end
  end

  defp compute_parent_status(:parallel, children) do
    statuses = Enum.map(children, fn c -> RoseTree.root(c).value.status end)

    cond do
      Enum.all?(statuses, &(&1 == :succeeded)) -> :succeeded
      Enum.any?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 == :cancelled)) -> :cancelled
      Enum.any?(statuses, &(&1 == :running)) -> :running
      true -> :pending
    end
  end

  defp compute_parent_status(:choice, children) do
    # For choice, any succeeded child means success
    statuses = Enum.map(children, fn c -> RoseTree.root(c).value.status end)

    cond do
      Enum.any?(statuses, &(&1 == :succeeded)) -> :succeeded
      Enum.all?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 == :running)) -> :running
      true -> :pending
    end
  end

  defp compute_parent_status(:root, children), do: compute_parent_status(:sequence, children)

  defp map_node_status_to_plan_status(:succeeded), do: :succeeded
  defp map_node_status_to_plan_status(:failed), do: :failed
  defp map_node_status_to_plan_status(:cancelled), do: :cancelled
  defp map_node_status_to_plan_status(:running), do: :running
  defp map_node_status_to_plan_status(_), do: :pending

  # ============================================================================
  # Tick
  # ============================================================================

  @doc """
  Advances the plan tree state by one tick.

  This operation:
  - Updates the tick counter in metadata
  - Transitions queued nodes to running
  - Checks for timeout conditions
  - Returns nodes ready for scheduling

  ## Parameters

  - `plan` - The plan tree
  - `opts` - Options including:
    - `:timeout_ticks` - Number of ticks before a running node times out
    - `:max_concurrent` - Maximum nodes to return for scheduling

  ## Returns

  `{:ok, updated_plan, ready_nodes}` tuple
  """
  @spec tick(t(), keyword()) :: {:ok, t(), [{binary(), node_value()}]}
  def tick(%__MODULE__{metadata: meta} = plan, opts \\ []) do
    timeout_ticks = Keyword.get(opts, :timeout_ticks)
    max_concurrent = Keyword.get(opts, :max_concurrent, 10)

    # Update tick counter
    plan = %{plan | metadata: %{meta | tick: (meta.tick || 0) + 1}}

    # Handle timeouts if configured
    plan =
      if timeout_ticks do
        handle_timeouts(plan, timeout_ticks)
      else
        plan
      end

    # Get ready nodes
    ready =
      plan
      |> schedule_ready_nodes()
      |> Enum.take(max_concurrent)

    # Mark scheduled nodes as queued
    plan =
      Enum.reduce(ready, plan, fn {node_id, _}, acc ->
        {:ok, updated} = mark_queued(acc, node_id)
        updated
      end)

    {:ok, plan, ready}
  end

  defp handle_timeouts(plan, _timeout_ticks) do
    # TODO: Implement timeout tracking
    plan
  end

  @doc """
  Marks a node as queued for execution.
  """
  @spec mark_queued(t(), binary()) :: {:ok, t()} | {:error, term()}
  def mark_queued(%__MODULE__{tree: tree} = plan, node_id) do
    case RoseTree.update_value(tree, node_id, fn value ->
           %{value | status: :queued}
         end) do
      {:ok, updated_tree} -> {:ok, %{plan | tree: updated_tree}}
      error -> error
    end
  end

  @doc """
  Marks a node as running.
  """
  @spec mark_running(t(), binary()) :: {:ok, t()} | {:error, term()}
  def mark_running(%__MODULE__{tree: tree} = plan, node_id) do
    case RoseTree.update_value(tree, node_id, fn value ->
           %{value | status: :running, started_at: DateTime.utc_now()}
         end) do
      {:ok, updated_tree} -> {:ok, %{plan | tree: updated_tree}}
      error -> error
    end
  end

  # ============================================================================
  # Cancellation
  # ============================================================================

  @doc """
  Cancels a node and all its descendants.

  ## Parameters

  - `plan` - The plan tree
  - `node_id` - ID of the node to cancel
  - `reason` - Optional cancellation reason

  ## Returns

  `{:ok, updated_plan}` or `{:error, reason}`
  """
  @spec cancel(t(), binary(), term()) :: {:ok, t()} | {:error, term()}
  def cancel(%__MODULE__{tree: tree} = plan, node_id, reason \\ :user_cancelled) do
    case RoseTree.find(tree, node_id) do
      {:ok, subtree} ->
        # Collect all node IDs in the subtree
        node_ids = subtree |> RoseTree.to_list() |> Enum.map(& &1.id)

        # Cancel each node
        updated_tree =
          Enum.reduce(node_ids, tree, fn id, acc ->
            case RoseTree.update_value(acc, id, fn value ->
                   if value.status in [:pending, :queued, :running] do
                     %{value | status: :cancelled, error: reason}
                   else
                     value
                   end
                 end) do
              {:ok, new_tree} -> new_tree
              _ -> acc
            end
          end)

        plan = %{plan | tree: updated_tree}
        {:ok, propagate_status(plan)}

      {:error, :not_found} ->
        {:error, {:node_not_found, node_id}}
    end
  end

  # ============================================================================
  # Query Functions
  # ============================================================================

  @doc """
  Folds over the plan tree, accumulating a result.

  ## Parameters

  - `plan` - The plan tree
  - `acc` - Initial accumulator
  - `fun` - Function `({node_id, node_value}, acc) -> new_acc`
  """
  @spec fold(t(), acc, ({binary(), node_value()}, acc -> acc)) :: acc when acc: term()
  def fold(%__MODULE__{tree: tree}, acc, fun) do
    RoseTree.fold(tree, acc, fn node, inner_acc ->
      fun.({node.id, node.value}, inner_acc)
    end)
  end

  @doc """
  Gets a node by ID.
  """
  @spec get_node(t(), binary()) :: {:ok, {binary(), node_value()}} | {:error, :not_found}
  def get_node(%__MODULE__{tree: tree}, node_id) do
    case RoseTree.find(tree, node_id) do
      {:ok, subtree} ->
        node = RoseTree.root(subtree)
        {:ok, {node.id, node.value}}

      error ->
        error
    end
  end

  @doc """
  Gets the root node.
  """
  @spec root(t()) :: {binary(), node_value()}
  def root(%__MODULE__{tree: tree}) do
    node = RoseTree.root(tree)
    {node.id, node.value}
  end

  @doc """
  Returns the plan ID.
  """
  @spec id(t()) :: plan_id()
  def id(%__MODULE__{metadata: %{id: id}}), do: id

  @doc """
  Returns the plan status.
  """
  @spec status(t()) :: plan_status()
  def status(%__MODULE__{metadata: %{status: status}}), do: status

  @doc """
  Checks if the plan is complete (succeeded, failed, or cancelled).
  """
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{metadata: %{status: status}}) do
    status in [:succeeded, :failed, :cancelled]
  end

  @doc """
  Returns all nodes with a specific status.
  """
  @spec nodes_by_status(t(), node_status()) :: [{binary(), node_value()}]
  def nodes_by_status(plan, status) do
    fold(plan, [], fn {id, value}, acc ->
      if value.status == status do
        [{id, value} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns all leaf nodes.
  """
  @spec leaf_nodes(t()) :: [{binary(), node_value()}]
  def leaf_nodes(plan) do
    fold(plan, [], fn {id, value}, acc ->
      if value.kind == :leaf do
        [{id, value} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Counts nodes by status.
  """
  @spec status_summary(t()) :: map()
  def status_summary(plan) do
    fold(plan, %{}, fn {_id, value}, acc ->
      Map.update(acc, value.status, 1, &(&1 + 1))
    end)
  end

  @doc """
  Returns the depth of the plan tree.
  """
  @spec depth(t()) :: non_neg_integer()
  def depth(%__MODULE__{tree: tree}), do: RoseTree.depth(tree)

  @doc """
  Counts total nodes in the plan.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{tree: tree}), do: RoseTree.count(tree)

  # ============================================================================
  # Serialization
  # ============================================================================

  @doc """
  Converts the plan tree to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{tree: tree, metadata: metadata}) do
    %{
      tree: RoseTree.to_map(tree),
      metadata: serialize_metadata(metadata)
    }
  end

  defp serialize_metadata(metadata) do
    metadata
    |> Map.update(:created_at, nil, &DateTime.to_iso8601/1)
  end

  @doc """
  Builds a plan tree from a serialized map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{tree: tree_map, metadata: meta_map}) do
    tree = RoseTree.from_map(tree_map)

    metadata =
      meta_map
      |> Map.new(fn {k, v} -> {to_atom(k), v} end)
      |> Map.update(:created_at, nil, fn
        nil -> nil
        dt when is_binary(dt) -> DateTime.from_iso8601(dt) |> elem(1)
        dt -> dt
      end)
      |> Map.update(:status, :pending, &to_atom/1)

    {:ok, %__MODULE__{tree: tree, metadata: metadata}}
  end

  def from_map(%{"tree" => tree_map, "metadata" => meta_map}) do
    from_map(%{tree: tree_map, metadata: meta_map})
  end

  defp to_atom(atom) when is_atom(atom), do: atom
  defp to_atom(string) when is_binary(string), do: String.to_existing_atom(string)
end
