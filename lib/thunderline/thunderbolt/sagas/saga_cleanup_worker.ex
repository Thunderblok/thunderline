defmodule Thunderline.Thunderbolt.Sagas.SagaCleanupWorker do
  @moduledoc """
  Oban worker for cleaning up stale and failed sagas via Thunderwall integration.

  Runs periodically to:
  - Find sagas that have been running too long (stale)
  - Find sagas that exceeded max attempts (failed)
  - Register them with DecayProcessor for archival
  - Clean up completed sagas older than retention period

  ## Schedule

  Configure in Oban config:

      config :thunderline, Oban,
        queues: [sagas: 10, saga_cleanup: 1],
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 * * * *", Thunderline.Thunderbolt.Sagas.SagaCleanupWorker}
           ]}
        ]

  ## Cleanup Policies

  - Stale running sagas (>1 hour): Mark as failed, register for decay
  - Failed sagas (>7 days): Archive and delete
  - Completed sagas (>30 days): Archive and delete
  - Cancelled sagas (>1 day): Delete immediately
  """

  use Oban.Worker,
    queue: :saga_cleanup,
    max_attempts: 1,
    tags: ["saga", "cleanup", "maintenance"]

  require Logger

  alias Thunderline.Thunderbolt.Sagas.SagaState
  alias Thunderline.Thunderwall.DecayProcessor
  alias Thunderline.Thunderwall.OverflowHandler

  @stale_threshold_seconds 3_600
  @failed_retention_days 7
  @completed_retention_days 30
  @cancelled_retention_days 1

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[SagaCleanupWorker] Starting saga cleanup cycle")

    results = %{
      stale_marked: mark_stale_sagas(),
      failed_archived: archive_old_failed_sagas(),
      completed_archived: archive_old_completed_sagas(),
      cancelled_deleted: delete_old_cancelled_sagas()
    }

    emit_cleanup_telemetry(results)

    Logger.info("[SagaCleanupWorker] Cleanup complete: #{inspect(results)}")

    :ok
  end

  @doc """
  Mark sagas that have been running too long as failed.
  """
  def mark_stale_sagas do
    case SagaState.find_stale(@stale_threshold_seconds) do
      {:ok, stale_sagas} ->
        count =
          Enum.reduce(stale_sagas, 0, fn saga, acc ->
            case mark_saga_stale(saga) do
              :ok -> acc + 1
              _ -> acc
            end
          end)

        Logger.info("[SagaCleanupWorker] Marked #{count} stale sagas as failed")
        count

      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to find stale sagas: #{inspect(reason)}")
        0
    end
  end

  @doc """
  Archive failed sagas older than retention period.
  """
  def archive_old_failed_sagas do
    cutoff = DateTime.add(DateTime.utc_now(), -@failed_retention_days, :day)

    case query_sagas_for_archival(:failed, cutoff) do
      {:ok, sagas} ->
        count =
          Enum.reduce(sagas, 0, fn saga, acc ->
            case archive_and_delete_saga(saga, :failed_retention) do
              :ok -> acc + 1
              _ -> acc
            end
          end)

        Logger.info("[SagaCleanupWorker] Archived #{count} old failed sagas")
        count

      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to query failed sagas: #{inspect(reason)}")
        0
    end
  end

  @doc """
  Archive completed sagas older than retention period.
  """
  def archive_old_completed_sagas do
    cutoff = DateTime.add(DateTime.utc_now(), -@completed_retention_days, :day)

    case query_sagas_for_archival(:completed, cutoff) do
      {:ok, sagas} ->
        count =
          Enum.reduce(sagas, 0, fn saga, acc ->
            case archive_and_delete_saga(saga, :completed_retention) do
              :ok -> acc + 1
              _ -> acc
            end
          end)

        Logger.info("[SagaCleanupWorker] Archived #{count} old completed sagas")
        count

      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to query completed sagas: #{inspect(reason)}")
        0
    end
  end

  @doc """
  Delete cancelled sagas older than retention period.
  """
  def delete_old_cancelled_sagas do
    cutoff = DateTime.add(DateTime.utc_now(), -@cancelled_retention_days, :day)

    case query_sagas_for_archival(:cancelled, cutoff) do
      {:ok, sagas} ->
        count =
          Enum.reduce(sagas, 0, fn saga, acc ->
            case Ash.destroy(saga) do
              :ok -> acc + 1
              {:ok, _} -> acc + 1
              _ -> acc
            end
          end)

        Logger.info("[SagaCleanupWorker] Deleted #{count} old cancelled sagas")
        count

      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to query cancelled sagas: #{inspect(reason)}")
        0
    end
  end

  # Private functions

  defp mark_saga_stale(saga) do
    # Mark as failed
    case Ash.update(saga, %{
           status: :failed,
           error: "Saga exceeded stale threshold (#{@stale_threshold_seconds}s)"
         }) do
      {:ok, updated} ->
        # Register with DecayProcessor
        DecayProcessor.register_decayable(%{
          resource_type: :saga_state,
          resource_id: updated.id,
          domain: :bolt,
          reason: :stale_timeout,
          ttl_seconds: @failed_retention_days * 86_400
        })

        # Notify overflow handler about the stuck saga
        OverflowHandler.route_reject(%{
          source_domain: :bolt,
          resource_type: :saga_state,
          resource_id: saga.id,
          reason: :stale_timeout,
          payload: %{
            saga_module: saga.saga_module,
            started_at: saga.last_attempt_at,
            correlation_id: saga.id
          }
        })

        :ok

      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to mark saga #{saga.id} as stale: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp query_sagas_for_archival(status, cutoff) do
    Ash.read(SagaState,
      filter: [
        status: status
      ],
      limit: 100
    )
    |> case do
      {:ok, sagas} ->
        # Filter by cutoff date (inserted_at)
        filtered =
          Enum.filter(sagas, fn saga ->
            DateTime.compare(saga.inserted_at, cutoff) == :lt
          end)

        {:ok, filtered}

      error ->
        error
    end
  end

  defp archive_and_delete_saga(saga, reason) do
    # Create archive entry via Thunderwall
    archive_attrs = %{
      original_id: saga.id,
      resource_type: :saga_state,
      domain: :bolt,
      archived_at: DateTime.utc_now(),
      reason: reason,
      data: %{
        saga_module: saga.saga_module,
        status: saga.status,
        inputs: saga.inputs,
        output: saga.output,
        error: saga.error,
        attempt_count: saga.attempt_count,
        created_at: saga.inserted_at,
        completed_at: saga.completed_at
      },
      meta: %{
        correlation_id: saga.id
      }
    }

    with {:ok, _archive} <- create_archive_entry(archive_attrs),
         {:ok, _} <- Ash.destroy(saga) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("[SagaCleanupWorker] Failed to archive saga #{saga.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_archive_entry(attrs) do
    alias Thunderline.Thunderwall.Resources.ArchiveEntry

    Ash.create(ArchiveEntry, attrs)
  rescue
    _ -> {:error, :archive_creation_failed}
  end

  defp emit_cleanup_telemetry(results) do
    :telemetry.execute(
      [:thunderline, :saga, :cleanup, :complete],
      %{
        stale_marked: results.stale_marked,
        failed_archived: results.failed_archived,
        completed_archived: results.completed_archived,
        cancelled_deleted: results.cancelled_deleted,
        total: results.stale_marked + results.failed_archived +
               results.completed_archived + results.cancelled_deleted
      },
      %{worker: __MODULE__}
    )
  end
end
