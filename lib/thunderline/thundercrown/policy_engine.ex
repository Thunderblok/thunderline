defmodule Thunderline.Thundercrown.PolicyEngine do
  @moduledoc """
  Extensible policy engine with composable constraints.

  The PolicyEngine provides a declarative DSL for defining governance rules
  that are evaluated at runtime against execution contexts.

  ## Architecture

  Policies are composed of:
  - **Constraints**: Atomic boolean predicates (resource limits, time windows, etc.)
  - **Rules**: Named combinations of constraints with actions
  - **Policies**: Collections of rules with evaluation strategy

  ## Evaluation Model

  1. Context flows into the engine with the target action
  2. Applicable policies are looked up (by domain, resource, action)
  3. Each policy's rules are evaluated
  4. Constraint outcomes are aggregated per evaluation strategy
  5. Final verdict is returned with enforcement directives

  ## Usage

      # Define constraints
      within_hours = Constraint.time_window(9, 17)
      under_limit = Constraint.resource_limit(:api_calls, 1000)

      # Create a policy
      policy = Policy.new("api_access")
               |> Policy.add_rule("business_hours", within_hours)
               |> Policy.add_rule("rate_limit", under_limit)
               |> Policy.with_strategy(:all_of)

      # Evaluate
      {:allow, meta} = PolicyEngine.evaluate(policy, context, action)

  ## Evaluation Strategies

  - `:all_of` - All rules must pass (AND)
  - `:any_of` - At least one rule must pass (OR)
  - `:first_match` - First matching rule determines outcome
  - `:weighted` - Rules have weights, threshold determines pass/fail

  ## Telemetry

  Emits `[:thunderline, :crown, :policy, :evaluate]` with:
  - `duration`: evaluation time in microseconds
  - `policy_id`: policy identifier
  - `verdict`: `:allow | :deny | :allow_with`
  - `rules_evaluated`: count of rules checked
  """

  alias Thunderline.Thundercrown.Constraint

  require Logger

  @type verdict :: {:allow, map()} | {:deny, term()} | {:allow_with, map()}
  @type context :: map()
  @type action_descriptor :: %{
          required(:domain) => atom(),
          required(:resource) => atom(),
          required(:action) => atom(),
          optional(:scopes) => [String.t()]
        }

  @type evaluation_strategy :: :all_of | :any_of | :first_match | :weighted

  @type rule :: %{
          name: String.t(),
          constraint: Constraint.t(),
          weight: float(),
          on_fail: :deny | :warn | :audit
        }

  @type policy :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          rules: [rule()],
          strategy: evaluation_strategy(),
          threshold: float(),
          metadata: map()
        }

  @doc """
  Creates a new empty policy.
  """
  @spec new_policy(String.t(), keyword()) :: policy()
  def new_policy(name, opts \\ []) do
    %{
      id: opts[:id] || generate_id(name),
      name: name,
      description: opts[:description],
      rules: [],
      strategy: opts[:strategy] || :all_of,
      threshold: opts[:threshold] || 1.0,
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Adds a rule to a policy.
  """
  @spec add_rule(policy(), String.t(), Constraint.t(), keyword()) :: policy()
  def add_rule(policy, name, constraint, opts \\ []) do
    rule = %{
      name: name,
      constraint: constraint,
      weight: opts[:weight] || 1.0,
      on_fail: opts[:on_fail] || :deny
    }

    %{policy | rules: policy.rules ++ [rule]}
  end

  @doc """
  Sets the evaluation strategy for a policy.
  """
  @spec with_strategy(policy(), evaluation_strategy()) :: policy()
  def with_strategy(policy, strategy) when strategy in [:all_of, :any_of, :first_match, :weighted] do
    %{policy | strategy: strategy}
  end

  @doc """
  Sets the threshold for weighted evaluation.
  """
  @spec with_threshold(policy(), float()) :: policy()
  def with_threshold(policy, threshold) when threshold >= 0.0 and threshold <= 1.0 do
    %{policy | threshold: threshold}
  end

  @doc """
  Evaluates a policy against the given context and action.

  Returns `{:allow, meta}`, `{:deny, reason}`, or `{:allow_with, limits}`.
  """
  @spec evaluate(policy(), context(), action_descriptor()) :: verdict()
  def evaluate(policy, context, action) do
    start = System.monotonic_time(:microsecond)

    # Enrich context with action info
    eval_context = Map.merge(context, %{
      __action_domain: action[:domain],
      __action_resource: action[:resource],
      __action_name: action[:action]
    })

    # Evaluate all rules
    rule_results = Enum.map(policy.rules, fn rule ->
      result = Constraint.evaluate(rule.constraint, eval_context)
      {rule, result}
    end)

    # Aggregate based on strategy
    verdict = aggregate(policy, rule_results)

    # Emit telemetry
    emit_telemetry(policy, verdict, length(rule_results), start)

    verdict
  end

  @doc """
  Evaluates multiple policies, returning the most restrictive outcome.
  """
  @spec evaluate_all([policy()], context(), action_descriptor()) :: verdict()
  def evaluate_all(policies, context, action) do
    results = Enum.map(policies, &evaluate(&1, context, action))

    # Find most restrictive
    cond do
      Enum.any?(results, &match?({:deny, _}, &1)) ->
        Enum.find(results, &match?({:deny, _}, &1))

      Enum.any?(results, &match?({:allow_with, _}, &1)) ->
        # Merge all limits
        limits =
          results
          |> Enum.filter(&match?({:allow_with, _}, &1))
          |> Enum.map(fn {:allow_with, l} -> l end)
          |> Enum.reduce(%{}, &Map.merge/2)

        {:allow_with, limits}

      true ->
        {:allow, %{policies_evaluated: length(policies)}}
    end
  end

  # Aggregation strategies

  defp aggregate(%{strategy: :all_of} = policy, results) do
    failures = Enum.filter(results, fn {_rule, res} -> res == false end)

    case failures do
      [] ->
        {:allow, %{policy_id: policy.id, rules_passed: length(results)}}

      [{rule, _} | _] ->
        case rule.on_fail do
          :deny -> {:deny, {:rule_failed, rule.name}}
          :warn -> {:allow_with, %{warning: rule.name}}
          :audit -> {:allow, %{audit: rule.name}}
        end
    end
  end

  defp aggregate(%{strategy: :any_of} = policy, results) do
    passes = Enum.filter(results, fn {_rule, res} -> res == true end)

    case passes do
      [] ->
        {:deny, {:no_rules_passed, policy.id}}

      [{rule, _} | _] ->
        {:allow, %{policy_id: policy.id, matched_rule: rule.name}}
    end
  end

  defp aggregate(%{strategy: :first_match} = policy, results) do
    case Enum.find(results, fn {_rule, res} -> res == true end) do
      {rule, _} ->
        {:allow, %{policy_id: policy.id, matched_rule: rule.name}}

      nil ->
        {:deny, {:no_match, policy.id}}
    end
  end

  defp aggregate(%{strategy: :weighted, threshold: threshold} = policy, results) do
    total_weight = Enum.reduce(policy.rules, 0.0, fn r, acc -> acc + r.weight end)

    passed_weight =
      results
      |> Enum.filter(fn {_rule, res} -> res == true end)
      |> Enum.reduce(0.0, fn {rule, _}, acc -> acc + rule.weight end)

    score = if total_weight > 0, do: passed_weight / total_weight, else: 0.0

    if score >= threshold do
      {:allow, %{policy_id: policy.id, score: score}}
    else
      {:deny, {:score_below_threshold, score, threshold}}
    end
  end

  # Helpers

  defp generate_id(name) do
    slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "policy_#{slug}_#{suffix}"
  end

  defp emit_telemetry(policy, verdict, rules_count, start) do
    duration = System.monotonic_time(:microsecond) - start

    verdict_type =
      case verdict do
        {:allow, _} -> :allow
        {:deny, _} -> :deny
        {:allow_with, _} -> :allow_with
      end

    meta = %{
      policy_id: policy.id,
      policy_name: policy.name,
      verdict: verdict_type,
      rules_evaluated: rules_count,
      strategy: policy.strategy
    }

    :telemetry.execute([:thunderline, :crown, :policy, :evaluate], %{duration: duration}, meta)
  end
end
