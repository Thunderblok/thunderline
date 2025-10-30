defmodule ThunderlineWeb.CerebrosJobsController do
  @moduledoc """
  REST API for Cerebros service coordination.

  Endpoints:
  - GET /api/jobs/poll - Poll for next queued job
  - PATCH /api/jobs/:id/status - Update job status
  - PATCH /api/jobs/:id/metrics - Update job metrics
  - POST /api/jobs/:id/checkpoints - Add checkpoint URL
  - GET /api/datasets/:id/corpus - Get dataset corpus path
  """
  use ThunderlineWeb, :controller
  alias Thunderline.Cerebros.Training.{Job, Dataset}
  require Logger

  action_fallback ThunderlineWeb.FallbackController

  @doc """
  Poll for the next queued job.

  GET /api/jobs/poll

  Returns the oldest queued job, or 204 No Content if no jobs available.
  """
  def poll(conn, _params) do
    Logger.debug("Job poll request")

    case get_next_queued_job() do
      nil ->
        Logger.debug("No queued jobs available")
        send_resp(conn, 204, "")

      job ->
        Logger.info("Returning queued job: #{job.id}")
        render(conn, :job, job: job)
    end
  end

  @doc """
  Update job status.

  PATCH /api/jobs/:id/status

  Body:
  {
    "status": "training",  // queued, training, completed, failed
    "error_message": "Optional error message"
  }
  """
  def update_status(conn, %{"id" => id} = params) do
    Logger.info("Updating job #{id} status to: #{params["status"]}")

    with {:ok, job} <- Job.by_id(id),
         update_params <- build_status_update_params(params),
         {:ok, updated_job} <- Job.update_status(job, update_params) do
      Logger.info("Job #{id} status updated successfully")
      render(conn, :ok, %{})
    end
  end

  @doc """
  Update job metrics.

  PATCH /api/jobs/:id/metrics

  Body:
  {
    "metrics": {
      "perplexity": 2.45,
      "loss": 0.123,
      "accuracy": 0.87
    },
    "phase": 10  // Optional: current epoch/phase
  }
  """
  def update_metrics(conn, %{"id" => id} = params) do
    Logger.debug("Updating job #{id} metrics")

    with {:ok, job} <- Job.by_id(id),
         update_params <- build_metrics_update_params(job, params),
         {:ok, updated_job} <- Job.update_progress(job, update_params) do
      render(conn, :ok, %{})
    end
  end

  @doc """
  Add checkpoint URL to job.

  POST /api/jobs/:id/checkpoints

  Body:
  {
    "checkpoint_url": "s3://bucket/path/to/checkpoint.keras"
  }
  """
  def add_checkpoint(conn, %{"id" => id, "checkpoint_url" => checkpoint_url}) do
    Logger.info("Adding checkpoint to job #{id}: #{checkpoint_url}")

    with {:ok, job} <- Job.by_id(id),
         current_checkpoints <- job.checkpoint_urls || [],
         new_checkpoints <- current_checkpoints ++ [checkpoint_url],
         {:ok, updated_job} <-
           Job.update_progress(job, %{checkpoint_urls: new_checkpoints}) do
      render(conn, :ok, %{})
    end
  end

  @doc """
  Get dataset corpus path.

  GET /api/datasets/:id/corpus

  Returns the JSONL corpus file path for the dataset.
  """
  def get_corpus(conn, %{"id" => id}) do
    Logger.debug("Fetching corpus path for dataset: #{id}")

    with {:ok, dataset} <- Dataset.by_id(id),
         {:ok, corpus_path} <- verify_corpus_exists(dataset) do
      render(conn, :corpus, corpus_path: corpus_path, dataset: dataset)
    end
  end

  # Private functions

  defp get_next_queued_job do
    Job.list_queued!()
    |> Enum.sort_by(& &1.created_at, {:asc, DateTime})
    |> List.first()
  end

  defp build_status_update_params(params) do
    base_params = %{
      status: params["status"]
    }

    case params["status"] do
      "training" ->
        Map.put(base_params, :started_at, DateTime.utc_now())

      "completed" ->
        base_params
        |> Map.put(:completed_at, DateTime.utc_now())
        |> maybe_put(:fine_tuned_model, params["fine_tuned_model"])

      "failed" ->
        base_params
        |> Map.put(:completed_at, DateTime.utc_now())
        |> Map.put(:error_message, params["error_message"] || "Unknown error")

      _ ->
        base_params
    end
    |> maybe_put(:error_message, params["error_message"])
  end

  defp build_metrics_update_params(job, params) do
    %{}
    |> maybe_put(:metrics, merge_metrics(job.metrics, params["metrics"]))
    |> maybe_put(:phase, params["phase"])
  end

  defp merge_metrics(existing, new) when is_map(existing) and is_map(new) do
    Map.merge(existing, new)
  end

  defp merge_metrics(_existing, new) when is_map(new), do: new
  defp merge_metrics(existing, _new), do: existing

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp verify_corpus_exists(dataset) do
    case dataset.corpus_path do
      nil ->
        {:error, "Dataset corpus not generated yet"}

      path ->
        if File.exists?(path) do
          {:ok, path}
        else
          Logger.error("Corpus file missing: #{path}")
          {:error, "Corpus file not found at: #{path}"}
        end
    end
  end
end
