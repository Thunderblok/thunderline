defmodule Thunderline.Thunderbolt.Workers.CerebrosTrainer do
  @moduledoc """
  Oban worker for sending training datasets to Cerebros service.

  Workflow:
  1. Load dataset and corpus CSVs
  2. POST to Cerebros training endpoint
  3. Poll for phase updates (1-4)
  4. Download checkpoints
  5. Update job status and checkpoints
  """

  use Oban.Worker,
    queue: :cerebros_training,
    max_attempts: 3

  alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
  require Logger

  @cerebros_base_url Application.compile_env(:thunderline, :cerebros_url, "http://localhost:8000")
  # 30 seconds
  @poll_interval_ms 30_000
  # 1 hour max
  @max_poll_attempts 120

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"training_dataset_id" => dataset_id, "job_id" => job_id}}) do
    Logger.info("Starting Cerebros training for dataset #{dataset_id}, job #{job_id}")

    with {:ok, dataset} <- get_dataset(dataset_id),
         {:ok, job} <- get_job(job_id),
         {:ok, job} <- start_job(job),
         {:ok, cerebros_job_id} <- submit_to_cerebros(dataset),
         {:ok, job} <- update_cerebros_job_id(job, cerebros_job_id),
         {:ok, job} <- poll_until_complete(job, cerebros_job_id) do
      Logger.info("Cerebros training completed for job #{job_id}")
      {:ok, job}
    else
      {:error, reason} = error ->
        Logger.error("Cerebros training failed for job #{job_id}: #{inspect(reason)}")

        # Mark job as failed
        case get_job(job_id) do
          {:ok, job} ->
            CerebrosTrainingJob.fail!(job, %{error_message: inspect(reason)})

          _ ->
            :ok
        end

        error
    end
  end

  @doc """
  Enqueue a training job for a dataset.
  """
  def enqueue_training(dataset_id, opts \\ []) do
    # Create job record
    {:ok, job} =
      CerebrosTrainingJob.create!(%{
        training_dataset_id: dataset_id,
        metadata: Keyword.get(opts, :metadata, %{})
      })

    # Enqueue Oban job
    %{
      "training_dataset_id" => dataset_id,
      "job_id" => job.id
    }
    |> new(
      queue: Keyword.get(opts, :queue, :cerebros_training),
      max_attempts: Keyword.get(opts, :max_attempts, 3)
    )
    |> Oban.insert()
  end

  defp get_dataset(dataset_id) do
    case Ash.get(TrainingDataset, dataset_id) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, _} -> {:error, :dataset_not_found}
    end
  end

  defp get_job(job_id) do
    case Ash.get(CerebrosTrainingJob, job_id) do
      {:ok, job} -> {:ok, job}
      {:error, _} -> {:error, :job_not_found}
    end
  end

  defp start_job(job) do
    {:ok, CerebrosTrainingJob.start!(job)}
  end

  defp submit_to_cerebros(dataset) do
    if !dataset.corpus_path do
      {:error, :no_corpus_path}
    else
      # Load CSV files
      csv_files = load_corpus_files(dataset.corpus_path)

      # Prepare request
      payload = %{
        dataset_id: dataset.id,
        dataset_name: dataset.name,
        csv_files: csv_files,
        config: %{
          phases: 4,
          # or "keras", "tensorflow"
          checkpoint_format: "onnx"
        }
      }

      # POST to Cerebros
      case http_post("/api/v1/training/submit", payload) do
        {:ok, %{"job_id" => job_id}} ->
          Logger.info("Submitted to Cerebros, job_id: #{job_id}")
          {:ok, job_id}

        {:ok, response} ->
          {:error, {:invalid_response, response}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp load_corpus_files(corpus_path) do
    csv_files = Path.wildcard(Path.join(corpus_path, "*.csv"))

    Enum.map(csv_files, fn file ->
      %{
        filename: Path.basename(file),
        content: File.read!(file)
      }
    end)
  end

  defp update_cerebros_job_id(job, cerebros_job_id) do
    {:ok, updated} = Ash.update(job, %{cerebros_job_id: cerebros_job_id})
    {:ok, updated}
  end

  defp poll_until_complete(job, cerebros_job_id, attempt \\ 0) do
    if attempt >= @max_poll_attempts do
      {:error, :timeout}
    else
      case check_cerebros_status(cerebros_job_id) do
        {:ok, %{"status" => "completed", "checkpoints" => checkpoints, "metrics" => metrics}} ->
          # Download and save checkpoints
          checkpoint_urls = download_checkpoints(checkpoints, job.id)

          # Mark complete
          {:ok, completed_job} =
            CerebrosTrainingJob.complete!(job, %{
              checkpoint_urls: checkpoint_urls,
              metrics: metrics
            })

          {:ok, completed_job}

        {:ok, %{"status" => "running", "phase" => phase, "checkpoint" => checkpoint}}
        when not is_nil(checkpoint) ->
          # Phase completed, save checkpoint
          checkpoint_url = download_checkpoint(checkpoint, job.id, phase)

          CerebrosTrainingJob.update_checkpoint!(job, %{
            phase: phase,
            checkpoint_url: checkpoint_url
          })

          # Continue polling
          Process.sleep(@poll_interval_ms)
          poll_until_complete(job, cerebros_job_id, attempt + 1)

        {:ok, %{"status" => "running"}} ->
          # Still running, no new checkpoint
          Process.sleep(@poll_interval_ms)
          poll_until_complete(job, cerebros_job_id, attempt + 1)

        {:ok, %{"status" => "failed", "error" => error}} ->
          {:error, {:cerebros_failed, error}}

        {:error, reason} ->
          {:error, {:poll_failed, reason}}
      end
    end
  end

  defp check_cerebros_status(cerebros_job_id) do
    http_get("/api/v1/training/status/#{cerebros_job_id}")
  end

  defp download_checkpoints(checkpoints, job_id) when is_list(checkpoints) do
    Enum.map(checkpoints, fn checkpoint ->
      phase = checkpoint["phase"]
      download_checkpoint(checkpoint, job_id, phase)
    end)
  end

  defp download_checkpoint(checkpoint, job_id, phase) do
    checkpoint_url = checkpoint["url"]

    local_path =
      Path.join([
        "/data/checkpoints",
        job_id,
        "phase_#{phase}.onnx"
      ])

    File.mkdir_p!(Path.dirname(local_path))

    case http_download(checkpoint_url, local_path) do
      :ok ->
        Logger.info("Downloaded checkpoint for job #{job_id} phase #{phase}")
        local_path

      {:error, reason} ->
        Logger.error("Failed to download checkpoint: #{inspect(reason)}")
        # Return URL as fallback
        checkpoint_url
    end
  end

  # HTTP client functions (using Req)

  defp http_post(path, payload) do
    url = @cerebros_base_url <> path

    case Req.post(url, json: payload, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(path) do
    url = @cerebros_base_url <> path

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_download(url, local_path) do
    case Req.get(url, into: File.stream!(local_path)) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
