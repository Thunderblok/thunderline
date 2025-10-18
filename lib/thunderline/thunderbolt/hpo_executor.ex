defmodule Thunderline.Thunderbolt.HPOExecutor do
  @moduledoc """
  HPO Executor worker for running individual trials.

  Designed to scale-to-zero using Oban workers.
  Each trial runs independently and reports back via HTTP.
  """

  use Oban.Worker, queue: :hpo_trials, max_attempts: 3
  require Logger
  alias Thunderline.Thunderbolt.AutoMLDriver

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"study_id" => study_id, "trial_id" => trial_id, "suggestion" => suggestion}
      }) do
    Logger.info("[HPOExecutor] Starting trial #{trial_id} for study #{study_id}")

    try do
      # Execute training with suggested hyperparameters
      result = execute_training(suggestion)

      # Report result back to AutoMLDriver
      AutoMLDriver.tell_result(study_id, trial_id, result.objective, result.artifact)

      Logger.info(
        "[HPOExecutor] Completed trial #{trial_id}: perplexity=#{result.objective["perplexity"]}"
      )

      :ok
    rescue
      error ->
        Logger.error("[HPOExecutor] Trial #{trial_id} failed: #{inspect(error)}")

        # Report failure
        AutoMLDriver.tell_result(study_id, trial_id, %{
          "perplexity" => 999.0,
          "error" => inspect(error)
        })

        {:error, error}
    end
  end

  # Public API
  def execute_trial(study_id, trial_id, suggestion) do
    %{
      "study_id" => study_id,
      "trial_id" => trial_id,
      "suggestion" => suggestion
    }
    |> new()
    |> Oban.insert()

    :ok
  end

  # Private Functions
  defp execute_training(suggestion) do
    Logger.info("[HPOExecutor] Training with params: #{inspect(suggestion)}")

    # TODO: Replace with actual model training
    # For now, simulate training with random results
    # 10-40 seconds
    training_time = :rand.uniform(30_000) + 10_000
    Process.sleep(training_time)

    # Simulate perplexity result (lower is better)
    base_perplexity = 15.0
    param_quality = calculate_param_quality(suggestion)
    # ±2.0 noise
    noise = (:rand.uniform() - 0.5) * 4.0

    perplexity = base_perplexity - param_quality + noise
    # Floor at 2.0
    perplexity = max(perplexity, 2.0)

    # 50-250ms per token
    gen_time_ms = :rand.uniform(200) + 50

    # Simulate MLflow artifact
    mlflow_run_id = "run-#{System.unique_integer([:positive])}"

    %{
      objective: %{
        "perplexity" => Float.round(perplexity, 2),
        "gen_time_ms_per_tok" => gen_time_ms
      },
      artifact: %{
        "mlflow_run_id" => mlflow_run_id,
        "model_path" => "models/#{mlflow_run_id}/model.keras",
        "training_time_sec" => div(training_time, 1000)
      }
    }
  end

  defp calculate_param_quality(suggestion) do
    # Simulate how "good" the hyperparameters are
    # Higher embedding_dim and optimal lr range = better

    embedding_bonus = (suggestion["embedding_dim"] - 256) / 256 * 2.0

    lr_bonus =
      case suggestion["lr"] do
        # Sweet spot
        lr when lr >= 0.0001 and lr <= 0.0005 -> 2.0
        # OK range
        lr when lr >= 0.00005 and lr <= 0.001 -> 1.0
        # Poor range
        _ -> 0.0
      end

    layer_bonus =
      case suggestion["n_layers"] do
        layers when layers >= 6 and layers <= 8 -> 1.5
        layers when layers >= 4 and layers <= 10 -> 0.5
        _ -> 0.0
      end

    embedding_bonus + lr_bonus + layer_bonus
  end
end
