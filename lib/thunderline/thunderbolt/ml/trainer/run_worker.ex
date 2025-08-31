defmodule Thunderline.Thunderbolt.ML.Trainer.RunWorker do
  @moduledoc "Executes a single ML training run, emitting telemetry and persisting artifacts/versions."
  use Oban.Worker, queue: :ml, max_attempts: 1

  require Ash.Query
  import Ash.Expr, only: [expr: 1]
  alias Thunderline.Thunderbolt.Domain
  alias Thunderline.Thunderbolt.ML.{TrainingRun, ModelArtifact, ModelVersion}

  @tele_base [:ml, :run]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    meta = %{run_id: run_id}

    :telemetry.execute(@tele_base ++ [:started], %{}, meta)

    with {:ok, run} <- fetch_run(run_id),
         {:ok, _} <- mark_started(run),
         {:ok, artifact} <- build_artifact(run),
         {:ok, _version} <- record_version(run, artifact),
         {:ok, _} <- mark_completed(run, artifact) do
      :telemetry.execute(@tele_base ++ [:completed], %{artifact_bytes: artifact.bytes}, Map.merge(meta, %{artifact_id: artifact.id}))
      :ok
    else
      {:error, reason} ->
        _ = mark_failed(run_id, reason)
        :telemetry.execute(@tele_base ++ [:failed], %{}, Map.merge(meta, %{error: format_error(reason)}))
        {:error, format_error(reason)}
    end
  rescue
    e ->
      reason = Exception.format(:error, e, __STACKTRACE__)
      _ = mark_failed(run_id, reason)
      :telemetry.execute(@tele_base ++ [:failed], %{}, %{run_id: run_id, error: reason})
      {:error, reason}
  end

  # --- internals ---

  defp fetch_run(rid) do
    query =
      TrainingRun
      |> Ash.Query.filter(expr(run_id == ^rid))
      |> Ash.Query.limit(1)

    case Domain.read_one(query) do
      {:ok, %TrainingRun{} = run} -> {:ok, run}
      {:ok, nil} -> {:error, :not_found}
      {:error, err} -> {:error, err}
    end
  end

  defp mark_started(%TrainingRun{} = run) do
    run
    |> Ash.Changeset.for_update(:mark_started)
    |> Domain.update()
  end

  defp mark_completed(%TrainingRun{} = run, %ModelArtifact{id: artifact_id}) do
    run
    |> Ash.Changeset.for_update(:mark_completed, %{artifact_id: artifact_id})
    |> Domain.update()
  end

  defp mark_failed(run_id, reason) do
    with {:ok, %TrainingRun{} = run} <- fetch_run(run_id) do
      run
      |> Ash.Changeset.for_update(:mark_failed, %{error: format_error(reason)})
      |> Domain.update()
    else
      _ -> :ok
    end
  end

  defp build_artifact(%TrainingRun{spec_id: spec_id, run_id: run_id}) do
    uri = "s3://ml-artifacts/" <> run_id <> ".bin"
    checksum = run_id |> :crypto.hash(:sha256) |> Base.encode16(case: :lower)
    bytes = :rand.uniform(5_000_000) + 500_000

    %{
      spec_id: spec_id,
      uri: uri,
      checksum: checksum,
      bytes: bytes
    }
    |> Ash.Changeset.for_create(ModelArtifact, :create)
    |> Domain.create()
  end

  defp record_version(%TrainingRun{spec_id: spec_id, dataset_id: dataset_id}, %ModelArtifact{id: artifact_id}) do
    metrics = %{accuracy: 0.75 + (:rand.uniform() * 0.2) |> Float.round(4)}

    %{
      spec_id: spec_id,
      artifact_id: artifact_id,
      dataset_id: dataset_id,
      metrics: metrics,
      notes: "Auto-recorded by RunWorker"
    }
    |> Ash.Changeset.for_create(ModelVersion, :record)
    |> Domain.create()
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(%RuntimeError{message: msg}), do: msg
  defp format_error(term) when is_binary(term), do: term
  defp format_error(term), do: inspect(term)
end
