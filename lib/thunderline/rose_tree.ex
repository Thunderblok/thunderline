defmodule Thunderline.RoseTree do
  @moduledoc """
  Rose Tree utilities for Thunderline.

  A rose tree is a tree where each node can have 0..N children (multi-branching).
  This module wraps `ex_rose_tree` and provides Thunderline-specific operations.

  ## Usage

      # Create a tree
      tree = RoseTree.new(:root, %{goal: "process data"})

      # Add children
      tree = RoseTree.add_child(tree, :child1, %{action: :fetch})
      tree = RoseTree.add_child(tree, :child2, %{action: :transform})

      # Fold over tree
      total = RoseTree.fold(tree, 0, fn node, acc -> acc + node.value.count end)

      # Map over tree
      updated = RoseTree.map(tree, fn node -> %{node | visited: true} end)

  ## Structure

  Each node contains:
  - `id` - unique identifier
  - `value` - arbitrary payload
  - `children` - list of child nodes (rose trees)
  """

  alias ExRoseTree, as: RT

  @type node_id :: binary() | atom()
  @type value :: term()
  @type t :: RT.t()

  @doc """
  Creates a new rose tree with a single root node.

  ## Parameters

  - `id` - Unique identifier for the root node
  - `value` - Payload for the root node

  ## Examples

      iex> RoseTree.new(:root, %{name: "plan"})
      %ExRoseTree{term: %{id: :root, value: %{name: "plan"}}, children: []}
  """
  @spec new(node_id(), value()) :: t()
  def new(id, value) do
    RT.new(%{id: id, value: value})
  end

  @doc """
  Returns the root node's data.
  """
  @spec root(t()) :: %{id: node_id(), value: value()}
  def root(tree), do: RT.get_term(tree)

  @doc """
  Returns the children of the root node.
  """
  @spec children(t()) :: [t()]
  def children(tree), do: RT.get_children(tree)

  @doc """
  Adds a child to the root of the tree.

  ## Parameters

  - `tree` - The parent tree
  - `id` - Unique identifier for the new child
  - `value` - Payload for the new child

  ## Returns

  Updated tree with the new child appended.
  """
  @spec add_child(t(), node_id(), value()) :: t()
  def add_child(tree, id, value) do
    child = new(id, value)
    add_subtree(tree, child)
  end

  @doc """
  Adds a subtree as a child of the root.
  """
  @spec add_subtree(t(), t()) :: t()
  def add_subtree(tree, subtree) do
    RT.set_children(tree, RT.get_children(tree) ++ [subtree])
  end

  @doc """
  Inserts a child under a specific node by id.

  Searches the tree for a node matching `parent_id` and adds the child there.

  ## Returns

  `{:ok, updated_tree}` if parent found, `{:error, :not_found}` otherwise.
  """
  @spec insert_child(t(), node_id(), node_id(), value()) :: {:ok, t()} | {:error, :not_found}
  def insert_child(tree, parent_id, child_id, child_value) do
    case find_and_update(tree, parent_id, fn parent_tree ->
           add_child(parent_tree, child_id, child_value)
         end) do
      {:ok, updated} -> {:ok, updated}
      :not_found -> {:error, :not_found}
    end
  end

  @doc """
  Finds a node by id and applies an update function.

  ## Returns

  `{:ok, updated_tree}` if found, `:not_found` otherwise.
  """
  @spec find_and_update(t(), node_id(), (t() -> t())) :: {:ok, t()} | :not_found
  def find_and_update(tree, target_id, update_fn) do
    node = root(tree)

    if node.id == target_id do
      {:ok, update_fn.(tree)}
    else
      case update_children(children(tree), target_id, update_fn) do
        {:ok, updated_children} ->
          {:ok, RT.set_children(tree, updated_children)}

        :not_found ->
          :not_found
      end
    end
  end

  defp update_children([], _target_id, _update_fn), do: :not_found

  defp update_children([child | rest], target_id, update_fn) do
    case find_and_update(child, target_id, update_fn) do
      {:ok, updated_child} ->
        {:ok, [updated_child | rest]}

      :not_found ->
        case update_children(rest, target_id, update_fn) do
          {:ok, updated_rest} -> {:ok, [child | updated_rest]}
          :not_found -> :not_found
        end
    end
  end

  @doc """
  Finds a node by id.

  ## Returns

  `{:ok, subtree}` where subtree is rooted at the matching node,
  or `{:error, :not_found}`.
  """
  @spec find(t(), node_id()) :: {:ok, t()} | {:error, :not_found}
  def find(tree, target_id) do
    node = root(tree)

    if node.id == target_id do
      {:ok, tree}
    else
      Enum.find_value(children(tree), {:error, :not_found}, fn child ->
        case find(child, target_id) do
          {:ok, _} = found -> found
          _ -> nil
        end
      end)
    end
  end

  @doc """
  Returns the path from root to a node with the given id.

  ## Returns

  List of node data from root to target (inclusive), or empty list if not found.
  """
  @spec path_to(t(), node_id()) :: [%{id: node_id(), value: value()}]
  def path_to(tree, target_id) do
    case do_path_to(tree, target_id, []) do
      {:found, path} -> Enum.reverse(path)
      :not_found -> []
    end
  end

  defp do_path_to(tree, target_id, acc) do
    node = root(tree)
    new_acc = [node | acc]

    if node.id == target_id do
      {:found, new_acc}
    else
      Enum.find_value(children(tree), :not_found, fn child ->
        case do_path_to(child, target_id, new_acc) do
          {:found, _} = found -> found
          :not_found -> nil
        end
      end)
    end
  end

  @doc """
  Maps a function over all nodes in the tree.

  The function receives the node data `%{id: id, value: value}` and should
  return the updated node data.

  ## Examples

      RoseTree.map(tree, fn node ->
        %{node | value: Map.put(node.value, :visited, true)}
      end)
  """
  @spec map(t(), (map() -> map())) :: t()
  def map(tree, fun) do
    node = root(tree)
    updated_node = fun.(node)
    updated_children = Enum.map(children(tree), &map(&1, fun))
    RT.new(updated_node, updated_children)
  end

  @doc """
  Folds over the tree, accumulating a result.

  Traverses depth-first, applying the function to each node.

  ## Parameters

  - `tree` - The tree to fold over
  - `acc` - Initial accumulator value
  - `fun` - Function `(node_data, acc) -> new_acc`

  ## Examples

      # Count nodes
      RoseTree.fold(tree, 0, fn _node, count -> count + 1 end)

      # Collect all ids
      RoseTree.fold(tree, [], fn node, ids -> [node.id | ids] end)
  """
  @spec fold(t(), acc, (map(), acc -> acc)) :: acc when acc: term()
  def fold(tree, acc, fun) do
    node = root(tree)
    acc = fun.(node, acc)
    Enum.reduce(children(tree), acc, &fold(&1, &2, fun))
  end

  @doc """
  Prunes the tree, removing subtrees where the predicate returns false.

  The predicate receives node data and should return true to keep the subtree.

  ## Examples

      # Keep only nodes with status != :failed
      RoseTree.prune(tree, fn node -> node.value.status != :failed end)
  """
  @spec prune(t(), (map() -> boolean())) :: t() | nil
  def prune(tree, predicate) do
    node = root(tree)

    if predicate.(node) do
      pruned_children =
        children(tree)
        |> Enum.map(&prune(&1, predicate))
        |> Enum.reject(&is_nil/1)

      RT.new(node, pruned_children)
    else
      nil
    end
  end

  @doc """
  Returns all nodes as a flat list (depth-first order).
  """
  @spec to_list(t()) :: [%{id: node_id(), value: value()}]
  def to_list(tree) do
    fold(tree, [], fn node, acc -> [node | acc] end)
    |> Enum.reverse()
  end

  @doc """
  Returns leaf nodes (nodes with no children).
  """
  @spec leaves(t()) :: [%{id: node_id(), value: value()}]
  def leaves(tree) do
    fold(tree, [], fn node, acc ->
      case find(tree, node.id) do
        {:ok, subtree} ->
          if children(subtree) == [] do
            [node | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Counts total nodes in the tree.
  """
  @spec count(t()) :: non_neg_integer()
  def count(tree) do
    fold(tree, 0, fn _node, acc -> acc + 1 end)
  end

  @doc """
  Returns the depth of the tree.
  """
  @spec depth(t()) :: non_neg_integer()
  def depth(tree) do
    case children(tree) do
      [] -> 1
      kids -> 1 + (kids |> Enum.map(&depth/1) |> Enum.max())
    end
  end

  @doc """
  Updates the value of a specific node by id.
  """
  @spec update_value(t(), node_id(), (value() -> value())) :: {:ok, t()} | {:error, :not_found}
  def update_value(tree, target_id, update_fn) do
    case find_and_update(tree, target_id, fn subtree ->
           node = root(subtree)
           updated_node = %{node | value: update_fn.(node.value)}
           RT.new(updated_node, children(subtree))
         end) do
      {:ok, _} = ok -> ok
      :not_found -> {:error, :not_found}
    end
  end

  @doc """
  Converts the tree to a nested map structure for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(tree) do
    node = root(tree)

    %{
      id: node.id,
      value: node.value,
      children: Enum.map(children(tree), &to_map/1)
    }
  end

  @doc """
  Builds a tree from a nested map structure.
  """
  @spec from_map(map()) :: t()
  def from_map(%{id: id, value: value, children: children}) do
    child_trees = Enum.map(children, &from_map/1)
    RT.new(%{id: id, value: value}, child_trees)
  end

  def from_map(%{"id" => id, "value" => value, "children" => children}) do
    from_map(%{id: id, value: value, children: children})
  end
end
