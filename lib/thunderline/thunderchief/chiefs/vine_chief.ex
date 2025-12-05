defmodule Thunderline.Thunderchief.Chiefs.VineChief do
  @moduledoc """
  Thundervine (DAG) Domain Orchestrator (Puppeteer).

  The VineChief observes the Thundervine workflow domain and decides
  when to advance graph execution, which nodes to prioritize, and
  when to compact completed workflows.

  ## Responsibilities

  - Monitor active workflows (graphs) and their execution state
  - Decide node scheduling order within ready-to-execute sets
  - Detect stalled workflows and trigger recovery
  - Compact completed workflows for memory efficiency
  - Log trajectory data for Cerebros policy learning

  ## Action Space

  - `{:advance_node, node_id}` - Execute a specific ready node
  - `{:advance_batch, node_ids}` - Execute multiple ready nodes
  - `{:recover_stalled, graph_id}` - Retry stalled workflow
  - `{:compact_graph, graph_id}` - Archive completed workflow
  - `:checkpoint` - Save execution state
  - `:wait` - No action, wait for events

  ## Example

      state = VineChief.observe_state(registry)
      {:ok, action} = VineChief.choose_action(state)
      {:ok, updated} = VineChief.apply_action(action, registry)
  """

  @behaviour Thunderline.Thunderchief.Behaviour

  require Logger

  alias Thunderline.Thunderchief.{State, Action}

  @max_parallel_nodes 10
  @stall_threshold_ms 30_000
  @compact_after_ms 60_000

  # ===========================================================================
  # Behaviour Implementation
  # ===========================================================================

  @impl true
  def observe_state(registry) do
    graphs = get_active_graphs(registry)

    # Collect metrics across all active workflows
    {ready_nodes, executing_nodes, completed_nodes, stalled_nodes} =
      analyze_graphs(graphs)

    total_nodes = length(ready_nodes) + length(executing_nodes) + length(completed_nodes)
    completion_rate = if total_nodes > 0, do: length(completed_nodes) / total_nodes, else: 0.0

    State.new(
      :vine,
      %{
        # Graph counts
        active_graphs: length(graphs),
        completed_graphs: count_completed(graphs),

        # Node states across all graphs
        ready_nodes: ready_nodes,
        ready_count: length(ready_nodes),
        executing_count: length(executing_nodes),
        completed_count: length(completed_nodes),
        stalled_count: length(stalled_nodes),

        # Health metrics
        stalled_nodes: stalled_nodes,
        has_stalled: length(stalled_nodes) > 0,
        completion_rate: completion_rate,

        # Compaction candidates
        compactable: find_compactable(graphs),

        # Parallelism
        parallel_capacity: max(0, @max_parallel_nodes - length(executing_nodes))
      },
      tick: get_tick(registry),
      context: registry
    )
  end

  @impl true
  def choose_action(%State{features: state}) do
    cond do
      # Priority 1: Recover stalled workflows
      state.has_stalled ->
        [first_stalled | _] = state.stalled_nodes
        {:ok, {:recover_stalled, first_stalled.graph_id}}

      # Priority 2: Advance ready nodes if capacity available
      state.ready_count > 0 and state.parallel_capacity > 0 ->
        nodes_to_advance = select_nodes(state.ready_nodes, state.parallel_capacity)

        case nodes_to_advance do
          [single] -> {:ok, {:advance_node, single.id}}
          multiple -> {:ok, {:advance_batch, Enum.map(multiple, & &1.id)}}
        end

      # Priority 3: Compact finished workflows
      length(state.compactable) > 0 ->
        [graph | _] = state.compactable
        {:ok, {:compact_graph, graph.id}}

      # Priority 4: Checkpoint if many completions
      state.completed_count > 50 ->
        {:ok, :checkpoint}

      # No action needed
      true ->
        {:wait, 100}
    end
  end

  @impl true
  def apply_action(action, registry) do
    action_struct = Action.from_tuple(action)
    action_struct = Action.mark_executing(action_struct)

    result = do_apply_action(action, registry)

    case result do
      {:ok, updated} ->
        Action.log(Action.mark_completed(action_struct), :executed, %{})
        {:ok, updated}

      {:error, reason} = error ->
        Action.log(Action.mark_failed(action_struct, reason), :failed, %{})
        error
    end
  end

  @impl true
  def report_outcome(registry) do
    state = observe_state(registry)

    %{
      reward: calculate_reward(state),
      metrics: %{
        active_graphs: state.features.active_graphs,
        ready_nodes: state.features.ready_count,
        executing: state.features.executing_count,
        completed: state.features.completed_count,
        stalled: state.features.stalled_count,
        completion_rate: state.features.completion_rate
      },
      trajectory_step: %{
        state: state.features,
        # filled by caller
        action: nil,
        next_state: state.features,
        timestamp: DateTime.utc_now()
      }
    }
  end

  @impl true
  def action_space do
    [
      :checkpoint,
      :wait,
      {:advance_node, "node_id"},
      {:advance_batch, ["node_ids"]},
      {:recover_stalled, "graph_id"},
      {:compact_graph, "graph_id"}
    ]
  end

  # ===========================================================================
  # Action Execution
  # ===========================================================================

  defp do_apply_action({:advance_node, node_id}, registry) do
    # execute_node/2 always returns {:ok, _} (stub)
    {:ok, _result} = execute_node(registry, node_id)
    {:ok, registry}
  end

  defp do_apply_action({:advance_batch, node_ids}, registry) do
    # Execute multiple nodes in parallel
    results = Enum.map(node_ids, &execute_node(registry, &1))
    failures = Enum.filter(results, &match?({:error, _}, &1))

    if length(failures) > 0 do
      {:error, {:batch_partial_failure, length(failures)}}
    else
      {:ok, registry}
    end
  end

  defp do_apply_action({:recover_stalled, graph_id}, registry) do
    # Reset stalled nodes in a graph
    case reset_stalled_nodes(registry, graph_id) do
      :ok -> {:ok, registry}
      error -> error
    end
  end

  defp do_apply_action({:compact_graph, graph_id}, registry) do
    # Archive completed workflow
    case archive_graph(registry, graph_id) do
      :ok -> {:ok, registry}
      error -> error
    end
  end

  defp do_apply_action(:checkpoint, registry) do
    # Save current state - no-op for now
    {:ok, registry}
  end

  defp do_apply_action(_action, registry) do
    {:ok, registry}
  end

  # ===========================================================================
  # Node Selection
  # ===========================================================================

  defp select_nodes(ready_nodes, capacity) do
    ready_nodes
    |> sort_by_priority()
    |> Enum.take(capacity)
  end

  defp sort_by_priority(nodes) do
    Enum.sort_by(nodes, fn node ->
      # Priority: older nodes first, then by explicit priority
      age = DateTime.diff(DateTime.utc_now(), node.ready_at || DateTime.utc_now(), :millisecond)
      priority = Map.get(node, :priority, 0)
      {-priority, -age}
    end)
  end

  # ===========================================================================
  # Graph Analysis
  # ===========================================================================

  defp get_active_graphs(registry) do
    # Get active graphs from registry or return empty
    case registry do
      %{graphs: graphs} when is_map(graphs) ->
        graphs |> Map.values() |> Enum.filter(&(&1.status != :completed))

      _ ->
        []
    end
  end

  defp analyze_graphs(graphs) do
    Enum.reduce(graphs, {[], [], [], []}, fn graph, {ready, exec, done, stalled} ->
      nodes = Map.values(graph.nodes)

      new_ready = Enum.filter(nodes, &(&1.status == :ready))
      new_exec = Enum.filter(nodes, &(&1.status == :executing))
      new_done = Enum.filter(nodes, &(&1.status == :completed))
      new_stalled = detect_stalled(new_exec, graph.id)

      {ready ++ new_ready, exec ++ new_exec, done ++ new_done, stalled ++ new_stalled}
    end)
  end

  defp detect_stalled(executing_nodes, graph_id) do
    now = DateTime.utc_now()

    executing_nodes
    |> Enum.filter(fn node ->
      case node[:started_at] do
        nil ->
          false

        started ->
          age_ms = DateTime.diff(now, started, :millisecond)
          age_ms > @stall_threshold_ms
      end
    end)
    |> Enum.map(&Map.put(&1, :graph_id, graph_id))
  end

  defp count_completed(graphs) do
    Enum.count(graphs, &(&1.status == :completed))
  end

  defp find_compactable(graphs) do
    now = DateTime.utc_now()

    graphs
    |> Enum.filter(fn graph ->
      graph.status == :completed and
        DateTime.diff(now, graph[:completed_at] || now, :millisecond) > @compact_after_ms
    end)
  end

  defp get_tick(registry) do
    case registry do
      %{metadata: %{tick: tick}} -> tick
      _ -> 0
    end
  end

  # ===========================================================================
  # Execution Stubs
  # ===========================================================================

  defp execute_node(_registry, _node_id) do
    # Delegate to Thundervine.Executor
    # For now, stub success
    {:ok, :executed}
  end

  defp reset_stalled_nodes(_registry, _graph_id) do
    # Reset stalled nodes to ready state
    :ok
  end

  defp archive_graph(_registry, _graph_id) do
    # Archive to Thundervine.WorkflowCompactor
    :ok
  end

  # ===========================================================================
  # Reward Calculation
  # ===========================================================================

  defp calculate_reward(state) do
    # Reward: high completion rate, low stalls, throughput
    completion_bonus = state.features.completion_rate * 10
    stall_penalty = state.features.stalled_count * 5
    throughput = state.features.completed_count * 0.1

    completion_bonus + throughput - stall_penalty
  end
end
