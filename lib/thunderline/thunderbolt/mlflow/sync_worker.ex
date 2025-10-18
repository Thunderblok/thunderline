defmodule Thunderline.Thunderbolt.MLflow.SyncWorker do
  @moduledoc """
  Oban worker for synchronizing trial data with MLflow tracking server.

  Handles:
  - Creating MLflow runs from Thunderline trials
  - Syncing trial metrics/params to MLflow
  - Pulling MLflow run data back to Thunderline
  - Batch syncing entire experiments

  ## Job Types
  - `:sync_trial_to_mlflow` - Push trial data to MLflow
  - `:sync_mlflow_to_trial` - Pull MLflow run data to trial
  - `:sync_experiment` - Sync all runs in an experiment
  - `:create_run` - Create MLflow run for new trial
  """

  use Oban.Worker,
    queue: :mlflow_sync,
    max_attempts: 5,
    priority: 2

  require Logger
  require Ash.Query

  alias Thunderline.Thunderbolt.MLflow.{Client, Experiment, Run}
  alias Thunderline.Thunderbolt.Resources.{ModelTrial, ModelRun}
  alias Thunderline.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "sync_trial_to_mlflow", "trial_id" => trial_id}}) do
    with {:ok, trial} <- load_trial(trial_id),
         {:ok, mlflow_run} <- ensure_mlflow_run(trial),
         :ok <- sync_metrics(mlflow_run, trial),
         :ok <- sync_params(mlflow_run, trial),
         :ok <- sync_status(mlflow_run, trial),
         {:ok, _run} <- update_sync_timestamp(mlflow_run) do
      {:ok, %{synced_trial: trial_id, mlflow_run: mlflow_run.mlflow_run_id}}
    else
      {:error, :mlflow_disabled} ->
        {:cancel, "MLflow integration disabled"}

      {:error, reason} = error ->
        Logger.error("Failed to sync trial #{trial_id} to MLflow: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{args: %{"action" => "sync_mlflow_to_trial", "mlflow_run_id" => run_id}}) do
    with {:ok, mlflow_data} <- Client.get_run(run_id),
         {:ok, local_run} <- find_or_create_local_run(mlflow_data),
         {:ok, trial} <- maybe_update_trial(local_run, mlflow_data),
         {:ok, _run} <- update_local_run(local_run, mlflow_data) do
      {:ok, %{synced_run: run_id, trial_id: trial && trial.id}}
    else
      {:error, :not_found} ->
        {:cancel, "MLflow run #{run_id} not found"}

      {:error, reason} = error ->
        Logger.error("Failed to sync MLflow run #{run_id} to trial: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{
        args: %{"action" => "sync_experiment", "experiment_id" => experiment_id}
      }) do
    with {:ok, experiment} <- get_or_fetch_experiment(experiment_id),
         {:ok, runs} <- list_experiment_runs(experiment),
         results <- sync_runs_batch(runs) do
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      failure_count = Enum.count(results, &match?({:error, _}, &1))

      Logger.info(
        "Synced experiment #{experiment_id}: #{success_count} success, #{failure_count} failures"
      )

      {:ok, %{synced: success_count, failed: failure_count}}
    end
  end

  def perform(%Oban.Job{
        args: %{
          "action" => "create_run",
          "trial_id" => trial_id,
          "experiment_id" => experiment_id
        }
      }) do
    with {:ok, trial} <- load_trial(trial_id),
         {:ok, mlflow_run_data} <- create_mlflow_run(trial, experiment_id),
         {:ok, local_run} <- create_local_run(trial, mlflow_run_data) do
      Logger.info("Created MLflow run #{mlflow_run_data.run_id} for trial #{trial_id}")
      {:ok, %{mlflow_run_id: mlflow_run_data.run_id, local_run_id: local_run.id}}
    else
      {:error, reason} = error ->
        Logger.error("Failed to create MLflow run for trial #{trial_id}: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("Unknown MLflow sync action: #{inspect(args)}")
    {:cancel, "Unknown action"}
  end

  # -- Public API for queueing jobs --

  @doc """
  Queue a job to sync trial data to MLflow.
  Creates MLflow run if it doesn't exist.
  """
  def sync_trial_to_mlflow(trial_id, opts \\ []) do
    %{action: "sync_trial_to_mlflow", trial_id: trial_id}
    |> new(opts)
    |> Oban.insert()
  end

  @doc """
  Queue a job to pull MLflow run data to Thunderline trial.
  """
  def sync_mlflow_to_trial(mlflow_run_id, opts \\ []) do
    %{action: "sync_mlflow_to_trial", mlflow_run_id: mlflow_run_id}
    |> new(opts)
    |> Oban.insert()
  end

  @doc """
  Queue a job to sync all runs in an experiment.
  """
  def sync_experiment(experiment_id, opts \\ []) do
    %{action: "sync_experiment", experiment_id: experiment_id}
    |> new(opts)
    |> Oban.insert()
  end

  @doc """
  Queue a job to create a new MLflow run for a trial.
  """
  def create_run(trial_id, experiment_id, opts \\ []) do
    %{action: "create_run", trial_id: trial_id, experiment_id: experiment_id}
    |> new(opts)
    |> Oban.insert()
  end

  # -- Sync implementation --

  defp ensure_mlflow_run(trial) do
    case trial.mlflow_run_id do
      nil ->
        # No MLflow run linked yet, need to create one
        {:error, :no_mlflow_run}

      mlflow_run_id ->
        # Find existing local Run record
        Run
        |> Ash.Query.filter(mlflow_run_id == ^mlflow_run_id)
        |> Ash.read_one()
        |> case do
          {:ok, nil} ->
            # Local record doesn't exist, create it
            create_local_run_from_trial(trial)

          {:ok, run} ->
            {:ok, run}

          error ->
            error
        end
    end
  end

  defp create_local_run_from_trial(trial) do
    attrs = %{
      mlflow_run_id: trial.mlflow_run_id,
      mlflow_experiment_id: trial.experiment_id || "default",
      model_trial_id: trial.id,
      model_run_id: trial.model_run_id,
      run_name: "trial_#{trial.id}",
      status: map_trial_status(trial.status),
      params: trial.hyperparameters || %{},
      metrics: extract_metrics(trial),
      tags: %{"thunderline_trial_id" => trial.id}
    }

    Run.create(attrs)
  end

  defp sync_metrics(mlflow_run, trial) do
    metrics = extract_metrics(trial)

    if map_size(metrics) > 0 do
      Client.log_batch_metrics(mlflow_run.mlflow_run_id, metrics)
    else
      :ok
    end
  end

  defp sync_params(mlflow_run, trial) do
    params = trial.hyperparameters || %{}

    # Add spectral_norm as a parameter if set
    params =
      if trial.spectral_norm do
        Map.put(params, "spectral_norm", "true")
      else
        params
      end

    if map_size(params) > 0 do
      Client.log_batch_params(mlflow_run.mlflow_run_id, params)
    else
      :ok
    end
  end

  defp sync_status(mlflow_run, trial) do
    mlflow_status = map_trial_status_to_mlflow(trial.status)

    if mlflow_status != mlflow_run.status do
      opts =
        if trial.completed_at do
          [end_time: DateTime.to_unix(trial.completed_at, :millisecond)]
        else
          []
        end

      Client.update_run(mlflow_run.mlflow_run_id, mlflow_status, opts)
    else
      :ok
    end
  end

  defp extract_metrics(trial) do
    metrics = %{}

    metrics =
      if trial.final_accuracy do
        Map.put(metrics, "accuracy", trial.final_accuracy)
      else
        metrics
      end

    metrics =
      if trial.final_loss do
        Map.put(metrics, "loss", trial.final_loss)
      else
        metrics
      end

    metrics =
      if trial.best_metric_value do
        Map.put(metrics, "best_metric", trial.best_metric_value)
      else
        metrics
      end

    metrics
  end

  defp map_trial_status(:pending), do: :scheduled
  defp map_trial_status(:running), do: :running
  defp map_trial_status(:completed), do: :finished
  defp map_trial_status(:failed), do: :failed
  defp map_trial_status(:cancelled), do: :killed
  defp map_trial_status(_), do: :running

  defp map_trial_status_to_mlflow(status),
    do: map_trial_status(status) |> to_string() |> String.upcase()

  defp create_mlflow_run(trial, experiment_id) do
    opts = [
      run_name: "trial_#{trial.id}",
      start_time: trial.started_at && DateTime.to_unix(trial.started_at, :millisecond),
      tags: %{
        "thunderline_trial_id" => trial.id,
        "thunderline_model_run_id" => trial.model_run_id,
        "spectral_norm" => to_string(trial.spectral_norm || false)
      }
    ]

    Client.create_run(experiment_id, opts)
  end

  defp create_local_run(trial, mlflow_run_data) do
    attrs = %{
      mlflow_run_id: mlflow_run_data.run_id,
      mlflow_experiment_id: trial.experiment_id || "default",
      model_trial_id: trial.id,
      model_run_id: trial.model_run_id,
      run_name: "trial_#{trial.id}",
      status: :running,
      params: trial.hyperparameters || %{},
      tags: %{"thunderline_trial_id" => trial.id}
    }

    Run.create(attrs)
  end

  defp find_or_create_local_run(mlflow_data) do
    Run
    |> Ash.Query.filter(mlflow_run_id == ^mlflow_data.run_id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} ->
        # Create local record
        attrs = %{
          mlflow_run_id: mlflow_data.run_id,
          mlflow_experiment_id: mlflow_data.experiment_id,
          run_name: mlflow_data.run_name,
          status: mlflow_data.status,
          start_time: mlflow_data.start_time,
          end_time: mlflow_data.end_time,
          artifact_uri: mlflow_data.artifact_uri,
          params: mlflow_data.params,
          metrics: mlflow_data.metrics,
          tags: mlflow_data.tags
        }

        Run.create(attrs)

      {:ok, run} ->
        {:ok, run}

      error ->
        error
    end
  end

  defp maybe_update_trial(local_run, _mlflow_data) do
    # If local run is linked to a trial, we could update trial with MLflow data
    # For now, skip - trials are source of truth
    if local_run.model_trial_id do
      load_trial(local_run.model_trial_id)
    else
      {:ok, nil}
    end
  end

  defp update_local_run(local_run, mlflow_data) do
    # Update local run with latest MLflow data
    changeset =
      Ash.Changeset.for_update(local_run, :update_metadata, %{
        status: mlflow_data.status,
        end_time: mlflow_data.end_time,
        params: mlflow_data.params,
        metrics: mlflow_data.metrics,
        tags: mlflow_data.tags
      })

    Ash.update(changeset)
  end

  defp update_sync_timestamp(mlflow_run) do
    changeset =
      Ash.Changeset.for_update(mlflow_run, :update_metadata, %{
        synced_at: DateTime.utc_now()
      })

    Ash.update(changeset)
  end

  defp get_or_fetch_experiment(experiment_id) do
    Experiment
    |> Ash.Query.filter(mlflow_experiment_id == ^experiment_id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} ->
        # Fetch from MLflow and create local record
        with {:ok, mlflow_exp} <- Client.get_experiment(experiment_id) do
          Experiment.create(%{
            mlflow_experiment_id: mlflow_exp.experiment_id,
            name: mlflow_exp.name,
            artifact_location: mlflow_exp.artifact_location,
            lifecycle_stage: mlflow_exp.lifecycle_stage,
            tags: mlflow_exp.tags
          })
        end

      result ->
        result
    end
  end

  defp list_experiment_runs(experiment) do
    Run
    |> Ash.Query.filter(mlflow_experiment_id == ^experiment.mlflow_experiment_id)
    |> Ash.read()
  end

  defp sync_runs_batch(runs) do
    Enum.map(runs, fn run ->
      if run.model_trial_id do
        case sync_trial_to_mlflow(run.model_trial_id, schedule_in: 0) do
          {:ok, _job} -> {:ok, run.id}
          error -> error
        end
      else
        {:ok, run.id}
      end
    end)
  end

  defp load_trial(trial_id) do
    ModelTrial
    |> Ash.Query.filter(id == ^trial_id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :trial_not_found}
      result -> result
    end
  end
end
