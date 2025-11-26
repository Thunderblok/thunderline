defmodule Thunderline.Cerebros.Automat do
  @moduledoc """
  Cerebros Automat Bridge - Job-based async pattern for ML workloads.

  HC-20A: Provides ergonomic interface for submitting heavy ML/geometry work
  to the Cerebros Python service. Jobs flow through:

  1. `submit_job/3` → Creates `CerebrosTrainingJob` (status: :queued)
  2. Event `cerebros.job.created` emitted
  3. Python worker polls `/api/jobs/poll`
  4. Worker completes → `cerebros.job.completed` or `cerebros.job.failed`

  ## Usage

      # Submit a training job
      {:ok, job} = Automat.submit_job(dataset_id, "gpt-4o-mini", %{
        n_epochs: 3,
        learning_rate_multiplier: 0.1
      })

      # Check job status
      {:ok, job} = Automat.get_job(job.id)
      job.status  # => :queued | :running | :completed | :failed

  ## Events Emitted

  | Event | Trigger |
  |-------|---------|
  | `cerebros.job.created` | Job queued |
  | `cerebros.job.started` | Worker picked up job |
  | `cerebros.job.completed` | Training succeeded |
  | `cerebros.job.failed` | Training failed |

  See `Thunderline.Thunderbolt.Resources.CerebrosTrainingJob` for the underlying resource.
  """

  alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
  alias Thunderline.Thunderbolt.Domain
  alias Thunderline.Thunderflow.EventBus
  require Ash.Query
  require Logger

  @type job :: CerebrosTrainingJob.t()
  @type job_id :: String.t()
  @type model_id :: String.t()
  @type hyperparams :: %{
          optional(:n_epochs) => pos_integer(),
          optional(:learning_rate_multiplier) => float(),
          optional(:batch_size) => pos_integer()
        }

  @doc """
  Submit a training job to the Cerebros service.

  Creates a queued job that will be picked up by the Python worker
  on its next poll cycle.

  ## Parameters

    * `dataset_id` - UUID of the frozen TrainingDataset
    * `model_id` - Base model to fine-tune (e.g., "gpt-4o-mini")
    * `hyperparams` - Training hyperparameters (optional)
    * `opts` - Additional options
      * `:metadata` - Arbitrary metadata map

  ## Returns

    * `{:ok, job}` - Job created and queued
    * `{:error, reason}` - Creation failed

  ## Examples

      {:ok, job} = Automat.submit_job(dataset_id, "gpt-4o-mini")

      {:ok, job} = Automat.submit_job(dataset_id, "gpt-4o-mini", %{
        n_epochs: 5,
        learning_rate_multiplier: 0.2
      })
  """
  @spec submit_job(Ecto.UUID.t(), model_id(), hyperparams(), keyword()) ::
          {:ok, job()} | {:error, term()}
  def submit_job(dataset_id, model_id, hyperparams \\ %{}, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    attrs = %{
      training_dataset_id: dataset_id,
      model_id: model_id,
      hyperparameters: hyperparams,
      metadata: metadata
    }

    case CerebrosTrainingJob.create(attrs, domain: Domain) do
      {:ok, job} ->
        # Event emission handled by after_action in resource
        Logger.info("[Automat] Job submitted: #{job.id} for model #{model_id}")
        {:ok, job}

      {:error, reason} = error ->
        Logger.warning("[Automat] Job submission failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Get a job by ID.

  ## Examples

      {:ok, job} = Automat.get_job("550e8400-e29b-41d4-a716-446655440000")
  """
  @spec get_job(job_id()) :: {:ok, job()} | {:error, term()}
  def get_job(job_id) do
    CerebrosTrainingJob
    |> Ash.Query.filter(id == ^job_id)
    |> Ash.read_one(domain: Domain)
  end

  @doc """
  List jobs with optional filters.

  ## Options

    * `:status` - Filter by status atom
    * `:dataset_id` - Filter by dataset
    * `:limit` - Max results (default 50)

  ## Examples

      {:ok, jobs} = Automat.list_jobs(status: :queued)
      {:ok, jobs} = Automat.list_jobs(dataset_id: uuid, limit: 10)
  """
  @spec list_jobs(keyword()) :: {:ok, [job()]} | {:error, term()}
  def list_jobs(opts \\ []) do
    status = Keyword.get(opts, :status)
    dataset_id = Keyword.get(opts, :dataset_id)
    limit = Keyword.get(opts, :limit, 50)

    query =
      CerebrosTrainingJob
      |> maybe_filter_status(status)
      |> maybe_filter_dataset(dataset_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)

    Ash.read(query, domain: Domain)
  end

  @doc """
  Cancel a queued job.

  Only jobs in `:queued` status can be cancelled.

  ## Examples

      {:ok, job} = Automat.cancel_job(job_id)
  """
  @spec cancel_job(job_id()) :: {:ok, job()} | {:error, term()}
  def cancel_job(job_id) do
    with {:ok, job} <- get_job(job_id),
         :ok <- validate_cancellable(job) do
      job
      |> Ash.Changeset.for_update(:update, %{status: :cancelled})
      |> Ash.update(domain: Domain)
    end
  end

  # Event emission helpers - called from after_action hooks

  @doc false
  @spec emit_job_created(job()) :: :ok
  def emit_job_created(job) do
    emit_event("cerebros.job.created", job, %{
      dataset_id: job.training_dataset_id,
      model_id: job.model_id,
      hyperparameters: job.hyperparameters
    })
  end

  @doc false
  @spec emit_job_started(job()) :: :ok
  def emit_job_started(job) do
    emit_event("cerebros.job.started", job, %{
      started_at: job.started_at
    })
  end

  @doc false
  @spec emit_job_completed(job()) :: :ok
  def emit_job_completed(job) do
    emit_event("cerebros.job.completed", job, %{
      checkpoint_urls: job.checkpoint_urls,
      metrics: job.metrics,
      completed_at: job.completed_at
    })
  end

  @doc false
  @spec emit_job_failed(job()) :: :ok
  def emit_job_failed(job) do
    emit_event("cerebros.job.failed", job, %{
      error_message: job.error_message,
      failed_at: job.completed_at
    })
  end

  # Private helpers

  defp emit_event(event_name, job, extra_payload) do
    base_payload = %{
      job_id: job.id,
      status: job.status,
      phase: job.phase
    }

    payload = Map.merge(base_payload, extra_payload)

    case EventBus.publish_event(%{
           type: String.to_atom(event_name),
           domain: "thunderbolt",
           payload: payload,
           timestamp: DateTime.utc_now()
         }) do
      {:ok, _event} ->
        :telemetry.execute(
          [:thunderline, :cerebros, :job, :event],
          %{count: 1},
          %{event: event_name, job_id: job.id, status: job.status}
        )

        :ok

      {:error, reason} ->
        Logger.warning("[Automat] Failed to emit #{event_name}: #{inspect(reason)}")
        :ok
    end
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_atom(status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_dataset(query, nil), do: query

  defp maybe_filter_dataset(query, dataset_id) do
    Ash.Query.filter(query, training_dataset_id == ^dataset_id)
  end

  defp validate_cancellable(%{status: :queued}), do: :ok
  defp validate_cancellable(%{status: status}), do: {:error, {:not_cancellable, status}}
end
