defmodule Thunderline.Thundervine.Thunderoll.Nodes do
  @moduledoc """
  Behavior DAG node handlers for Thunderoll optimization loops.

  These handlers integrate with the Thundervine Executor to orchestrate
  EGGROLL optimization as a composable behavior graph.

  ## Node Types

  - `:thunderoll_init` - Initialize experiment and runner
  - `:thunderoll_generation` - Run one generation of optimization
  - `:thunderoll_apply_update` - Apply parameter delta to target
  - `:thunderoll_check_convergence` - Check if optimization should continue

  ## Example Graph

  ```
  init -> generation -> apply_update -> check_convergence
                ^                              |
                |______________________________|
                       (loop until converged)
  ```
  """
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.Init do
  @moduledoc """
  Initialize a Thunderoll optimization experiment.

  Creates the runner state and optionally persists an Experiment record.

  ## Config

  - `:base_params` - Base model parameters (required)
  - `:population_size` - Population size (required)
  - `:fitness_spec` - Fitness specification (required)
  - `:policy_context` - Thundercrown context (required)
  - `:rank` - Low-rank dimension (default: 1)
  - `:sigma` - Perturbation std (default: 0.02)
  - `:backend` - Compute backend (default: :nx_native)
  - `:persist?` - Whether to create DB record (default: false)
  - `:name` - Experiment name (required if persist?)
  """

  alias Thunderline.Thundervine.Thunderoll.Runner

  require Logger

  @doc """
  Execute the init node.

  Returns `{:ok, output}` with runner state, or `{:error, reason}`.
  """
  def execute(%{config: config}, _context) do
    Logger.info("[Thunderoll.Node.Init] Initializing experiment")

    case Runner.init(config) do
      {:ok, runner} ->
        output = %{
          experiment_id: runner.experiment_id,
          runner: runner,
          generation: 0
        }

        Logger.info(
          "[Thunderoll.Node.Init] Experiment initialized: #{inspect(runner.experiment_id)}"
        )

        {:ok, output}

      {:error, reason} ->
        Logger.error("[Thunderoll.Node.Init] Failed to initialize: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.Generation do
  @moduledoc """
  Run one generation of EGGROLL optimization.

  Samples perturbations, evaluates fitness, and computes the aggregated update.

  ## Input

  - `:runner` - Runner state from init or previous generation

  ## Output

  - `:delta` - Parameter delta
  - `:runner` - Updated runner state
  - `:converged` - Boolean indicating if optimization has converged
  - `:fitness_stats` - Statistics from this generation
  """

  alias Thunderline.Thundervine.Thunderoll.Runner

  require Logger

  @doc """
  Execute the generation node.
  """
  def execute(%{runner: runner}, _context) do
    Logger.info("[Thunderoll.Node.Generation] Starting generation #{runner.generation}")

    case Runner.run_generation(runner) do
      {:ok, delta, new_runner} ->
        converged = Runner.converged?(new_runner)

        output = %{
          delta: delta,
          runner: new_runner,
          converged: converged,
          generation: new_runner.generation,
          fitness_stats: %{
            # Stats would come from the runner in full implementation
            generation: new_runner.generation
          }
        }

        Logger.info(
          "[Thunderoll.Node.Generation] Generation #{runner.generation} complete, " <>
            "converged=#{converged}"
        )

        {:ok, output}

      {:error, reason} ->
        Logger.error("[Thunderoll.Node.Generation] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.ApplyUpdate do
  @moduledoc """
  Apply the aggregated parameter delta to the target model/PAC.

  ## Input

  - `:delta` - Parameter delta from generation node
  - `:runner` - Runner state with base params
  - `:target_ref` - Optional external target reference

  ## Output

  - `:applied` - Boolean success indicator
  - `:updated_params` - The new parameter values
  """

  alias Thunderline.Thundervine.Thunderoll.Runner

  require Logger

  @doc """
  Execute the apply update node.
  """
  def execute(%{delta: delta, runner: runner} = input, _context) do
    Logger.info("[Thunderoll.Node.ApplyUpdate] Applying delta to base params")

    case Runner.apply_update(runner, delta) do
      {:ok, updated_params} ->
        # If there's an external target, apply there too
        if target_ref = input[:target_ref] do
          apply_to_external_target(target_ref, delta)
        end

        output = %{
          applied: true,
          updated_params: updated_params,
          # Update runner with new base params for next generation
          runner: %{runner | base_params: updated_params}
        }

        Logger.info("[Thunderoll.Node.ApplyUpdate] Delta applied successfully")
        {:ok, output}
    end
  end

  defp apply_to_external_target(target_ref, _delta) do
    # In full implementation, this would:
    # 1. Look up the PAC/model by reference
    # 2. Apply the delta to its parameters
    # 3. Persist the updated parameters
    Logger.debug("[Thunderoll.Node.ApplyUpdate] Would apply to external target: #{target_ref}")
    :ok
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.CheckConvergence do
  @moduledoc """
  Check if optimization has converged and determine next action.

  ## Input

  - `:converged` - Boolean from generation node
  - `:runner` - Runner state
  - `:generation` - Current generation number

  ## Output

  - `:action` - `:continue` or `:complete`
  - `:final_generation` - Generation number (if complete)
  - `:reason` - Convergence reason (if complete)
  """

  require Logger

  @doc """
  Execute the convergence check node.
  """
  def execute(%{converged: converged, runner: runner, generation: generation}, _context) do
    if converged do
      reason = determine_convergence_reason(runner)

      output = %{
        action: :complete,
        final_generation: generation,
        reason: reason
      }

      Logger.info(
        "[Thunderoll.Node.CheckConvergence] Converged at generation #{generation}: #{reason}"
      )

      {:ok, output}
    else
      output = %{
        action: :continue,
        next_generation: generation + 1
      }

      Logger.debug(
        "[Thunderoll.Node.CheckConvergence] Continuing to generation #{generation + 1}"
      )

      {:ok, output}
    end
  end

  defp determine_convergence_reason(runner) do
    cond do
      runner.generation >= runner.convergence_criteria.max_generations ->
        :max_generations_reached

      # Future: Add fitness plateau detection
      true ->
        :unknown
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.Complete do
  @moduledoc """
  Finalize a completed Thunderoll experiment.

  Records final results and optionally triggers downstream actions.

  ## Input

  - `:runner` - Final runner state
  - `:final_generation` - Last generation number
  - `:reason` - Convergence reason

  ## Output

  - `:experiment_id` - Experiment identifier
  - `:total_generations` - Number of generations completed
  - `:final_params` - Optimized parameters
  """

  alias Thunderline.Thundervine.Thunderoll.Runner

  require Logger

  @doc """
  Execute the completion node.
  """
  def execute(%{runner: runner, final_generation: final_gen, reason: reason}, _context) do
    Logger.info(
      "[Thunderoll.Node.Complete] Experiment complete after #{final_gen} generations " <>
        "(reason: #{reason})"
    )

    summary = Runner.state_summary(runner)

    output = %{
      experiment_id: runner.experiment_id,
      total_generations: final_gen,
      final_params: runner.base_params,
      summary: summary,
      completed_at: DateTime.utc_now()
    }

    # Emit completion telemetry
    :telemetry.execute(
      [:thunderline, :vine, :thunderoll, :experiment_complete],
      %{
        generations: final_gen,
        population_size: runner.population_size
      },
      %{
        experiment_id: runner.experiment_id,
        reason: reason
      }
    )

    {:ok, output}
  end
end
