defmodule Thunderline.Thunderchief.Chiefs.PlanChief do
  @moduledoc """
  Reference Chief implementation with full PlanTree support.

  This Chief demonstrates the complete integration of plan tree capabilities
  with the Chief behaviour. Use as a template for Chiefs that need hierarchical
  planning.

  ## Features

  - Full `ChiefBehaviour` implementation with plan support
  - Node expansion for hierarchical decomposition
  - Step execution for leaf nodes
  - Priority estimation for scheduling

  ## Example

      # Create a plan and execute via DomainProcessor
      {:ok, plan} = PlanTree.new("sync_plan", goal: "sync all data", domain: :plan)

      # Expand root into steps
      {:ok, plan} = PlanTree.expand(plan, "sync_plan", [
        {"fetch", %{action: :fetch_data, domain: :plan}},
        {"transform", %{action: :transform, domain: :plan}}
      ])

      # Enqueue ready nodes
      DomainProcessor.enqueue_ready_nodes(plan)
  """

  use Thunderline.Thunderchief.ChiefBehaviour

  require Logger

  @action_space [:plan_start, :expand_node, :execute_step, :rollback, :wait]

  @capabilities [
    %{action: :fetch_data, domain: :plan, description: "Fetch data from source"},
    %{action: :transform, domain: :plan, description: "Transform data"},
    %{action: :validate, domain: :plan, description: "Validate data integrity"},
    %{action: :persist, domain: :plan, description: "Persist to storage"},
    %{action: :notify, domain: :plan, description: "Send notification"}
  ]

  # ============================================================================
  # Core Chief Callbacks
  # ============================================================================

  @impl true
  def observe_state(context) do
    # Build observation state from context
    state = %{
      features: extract_features(context),
      context: context,
      timestamp: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def choose_action(observed_state) do
    # Simple heuristic-based action selection
    features = observed_state.features

    action =
      cond do
        features[:has_pending_plan] -> :expand_node
        features[:has_ready_nodes] -> :execute_step
        features[:has_failed_nodes] -> :rollback
        true -> :wait
      end

    {:ok, action}
  end

  @impl true
  def apply_action(action, context) do
    Logger.debug("[PlanChief] Applying action: #{inspect(action)}")

    case action do
      :plan_start ->
        {:ok, %{started: true, timestamp: DateTime.utc_now()}}

      :expand_node ->
        {:ok, %{expanded: true}}

      :execute_step ->
        {:ok, %{executed: true}}

      :rollback ->
        {:ok, %{rolled_back: true}}

      :wait ->
        {:ok, %{waited: true}}

      {action_atom, params} ->
        apply_action_with_params(action_atom, params, context)

      _ ->
        {:error, {:unknown_action, action}}
    end
  end

  @impl true
  def report_outcome(result) do
    reward = calculate_reward(result)

    :telemetry.execute(
      [:thunderline, :thunderchief, :plan_chief, :outcome],
      %{reward: reward},
      %{result: result}
    )

    %{
      reward: reward,
      metrics: %{
        action_taken: Map.get(result, :action, :unknown),
        success: Map.get(result, :success, true)
      },
      trajectory_step: %{
        reward: reward,
        done: Map.get(result, :done, false)
      }
    }
  end

  # ============================================================================
  # Plan Capability Callbacks
  # ============================================================================

  @impl true
  def action_space, do: @action_space

  @impl true
  def plan_capabilities, do: @capabilities

  @impl true
  def expand_node(node_id, node_value, _context) do
    Logger.debug("[PlanChief] Expanding node: #{node_id}")

    case node_value[:action] do
      :fetch_data ->
        # Decompose fetch into pagination steps
        {:ok,
         [
           {generate_id("fetch_page"), %{action: :fetch_page, params: %{page: 1}, kind: :leaf}},
           {generate_id("fetch_page"), %{action: :fetch_page, params: %{page: 2}, kind: :leaf}}
         ]}

      :transform ->
        # Decompose transform into parallel steps
        {:ok,
         [
           {generate_id("validate"), %{action: :validate, kind: :leaf}},
           {generate_id("normalize"), %{action: :normalize, kind: :leaf}},
           {generate_id("enrich"), %{action: :enrich, kind: :leaf}}
         ]}

      :persist ->
        # Single step, no expansion needed
        {:skip, :atomic_action}

      _ ->
        # Default: no expansion
        {:skip, :not_expandable}
    end
  end

  @impl true
  def perform_step(node_id, node_value, _context) do
    Logger.debug("[PlanChief] Performing step: #{node_id} -> #{inspect(node_value[:action])}")

    action = node_value[:action]
    params = node_value[:params] || %{}

    # Simulate step execution
    result =
      case action do
        :fetch_page ->
          # Simulate fetching a page of data
          Process.sleep(10)
          {:ok, %{status: :succeeded, output: %{records: 100, page: params[:page]}}}

        :validate ->
          {:ok, %{status: :succeeded, output: %{valid: true}}}

        :normalize ->
          {:ok, %{status: :succeeded, output: %{normalized: true}}}

        :enrich ->
          {:ok, %{status: :succeeded, output: %{enriched: true}}}

        :persist ->
          {:ok, %{status: :succeeded, output: %{persisted: true}}}

        :notify ->
          {:ok, %{status: :succeeded, output: %{notified: true}}}

        :fetch_data ->
          {:ok, %{status: :succeeded, output: %{fetched: true}}}

        :transform ->
          {:ok, %{status: :succeeded, output: %{transformed: true}}}

        _ ->
          Logger.warning("[PlanChief] Unknown step action: #{inspect(action)}")
          {:ok, %{status: :skipped, metadata: %{reason: :unknown_action}}}
      end

    result
  rescue
    e ->
      {:ok, %{status: :failed, error: Exception.message(e)}}
  end

  @impl true
  def estimate_priority(node_value) do
    # Higher priority for certain actions
    case node_value[:action] do
      :persist -> 0.9
      :notify -> 0.3
      :validate -> 0.7
      _ -> 0.5
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp extract_features(context) do
    %{
      has_pending_plan: Map.get(context, :pending_plan, false),
      has_ready_nodes: Map.get(context, :ready_nodes, 0) > 0,
      has_failed_nodes: Map.get(context, :failed_nodes, 0) > 0,
      tick: Map.get(context, :tick, 0)
    }
  end

  defp apply_action_with_params(action, params, _context) do
    {:ok, %{action: action, params: params, executed: true}}
  end

  defp calculate_reward(result) do
    cond do
      Map.get(result, :error) -> -1.0
      Map.get(result, :rolled_back) -> -0.5
      Map.get(result, :waited) -> 0.0
      Map.get(result, :executed) -> 1.0
      Map.get(result, :expanded) -> 0.5
      true -> 0.0
    end
  end

  defp generate_id(prefix) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_#{suffix}"
  end
end
