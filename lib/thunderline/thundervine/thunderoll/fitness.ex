defmodule Thunderline.Thundervine.Thunderoll.Fitness do
  @moduledoc """
  Fitness evaluation for EGGROLL population members.

  Fitness is computed by Thunderline (not EGGROLL backend) because:
  1. We control the rollout environment
  2. We can inject domain-specific metrics (PLV, near-critical, safety)
  3. Thundercrown can abort unsafe members mid-evaluation

  ## Fitness Specification

  The `fitness_spec` map controls how fitness is evaluated:

      %{
        rollout_type: :pac_behavior | :environment_steps | :custom,
        weights: %{reward: 1.0, safety_violations: -10.0},
        max_concurrency: 8,
        timeout: 30_000
      }

  ## Supported Metrics

  - `:reward` - Task reward (higher is better)
  - `:safety_violations` - Constraint violations (lower is better)
  - `:plv_sync` - Phase-locking value for near-critical dynamics
  - `:sigma_flow` - Propagatability efficiency
  - `:lambda_hat` - Local FTLE (chaos/stability measure)
  - `:stability` - General stability metric

  ## Custom Fitness Functions

  For custom fitness, provide a `:rollout_fn` in the spec:

      %{
        rollout_type: :custom,
        rollout_fn: fn base_params, perturbation -> 
          # ... evaluate and return metrics map
        end
      }
  """

  alias Thunderline.Thundervine.Thunderoll.Perturbation

  require Logger

  @default_weights %{
    reward: 1.0,
    safety_violations: -10.0,
    plv_sync: 0.5,
    stability: 0.2
  }

  @default_max_concurrency System.schedulers_online()
  @default_timeout 30_000

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Evaluate fitness for all population members.

  Returns fitness vector as list of floats.

  ## Parameters

  - `base_params` - Base model/PAC parameters
  - `perturbations` - List of `%Perturbation{}` structs
  - `fitness_spec` - Fitness evaluation specification
  """
  @spec evaluate_population(map(), [Perturbation.t()], map()) :: [float()]
  def evaluate_population(base_params, perturbations, fitness_spec) do
    max_concurrency = fitness_spec[:max_concurrency] || @default_max_concurrency
    timeout = fitness_spec[:timeout] || @default_timeout

    start_time = System.monotonic_time(:millisecond)

    # Parallel evaluation with controlled concurrency
    results =
      perturbations
      |> Enum.with_index()
      |> Task.async_stream(
        fn {pert, idx} ->
          evaluate_one(base_params, pert, fitness_spec, idx)
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, fitness} -> fitness
        {:exit, :timeout} -> 0.0
        {:exit, _reason} -> 0.0
      end)

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.debug(
      "[Thunderoll.Fitness] Evaluated #{length(perturbations)} members in #{duration}ms"
    )

    results
  end

  @doc """
  Evaluate fitness for a single population member.

  Returns scalar fitness value.
  """
  @spec evaluate_one(map(), Perturbation.t(), map(), non_neg_integer()) :: float()
  def evaluate_one(base_params, perturbation, spec, member_idx) do
    # Run rollout based on type
    rollout_result = run_rollout(base_params, perturbation, spec, member_idx)

    # Extract metrics
    metrics = extract_metrics(rollout_result, spec)

    # Aggregate into scalar fitness
    aggregate_fitness(metrics, spec)
  end

  @doc """
  Default fitness aggregation: weighted sum of metrics.

  Supports:
  - :reward (higher is better)
  - :safety_violations (lower is better, inverted via negative weight)
  - :plv_sync (phase-locking value, target ~0.3-0.7)
  - :stability (lower chaos is better for some tasks)
  """
  @spec aggregate_fitness(map(), map()) :: float()
  def aggregate_fitness(metrics, spec) do
    weights = spec[:weights] || @default_weights

    Enum.reduce(weights, 0.0, fn {metric, weight}, acc ->
      value = Map.get(metrics, metric, 0.0)
      acc + weight * value
    end)
  end

  @doc """
  Compute PLV (Phase-Locking Value) target deviation.

  PLV measures phase synchronization. For "edge of chaos" operation,
  we target PLV ≈ 0.5 (neither fully synchronized nor fully random).
  """
  @spec plv_deviation(float(), float()) :: float()
  def plv_deviation(actual_plv, target_plv \\ 0.5) do
    # Returns negative deviation (penalty)
    -abs(actual_plv - target_plv)
  end

  # ═══════════════════════════════════════════════════════════════
  # ROLLOUT IMPLEMENTATIONS
  # ═══════════════════════════════════════════════════════════════

  defp run_rollout(base_params, perturbation, spec, member_idx) do
    case spec[:rollout_type] do
      :pac_behavior ->
        run_pac_rollout(base_params, perturbation, spec, member_idx)

      :environment_steps ->
        run_env_rollout(base_params, perturbation, spec, member_idx)

      :custom ->
        run_custom_rollout(base_params, perturbation, spec)

      :mock ->
        # For testing - returns deterministic metrics based on perturbation
        run_mock_rollout(perturbation, member_idx)

      _ ->
        Logger.warning(
          "[Thunderoll.Fitness] Unknown rollout type: #{inspect(spec[:rollout_type])}"
        )

        %{reward: 0.0}
    end
  end

  defp run_pac_rollout(base_params, perturbation, spec, _member_idx) do
    # Run PAC with perturbed policy
    # This integrates with Thunderpac's behavior system

    # For now, simulate a rollout
    # In full implementation:
    # 1. Create perturbed PAC policy
    # 2. Run behavior tree / state machine
    # 3. Collect metrics from environment interaction

    perturbed_params = apply_perturbation(base_params, perturbation)

    # Placeholder: compute simple fitness based on parameter norm
    # Real implementation would run actual PAC behaviors
    param_norm = compute_param_norm(perturbed_params)

    %{
      reward: :math.exp(-param_norm / 100.0),
      safety_violations: 0,
      stability: 1.0 - :math.tanh(param_norm / 1000.0)
    }
  end

  defp run_env_rollout(base_params, perturbation, spec, _member_idx) do
    # Run in simulated environment
    # This would integrate with a Thunderline environment simulator

    perturbed_params = apply_perturbation(base_params, perturbation)
    steps = spec[:env_steps] || 100

    # Placeholder: simulate environment steps
    # Real implementation would step through environment
    accumulated_reward =
      Enum.reduce(1..steps, 0.0, fn _step, acc ->
        # Each step produces some reward
        step_reward = :rand.uniform() * 0.1
        acc + step_reward
      end)

    %{
      reward: accumulated_reward,
      safety_violations: 0,
      stability: 0.8
    }
  end

  defp run_custom_rollout(base_params, perturbation, spec) do
    # User-provided rollout function
    case spec[:rollout_fn] do
      fun when is_function(fun, 2) ->
        fun.(base_params, perturbation)

      _ ->
        Logger.error("[Thunderoll.Fitness] Custom rollout requires :rollout_fn")
        %{reward: 0.0}
    end
  end

  defp run_mock_rollout(perturbation, member_idx) do
    # Deterministic mock for testing
    # Higher fitness for lower member indices (for predictable testing)
    base_fitness = 1.0 - member_idx / 100.0

    # Add some variation based on perturbation seed
    variation = :math.sin(perturbation.seed / 1000.0) * 0.1

    %{
      reward: base_fitness + variation,
      safety_violations: 0,
      plv_sync: 0.5,
      stability: 0.9
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp extract_metrics(rollout_result, spec) do
    # Start with rollout result
    base_metrics = rollout_result

    # Add PLV deviation if PLV is measured and target specified
    metrics =
      case {Map.get(base_metrics, :plv_sync), spec[:plv_target]} do
        {plv, target} when is_number(plv) and is_number(target) ->
          Map.put(base_metrics, :plv_target_deviation, plv_deviation(plv, target))

        _ ->
          base_metrics
      end

    metrics
  end

  defp apply_perturbation(base_params, perturbation) do
    # Apply low-rank perturbation to parameters
    case base_params do
      %{weights: weights} when is_struct(weights, Nx.Tensor) ->
        outer = Perturbation.outer_product(perturbation)
        perturbed_weights = Nx.add(weights, Nx.multiply(outer, perturbation.sigma))
        %{base_params | weights: perturbed_weights}

      _ ->
        # No tensor weights, return as-is
        base_params
    end
  end

  defp compute_param_norm(params) do
    case params do
      %{weights: weights} when is_struct(weights, Nx.Tensor) ->
        weights
        |> Nx.flatten()
        |> Nx.pow(2)
        |> Nx.sum()
        |> Nx.sqrt()
        |> Nx.to_number()

      _ ->
        0.0
    end
  end
end
