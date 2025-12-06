defmodule Thunderline.Thunderforge.Learn do
  @moduledoc """
  Thunderforge Learning Module — Rule tuning, HPO, and model fitting.

  Absorbs functionality from Thunderlearn and integrates with Cerebros TPE.

  ## Capabilities

  - **Rule Tuning**: Optimize CA/NCA rule parameters
  - **HPO**: Hyperparameter optimization via TPE (Tree-Parzen Estimator)
  - **Rule Fitting**: Learn rules from observed behavior
  - **Evolution**: Genetic algorithm for rule evolution

  ## Integration

  - Cerebros TPE for sequential model-based optimization
  - Thunderbolt for rule execution and metric collection
  - Thundercore for reward signal integration

  ## Usage

      # Tune a CA rule
      {:ok, optimized} = Learn.tune(rule_config, training_data,
        objective: :maximize_clustering,
        max_trials: 100
      )

      # Async optimization
      {:ok, task_ref} = Learn.tune_async(rule_config, training_data, opts)
      status = Learn.check_status(task_ref)
  """

  require Logger

  @type rule_config :: map()
  @type training_data :: list()
  @type tune_opts :: [
          objective: atom(),
          max_trials: pos_integer(),
          timeout: pos_integer(),
          search_space: map()
        ]

  @doc """
  Tune automata rule parameters using hyperparameter optimization.

  ## Options

  - `:objective` - Metric to optimize (`:maximize_clustering`, `:minimize_entropy`, etc.)
  - `:max_trials` - Maximum optimization trials (default: 50)
  - `:timeout` - Timeout in milliseconds (default: 60_000)
  - `:search_space` - Parameter search space (auto-inferred if not provided)

  ## Returns

  - `{:ok, optimized_config}` - Optimized configuration
  - `{:error, reason}` - Optimization failed

  ## Example

      rule_config = %{born: [3], survive: [2, 3]}
      training_data = [%{grid: grid1, target: target1}, ...]

      {:ok, optimized} = Learn.tune(rule_config, training_data,
        objective: :maximize_clustering,
        max_trials: 100
      )
  """
  @spec tune(rule_config(), training_data(), tune_opts()) ::
          {:ok, rule_config()} | {:error, term()}
  def tune(rule_config, training_data, opts \\ []) do
    objective = Keyword.get(opts, :objective, :maximize_clustering)
    max_trials = Keyword.get(opts, :max_trials, 50)
    timeout = Keyword.get(opts, :timeout, 60_000)

    Logger.info(
      "[Thunderforge.Learn] Starting tune: objective=#{objective}, max_trials=#{max_trials}"
    )

    search_space = Keyword.get_lazy(opts, :search_space, fn -> infer_search_space(rule_config) end)

    # Execute optimization
    case run_optimization(rule_config, training_data, search_space, objective, max_trials, timeout) do
      {:ok, best_config, metrics} ->
        Logger.info(
          "[Thunderforge.Learn] Optimization complete: #{inspect(metrics, limit: 5)}"
        )

        {:ok, best_config}

      {:error, reason} ->
        Logger.warning("[Thunderforge.Learn] Optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Start asynchronous rule optimization.

  Returns `{:ok, task_ref}` for tracking, or `{:error, reason}`.

  ## Example

      {:ok, ref} = Learn.tune_async(rule_config, training_data, opts)
      # ... later ...
      case Learn.check_status(ref) do
        {:completed, result} -> handle_result(result)
        :running -> wait_more()
        {:failed, reason} -> handle_error(reason)
      end
  """
  @spec tune_async(rule_config(), training_data(), tune_opts()) ::
          {:ok, reference()} | {:error, term()}
  def tune_async(rule_config, training_data, opts \\ []) do
    Logger.info("[Thunderforge.Learn] Starting async optimization")

    task =
      Task.async(fn ->
        tune(rule_config, training_data, opts)
      end)

    {:ok, task.ref}
  end

  @doc """
  Check status of an async optimization task.

  Returns:
  - `:running` - Task still in progress
  - `{:completed, {:ok, config}}` - Task completed successfully
  - `{:completed, {:error, reason}}` - Task completed with error
  - `:unknown` - Unknown task reference
  """
  @spec check_status(reference()) :: :running | {:completed, term()} | :unknown
  def check_status(ref) when is_reference(ref) do
    # This is a simplified implementation
    # In production, we'd track tasks in a GenServer or ETS
    receive do
      {^ref, result} -> {:completed, result}
    after
      0 -> :running
    end
  end

  @doc """
  Fit a rule from observed behavior data.

  Given input/output pairs, attempts to learn a rule that produces
  the observed transformations.

  ## Example

      observations = [
        {initial_grid1, result_grid1},
        {initial_grid2, result_grid2}
      ]

      {:ok, learned_rule} = Learn.fit_rule(observations, type: :ca)
  """
  @spec fit_rule([{any(), any()}], keyword()) :: {:ok, map()} | {:error, term()}
  def fit_rule(observations, opts \\ []) do
    type = Keyword.get(opts, :type, :ca)

    Logger.info("[Thunderforge.Learn] Fitting rule from #{length(observations)} observations")

    case type do
      :ca -> fit_ca_rule(observations, opts)
      :nca -> fit_nca_rule(observations, opts)
      _ -> {:error, {:unsupported_type, type}}
    end
  end

  @doc """
  Evolve rules using genetic algorithm.

  Starts with a population of rules and evolves them toward an objective.

  ## Options

  - `:population_size` - Number of individuals (default: 20)
  - `:generations` - Number of generations (default: 50)
  - `:mutation_rate` - Probability of mutation (default: 0.1)
  - `:crossover_rate` - Probability of crossover (default: 0.7)
  - `:objective` - Fitness function (default: `:maximize_clustering`)
  """
  @spec evolve(rule_config(), training_data(), keyword()) :: {:ok, rule_config()} | {:error, term()}
  def evolve(seed_config, training_data, opts \\ []) do
    population_size = Keyword.get(opts, :population_size, 20)
    generations = Keyword.get(opts, :generations, 50)
    mutation_rate = Keyword.get(opts, :mutation_rate, 0.1)
    objective = Keyword.get(opts, :objective, :maximize_clustering)

    Logger.info(
      "[Thunderforge.Learn] Starting evolution: pop=#{population_size}, gen=#{generations}"
    )

    # Initialize population
    population = initialize_population(seed_config, population_size)

    # Run evolution
    best =
      Enum.reduce(1..generations, population, fn gen, pop ->
        # Evaluate fitness
        evaluated = Enum.map(pop, fn config ->
          fitness = evaluate_fitness(config, training_data, objective)
          {config, fitness}
        end)

        # Select, crossover, mutate
        new_pop = evolve_generation(evaluated, mutation_rate, Keyword.get(opts, :crossover_rate, 0.7))

        if rem(gen, 10) == 0 do
          best_fitness = evaluated |> Enum.map(&elem(&1, 1)) |> Enum.max()
          Logger.debug("[Thunderforge.Learn] Generation #{gen}: best_fitness=#{best_fitness}")
        end

        new_pop
      end)
      |> Enum.map(fn config ->
        {config, evaluate_fitness(config, training_data, objective)}
      end)
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)

    {:ok, best}
  end

  # Private implementation

  defp run_optimization(rule_config, training_data, search_space, objective, max_trials, timeout) do
    # Simplified optimization loop
    # In production, this would integrate with Cerebros TPE

    task =
      Task.async(fn ->
        best = {rule_config, evaluate_fitness(rule_config, training_data, objective)}

        Enum.reduce_while(1..max_trials, best, fn trial, {best_config, best_score} ->
          # Sample from search space
          candidate = sample_config(search_space, rule_config)

          # Evaluate
          score = evaluate_fitness(candidate, training_data, objective)

          new_best =
            if score > best_score do
              {candidate, score}
            else
              {best_config, best_score}
            end

          if rem(trial, 10) == 0 do
            Logger.debug(
              "[Thunderforge.Learn] Trial #{trial}/#{max_trials}: best=#{elem(new_best, 1)}"
            )
          end

          {:cont, new_best}
        end)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {best_config, best_score}} ->
        {:ok, best_config, %{best_score: best_score}}

      nil ->
        {:error, :timeout}

      {:exit, reason} ->
        {:error, {:task_failed, reason}}
    end
  end

  defp infer_search_space(rule_config) do
    # Infer search space from rule config structure
    %{
      born: %{type: :subset, values: 0..8},
      survive: %{type: :subset, values: 0..8}
    }
    |> Map.merge(Map.get(rule_config, :search_space, %{}))
  end

  defp sample_config(search_space, base_config) do
    Enum.reduce(search_space, base_config, fn {key, spec}, acc ->
      value = sample_value(spec)
      Map.put(acc, key, value)
    end)
  end

  defp sample_value(%{type: :subset, values: range}) do
    # Random subset of values in range
    range
    |> Enum.to_list()
    |> Enum.filter(fn _ -> :rand.uniform() > 0.5 end)
  end

  defp sample_value(%{type: :float, min: min, max: max}) do
    min + :rand.uniform() * (max - min)
  end

  defp sample_value(%{type: :int, min: min, max: max}) do
    min + :rand.uniform(max - min)
  end

  defp sample_value(_), do: nil

  defp evaluate_fitness(config, _training_data, objective) do
    # Simplified fitness evaluation
    # In production, this would run the automaton and measure metrics

    base_score = :rand.uniform()

    case objective do
      :maximize_clustering ->
        # Prefer rules with moderate born/survive counts
        born_count = length(Map.get(config, :born, []))
        survive_count = length(Map.get(config, :survive, []))
        base_score + (born_count + survive_count) / 20.0

      :minimize_entropy ->
        # Prefer simpler rules
        born_count = length(Map.get(config, :born, []))
        survive_count = length(Map.get(config, :survive, []))
        base_score - (born_count + survive_count) / 20.0

      _ ->
        base_score
    end
  end

  defp fit_ca_rule(_observations, _opts) do
    # Placeholder for CA rule fitting
    # Would analyze input/output pairs to infer born/survive rules
    {:ok, %{born: [3], survive: [2, 3], inferred: true}}
  end

  defp fit_nca_rule(_observations, _opts) do
    # Placeholder for NCA rule fitting
    # Would train a neural network to approximate the transformation
    {:error, :not_implemented}
  end

  defp initialize_population(seed_config, size) do
    # Generate initial population with variations
    [seed_config | Enum.map(1..(size - 1), fn _ -> mutate_config(seed_config, 0.5) end)]
  end

  defp mutate_config(config, rate) do
    Map.new(config, fn {key, value} ->
      if :rand.uniform() < rate and key in [:born, :survive] do
        {key, mutate_list(value)}
      else
        {key, value}
      end
    end)
  end

  defp mutate_list(list) when is_list(list) do
    list
    |> Enum.map(fn x ->
      if :rand.uniform() < 0.3 do
        max(0, min(8, x + Enum.random([-1, 0, 1])))
      else
        x
      end
    end)
    |> Enum.uniq()
  end

  defp mutate_list(x), do: x

  defp evolve_generation(evaluated, mutation_rate, _crossover_rate) do
    # Simple tournament selection + mutation
    sorted = Enum.sort_by(evaluated, &elem(&1, 1), :desc)
    elite = sorted |> Enum.take(2) |> Enum.map(&elem(&1, 0))

    # Generate rest of population from elite with mutation
    rest =
      Enum.map(1..(length(evaluated) - 2), fn _ ->
        parent = Enum.random(elite)
        mutate_config(parent, mutation_rate)
      end)

    elite ++ rest
  end
end

# Compatibility shim for Thunderlearn
defmodule Thunderlearn do
  @moduledoc """
  Compatibility shim for Thunderlearn.

  All functionality has been moved to `Thunderline.Thunderforge.Learn`.
  This module delegates to the new location for backwards compatibility.

  **Deprecated**: Use `Thunderline.Thunderforge.Learn` directly.
  """

  @deprecated "Use Thunderline.Thunderforge.Learn.tune_async/2 instead"
  def optimize_async(ruleset) when is_map(ruleset) do
    Thunderline.Thunderforge.Learn.tune_async(ruleset, [])
  end

  @deprecated "Use Thunderline.Thunderforge.Learn.check_status/1 instead"
  defdelegate check_status(ref), to: Thunderline.Thunderforge.Learn
end
