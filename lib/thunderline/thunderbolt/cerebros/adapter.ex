defmodule Thunderline.Thunderbolt.Cerebros.Adapter do
  @moduledoc """
  Hybrid Cerebros delegation façade.

  Resolution order (Mode C - Hybrid):
    1. In-process external Cerebros lib (if loaded & API present)
    2. CLI (`cerebros json --spec <json>`), tool path configurable via `CEREBROS_CLI`
    3. Internal SimpleSearch fallback (legacy stub)

  Returns a unified map (contract subset) regardless of path:
    %{
      best_metric: float,
      best_trial: map | nil,
      trials: non_neg_integer,
      artifact_path: binary | :noop,
      metrics_summary: map
    }

  Internal SimpleSearch fields are remapped to this shape.
  """
  alias Thunderline.Thunderbolt.Cerebros.{SimpleSearch, Artifacts, Telemetry, Spec, Result}
  require Logger

  @type unified_result :: %{
          run_id: String.t(),
          best_metric: float(),
          best_trial: map() | nil,
          trials: non_neg_integer(),
          artifact_path: binary() | :noop,
          metrics_summary: map(),
          schema_version: non_neg_integer()
        }

  @external_fun {:Cerebros, :run_search, 1}

  @doc "Public entry point; accepts keyword opts or map spec. Always returns versioned result map."
  @spec run_search(Keyword.t() | map()) :: {:ok, unified_result} | {:error, term()}
  def run_search(opts) when is_list(opts), do: opts |> Map.new() |> run_search()
  def run_search(%{} = spec_map) do
    Telemetry.attach_logger()
    run_id = Map.get(spec_map, :telemetry_run_id) || Map.get(spec_map, "telemetry_run_id") || UUID.uuid4()
    spec_map = Map.put(spec_map, :telemetry_run_id, run_id)
    cond do
      external_lib?() -> delegate_external(spec_map)
      cli_path() -> delegate_cli(spec_map)
      true -> delegate_internal(Map.to_list(spec_map))
    end
  end

  @doc "Load an artifact (delegates)."
  def load_artifact(path), do: Artifacts.load(path)

  @doc "Predict with an artifact path (stub)."
  def predict_with_artifact(path, samples) do
    with {:ok, art} <- Artifacts.load(path) do
      {:ok, Artifacts.predict_stub(art, samples)}
    end
  end

  ## Internal delegation paths

  defp delegate_internal(opts) do
    Logger.info("[Cerebros.Adapter] using internal SimpleSearch fallback")
    case SimpleSearch.simple_search(opts) do
      {:ok, %{best_metric: m, best_spec: spec, artifact: art, trials: t, median_metric: med} = raw} ->
        {:ok,
         wrap_result(%{
           run_id: Map.get(Enum.into(opts, %{}), :telemetry_run_id) || UUID.uuid4(),
           best_metric: m,
           best_trial: %{spec: spec, metric: m},
           trials: t,
           artifact_path: art,
           metrics_summary: %{median: med}
         })}

      other -> other
    end
  end

  defp delegate_external(opts) do
    Logger.info("[Cerebros.Adapter] delegating to in-process Cerebros")
    try do
      spec_struct = Spec.new!(opts)
      result = apply(Cerebros, :run_search, [Map.from_struct(spec_struct)])
      {:ok, wrap_result(normalize_external_result(result) |> Map.put(:run_id, spec_struct.telemetry_run_id))}
    rescue
      e ->
        Logger.error("[Cerebros.Adapter] external Cerebros failure: #{Exception.message(e)} – falling back")
        delegate_internal(opts)
    end
  end

  defp delegate_cli(opts) do
    cli = cli_path()
    Logger.info("[Cerebros.Adapter] attempting CLI delegation via #{cli}")
    spec_map = normalize_external_spec(opts) |> Map.put(:telemetry_run_id, Map.get(opts, :telemetry_run_id))
    json = Jason.encode!(%{action: "run_search", spec: spec_map})
    {out, status} = System.cmd(cli, ["json", "--spec", json], stderr_to_stdout: true)
    if status == 0 do
      with {:ok, decoded} <- Jason.decode(out),
           %{"status" => "ok", "result" => res} <- decoded do
        {:ok,
         wrap_result(%{
           run_id: res["run_id"] || spec_map[:telemetry_run_id],
           best_metric: res["best_metric"],
           best_trial: res["best_trial"],
           trials: res["trials"],
           artifact_path: res["artifact_path"],
           metrics_summary: res["metrics_summary"] || %{}
         })}
      else
        _ ->
          Logger.error("[Cerebros.Adapter] malformed CLI response – falling back internal")
          delegate_internal(opts)
      end
    else
      Logger.error("[Cerebros.Adapter] CLI exited #{status}: #{String.slice(out,0,250)} – falling back internal")
      delegate_internal(opts)
    end
  rescue
    e ->
      Logger.error("[Cerebros.Adapter] CLI error #{inspect(e)} – internal fallback")
      delegate_internal(opts)
  end

  ## Normalization helpers
  defp normalize_external_spec(opts) do
    %{
      input_shapes: Keyword.get(opts, :input_shapes, []),
      output_shapes: Keyword.get(opts, :output_shapes, []),
      trials: Keyword.get(opts, :trials, 3),
      epochs: Keyword.get(opts, :epochs, 1),
      batch_size: Keyword.get(opts, :batch_size, 32),
      learning_rate: Keyword.get(opts, :learning_rate, 0.001),
      seed: Keyword.get(opts, :seed)
    }
  end

  defp normalize_external_result(%{best_metric: _} = r), do: r
  defp normalize_external_result(map) when is_map(map) do
    %{
      best_metric: Map.get(map, :best_metric) || Map.get(map, "best_metric"),
      best_trial: Map.get(map, :best_trial) || Map.get(map, "best_trial"),
      trials: Map.get(map, :trials) || Map.get(map, "trials"),
      artifact_path: Map.get(map, :artifact_path) || Map.get(map, "artifact_path"),
      metrics_summary: Map.get(map, :metrics_summary) || %{}
    }
  end

  defp external_lib?, do: function_exported?(elem(@external_fun, 0), elem(@external_fun, 1), elem(@external_fun, 2))
  defp cli_path, do: System.get_env("CEREBROS_CLI")
  defp wrap_result(map) do
    %{
      run_id: Map.get(map, :run_id) || UUID.uuid4(),
      best_metric: Map.fetch!(map, :best_metric),
      best_trial: Map.get(map, :best_trial),
      trials: Map.fetch!(map, :trials),
      artifact_path: Map.get(map, :artifact_path, :noop),
      metrics_summary: Map.get(map, :metrics_summary, %{}),
      schema_version: Result.schema_version()
    }
  end
end
