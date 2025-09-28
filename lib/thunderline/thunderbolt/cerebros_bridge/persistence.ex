defmodule Thunderline.Thunderbolt.CerebrosBridge.Persistence do
  @moduledoc """
  Handles persistence of Cerebros NAS lifecycle data into ThunderBolt Ash
  resources. Called by the bridge worker and telemetry/event handlers so that
  ModelRun and ModelTrial stay in sync with emitted contracts.
  """

  alias Ash
  alias Ash.Changeset
  alias Ash.Query
  require Ash.Query
  alias AshStateMachine.Errors.NoMatchingTransition
  alias Thunderline.Thunderbolt.CerebrosBridge.Contracts
  alias Thunderline.Thunderbolt.Domain
  alias Thunderline.Thunderbolt.ML.ModelArtifact
  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelTrial}
  alias Thunderline.Thunderflow.ErrorClass

  @spec ensure_run_record(Contracts.RunStartedV1.t(), map()) ::
          {:ok, ModelRun.t()} | {:error, term()}
  def ensure_run_record(%Contracts.RunStartedV1{} = contract, spec) do
    with {:ok, %ModelRun{} = run} <- fetch_run(contract.run_id) do
      {:ok, run}
    else
      {:ok, nil} -> create_run(contract, spec)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec record_run_started(Contracts.RunStartedV1.t(), map(), map()) :: :ok | {:error, term()}
  def record_run_started(%Contracts.RunStartedV1{} = contract, response, spec) do
    with {:ok, %ModelRun{} = run} <- fetch_run(contract.run_id),
         {:ok, _} <-
           run
           |> Changeset.for_update(:start, %{
             bridge_payload: start_payload(contract, response, spec)
           })
           |> Domain.update() do
      :ok
    else
      {:ok, nil} -> {:error, :run_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec record_trial_reported(Contracts.TrialReportedV1.t(), map(), map()) ::
          :ok | {:error, term()}
  def record_trial_reported(%Contracts.TrialReportedV1{} = contract, response, spec) do
    with {:ok, %ModelRun{} = run} <- fetch_run(contract.run_id),
         {:ok, _trial} <- upsert_trial(run, contract, response, spec) do
      :ok
    else
      {:ok, nil} -> {:error, :run_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec record_run_finalized(Contracts.RunFinalizedV1.t(), map(), map()) ::
          :ok | {:error, term()}
  def record_run_finalized(%Contracts.RunFinalizedV1{} = contract, response, spec) do
    with {:ok, %ModelRun{} = run} <- fetch_run(contract.run_id),
         completed <- count_trials(run),
         attrs <- %{
           best_metric: select_metric(contract.metrics),
           completed_trials: completed,
           metadata: merge_metadata(run.metadata, finalize_metadata(contract)),
           bridge_result: finalize_payload(contract, response, spec)
         },
         {:ok, %ModelRun{} = updated} <-
           run
           |> Changeset.for_update(:complete, %{
             best_metric: attrs.best_metric,
             completed_trials: attrs.completed_trials,
             metadata: attrs.metadata,
             bridge_result: attrs.bridge_result
           })
           |> Domain.update(),
         :ok <- persist_artifacts(updated, contract, spec) do
      :ok
    else
      {:ok, nil} -> {:error, :run_missing}
      {:error,
       %Ash.Error.Invalid{errors: [%NoMatchingTransition{target: :succeeded, action: :complete} | _]}} ->
        with {:ok, %ModelRun{} = run} <- fetch_run(contract.run_id) do
          persist_artifacts(run, contract, spec)
        end

      {:already_finalized, %ModelRun{} = run} ->
        persist_artifacts(run, contract, spec)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec record_run_failed(String.t(), ErrorClass.t(), map()) :: :ok | {:error, term()}
  def record_run_failed(run_id, %ErrorClass{} = error, spec) do
    with {:ok, %ModelRun{} = run} <- fetch_run(run_id),
         {:ok, _} <-
           run
           |> Changeset.for_update(:fail, %{
             error_message: format_error(error),
             bridge_result: failure_payload(error, spec)
           })
           |> Domain.update() do
      :ok
    else
      {:ok, nil} -> {:error, :run_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_artifacts(%ModelRun{} = run, contract, spec) do
    contract
    |> extract_artifact_refs()
    |> Enum.reduce_while(:ok, fn ref, _ ->
      case ensure_artifact_record(run, ref, spec) do
        {:ok, _artifact} -> {:cont, :ok}
        {:skip, _reason} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_artifact_refs(contract) do
    cond do
      is_list(contract.artifact_refs) -> contract.artifact_refs
      is_map(contract.payload) ->
        contract.payload
        |> Map.get(:result) || contract.payload |> Map.get("result")
        |> case do
          %{} = result ->
            Map.get(result, :artifact_refs) || Map.get(result, "artifact_refs") || []

          _ ->
            []
        end

      true ->
        []
    end
  end

  defp ensure_artifact_record(%ModelRun{} = run, ref, spec) do
    normalized = normalize_artifact_ref(ref)
    uri = artifact_uri(normalized)
    checksum = artifact_checksum(normalized, uri)

    if is_nil(uri) and is_nil(checksum) do
      {:skip, :insufficient_reference}
    else
      case lookup_artifact(checksum, uri) do
        {:ok, %ModelArtifact{} = artifact} ->
          {:ok, artifact}

        {:ok, nil} ->
          attrs = %{
            spec_id: artifact_spec_id(normalized, spec, run),
            model_run_id: run.id,
            uri: uri || checksum,
            checksum: checksum || checksum_from_uri(uri),
            bytes: artifact_bytes(normalized),
            semver: artifact_semver(normalized, spec)
          }

          case attrs.spec_id do
            nil -> {:skip, :missing_spec_id}
            _ -> ModelArtifact.create(attrs)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp lookup_artifact(checksum, uri) when is_binary(checksum) and checksum != "" do
    case ModelArtifact
         |> Query.filter(checksum == ^checksum)
         |> Query.limit(1)
         |> Ash.read_one() do
      {:ok, %ModelArtifact{} = artifact} -> {:ok, artifact}
      {:ok, nil} -> lookup_by_uri(uri)
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_artifact(_checksum, uri), do: lookup_by_uri(uri)

  defp lookup_by_uri(uri) when is_binary(uri) and uri != "" do
    ModelArtifact
    |> Query.filter(uri == ^uri)
    |> Query.limit(1)
    |> Ash.read_one()
  end

  defp lookup_by_uri(_), do: {:ok, nil}

  defp normalize_artifact_ref(ref) when is_map(ref) do
    %{
      uri: Map.get(ref, :uri) || Map.get(ref, "uri"),
      checksum: Map.get(ref, :checksum) || Map.get(ref, "checksum"),
      bytes: Map.get(ref, :bytes) || Map.get(ref, "bytes"),
      spec_id: Map.get(ref, :spec_id) || Map.get(ref, "spec_id"),
      semver: Map.get(ref, :semver) || Map.get(ref, "semver")
    }
  end

  defp normalize_artifact_ref(_), do: %{}

  defp artifact_uri(%{uri: uri}) when is_binary(uri) and uri != "", do: uri
  defp artifact_uri(_), do: nil

  defp artifact_checksum(%{checksum: checksum}, _uri) when is_binary(checksum) and checksum != "",
    do: checksum

  defp artifact_checksum(_ref, uri) when is_binary(uri) and uri != "", do: checksum_from_uri(uri)
  defp artifact_checksum(_, _), do: nil

  defp artifact_spec_id(%{spec_id: spec_id}, _spec, _run) when is_binary(spec_id), do: spec_id

  defp artifact_spec_id(_ref, spec, run) do
    spec_id_from_map(spec) || spec_id_from_map(run.metadata)
  end

  defp spec_id_from_map(%{} = map) do
    Map.get(map, "spec_id") || Map.get(map, :spec_id) || get_in(map, ["spec", "spec_id"]) ||
      get_in(map, [:spec, :spec_id])
  end

  defp spec_id_from_map(_), do: nil

  defp artifact_bytes(%{bytes: bytes}) when is_integer(bytes) and bytes >= 0, do: bytes

  defp artifact_bytes(%{bytes: bytes}) when is_binary(bytes) do
    case Integer.parse(bytes) do
      {value, _} -> value
      :error -> 0
    end
  end

  defp artifact_bytes(_), do: 0

  defp artifact_semver(%{semver: semver}, _spec) when is_binary(semver) and semver != "",
    do: semver

  defp artifact_semver(_ref, spec) when is_map(spec) do
    Map.get(spec, "artifact_semver") || Map.get(spec, :artifact_semver) || "0.1.0"
  end

  defp artifact_semver(_, _), do: "0.1.0"

  defp checksum_from_uri(uri) when is_binary(uri) do
    uri
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp checksum_from_uri(_), do: nil

  # -- helpers ----------------------------------------------------------------

  defp create_run(contract, spec) do
    attrs = %{
      run_id: contract.run_id,
      search_space_version: Map.get(spec, "search_space_version", 1),
      max_params: Map.get(spec, "max_params", 2_000_000),
      requested_trials: requested_trials(contract, spec),
      metadata: %{
        "spec" => spec,
        "budget" => contract.budget,
        "tau" => contract.tau,
        "pulse_id" => contract.pulse_id,
        "extra" => contract.extra
      }
    }

    ModelRun.create(attrs)
  end

  defp fetch_run(run_id) do
    ModelRun
    |> Query.filter(run_id == ^run_id)
    |> Query.limit(1)
    |> Ash.read_one()
  end

  defp requested_trials(contract, spec) do
    cond do
      is_integer(spec["requested_trials"]) -> spec["requested_trials"]
      is_integer(contract.budget["trials"]) -> contract.budget["trials"]
      is_integer(spec[:requested_trials]) -> spec[:requested_trials]
      true -> 0
    end
  end

  defp start_payload(contract, response, spec) do
    %{
      "parameters" => contract.parameters,
      "budget" => contract.budget,
      "extra" => contract.extra,
      "spec" => spec,
      "response" => summarize_response(response)
    }
  end

  defp finalize_metadata(contract) do
    %{
      "final_status" => contract.status,
      "final_metrics" => contract.metrics,
      "best_trial_id" => contract.best_trial_id
    }
  end

  defp finalize_payload(contract, response, spec) do
    %{
      "contract" => Map.from_struct(contract) |> Map.drop([:__struct__]),
      "response" => summarize_response(response),
      "spec" => spec
    }
  end

  defp failure_payload(error, spec) do
    %{
      "error" => Map.from_struct(error),
      "spec" => spec
    }
  end

  defp summarize_response(response) when is_map(response) do
    Map.take(response, [
      :returncode,
      :stdout_excerpt,
      :stderr_excerpt,
      :duration_ms,
      :parsed,
      :result
    ])
  end

  defp summarize_response(_), do: %{}

  defp merge_metadata(existing, addition) do
    (existing || %{}) |> Map.merge(addition || %{})
  end

  defp upsert_trial(run, contract, response, spec) do
    attrs = %{
      model_run_id: run.id,
      trial_id: contract.trial_id,
      status: contract.status,
      metrics: contract.metrics,
      parameters: contract.parameters,
      artifact_uri: contract.artifact_uri,
      duration_ms: contract.duration_ms,
      rank: contract.rank,
      warnings: contract.warnings,
      candidate_id: contract.candidate_id,
      pulse_id: contract.pulse_id,
      bridge_payload: %{
        "response" => summarize_response(response),
        "spec" => spec
      }
    }

    case fetch_trial(run.id, contract.trial_id) do
      {:ok, %ModelTrial{} = trial} ->
        trial
        |> Changeset.for_update(
          :record,
          Map.delete(attrs, :trial_id) |> Map.delete(:model_run_id)
        )
        |> Domain.update()

      {:ok, nil} ->
        ModelTrial
        |> Changeset.for_create(:log, attrs)
        |> Domain.create()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_trial(model_run_id, trial_id) do
    ModelTrial
    |> Query.filter(model_run_id == ^model_run_id and trial_id == ^trial_id)
    |> Query.limit(1)
    |> Ash.read_one()
  end

  defp count_trials(%ModelRun{id: id}) do
    ModelTrial
    |> Query.filter(model_run_id == ^id)
    |> Ash.read()
    |> case do
      {:ok, list} -> length(list)
      _ -> 0
    end
  end

  defp select_metric(metrics) when is_map(metrics) do
    metrics
    |> Enum.find_value(fn {_, value} ->
      cond do
        is_number(value) -> value
        is_map(value) -> select_metric(value)
        true -> nil
      end
    end)
  end

  defp select_metric(_), do: nil

  defp format_error(%ErrorClass{} = error) do
    error
    |> Map.from_struct()
    |> Map.get(:context)
    |> case do
      %{} = context -> context[:reason] || inspect(error)
      _ -> inspect(error)
    end
  end
end
