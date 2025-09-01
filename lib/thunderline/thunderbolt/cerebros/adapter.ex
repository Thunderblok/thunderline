defmodule Thunderline.Thunderbolt.Cerebros.Adapter do
  @moduledoc """
  Unified façade for ML search with hybrid delegation strategy.

  Delegation Order (Phase 2 / 3 Hybrid):
    1. In-process external library (`Cerebros.run_search/1`)
    2. CLI fallback (`cerebros json --spec <json>`)
    3. Internal stub search (`SimpleSearch.simple_search/1`)

  Also persists lifecycle to Ash resources (`ModelRun`, `ModelArtifact`) via state machine actions.

  Returned unified result contract:
    %{
      best_metric: float(),
      best_spec: map(),
      artifact: binary() | :noop,
      trials: non_neg_integer(),
      search_space_version: pos_integer(),
      max_params: pos_integer(),
      persisted: %{model_run_id: term() | nil, artifact_ids: [term()]}
    }
  """
  require Logger
  alias Thunderline.EventBus
  alias Thunderline.Thunderbolt.Cerebros.{SimpleSearch, Artifacts, Telemetry}
  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelArtifact}

  @external_fun {:Cerebros, :run_search, 1}

  @doc "Run a search (opts list for internal stub or spec map for hybrid). Does NOT persist ModelRun by default."
  def run_search(opts_or_spec) do
    Telemetry.attach_logger()

    case delegate(opts_or_spec) do
      {:ok, result} -> {:ok, normalize_result(result)}
      other -> other
    end
  end

  @doc "Run a search and persist lifecycle (ModelRun + ModelArtifact). Returns unified result with :persisted metadata."
  def run_and_record(opts_or_spec, meta \\ %{}) do
    {:ok, result} = run_search(opts_or_spec)

    with {:ok, run} <- create_model_run(result, meta),
         {:ok, run} <- maybe_start_run(run),
         {:ok, artifacts} <- persist_artifacts(run, result),
         {:ok, run} <- complete_run(run, result) do
      {:ok, put_in(result[:persisted], %{model_run_id: run.id, artifact_ids: Enum.map(artifacts, & &1.id)})}
    else
      error ->
        Logger.error("[Cerebros.Adapter] persistence pipeline failed: #{inspect(error)}")
        {:ok, put_in(result[:persisted], %{model_run_id: nil, artifact_ids: []})}
    end
  end

  @doc "Load an artifact (delegates to Artifacts)."
  def load_artifact(path), do: Artifacts.load(path)

  @doc "Predict with an artifact path (stub)."
  def predict_with_artifact(path, samples) do
    with {:ok, art} <- Artifacts.load(path) do
      {:ok, Artifacts.predict_stub(art, samples)}
    end
  end

  ## Delegation ------------------------------------------------------------

  defp delegate(%{} = spec_map) do
    spec_map = Map.put_new(spec_map, :search_space_version, 1)
    emit_progress(:start, spec_map)

    cond do
      external_available?() ->
        Logger.info("[Cerebros.Adapter] External library available – delegating in-process")
        external(spec_map)

      cli_available?() ->
        Logger.info("[Cerebros.Adapter] CLI available – delegating to system executable")
        cli(spec_map)

      true ->
        Logger.info("[Cerebros.Adapter] Falling back to internal stub search")
        internal(spec_to_internal_opts(spec_map))
    end
    |> tap(fn
      {:ok, res} -> emit_progress(:complete, res)
      {:error, _} = err -> emit_progress(:error, %{error: err, spec: spec_map})
    end)
  end

  defp delegate(opts) when is_list(opts) do
    emit_progress(:start, %{mode: :opts})
    internal(opts)
    |> tap(fn
      {:ok, res} -> emit_progress(:complete, res)
      {:error, _} = err -> emit_progress(:error, %{error: err})
    end)
  end

  defp external_available?, do: function_exported?(elem(@external_fun, 0), elem(@external_fun, 1), elem(@external_fun, 2))
  defp cli_available?, do: System.find_executable("cerebros") != nil

  defp external(spec) do
    try do
      {:ok, apply(elem(@external_fun, 0), elem(@external_fun, 1), [spec])}
    rescue
      e ->
        Logger.error("[Cerebros.Adapter] external failure #{Exception.message(e)}; falling back")
        internal(spec_to_internal_opts(spec))
    end
  end

  defp cli(spec) do
    json = Jason.encode!(spec)
    {out, exit} = System.cmd("cerebros", ["json", "--spec"], input: json, stderr_to_stdout: true)
    case exit do
      0 -> Jason.decode(out)
      _ ->
        Logger.error("[Cerebros.Adapter] CLI failed (code #{exit}): #{out}")
        internal(spec_to_internal_opts(spec))
    end
  rescue
    e ->
      Logger.error("[Cerebros.Adapter] CLI exception #{inspect(e)}; falling back")
      internal(spec_to_internal_opts(spec))
  end

  defp internal(opts) do
    case SimpleSearch.simple_search(opts) do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  ## Spec Mapping ----------------------------------------------------------

  # Map external spec contract to internal simple search opts.
  defp spec_to_internal_opts(spec) do
    dataset = Map.get(spec, :dataset) || raise ArgumentError, "spec requires :dataset"
    trials = Map.get(spec, :trials, 3)
    max_params = Map.get(spec, :max_params, 2_000_000)
    seed = Map.get(spec, :seed)
    [dataset: dataset, trials: trials, max_params: max_params, seed: seed]
  end

  defp normalize_result(%{best_metric: _} = res), do: Map.put_new(res, :persisted, %{model_run_id: nil, artifact_ids: []})
  defp normalize_result(other), do: other

  ## Persistence -----------------------------------------------------------

  defp create_model_run(result, meta) do
    ModelRun.create(%{
      search_space_version: result.search_space_version || 1,
      max_params: result.max_params,
      requested_trials: result.trials,
      metadata: Map.merge(%{adapter: :cerebros_hybrid}, Map.take(meta, [:initiator, :source]))
    })
  end

  defp maybe_start_run(run) do
    ModelRun.start(run)
  end

  defp complete_run(run, result) do
    ModelRun.complete(run, %{best_metric: result.best_metric, completed_trials: result.trials})
  end

  defp persist_artifacts(run, result) do
    spec = result.best_spec || %{}
    artifact_path = result.artifact
    metrics = %{metric: result.best_metric, params: Map.get(result, :params, Map.get(spec, :params, -1))}

    artifacts = [
      %{
        model_run_id: run.id,
        trial_index: Map.get(spec, :id, 0),
        metric: metrics.metric,
        params: metrics.params,
        spec: spec,
        path: artifact_path,
        metadata: %{source: :adapter}
      }
    ]

    created =
      Enum.reduce(artifacts, [], fn attrs, acc ->
        case ModelArtifact.create(attrs) do
          {:ok, art} -> [art | acc]
          {:error, reason} ->
            Logger.error("[Cerebros.Adapter] artifact persist failed: #{inspect(reason)}")
            acc
        end
      end)
      |> Enum.reverse()

    {:ok, created}
  end

  ## Progress Emission -----------------------------------------------------

    defp emit_progress(stage, data) do
      with {:ok, ev} <- Thunderline.Event.new(name: "ai.cerebros_search_progress", source: :bolt, payload: %{stage: stage, at: System.system_time(:millisecond), data: sanitize_progress(data)}, meta: %{pipeline: :realtime}, type: :cerebros_search_progress) do
        EventBus.publish_event(ev)
      end
      :ok
  end

  defp sanitize_progress(%{artifact: path} = data) when is_binary(path) do
    Map.put(data, :artifact, Path.basename(path))
  end
  defp sanitize_progress(data), do: data
end
