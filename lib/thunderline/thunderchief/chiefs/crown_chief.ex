defmodule Thunderline.Thunderchief.Chiefs.CrownChief do
  @moduledoc """
  Thundercrown (Governance) Domain Orchestrator (Meta-Puppeteer).

  The CrownChief observes the governance state across all domains and
  decides when to adjust policies, escalate violations, or reconfigure
  system constraints. As the meta-chief, it can influence other chiefs.

  ## Responsibilities

  - Monitor policy evaluations and violation rates
  - Adjust policy thresholds based on system load
  - Escalate critical violations to administrators
  - Coordinate cross-domain governance decisions
  - Log trajectory data for Cerebros governance learning

  ## Action Space

  - `{:adjust_threshold, policy_id, new_threshold}` - Tune policy strictness
  - `{:escalate_violation, violation_id}` - Alert admin of critical issue
  - `{:suspend_policy, policy_id}` - Temporarily disable problematic policy
  - `{:resume_policy, policy_id}` - Re-enable suspended policy
  - `{:emit_directive, directive_map}` - Send governance directive to chiefs
  - `:audit` - Trigger governance audit
  - `:wait` - No action

  ## Meta-Governance

  The CrownChief operates at a higher abstraction level:

  1. Observes aggregate metrics from all domains
  2. Detects systemic issues (cascade failures, resource exhaustion)
  3. Emits directives that other chiefs should respect
  4. Can override chief decisions in critical situations

  ## Example

      state = CrownChief.observe_state(governance_ctx)
      {:ok, action} = CrownChief.choose_action(state)
      {:ok, updated} = CrownChief.apply_action(action, governance_ctx)
  """

  @behaviour Thunderline.Thunderchief.Behaviour

  alias Thunderline.Thunderchief.{State, Action}

  @violation_threshold 0.1  # 10% violation rate triggers response
  @critical_violation_rate 0.3  # 30% triggers escalation
  @policy_suspension_threshold 0.5  # 50% failure rate suspends policy

  # ===========================================================================
  # Behaviour Implementation
  # ===========================================================================

  @impl true
  def observe_state(governance_ctx) do
    policies = get_active_policies(governance_ctx)
    evaluations = get_recent_evaluations(governance_ctx)
    violations = get_violations(governance_ctx)

    # Aggregate metrics
    total_evals = length(evaluations)
    violation_count = length(violations)
    violation_rate = if total_evals > 0, do: violation_count / total_evals, else: 0.0

    # Per-policy analysis
    policy_stats = analyze_policy_health(policies, evaluations)
    problematic_policies = find_problematic_policies(policy_stats)
    suspended_policies = Enum.filter(policies, &(&1.status == :suspended))

    # Critical violations needing escalation
    critical = Enum.filter(violations, &(&1.severity == :critical))
    unescalated = Enum.filter(critical, &(!&1.escalated))

    # Cross-domain health
    domain_health = assess_domain_health(governance_ctx)

    State.new(:crown, %{
      # Policy state
      active_policies: length(policies),
      suspended_policies: length(suspended_policies),
      problematic_policies: problematic_policies,

      # Evaluation metrics
      total_evaluations: total_evals,
      violation_count: violation_count,
      violation_rate: violation_rate,

      # Critical items
      critical_violations: critical,
      unescalated_critical: unescalated,
      needs_escalation: length(unescalated) > 0,

      # Health
      policy_stats: policy_stats,
      domain_health: domain_health,
      system_healthy: violation_rate < @violation_threshold,

      # Governance directives in flight
      pending_directives: get_pending_directives(governance_ctx)
    },
    tick: Map.get(governance_ctx, :tick, 0),
    context: governance_ctx
    )
  end

  @impl true
  def choose_action(%State{features: state}) do
    cond do
      # Priority 1: Escalate critical violations
      state.needs_escalation ->
        [violation | _] = state.unescalated_critical
        {:ok, {:escalate_violation, violation.id}}

      # Priority 2: Suspend failing policies
      length(state.problematic_policies) > 0 ->
        [policy | _] = state.problematic_policies
        {:ok, {:suspend_policy, policy.id}}

      # Priority 3: Address high violation rate
      state.violation_rate > @violation_threshold and state.system_healthy == false ->
        # Emit system-wide caution directive
        directive = %{
          type: :caution,
          reason: :high_violation_rate,
          rate: state.violation_rate,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        }
        {:ok, {:emit_directive, directive}}

      # Priority 4: Resume suspended policies if health restored
      state.suspended_policies > 0 and state.violation_rate < @violation_threshold / 2 ->
        candidate = find_resumable_policy(state)
        if candidate do
          {:ok, {:resume_policy, candidate.id}}
        else
          {:ok, :audit}
        end

      # Priority 5: Periodic audit
      rem(state.tick || 0, 100) == 0 ->
        {:ok, :audit}

      # No action needed
      true ->
        {:wait, 200}
    end
  end

  @impl true
  def apply_action(action, governance_ctx) do
    action_struct = Action.from_tuple(action)
    action_struct = Action.mark_executing(action_struct)

    result = do_apply_action(action, governance_ctx)

    case result do
      {:ok, updated} ->
        Action.log(Action.mark_completed(action_struct), :executed, %{chief: :crown})
        {:ok, updated}

      {:error, reason} = error ->
        Action.log(Action.mark_failed(action_struct, reason), :failed, %{chief: :crown})
        error
    end
  end

  @impl true
  def report_outcome(governance_ctx) do
    state = observe_state(governance_ctx)

    %{
      reward: calculate_reward(state),
      metrics: %{
        violation_rate: state.features.violation_rate,
        active_policies: state.features.active_policies,
        suspended_policies: state.features.suspended_policies,
        critical_pending: length(state.features.unescalated_critical),
        system_healthy: state.features.system_healthy
      },
      trajectory_step: %{
        state: state.features,
        action: nil,
        next_state: state.features,
        timestamp: DateTime.utc_now()
      }
    }
  end

  @impl true
  def action_space do
    [
      :audit,
      :wait,
      {:escalate_violation, "violation_id"},
      {:suspend_policy, "policy_id"},
      {:resume_policy, "policy_id"},
      {:adjust_threshold, "policy_id", 0.5},
      {:emit_directive, %{type: :caution}}
    ]
  end

  # ===========================================================================
  # Action Execution
  # ===========================================================================

  defp do_apply_action({:escalate_violation, violation_id}, ctx) do
    # Mark violation as escalated, notify admins
    violations = ctx[:violations] || []
    updated = Enum.map(violations, fn v ->
      if v.id == violation_id, do: Map.put(v, :escalated, true), else: v
    end)

    # Emit escalation event
    emit_governance_event(:violation_escalated, %{
      violation_id: violation_id,
      escalated_at: DateTime.utc_now()
    })

    {:ok, Map.put(ctx, :violations, updated)}
  end

  defp do_apply_action({:suspend_policy, policy_id}, ctx) do
    policies = ctx[:policies] || []
    updated = Enum.map(policies, fn p ->
      if p.id == policy_id do
        p
        |> Map.put(:status, :suspended)
        |> Map.put(:suspended_at, DateTime.utc_now())
      else
        p
      end
    end)

    emit_governance_event(:policy_suspended, %{policy_id: policy_id})
    {:ok, Map.put(ctx, :policies, updated)}
  end

  defp do_apply_action({:resume_policy, policy_id}, ctx) do
    policies = ctx[:policies] || []
    updated = Enum.map(policies, fn p ->
      if p.id == policy_id do
        p
        |> Map.put(:status, :active)
        |> Map.delete(:suspended_at)
      else
        p
      end
    end)

    emit_governance_event(:policy_resumed, %{policy_id: policy_id})
    {:ok, Map.put(ctx, :policies, updated)}
  end

  defp do_apply_action({:adjust_threshold, policy_id, new_threshold}, ctx) do
    policies = ctx[:policies] || []
    updated = Enum.map(policies, fn p ->
      if p.id == policy_id, do: Map.put(p, :threshold, new_threshold), else: p
    end)

    {:ok, Map.put(ctx, :policies, updated)}
  end

  defp do_apply_action({:emit_directive, directive}, ctx) do
    directives = ctx[:directives] || []
    new_directive = Map.merge(directive, %{
      id: generate_directive_id(),
      issued_at: DateTime.utc_now(),
      status: :pending
    })

    emit_governance_event(:directive_issued, new_directive)
    {:ok, Map.put(ctx, :directives, [new_directive | directives])}
  end

  defp do_apply_action(:audit, ctx) do
    # Trigger governance audit
    emit_governance_event(:audit_triggered, %{
      timestamp: DateTime.utc_now(),
      context_snapshot: summarize_context(ctx)
    })
    {:ok, ctx}
  end

  defp do_apply_action(_action, ctx) do
    {:ok, ctx}
  end

  # ===========================================================================
  # Analysis Helpers
  # ===========================================================================

  defp get_active_policies(ctx) do
    ctx[:policies] || []
  end

  defp get_recent_evaluations(ctx) do
    ctx[:evaluations] || []
  end

  defp get_violations(ctx) do
    ctx[:violations] || []
  end

  defp get_pending_directives(ctx) do
    (ctx[:directives] || [])
    |> Enum.filter(&(&1.status == :pending))
  end

  defp analyze_policy_health(policies, evaluations) do
    Enum.map(policies, fn policy ->
      policy_evals = Enum.filter(evaluations, &(&1.policy_id == policy.id))
      failures = Enum.count(policy_evals, &(&1.verdict == :deny))
      total = length(policy_evals)
      failure_rate = if total > 0, do: failures / total, else: 0.0

      %{
        id: policy.id,
        name: policy.name,
        total_evals: total,
        failures: failures,
        failure_rate: failure_rate,
        healthy: failure_rate < @policy_suspension_threshold
      }
    end)
  end

  defp find_problematic_policies(stats) do
    stats
    |> Enum.filter(&(!&1.healthy))
    |> Enum.sort_by(& -&1.failure_rate)
  end

  defp find_resumable_policy(state) do
    # Find a suspended policy that might be safe to resume
    state.policy_stats
    |> Enum.find(fn stat ->
      stat.failure_rate < @violation_threshold
    end)
  end

  defp assess_domain_health(ctx) do
    # Aggregate health from domain metrics
    %{
      bit: Map.get(ctx, :bit_health, :unknown),
      vine: Map.get(ctx, :vine_health, :unknown),
      prism: Map.get(ctx, :prism_health, :unknown)
    }
  end

  defp summarize_context(ctx) do
    %{
      policies: length(ctx[:policies] || []),
      violations: length(ctx[:violations] || []),
      directives: length(ctx[:directives] || [])
    }
  end

  defp generate_directive_id do
    "dir_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end

  defp emit_governance_event(event_type, payload) do
    # Emit via EventBus
    event_name = "crown.governance.#{event_type}"
    case Thunderline.Thunderflow.EventBus.publish_event(%{
      name: event_name,
      source: :crown,
      payload: payload
    }) do
      {:ok, _} -> :ok
      {:error, _} -> :ok  # Log but don't fail
    end
  rescue
    _ -> :ok
  end

  # ===========================================================================
  # Reward Calculation
  # ===========================================================================

  defp calculate_reward(state) do
    # Reward: system health, low violations, efficient governance
    health_bonus = if state.features.system_healthy, do: 10, else: -10
    violation_penalty = state.features.violation_rate * 20
    escalation_penalty = length(state.features.unescalated_critical) * 5

    health_bonus - violation_penalty - escalation_penalty
  end
end
