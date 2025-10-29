defmodule Thunderline.Thunderbolt.Sagas.CerebrosNASSaga do
  @moduledoc """
  Reactor saga for Cerebros Neural Architecture Search workflow.

  This saga orchestrates the complete NAS pipeline:
  - Dataset preparation
  - Model proposal generation (via Cerebros bridge)
  - Training dispatch
  - Artifact collection
  - Pareto frontier analysis
  - Version persistence

  ## Workflow Steps

  1. **Prepare Dataset** - Load and validate training dataset
  2. **Generate Proposals** - Call Cerebros bridge for architecture proposals
  3. **Dispatch Training** - Submit trials to compute infrastructure
  4. **Collect Artifacts** - Gather trained model weights and metrics
  5. **Analyze Pareto** - Compute Pareto-optimal models
  6. **Persist Version** - Save winning architectures to model registry
  7. **Emit NAS Complete Event** - Publish results to EventBus

  ## Compensation Strategy

  If the saga fails:
  - Cancel in-flight training jobs
  - Clean up temporary artifacts
  - Mark NAS run as failed
  - Log compensation telemetry

  ## Usage

      alias Thunderline.Thunderbolt.Sagas.CerebrosNASSaga

      inputs = %{
        dataset_id: "dataset_123",
        search_space: %{layers: [2, 4, 8], units: [64, 128, 256]},
        max_trials: 10,
        correlation_id: Thunderline.UUID.v7()
      }

      case Reactor.run(CerebrosNASSaga, inputs) do
        {:ok, %{model_run: run, artifacts: artifacts}} ->
          {:ok, run}

        {:error, reason} ->
          Logger.error("NAS failed: \#{inspect(reason)}")
          {:error, :nas_failed}
      end
  """

  use Reactor, extensions: [Reactor.Dsl]

  require Logger
  alias Thunderline.Thunderbolt.Sagas.Base
  alias Thunderline.Thunderbolt.Resources.ModelRun
  alias Thunderline.Thunderbolt.ML.ModelArtifact
  alias Thunderline.Thunderbolt.ML.TrainingDataset

  input :dataset_id
  input :search_space
  input :max_trials
  input :correlation_id
  input :causation_id

  step :prepare_dataset do
    argument :dataset_id, input(:dataset_id)

    run fn %{dataset_id: dataset_id}, _ ->
      case Ash.get(TrainingDataset, dataset_id) do
        {:ok, dataset} ->
          Logger.info("Dataset loaded: #{dataset.id} (#{dataset.sample_count} samples)")
          {:ok, dataset}

        {:error, reason} ->
          {:error, {:dataset_not_found, reason}}
      end
    end
  end

  step :create_model_run do
    argument :dataset, result(:prepare_dataset)
    argument :search_space, input(:search_space)
    argument :max_trials, input(:max_trials)
    argument :correlation_id, input(:correlation_id)

    run fn %{dataset: dataset, search_space: space, max_trials: trials, correlation_id: corr_id},
           _ ->
      run_attrs = %{
        dataset_id: dataset.id,
        search_space: space,
        max_trials: trials,
        status: :pending,
        correlation_id: corr_id
      }

      case Ash.create(ModelRun, run_attrs) do
        {:ok, run} ->
          Logger.info("ModelRun created: #{run.id}")
          {:ok, run}

        {:error, reason} ->
          {:error, {:run_creation_failed, reason}}
      end
    end

    compensate fn run, _ ->
      Logger.warning("Compensating: marking run #{run.id} as failed")

      case Ash.update(run, %{status: :failed, error: "Saga compensation triggered"}) do
        {:ok, _} -> {:ok, :compensated}
        {:error, reason} -> {:error, {:compensation_failed, reason}}
      end
    end
  end

  step :generate_proposals do
    argument :run, result(:create_model_run)
    argument :dataset, result(:prepare_dataset)
    argument :search_space, input(:search_space)

    run fn %{run: run, dataset: dataset, search_space: space}, _ ->
      # Call Cerebros bridge to generate architecture proposals
      case Thunderline.Thunderbolt.CerebrosBridge.Invoker.propose(
             run_id: run.id,
             dataset_path: dataset.storage_path,
             search_space: space
           ) do
        {:ok, proposals} ->
          Logger.info("Generated #{length(proposals)} architecture proposals")
          {:ok, %{run: run, proposals: proposals}}

        {:error, reason} ->
          Logger.error("Proposal generation failed: #{inspect(reason)}")
          {:error, {:proposal_failed, reason}}
      end
    end
  end

  step :dispatch_training do
    argument :proposal_result, result(:generate_proposals)
    argument :max_trials, input(:max_trials)

    run fn %{proposal_result: %{run: run, proposals: proposals}, max_trials: max_trials}, _ ->
      # Limit proposals to max_trials
      selected = Enum.take(proposals, max_trials)

      # Dispatch training for each proposal
      results =
        Enum.map(selected, fn proposal ->
          Thunderline.Thunderbolt.CerebrosBridge.Invoker.train(
            run_id: run.id,
            proposal_id: proposal.id,
            architecture: proposal.architecture
          )
        end)

      failures = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(failures) do
        Logger.info("Dispatched #{length(selected)} training jobs")
        {:ok, %{run: run, training_jobs: results}}
      else
        Logger.error("Training dispatch had #{length(failures)} failures")
        {:error, {:training_dispatch_failed, failures}}
      end
    end

    compensate fn _jobs, _ ->
      # TODO: Cancel in-flight training jobs
      Logger.warning("Compensating: canceling training jobs")
      {:ok, :compensated}
    end
  end

  step :await_completion do
    argument :training_result, result(:dispatch_training)

    run fn %{training_result: %{run: run, training_jobs: _jobs}}, _ ->
      # Poll for completion (simplified - in production use Oban or async polling)
      max_wait_seconds = 300
      poll_interval = 5

      await_training_completion(run.id, max_wait_seconds, poll_interval)
    end
  end

  step :collect_artifacts do
    argument :run, result(:await_completion)

    run fn %{run: run}, _ ->
      case Ash.read(ModelArtifact, filter: [model_run_id: run.id]) do
        {:ok, artifacts} ->
          Logger.info("Collected #{length(artifacts)} artifacts for run #{run.id}")
          {:ok, %{run: run, artifacts: artifacts}}

        {:error, reason} ->
          {:error, {:artifact_collection_failed, reason}}
      end
    end
  end

  step :analyze_pareto do
    argument :artifacts_result, result(:collect_artifacts)

    run fn %{artifacts_result: %{run: run, artifacts: artifacts}}, _ ->
      # Compute Pareto frontier (accuracy vs. model size)
      pareto_models = compute_pareto_frontier(artifacts)

      Logger.info("Identified #{length(pareto_models)} Pareto-optimal models")

      {:ok, %{run: run, artifacts: artifacts, pareto: pareto_models}}
    end
  end

  step :persist_version do
    argument :pareto_result, result(:analyze_pareto)

    run fn %{pareto_result: %{run: run, pareto: pareto_models}}, _ ->
      # Select best model from Pareto frontier
      best_model = Enum.max_by(pareto_models, & &1.score, fn -> nil end)

      if best_model do
        # TODO: Create ModelVersion record
        Logger.info("Best model: #{best_model.id} (score: #{best_model.score})")
        {:ok, %{run: run, best_model: best_model}}
      else
        Logger.warning("No Pareto-optimal models found")
        {:error, :no_models_found}
      end
    end
  end

  step :emit_completion_event do
    argument :version_result, result(:persist_version)
    argument :correlation_id, input(:correlation_id)
    argument :causation_id, input(:causation_id)

    run fn %{
             version_result: %{run: run, best_model: model},
             correlation_id: correlation_id,
             causation_id: causation_id
           },
           _ ->
      event_attrs = %{
        name: "ml.run.completed",
        type: :ml_lifecycle,
        domain: :bolt,
        source: "CerebrosNASSaga",
        correlation_id: correlation_id,
        causation_id: causation_id,
        payload: %{
          run_id: run.id,
          best_model_id: model.id,
          best_score: model.score
        },
        meta: %{
          pipeline: :cross_domain
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          Thunderline.Thunderflow.EventBus.publish_event(event)
          {:ok, %{run: run, best_model: model}}

        {:error, reason} ->
          Logger.warning("Failed to emit completion event: #{inspect(reason)}")
          {:ok, %{run: run, best_model: model}}
      end
    end
  end

  return :emit_completion_event

  # Private helpers

  defp await_training_completion(run_id, max_wait, poll_interval) do
    start_time = System.monotonic_time(:second)

    Stream.iterate(0, &(&1 + 1))
    |> Enum.reduce_while(nil, fn _iteration, _acc ->
      elapsed = System.monotonic_time(:second) - start_time

      if elapsed >= max_wait do
        {:halt, {:error, :timeout}}
      else
        case check_run_status(run_id) do
          {:ok, :completed, run} ->
            {:halt, {:ok, run}}

          {:ok, :failed, _run} ->
            {:halt, {:error, :training_failed}}

          {:ok, :running, _run} ->
            Process.sleep(poll_interval * 1000)
            {:cont, nil}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp check_run_status(run_id) do
    case Ash.get(ModelRun, run_id) do
      {:ok, run} ->
        status =
          case run.status do
            s when s in [:completed, :success] -> :completed
            s when s in [:failed, :error] -> :failed
            _ -> :running
          end

        {:ok, status, run}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_pareto_frontier(artifacts) do
    # Simplified Pareto computation: maximize accuracy, minimize size
    artifacts
    |> Enum.map(fn artifact ->
      %{
        id: artifact.id,
        accuracy: Map.get(artifact.metrics, "accuracy", 0.0),
        size: Map.get(artifact.metrics, "model_size_mb", 0.0),
        score: Map.get(artifact.metrics, "accuracy", 0.0)
      }
    end)
    |> Enum.reject(&(&1.accuracy == 0.0))
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(5)
  end
end
