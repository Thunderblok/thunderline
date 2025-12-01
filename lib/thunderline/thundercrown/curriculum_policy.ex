defmodule Thunderline.Thundercrown.CurriculumPolicy do
  @moduledoc """
  Curriculum-Aware Policy Extension for ThunderCrown.

  Integrates Agent0-style curriculum rewards into the policy decision system.
  This module bridges the gap between:

  - **CurriculumRewards**: Computes R_unc, R_tool, R_rep for task generation
  - **Policy**: Makes allow/deny decisions with limits
  - **PAC Cerebros**: The executor agents that attempt tasks

  ## Curriculum-Aware Features

  1. **Adaptive Rate Limiting**: Tasks near the capability frontier get more generous limits
  2. **Tool Budget Allocation**: Higher tool budgets for high-reward tasks
  3. **Diversity Tracking**: Maintains task history for repetition penalty

  ## Usage

  ```elixir
  # Instead of plain Policy.decide/2:
  CurriculumPolicy.decide_with_curriculum(ctx, descriptor, curriculum_metrics)
  ```

  ## Reference

  Built on Agent0's curriculum learning loop (arXiv:2511.16043)
  """

  alias Thunderline.Thundergate.ActorContext
  alias Thunderline.Thundercrown.{Policy, CurriculumRewards}
  require Logger

  @type curriculum_metrics :: %{
          optional(:consistency_score) => float(),
          optional(:tool_calls) => non_neg_integer(),
          optional(:task_embedding) => list(float()),
          optional(:success_rate) => float()
        }

  @type curriculum_decision :: {
          :allow | :deny | :allow_with,
          map()
        }

  # Default limits for non-curriculum decisions
  @default_tool_budget 4
  @default_timeout_ms 30_000
  @default_retry_limit 3

  # Frontier boost factors
  @frontier_tool_boost 2.0
  @frontier_timeout_boost 1.5
  @frontier_retry_boost 2

  # History for repetition tracking (per-tenant)
  @history_table :thundercrown_curriculum_history

  # ═══════════════════════════════════════════════════════════════
  # INITIALIZATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Initialize the curriculum history ETS table.
  Call this in your supervision tree or application start.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@history_table) do
      :undefined ->
        :ets.new(@history_table, [:named_table, :public, :set])
        Logger.info("[CurriculumPolicy] Initialized history table")
        :ok

      _ ->
        :ok
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CURRICULUM-AWARE DECISIONS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Make a policy decision enhanced with curriculum reward signals.

  This wraps the standard Policy.decide/2 with:
  1. Curriculum reward computation
  2. Frontier-aware limit adjustment
  3. History tracking for repetition penalty

  ## Arguments

  - `ctx` - Actor context (tenant, actor_id, scopes)
  - `descriptor` - Action descriptor (domain, resource, action, scopes)
  - `metrics` - Curriculum metrics:
    - `:consistency_score` - Executor consistency from majority voting
    - `:tool_calls` - Number of tool invocations so far
    - `:task_embedding` - Vector representation for similarity
    - `:success_rate` - Historical success rate on similar tasks

  ## Returns

  Enhanced decision tuple with curriculum-adjusted limits:
  ```elixir
  {:allow_with, %{
    tool_budget: 8,      # Boosted for frontier tasks
    timeout_ms: 45000,   # Extended for complex tasks
    retry_limit: 6,      # More retries for learning
    curriculum_reward: 0.85,
    verdict_id: "abc123..."
  }}
  ```
  """
  @spec decide_with_curriculum(ActorContext.t(), map(), curriculum_metrics()) ::
          curriculum_decision()
  def decide_with_curriculum(%ActorContext{} = ctx, descriptor, metrics \\ %{}) do
    # Get base decision from standard policy
    base_decision = Policy.decide(ctx, descriptor)

    # Compute curriculum reward
    enriched_metrics = enrich_with_history(ctx.tenant, metrics)
    reward = CurriculumRewards.curriculum_reward(enriched_metrics)

    # Track this task for future repetition penalty
    if task_embedding = Map.get(metrics, :task_embedding) do
      record_task(ctx.tenant, task_embedding)
    end

    # Enhance decision with curriculum-aware limits
    enhance_decision(base_decision, enriched_metrics, reward)
  end

  defp enrich_with_history(tenant, metrics) do
    # Add history embeddings for repetition penalty
    history = get_task_history(tenant)
    Map.put(metrics, :history_embeddings, history)
  end

  defp enhance_decision({:deny, reason}, _metrics, _reward) do
    # Denied tasks stay denied
    {:deny, reason}
  end

  defp enhance_decision({:allow, meta}, metrics, reward) do
    limits = compute_limits(metrics, reward)

    enhanced_meta =
      Map.merge(meta, %{
        curriculum_reward: reward,
        limits: limits
      })

    {:allow_with, enhanced_meta}
  end

  defp enhance_decision({:allow_with, meta}, metrics, reward) do
    # Merge our computed limits with existing ones
    limits = compute_limits(metrics, reward)
    existing_limits = Map.get(meta, :limits, %{})

    merged_limits =
      Map.merge(limits, existing_limits, fn _k, our, their ->
        # Take the more generous limit
        max(our, their)
      end)

    enhanced_meta =
      Map.merge(meta, %{
        curriculum_reward: reward,
        limits: merged_limits
      })

    {:allow_with, enhanced_meta}
  end

  defp compute_limits(metrics, reward) do
    # Check if task is in capability frontier
    success_rate = Map.get(metrics, :success_rate, 0.5)
    in_frontier? = CurriculumRewards.in_frontier_band?(success_rate)

    # Apply frontier boosts for high-value learning opportunities
    {tool_budget, timeout_ms, retry_limit} =
      if in_frontier? and reward > 0.5 do
        {
          round(@default_tool_budget * @frontier_tool_boost),
          round(@default_timeout_ms * @frontier_timeout_boost),
          @default_retry_limit + @frontier_retry_boost
        }
      else
        {@default_tool_budget, @default_timeout_ms, @default_retry_limit}
      end

    %{
      tool_budget: tool_budget,
      timeout_ms: timeout_ms,
      retry_limit: retry_limit
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # TASK GENERATION FOR CURRICULUM
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Generate tasks for curriculum learning.

  Returns tasks ranked by curriculum reward (R_C).

  ## Arguments

  - `candidate_tasks` - List of {task, metrics} tuples
  - `opts` - Options for reward weights

  ## Returns

  Tasks sorted by descending curriculum reward.
  """
  @spec generate_curriculum_tasks(list({term(), map()}), keyword()) :: list({term(), float()})
  def generate_curriculum_tasks(candidate_tasks, opts \\ []) do
    CurriculumRewards.rank_tasks(candidate_tasks, opts)
  end

  @doc """
  Filter tasks to keep only frontier tasks.

  Frontier tasks (30-80% success rate) are most valuable for learning.
  """
  @spec filter_frontier_tasks(list({term(), float()})) :: list({term(), float()})
  def filter_frontier_tasks(tasks_with_success_rates) do
    CurriculumRewards.filter_frontier_tasks(tasks_with_success_rates)
  end

  # ═══════════════════════════════════════════════════════════════
  # EXECUTOR FEEDBACK INTEGRATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Record executor performance for consistency scoring.

  Call this after each executor attempt to build consistency data.

  ## Arguments

  - `tenant` - Tenant identifier
  - `task_id` - Unique task identifier
  - `response` - Executor's response
  - `success` - Whether the attempt succeeded
  """
  @spec record_executor_response(String.t(), String.t(), term(), boolean()) :: :ok
  def record_executor_response(tenant, task_id, response, success) do
    key = {tenant, :executor_responses, task_id}

    existing =
      case :ets.lookup(@history_table, key) do
        [{^key, responses}] -> responses
        [] -> []
      end

    entry = %{response: response, success: success, timestamp: System.system_time(:millisecond)}
    # Keep last 10 responses
    updated = [entry | existing] |> Enum.take(10)

    :ets.insert(@history_table, {key, updated})
    :ok
  end

  @doc """
  Get consistency score for a task based on executor responses.

  Uses majority voting over recorded responses.
  """
  @spec get_consistency_score(String.t(), String.t()) :: float()
  def get_consistency_score(tenant, task_id) do
    key = {tenant, :executor_responses, task_id}

    case :ets.lookup(@history_table, key) do
      [{^key, responses}] when responses != [] ->
        success_votes = Enum.map(responses, & &1.success)
        CurriculumRewards.compute_consistency(success_votes)

      _ ->
        # Default uncertainty
        0.5
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # TASK HISTORY (for repetition penalty)
  # ═══════════════════════════════════════════════════════════════

  defp record_task(tenant, embedding) do
    key = {tenant, :task_history}

    existing =
      case :ets.lookup(@history_table, key) do
        [{^key, history}] -> history
        [] -> []
      end

    # Keep last 100 task embeddings
    updated = [embedding | existing] |> Enum.take(100)
    :ets.insert(@history_table, {key, updated})
    :ok
  end

  defp get_task_history(tenant) do
    key = {tenant, :task_history}

    case :ets.lookup(@history_table, key) do
      [{^key, history}] -> history
      [] -> []
    end
  end

  @doc """
  Clear task history for a tenant.
  """
  @spec clear_history(String.t()) :: :ok
  def clear_history(tenant) do
    :ets.delete(@history_table, {tenant, :task_history})
    :ets.match_delete(@history_table, {{tenant, :executor_responses, :_}, :_})
    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # TELEMETRY
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Emit telemetry for curriculum decisions.
  """
  @spec emit_curriculum_telemetry(ActorContext.t(), map(), float(), curriculum_decision()) :: :ok
  def emit_curriculum_telemetry(ctx, descriptor, reward, decision) do
    {status, meta} = decision

    measurements = %{
      curriculum_reward: reward,
      tool_budget: get_in(meta, [:limits, :tool_budget]) || @default_tool_budget
    }

    metadata = %{
      tenant: ctx.tenant,
      actor_id: ctx.actor_id,
      domain: descriptor[:domain],
      resource: descriptor[:resource],
      action: descriptor[:action],
      decision: status
    }

    :telemetry.execute(
      [:thunderline, :thundercrown, :curriculum_decision],
      measurements,
      metadata
    )

    :ok
  end
end
