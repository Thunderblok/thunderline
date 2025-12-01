defmodule Thunderline.Thundervine.Executor do
  @moduledoc """
  DAG execution engine with parallel traversal.

  The Executor walks a behavior DAG (Graph), executing nodes in topological
  order while maximizing parallelism for independent branches.

  ## Execution Model

  1. **Entry nodes** execute first (no predecessors)
  2. **Parallel branches** run concurrently via Task.async_stream
  3. **Join points** wait for all predecessors to complete
  4. **Exit nodes** signal graph completion

  ## Usage

      graph = Graph.new("workflow")
               |> Graph.add_node(node_a)
               |> Graph.add_node(node_b)
               |> Graph.connect("a", "b")

      {:ok, result} = Executor.run(graph, %{input: "data"})

  ## Handlers

  Node execution is dispatched to handlers based on node type:

  - `:thunderpac` -> `handle_thunderpac/3`
  - `:ml_model` -> `handle_ml_model/3`
  - `:action` -> `handle_action/3`
  - `:subgraph` -> recursive `run/3`

  Custom handlers can be provided via options.
  """

  alias Thunderline.Thundervine.{Graph, Node}

  require Logger

  @type context :: map()
  @type result :: {:ok, context()} | {:error, term()}

  @type execution_opts :: [
          timeout: pos_integer(),
          max_concurrency: pos_integer(),
          handlers: map(),
          on_node_start: (Node.t(), context() -> :ok),
          on_node_complete: (Node.t(), result(), context() -> :ok)
        ]

  @default_opts [
    timeout: 60_000,
    max_concurrency: System.schedulers_online() * 2
  ]

  @doc """
  Executes a behavior DAG with the given initial context.

  Returns `{:ok, final_context}` on success or `{:error, reason}` on failure.

  ## Options

  - `:timeout` - Overall execution timeout (default: 60_000ms)
  - `:max_concurrency` - Max parallel node executions (default: 2 * schedulers)
  - `:handlers` - Custom handler map by node type
  - `:on_node_start` - Callback before node execution
  - `:on_node_complete` - Callback after node execution

  ## Examples

      {:ok, ctx} = Executor.run(graph, %{user_id: 123})
  """
  @spec run(Graph.t(), context(), execution_opts()) :: result()
  def run(%Graph{} = graph, initial_context \\ %{}, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    with :ok <- validate_for_execution(graph) do
      execution_order = Graph.topological_sort(graph)
      execute_ordered(graph, execution_order, initial_context, opts)
    end
  end

  @doc """
  Executes a single node with retry support.
  """
  @spec execute_node(Node.t(), context(), execution_opts()) :: result()
  def execute_node(%Node{} = node, context, opts \\ []) do
    handlers = opts[:handlers] || %{}

    with_retry(node, fn ->
      dispatch_node(node, context, handlers)
    end)
  end

  # Execution pipeline

  defp validate_for_execution(graph) do
    case Graph.validate(graph) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  defp execute_ordered(graph, execution_order, context, opts) do
    # Group nodes by "level" - nodes that can run in parallel
    levels = group_by_level(graph, execution_order)

    Enum.reduce_while(levels, {:ok, context}, fn level_nodes, {:ok, ctx} ->
      case execute_level(graph, level_nodes, ctx, opts) do
        {:ok, new_ctx} -> {:cont, {:ok, new_ctx}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp group_by_level(graph, execution_order) do
    # Calculate depth of each node
    depths =
      Enum.reduce(execution_order, %{}, fn node_id, acc ->
        preds = Graph.predecessors(graph, node_id)

        depth =
          case preds do
            [] -> 0
            _ -> Enum.max(Enum.map(preds, &Map.get(acc, &1, 0))) + 1
          end

        Map.put(acc, node_id, depth)
      end)

    # Group by depth
    execution_order
    |> Enum.group_by(&Map.get(depths, &1))
    |> Enum.sort_by(fn {depth, _} -> depth end)
    |> Enum.map(fn {_depth, nodes} -> nodes end)
  end

  defp execute_level(graph, node_ids, context, opts) do
    nodes = Enum.map(node_ids, &Graph.get_node(graph, &1))
    max_concurrency = opts[:max_concurrency]
    timeout = opts[:timeout]

    # Fire start callbacks
    Enum.each(nodes, fn node ->
      if opts[:on_node_start], do: opts[:on_node_start].(node, context)
    end)

    # Execute nodes in parallel
    results =
      nodes
      |> Task.async_stream(
        fn node -> {node, execute_node(node, context, opts)} end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Process results
    process_level_results(results, context, opts)
  end

  defp process_level_results(results, context, opts) do
    Enum.reduce_while(results, {:ok, context}, fn
      {:ok, {node, {:ok, node_result}}}, {:ok, ctx} ->
        # Fire complete callback
        if opts[:on_node_complete], do: opts[:on_node_complete].(node, {:ok, node_result}, ctx)

        # Merge node result into context
        new_ctx = merge_result(ctx, node, node_result)
        {:cont, {:ok, new_ctx}}

      {:ok, {node, {:error, reason}}}, {:ok, ctx} ->
        if opts[:on_node_complete], do: opts[:on_node_complete].(node, {:error, reason}, ctx)

        Logger.error("Node #{node.id} failed: #{inspect(reason)}")
        {:halt, {:error, {:node_failed, node.id, reason}}}

      {:exit, :timeout}, {:ok, _ctx} ->
        {:halt, {:error, :execution_timeout}}

      {:exit, reason}, {:ok, _ctx} ->
        {:halt, {:error, {:execution_crashed, reason}}}
    end)
  end

  defp merge_result(context, node, result) when is_map(result) do
    # Store result under node ID
    put_in(context, [Access.key(:node_results, %{}), node.id], result)
  end

  defp merge_result(context, node, result) do
    put_in(context, [Access.key(:node_results, %{}), node.id], result)
  end

  # Retry logic

  defp with_retry(%Node{retry_policy: :no_retry} = _node, fun) do
    fun.()
  end

  defp with_retry(%Node{retry_policy: {:max_attempts, max}} = node, fun) do
    with_retry_loop(fun, max, 1, node)
  end

  defp with_retry_loop(fun, max_attempts, attempt, node) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, reason} when attempt < max_attempts ->
        Logger.warning(
          "Node #{node.id} attempt #{attempt} failed: #{inspect(reason)}, retrying..."
        )

        # Exponential backoff with jitter
        delay = backoff_delay(attempt)
        Process.sleep(delay)
        with_retry_loop(fun, max_attempts, attempt + 1, node)

      {:error, _} = error ->
        error
    end
  end

  defp backoff_delay(attempt) do
    base = :math.pow(2, attempt) * 100
    jitter = :rand.uniform(100)
    trunc(base + jitter)
  end

  # Node dispatch

  defp dispatch_node(%Node{type: :thunderpac} = node, context, handlers) do
    handler = handlers[:thunderpac] || (&handle_thunderpac/2)
    handler.(node, context)
  end

  defp dispatch_node(%Node{type: :ml_model} = node, context, handlers) do
    handler = handlers[:ml_model] || (&handle_ml_model/2)
    handler.(node, context)
  end

  defp dispatch_node(%Node{type: :action} = node, context, handlers) do
    handler = handlers[:action] || (&handle_action/2)
    handler.(node, context)
  end

  defp dispatch_node(%Node{type: :subgraph} = node, context, handlers) do
    handler = handlers[:subgraph] || (&handle_subgraph/2)
    handler.(node, context)
  end

  # Default handlers

  @doc false
  def handle_thunderpac(%Node{config: config} = _node, context) do
    # Default: look for FSM module in config
    fsm_module = config[:fsm]

    cond do
      is_nil(fsm_module) ->
        {:error, :no_fsm_configured}

      Code.ensure_loaded?(fsm_module) and function_exported?(fsm_module, :handle, 2) ->
        fsm_module.handle(context[:input], context)

      true ->
        {:error, {:fsm_not_found, fsm_module}}
    end
  end

  @doc false
  def handle_ml_model(%Node{config: config} = _node, context) do
    model_id = config[:model]

    # Placeholder: integrate with Thunderbolt ML infrastructure
    Logger.debug("ML model execution: #{model_id}")
    {:ok, %{model: model_id, prediction: :placeholder, input: context[:input]}}
  end

  @doc false
  def handle_action(%Node{config: config} = _node, context) do
    handler = config[:handler]
    args = config[:args] || []

    cond do
      is_nil(handler) ->
        {:error, :no_handler_configured}

      Code.ensure_loaded?(handler) and function_exported?(handler, :execute, 2) ->
        handler.execute(context, args)

      Code.ensure_loaded?(handler) and function_exported?(handler, :run, 2) ->
        handler.run(context, args)

      true ->
        {:error, {:handler_not_found, handler}}
    end
  end

  @doc false
  def handle_subgraph(%Node{config: config} = _node, context) do
    subgraph = config[:graph]

    case subgraph do
      %Graph{} = g -> run(g, context)
      nil -> {:error, :no_subgraph_configured}
      _ -> {:error, :invalid_subgraph}
    end
  end
end
