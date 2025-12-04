defmodule Thunderline.Thunderchief.Jobs.DomainProcessor do
  @moduledoc """
  Oban job for asynchronous per-domain Chief delegation.

  Guerrilla #32: Implements per-domain delegation where each job execution
  routes to the appropriate domain Chief (BitChief, VineChief, CrownChief, UIChief).

  ## Why Oban?

  While the Conductor handles synchronous tick-based orchestration, this worker
  enables:
  - Async domain processing for long-running operations
  - Retry semantics for transient failures
  - Job scheduling (e.g., nightly consolidation)
  - Per-domain queue isolation for backpressure control
  - Independent scaling per domain workload

  ## Usage

      # Enqueue a domain processing job
      %{domain: "bit", context: %{tick: 42}}
      |> Thunderline.Thunderchief.Jobs.DomainProcessor.new()
      |> Oban.insert()

      # With priority (for governance/critical domains)
      %{domain: "crown", context: %{urgent: true}}
      |> Thunderline.Thunderchief.Jobs.DomainProcessor.new(priority: 0)
      |> Oban.insert()

      # Scheduled execution
      %{domain: "vine", context: %{action: :consolidate}}
      |> Thunderline.Thunderchief.Jobs.DomainProcessor.new(scheduled_at: tomorrow())
      |> Oban.insert()

  ## PlanTree Integration

  When a `plan_node_id` is provided, the job executes a specific plan node:

      %{domain: "vine", plan_id: "plan_123", plan_node_id: "node_456", context: %{}}
      |> DomainProcessor.new()
      |> Oban.insert()

  The job will:
  1. Load the plan from the registry (or context)
  2. Mark the node as running
  3. Call `chief.perform_step/3` for leaf nodes
  4. Update node result and persist

  ## Job Args

  - `domain` (required) - Domain key: "bit", "vine", "crown", "ui"
  - `context` - Optional map merged into chief context
  - `action_override` - Force specific action (bypasses choose_action)
  - `skip_logging` - Disable trajectory logging (default: false)
  - `plan_id` - Plan tree ID for plan-based execution
  - `plan_node_id` - Specific node to execute within the plan
  - `plan_tree` - Serialized plan tree (for stateless execution)

  ## Telemetry

  - `[:thunderline, :thunderchief, :job, :start]` - Job started
  - `[:thunderline, :thunderchief, :job, :stop]` - Job completed
  - `[:thunderline, :thunderchief, :job, :error]` - Job failed
  - `[:thunderline, :thunderchief, :plan_node, :start]` - Plan node started
  - `[:thunderline, :thunderchief, :plan_node, :stop]` - Plan node completed
  """

  use Oban.Worker,
    queue: :domain_processor,
    max_attempts: 3,
    priority: 2

  require Logger

  alias Thunderline.Thunderchief.Logger, as: TrajectoryLogger
  alias Thunderline.Thunderchief.State
  alias Thunderline.Thunderchief.PlanTree
  alias Thunderline.Thunderchief.ChiefBehaviour

  alias Thunderline.Thunderchief.Chiefs.{
    BitChief,
    VineChief,
    CrownChief,
    UIChief,
    PlanChief
  }

  @domain_chiefs %{
    "bit" => BitChief,
    "vine" => VineChief,
    "crown" => CrownChief,
    "ui" => UIChief,
    "plan" => PlanChief
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, id: job_id}) do
    start_time = System.monotonic_time()

    domain = Map.fetch!(args, "domain")
    context = Map.get(args, "context", %{})
    action_override = Map.get(args, "action_override")
    skip_logging = Map.get(args, "skip_logging", false)

    # PlanTree execution path
    plan_node_id = Map.get(args, "plan_node_id")
    plan_tree_data = Map.get(args, "plan_tree")

    :telemetry.execute(
      [:thunderline, :thunderchief, :job, :start],
      %{system_time: System.system_time()},
      %{domain: domain, job_id: job_id, attempt: attempt, plan_node: plan_node_id}
    )

    case Map.get(@domain_chiefs, domain) do
      nil ->
        error = {:unknown_domain, domain}
        emit_error_telemetry(start_time, domain, job_id, error)
        {:error, error}

      chief_module ->
        # Route to plan-based or classic execution
        if plan_node_id && plan_tree_data do
          execute_plan_node(
            chief_module,
            domain,
            plan_node_id,
            plan_tree_data,
            context,
            job_id,
            start_time
          )
        else
          execute_chief(
            chief_module,
            domain,
            context,
            action_override,
            skip_logging,
            job_id,
            start_time
          )
        end
    end
  end

  # ---------------------------------------------------------------------------
  # PlanTree Node Execution
  # ---------------------------------------------------------------------------

  defp execute_plan_node(chief_module, domain, node_id, plan_tree_data, context, job_id, start_time) do
    :telemetry.execute(
      [:thunderline, :thunderchief, :plan_node, :start],
      %{system_time: System.system_time()},
      %{domain: domain, node_id: node_id, job_id: job_id}
    )

    with {:ok, plan} <- PlanTree.from_map(plan_tree_data),
         {:ok, {^node_id, node_value}} <- PlanTree.get_node(plan, node_id),
         {:ok, plan} <- PlanTree.mark_running(plan, node_id),
         chief_context <- build_chief_context(domain, context, job_id),
         {:ok, step_result} <- execute_step(chief_module, node_id, node_value, chief_context),
         {:ok, plan} <- PlanTree.apply_node_result(plan, node_id, step_result) do

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:thunderline, :thunderchief, :plan_node, :stop],
        %{duration: duration},
        %{domain: domain, node_id: node_id, job_id: job_id, status: step_result.status}
      )

      {:ok, %{
        domain: domain,
        node_id: node_id,
        status: step_result.status,
        plan_tree: PlanTree.to_map(plan),
        output: step_result[:output]
      }}
    else
      {:error, reason} = error ->
        emit_error_telemetry(start_time, domain, job_id, {:plan_node_error, node_id, reason})
        error
    end
  end

  defp execute_step(chief_module, node_id, node_value, context) do
    # Check if chief supports plan tree interface
    if ChiefBehaviour.supports_plans?(chief_module) do
      chief_module.perform_step(node_id, node_value, context)
    else
      # Fallback: use the node's action as an action_override
      action = Map.get(node_value, :action, :noop)

      case chief_module.apply_action(action, context) do
        {:ok, result} ->
          {:ok, %{status: :succeeded, output: result}}

        {:error, reason} ->
          {:ok, %{status: :failed, error: reason}}
      end
    end
  rescue
    e ->
      Logger.error("[DomainProcessor] perform_step failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:ok, %{status: :failed, error: Exception.message(e)}}
  end

  # ---------------------------------------------------------------------------
  # Chief Execution
  # ---------------------------------------------------------------------------

  defp execute_chief(chief_module, domain, context, action_override, skip_logging, job_id, start_time) do
    chief_context = build_chief_context(domain, context, job_id)

    with {:ok, state} <- observe(chief_module, chief_context),
         {:ok, action} <- choose_or_override(chief_module, state, action_override),
         {:ok, updated_context} <- apply_action(chief_module, action, state.context),
         outcome <- report(chief_module, updated_context) do

      # Log trajectory unless skipped
      unless skip_logging do
        log_trajectory(domain, state, action, updated_context, outcome)
      end

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:thunderline, :thunderchief, :job, :stop],
        %{duration: duration},
        %{domain: domain, job_id: job_id, action: action_to_string(action)}
      )

      {:ok, %{domain: domain, action: action, outcome: outcome}}
    else
      {:error, reason} = error ->
        emit_error_telemetry(start_time, domain, job_id, reason)
        error

      {:wait, _timeout} ->
        # Chief decided to wait, not an error
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:thunderline, :thunderchief, :job, :stop],
          %{duration: duration},
          %{domain: domain, job_id: job_id, action: "wait"}
        )

        {:ok, %{domain: domain, action: :wait}}

      {:defer, reason} ->
        # Chief deferred, may need to re-enqueue
        Logger.info("[DomainProcessor] Chief #{domain} deferred: #{inspect(reason)}")
        {:ok, %{domain: domain, action: :defer, reason: reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Chief Callbacks
  # ---------------------------------------------------------------------------

  defp observe(chief_module, context) do
    state = chief_module.observe_state(context)
    {:ok, state}
  rescue
    e ->
      Logger.error("[DomainProcessor] observe_state failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:error, {:observe_failed, e}}
  end

  defp choose_or_override(_module, _state, action) when not is_nil(action) do
    {:ok, deserialize_action(action)}
  end

  defp choose_or_override(chief_module, state, nil) do
    chief_module.choose_action(state)
  rescue
    e ->
      Logger.error("[DomainProcessor] choose_action failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:error, {:choose_failed, e}}
  end

  defp apply_action(chief_module, action, context) do
    chief_module.apply_action(action, context)
  rescue
    e ->
      Logger.error("[DomainProcessor] apply_action failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:error, {:apply_failed, e}}
  end

  defp report(chief_module, context) do
    chief_module.report_outcome(context)
  rescue
    _ -> %{reward: 0.0, metrics: %{}, trajectory_step: %{}}
  end

  # ---------------------------------------------------------------------------
  # Context Building
  # ---------------------------------------------------------------------------

  defp build_chief_context(domain, extra_context, job_id) do
    base = %{
      chief: String.to_existing_atom(domain),
      job_id: job_id,
      timestamp: DateTime.utc_now(),
      node: node(),
      async: true,
      # Default empty structures for Chiefs that expect them
      bits_by_id: %{},
      cells_by_id: %{},
      started_at: DateTime.utc_now(),
      metadata: %{tick: 0}
    }

    # Merge extra context, allowing overrides
    Map.merge(base, atomize_keys(extra_context))
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        {String.to_existing_atom(k), atomize_keys(v)}
      {k, v} ->
        {k, atomize_keys(v)}
    end)
  rescue
    ArgumentError -> map
  end

  defp atomize_keys(other), do: other

  # ---------------------------------------------------------------------------
  # Trajectory Logging
  # ---------------------------------------------------------------------------

  defp log_trajectory(domain, state, action, _updated_context, outcome) do
    step = %{
      state: State.to_features(state),
      action: action,
      reward: Map.get(outcome, :reward, 0.0),
      next_state: state.features,
      done: false,
      metadata: %{
        domain: domain,
        job: true
      }
    }

    TrajectoryLogger.log_step(String.to_existing_atom(domain), step)
  rescue
    _ -> :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp action_to_string(action) when is_atom(action), do: Atom.to_string(action)
  defp action_to_string({action, _params}) when is_atom(action), do: Atom.to_string(action)
  defp action_to_string(action), do: inspect(action)

  defp deserialize_action(action) when is_binary(action) do
    String.to_existing_atom(action)
  rescue
    ArgumentError -> action
  end

  defp deserialize_action(%{"action" => action, "params" => params}) do
    {String.to_existing_atom(action), atomize_keys(params)}
  rescue
    ArgumentError -> action
  end

  defp deserialize_action(action), do: action

  defp emit_error_telemetry(start_time, domain, job_id, reason) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :thunderchief, :job, :error],
      %{duration: duration},
      %{domain: domain, job_id: job_id, reason: inspect(reason)}
    )

    Logger.error("[DomainProcessor] domain=#{domain} job=#{job_id} error=#{inspect(reason)}")
  end

  # ---------------------------------------------------------------------------
  # Convenience Functions
  # ---------------------------------------------------------------------------

  @doc """
  Enqueues a domain processing job for the given domain.

  ## Examples

      DomainProcessor.enqueue("bit")
      DomainProcessor.enqueue("crown", %{urgent: true}, priority: 0)
  """
  @spec enqueue(String.t(), map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(domain, context \\ %{}, opts \\ []) do
    %{domain: domain, context: context}
    |> new(opts)
    |> Oban.insert()
  end

  @doc """
  Enqueues jobs for all registered domains.

  Useful for scheduled full-system orchestration.
  """
  @spec enqueue_all(map(), keyword()) :: [{:ok, Oban.Job.t()} | {:error, term()}]
  def enqueue_all(context \\ %{}, opts \\ []) do
    Map.keys(@domain_chiefs)
    |> Enum.map(&enqueue(&1, context, opts))
  end

  @doc """
  Returns the list of registered domain keys.
  """
  @spec domains() :: [String.t()]
  def domains, do: Map.keys(@domain_chiefs)

  @doc """
  Returns the Chief module for a domain.
  """
  @spec chief_for(String.t()) :: module() | nil
  def chief_for(domain), do: Map.get(@domain_chiefs, domain)

  # ---------------------------------------------------------------------------
  # PlanTree Convenience Functions
  # ---------------------------------------------------------------------------

  @doc """
  Enqueues a job to execute a specific plan node.

  ## Parameters

  - `plan` - The PlanTree struct
  - `node_id` - ID of the node to execute
  - `opts` - Options including:
    - `:priority` - Job priority (default 2)
    - `:scheduled_at` - Scheduled execution time
    - `:context` - Additional context to merge

  ## Examples

      DomainProcessor.enqueue_plan_node(plan, "node_123")
      DomainProcessor.enqueue_plan_node(plan, "node_123", priority: 0)
  """
  @spec enqueue_plan_node(PlanTree.t(), binary(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_plan_node(plan, node_id, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    oban_opts = Keyword.drop(opts, [:context])

    with {:ok, {^node_id, node_value}} <- PlanTree.get_node(plan, node_id) do
      domain = node_value[:domain] || plan.metadata[:domain] || "bit"
      domain_string = if is_atom(domain), do: Atom.to_string(domain), else: domain

      %{
        domain: domain_string,
        plan_node_id: node_id,
        plan_tree: PlanTree.to_map(plan),
        context: context
      }
      |> new(oban_opts)
      |> Oban.insert()
    end
  end

  @doc """
  Enqueues jobs for all ready nodes in a plan tree.

  Returns list of `{node_id, job_result}` tuples.
  """
  @spec enqueue_ready_nodes(PlanTree.t(), keyword()) ::
          [{binary(), {:ok, Oban.Job.t()} | {:error, term()}}]
  def enqueue_ready_nodes(plan, opts \\ []) do
    plan
    |> PlanTree.schedule_ready_nodes()
    |> Enum.map(fn {node_id, _node_value} ->
      {node_id, enqueue_plan_node(plan, node_id, opts)}
    end)
  end
end
