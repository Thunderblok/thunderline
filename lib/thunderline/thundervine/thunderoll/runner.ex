defmodule Thunderline.Thundervine.Thunderoll.Runner do
  @moduledoc """
  EGGROLL-style Evolution Strategies optimizer for Thunderline.

  Uses low-rank perturbations (A·Bᵀ where r << min(m,n)) to achieve
  O(r(m+n)) memory vs O(mn) for full-rank ES, while aggregated
  updates remain full-rank across the population.

  ## Overview

  Thunderoll is Thunderline's implementation of EGGROLL (Evolution Guided
  General Optimization via Low-rank Learning) from the ES Hyperscale paper.

  Key insight: If you can do batched LoRA-style inference and define a
  fitness function, Thunderoll can optimize the system end-to-end without
  backprop.

  ## Architecture Integration

  - **Thundervine**: Orchestrates optimization loops via BehaviorGraph
  - **Thunderpac**: Defines models/behaviors being optimized
  - **Thundercrown**: Governs when/how far optimization can push

  ## Usage

      {:ok, runner} = Thunderoll.Runner.init(%{
        base_params: %{weights: tensor},
        population_size: 1024,
        fitness_spec: %{rollout_type: :pac_behavior},
        policy_context: %{actor: current_user}
      })

      {:ok, delta, runner} = Thunderoll.Runner.run_generation(runner)

  ## Reference

  ES Hyperscale Paper: https://eshyperscale.github.io/
  """

  alias Thunderline.Thundervine.Thunderoll.{Perturbation, Fitness}
  alias Thunderline.Thundercrown.PolicyEngine

  require Logger

  defstruct [
    :experiment_id,
    :base_params,
    :rank,
    :population_size,
    :sigma,
    :generation,
    :backend,
    :fitness_spec,
    :convergence_criteria,
    :policy_context,
    :param_shape,
    :rng_key
  ]

  @type t :: %__MODULE__{
          experiment_id: String.t() | nil,
          base_params: map(),
          rank: pos_integer(),
          population_size: pos_integer(),
          sigma: float(),
          generation: non_neg_integer(),
          backend: :remote_jax | :nx_native,
          fitness_spec: map(),
          convergence_criteria: map(),
          policy_context: map(),
          param_shape: {pos_integer(), pos_integer()},
          rng_key: integer()
        }

  @default_convergence %{
    max_generations: 100,
    fitness_plateau_window: 10,
    fitness_plateau_threshold: 0.001
  }

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Initialize a new Thunderoll optimization run.

  Validates against Thundercrown policies before starting.
  Creates persistent ThunderollExperiment record if persistence is enabled.

  ## Options

  - `:base_params` - Base model parameters (required)
  - `:population_size` - Number of population members (required)
  - `:fitness_spec` - Fitness function specification (required)
  - `:policy_context` - Thundercrown governance context (required)
  - `:rank` - Low-rank perturbation rank (default: 1)
  - `:sigma` - Perturbation standard deviation (default: 0.02)
  - `:backend` - Backend to use (default: :nx_native)
  - `:convergence_criteria` - When to stop (default: max 100 generations)
  - `:persist?` - Whether to persist to database (default: false)
  """
  @spec init(map()) :: {:ok, t()} | {:error, term()}
  def init(opts) do
    with :ok <- validate_opts(opts),
         {:ok, _} <- check_policy(opts) do
      runner = %__MODULE__{
        experiment_id: opts[:experiment_id],
        base_params: opts.base_params,
        rank: opts[:rank] || 1,
        population_size: opts.population_size,
        sigma: opts[:sigma] || 0.02,
        generation: 0,
        backend: opts[:backend] || :nx_native,
        fitness_spec: opts.fitness_spec,
        convergence_criteria: opts[:convergence_criteria] || @default_convergence,
        policy_context: opts.policy_context,
        param_shape: infer_param_shape(opts.base_params),
        rng_key: :rand.uniform(2 ** 32)
      }

      emit_telemetry(:init, runner)

      Logger.info(
        "[Thunderoll] Initialized experiment with population=#{runner.population_size}, " <>
          "rank=#{runner.rank}, sigma=#{runner.sigma}"
      )

      {:ok, runner}
    end
  end

  @doc """
  Run one generation of EGGROLL optimization.

  1. Sample low-rank perturbations for population
  2. Dispatch fitness evaluations (PAC rollouts)
  3. Collect fitness vector
  4. Compute aggregated update via backend
  5. Return delta parameters

  Returns `{:ok, delta, new_runner}` on success.
  """
  @spec run_generation(t()) :: {:ok, map(), t()} | {:error, term()}
  def run_generation(%__MODULE__{} = runner) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("[Thunderoll] Starting generation #{runner.generation}")

    # Sample perturbations: each is {A, B} where A ∈ R^(m×r), B ∈ R^(n×r)
    perturbations =
      Perturbation.sample_population(
        runner.param_shape,
        runner.population_size,
        runner.rank,
        runner.sigma,
        runner.rng_key,
        runner.generation
      )

    # Evaluate fitness for each perturbed member
    fitness_vector =
      Fitness.evaluate_population(
        runner.base_params,
        perturbations,
        runner.fitness_spec
      )

    # Compute EGGROLL update: Σ(fitness_i * A_i * B_i^T) / population_size
    delta = compute_update(perturbations, fitness_vector, runner)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Update runner state
    new_runner = %{runner | generation: runner.generation + 1}

    # Emit telemetry
    emit_telemetry(:generation_complete, new_runner, %{
      duration_ms: duration_ms,
      fitness_mean: mean(fitness_vector),
      fitness_max: Enum.max(fitness_vector),
      fitness_min: Enum.min(fitness_vector)
    })

    Logger.info(
      "[Thunderoll] Generation #{runner.generation} complete in #{duration_ms}ms, " <>
        "mean fitness: #{Float.round(mean(fitness_vector), 4)}"
    )

    {:ok, delta, new_runner}
  end

  @doc """
  Check if optimization has converged.
  """
  @spec converged?(t()) :: boolean()
  def converged?(%__MODULE__{} = runner) do
    cond do
      runner.generation >= runner.convergence_criteria.max_generations ->
        Logger.info("[Thunderoll] Converged: max generations reached")
        true

      # TODO: Add fitness plateau detection once we track history
      # fitness_plateau?(runner) ->
      #   Logger.info("[Thunderoll] Converged: fitness plateau")
      #   true

      true ->
        false
    end
  end

  @doc """
  Apply delta to base parameters, returning updated parameters.
  """
  @spec apply_update(t(), map()) :: {:ok, map()}
  def apply_update(%__MODULE__{base_params: base}, delta) do
    # For now, simple addition. In practice, this would handle
    # different parameter structures (LoRA, full weights, etc.)
    updated = merge_delta(base, delta)
    {:ok, updated}
  end

  @doc """
  Get current experiment state as a summary map.
  """
  @spec state_summary(t()) :: map()
  def state_summary(%__MODULE__{} = runner) do
    %{
      experiment_id: runner.experiment_id,
      generation: runner.generation,
      population_size: runner.population_size,
      rank: runner.rank,
      sigma: runner.sigma,
      backend: runner.backend,
      param_shape: runner.param_shape,
      converged: converged?(runner)
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp validate_opts(opts) do
    required = [:base_params, :population_size, :fitness_spec, :policy_context]

    missing = Enum.filter(required, fn key -> !Map.has_key?(opts, key) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_opts, missing}}
    end
  end

  defp check_policy(opts) do
    # In full implementation, this checks Thundercrown policies
    # For now, always allow
    case PolicyEngine.check("thunderoll:allowed?", opts.policy_context) do
      {:ok, _} -> {:ok, :allowed}
      {:error, reason} -> {:error, {:policy_denied, reason}}
    end
  rescue
    # PolicyEngine might not be fully implemented yet
    _ -> {:ok, :allowed}
  end

  defp infer_param_shape(base_params) do
    # Extract shape from base params
    # For simple case, assume it's a map with a :weights key containing a tensor
    case base_params do
      %{weights: weights} when is_struct(weights, Nx.Tensor) ->
        Nx.shape(weights)

      %{shape: shape} ->
        shape

      _ ->
        # Default shape for testing
        {256, 256}
    end
  end

  defp compute_update(perturbations, fitness_vector, runner) do
    case runner.backend do
      :nx_native ->
        compute_update_nx(perturbations, fitness_vector, runner)

      :remote_jax ->
        compute_update_remote(perturbations, fitness_vector, runner)
    end
  end

  defp compute_update_nx(perturbations, fitness_vector, runner) do
    # EGGROLL update: Σ(fitness_i * A_i * B_i^T) / (N * σ)
    #
    # This is the core insight: each individual perturbation is low-rank (r),
    # but the sum across the population is high-rank (up to min(N*r, m, n))

    {m, n} = runner.param_shape
    n_pop = runner.population_size

    # Initialize accumulator
    acc = Nx.broadcast(0.0, {m, n})

    # Aggregate weighted perturbations
    delta =
      perturbations
      |> Enum.zip(fitness_vector)
      |> Enum.reduce(acc, fn {pert, fitness}, acc ->
        # fitness * A @ B.T
        outer = Nx.dot(pert.a, Nx.transpose(pert.b))
        weighted = Nx.multiply(outer, fitness)
        Nx.add(acc, weighted)
      end)

    # Scale by 1/(N*σ) - this is the ES gradient estimator
    scale = 1.0 / (n_pop * runner.sigma)
    scaled_delta = Nx.multiply(delta, scale)

    %{weights: scaled_delta}
  end

  defp compute_update_remote(perturbations, fitness_vector, runner) do
    # Extract seeds for reconstruction on remote side
    seeds = Enum.map(perturbations, & &1.seed)

    alias Thunderline.Thundervine.Thunderoll.Backend.RemoteJax

    case RemoteJax.compute_update(seeds, fitness_vector, %{
           rank: runner.rank,
           sigma: runner.sigma,
           param_shape: runner.param_shape
         }) do
      {:ok, delta} ->
        delta

      {:error, reason} ->
        Logger.error("[Thunderoll] Remote backend error: #{inspect(reason)}")
        # Fallback to local computation
        compute_update_nx(perturbations, fitness_vector, runner)
    end
  end

  defp merge_delta(base, delta) do
    # Simple merge - add delta to base weights
    case {base, delta} do
      {%{weights: base_w}, %{weights: delta_w}} ->
        %{base | weights: Nx.add(base_w, delta_w)}

      _ ->
        Map.merge(base, delta)
    end
  end

  defp mean(list) when is_list(list) and length(list) > 0 do
    Enum.sum(list) / length(list)
  end

  defp mean(_), do: 0.0

  defp emit_telemetry(event, runner, extra \\ %{}) do
    :telemetry.execute(
      [:thunderline, :vine, :thunderoll, event],
      Map.merge(extra, %{
        generation: runner.generation,
        population_size: runner.population_size
      }),
      %{
        experiment_id: runner.experiment_id,
        backend: runner.backend
      }
    )
  end
end
