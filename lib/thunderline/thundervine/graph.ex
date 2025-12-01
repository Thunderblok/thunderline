defmodule Thunderline.Thundervine.Graph do
  @moduledoc """
  Behavior DAG representing complex workflows as composable graphs.

  Each node wraps a task (Thunderpac FSM, ML model, or custom action).
  Edges encode data/control dependencies between nodes.

  ## Structure

  A Graph consists of:
  - **Nodes**: Task wrappers (`Thunderline.Thundervine.Node`)
  - **Edges**: Dependencies between nodes with metadata
  - **Entry nodes**: Nodes with no incoming edges (execution starts here)
  - **Exit nodes**: Nodes with no outgoing edges (execution ends here)

  ## Building Graphs

      graph = Graph.new("my_workflow")
      |> Graph.add_node(Node.new("detect", :ml_model, %{model: "classifier"}))
      |> Graph.add_node(Node.new("decide", :thunderpac, %{fsm: MyFSM}))
      |> Graph.add_node(Node.new("act", :action, %{handler: MyHandler}))
      |> Graph.connect("detect", "decide")
      |> Graph.connect("decide", "act")

  ## Execution

  Graphs are executed by the `Thunderline.Thundervine.Executor`:

      {:ok, result} = Executor.run(graph, initial_context)

  ## Events

  - `vine.graph.started` - Graph execution initiated
  - `vine.graph.node.completed` - Node completed
  - `vine.graph.completed` - Full graph execution done
  """

  alias Thunderline.Thundervine.Node

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :description,
    nodes: %{},
    edges: [],
    entry_nodes: [],
    exit_nodes: [],
    metadata: %{}
  ]

  @type edge :: {from_id :: String.t(), to_id :: String.t(), metadata :: map()}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          nodes: %{String.t() => Node.t()},
          edges: [edge()],
          entry_nodes: [String.t()],
          exit_nodes: [String.t()],
          metadata: map()
        }

  @doc """
  Creates a new empty graph with the given name.

  ## Examples

      iex> graph = Graph.new("my_workflow")
      iex> graph.name
      "my_workflow"
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      id: opts[:id] || generate_id(),
      name: name,
      description: opts[:description],
      nodes: %{},
      edges: [],
      entry_nodes: [],
      exit_nodes: [],
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Adds a node to the graph.

  ## Examples

      graph = Graph.new("example")
      |> Graph.add_node(Node.new("step1", :action, %{}))
  """
  @spec add_node(t(), Node.t()) :: t()
  def add_node(%__MODULE__{} = graph, %Node{} = node) do
    if Map.has_key?(graph.nodes, node.id) do
      raise ArgumentError, "Node with id #{node.id} already exists in graph"
    end

    %{graph | nodes: Map.put(graph.nodes, node.id, node)}
    |> recompute_entry_exit_nodes()
  end

  @doc """
  Adds an edge connecting two nodes.

  ## Options

  - `:metadata` - Additional edge metadata (default: `%{}`)

  ## Examples

      graph = graph
      |> Graph.add_edge("source", "target")
      |> Graph.add_edge("source", "other", metadata: %{condition: :success})
  """
  @spec add_edge(t(), String.t(), String.t(), keyword()) :: t()
  def add_edge(%__MODULE__{} = graph, from_id, to_id, opts \\ []) do
    validate_node_exists!(graph, from_id)
    validate_node_exists!(graph, to_id)

    if has_edge?(graph, from_id, to_id) do
      raise ArgumentError, "Edge from #{from_id} to #{to_id} already exists"
    end

    metadata = opts[:metadata] || %{}
    edge = {from_id, to_id, metadata}

    %{graph | edges: [edge | graph.edges]}
    |> recompute_entry_exit_nodes()
  end

  @doc """
  Convenience function to add a node and connect it to an existing node.
  """
  @spec connect(t(), String.t(), String.t(), keyword()) :: t()
  def connect(%__MODULE__{} = graph, from_id, to_id, opts \\ []) do
    add_edge(graph, from_id, to_id, opts)
  end

  @doc """
  Gets a node by ID.
  """
  @spec get_node(t(), String.t()) :: Node.t() | nil
  def get_node(%__MODULE__{nodes: nodes}, node_id) do
    Map.get(nodes, node_id)
  end

  @doc """
  Gets a node by ID, raising if not found.
  """
  @spec get_node!(t(), String.t()) :: Node.t()
  def get_node!(%__MODULE__{} = graph, node_id) do
    case get_node(graph, node_id) do
      nil -> raise ArgumentError, "Node #{node_id} not found in graph #{graph.id}"
      node -> node
    end
  end

  @doc """
  Returns nodes that depend on the given node (successors).
  """
  @spec successors(t(), String.t()) :: [Node.t()]
  def successors(%__MODULE__{} = graph, node_id) do
    graph.edges
    |> Enum.filter(fn {from, _to, _meta} -> from == node_id end)
    |> Enum.map(fn {_from, to, _meta} -> get_node!(graph, to) end)
  end

  @doc """
  Returns nodes that the given node depends on (predecessors).
  """
  @spec predecessors(t(), String.t()) :: [Node.t()]
  def predecessors(%__MODULE__{} = graph, node_id) do
    graph.edges
    |> Enum.filter(fn {_from, to, _meta} -> to == node_id end)
    |> Enum.map(fn {from, _to, _meta} -> get_node!(graph, from) end)
  end

  @doc """
  Returns edges originating from the given node.
  """
  @spec outgoing_edges(t(), String.t()) :: [edge()]
  def outgoing_edges(%__MODULE__{edges: edges}, node_id) do
    Enum.filter(edges, fn {from, _to, _meta} -> from == node_id end)
  end

  @doc """
  Returns edges targeting the given node.
  """
  @spec incoming_edges(t(), String.t()) :: [edge()]
  def incoming_edges(%__MODULE__{edges: edges}, node_id) do
    Enum.filter(edges, fn {_from, to, _meta} -> to == node_id end)
  end

  @doc """
  Validates graph structure (no cycles, all edges valid, etc.).

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = graph) do
    with :ok <- validate_no_orphan_edges(graph),
         :ok <- validate_no_cycles(graph),
         :ok <- validate_has_entry_nodes(graph) do
      :ok
    end
  end

  @doc """
  Returns a topologically sorted list of node IDs.

  Raises if the graph contains cycles.
  """
  @spec topological_sort(t()) :: [String.t()]
  def topological_sort(%__MODULE__{} = graph) do
    case validate_no_cycles(graph) do
      :ok -> do_topological_sort(graph)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Returns the total number of nodes.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{nodes: nodes}), do: map_size(nodes)

  @doc """
  Returns the total number of edges.
  """
  @spec edge_count(t()) :: non_neg_integer()
  def edge_count(%__MODULE__{edges: edges}), do: length(edges)

  @doc """
  Checks if an edge exists between two nodes.
  """
  @spec has_edge?(t(), String.t(), String.t()) :: boolean()
  def has_edge?(%__MODULE__{edges: edges}, from_id, to_id) do
    Enum.any?(edges, fn {from, to, _meta} -> from == from_id and to == to_id end)
  end

  @doc """
  Serializes the graph to a map for persistence.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = graph) do
    %{
      id: graph.id,
      name: graph.name,
      description: graph.description,
      nodes: Map.new(graph.nodes, fn {id, node} -> {id, Node.to_map(node)} end),
      edges: Enum.map(graph.edges, fn {from, to, meta} -> %{from: from, to: to, metadata: meta} end),
      metadata: graph.metadata
    }
  end

  @doc """
  Deserializes a graph from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    nodes =
      Map.new(map.nodes || %{}, fn {id, node_map} ->
        {to_string(id), Node.from_map(node_map)}
      end)

    edges =
      Enum.map(map.edges || [], fn edge ->
        {to_string(edge.from), to_string(edge.to), edge.metadata || %{}}
      end)

    %__MODULE__{
      id: map.id,
      name: map.name,
      description: map[:description],
      nodes: nodes,
      edges: edges,
      entry_nodes: [],
      exit_nodes: [],
      metadata: map[:metadata] || %{}
    }
    |> recompute_entry_exit_nodes()
  end

  # Private helpers

  defp generate_id do
    "graph_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp validate_node_exists!(%__MODULE__{nodes: nodes}, node_id) do
    unless Map.has_key?(nodes, node_id) do
      raise ArgumentError, "Node #{node_id} does not exist in graph"
    end
  end

  defp recompute_entry_exit_nodes(%__MODULE__{} = graph) do
    all_node_ids = Map.keys(graph.nodes)

    # Entry nodes: have no incoming edges
    targets = MapSet.new(graph.edges, fn {_from, to, _meta} -> to end)
    entry_nodes = Enum.reject(all_node_ids, &MapSet.member?(targets, &1))

    # Exit nodes: have no outgoing edges
    sources = MapSet.new(graph.edges, fn {from, _to, _meta} -> from end)
    exit_nodes = Enum.reject(all_node_ids, &MapSet.member?(sources, &1))

    %{graph | entry_nodes: entry_nodes, exit_nodes: exit_nodes}
  end

  defp validate_no_orphan_edges(%__MODULE__{edges: edges, nodes: nodes}) do
    node_ids = Map.keys(nodes) |> MapSet.new()

    invalid_edges =
      Enum.filter(edges, fn {from, to, _meta} ->
        not MapSet.member?(node_ids, from) or not MapSet.member?(node_ids, to)
      end)

    if invalid_edges == [] do
      :ok
    else
      {:error, "Graph has edges referencing non-existent nodes: #{inspect(invalid_edges)}"}
    end
  end

  defp validate_no_cycles(%__MODULE__{} = graph) do
    # Kahn's algorithm for cycle detection
    in_degree = compute_in_degrees(graph)

    queue =
      in_degree
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _} -> id end)

    {processed, _} = process_queue(graph, queue, in_degree, 0)

    if processed == map_size(graph.nodes) do
      :ok
    else
      {:error, "Graph contains cycles"}
    end
  end

  defp validate_has_entry_nodes(%__MODULE__{entry_nodes: []}),
    do: {:error, "Graph has no entry nodes (all nodes have incoming edges)"}

  defp validate_has_entry_nodes(_graph), do: :ok

  defp compute_in_degrees(%__MODULE__{nodes: nodes, edges: edges}) do
    base = Map.new(nodes, fn {id, _} -> {id, 0} end)

    Enum.reduce(edges, base, fn {_from, to, _meta}, acc ->
      Map.update!(acc, to, &(&1 + 1))
    end)
  end

  defp process_queue(_graph, [], in_degree, processed), do: {processed, in_degree}

  defp process_queue(graph, [node_id | rest], in_degree, processed) do
    successors = successors(graph, node_id)

    updated_in_degree =
      Enum.reduce(successors, in_degree, fn successor, acc ->
        Map.update!(acc, successor.id, &(&1 - 1))
      end)

    new_zeros =
      successors
      |> Enum.filter(fn s -> Map.get(updated_in_degree, s.id) == 0 end)
      |> Enum.map(& &1.id)

    process_queue(graph, rest ++ new_zeros, updated_in_degree, processed + 1)
  end

  defp do_topological_sort(%__MODULE__{} = graph) do
    in_degree = compute_in_degrees(graph)

    queue =
      in_degree
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _} -> id end)
      |> Enum.sort()

    do_topological_sort_loop(graph, queue, in_degree, [])
  end

  defp do_topological_sort_loop(_graph, [], _in_degree, sorted), do: Enum.reverse(sorted)

  defp do_topological_sort_loop(graph, [node_id | rest], in_degree, sorted) do
    successors = successors(graph, node_id)

    updated_in_degree =
      Enum.reduce(successors, in_degree, fn successor, acc ->
        Map.update!(acc, successor.id, &(&1 - 1))
      end)

    new_zeros =
      successors
      |> Enum.filter(fn s -> Map.get(updated_in_degree, s.id) == 0 end)
      |> Enum.map(& &1.id)
      |> Enum.sort()

    do_topological_sort_loop(graph, rest ++ new_zeros, updated_in_degree, [node_id | sorted])
  end
end
