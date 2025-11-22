defmodule Thunderline.Thunderbolt.Cerebros.Adapter do
  @moduledoc """
  Unified façade for ML search with hybrid delegation strategy.

  Delegation order:
    1. When the Cerebros bridge feature is enabled, runs are enqueued through
       `Thunderline.Thunderbolt.CerebrosBridge.enqueue_run/2` and executed
       asynchronously by `CerebrosBridge.RunWorker` (Oban).
    2. If the bridge is unavailable or `:force_legacy` is supplied, the adapter
       falls back to the previous hybrid path: external library → CLI →
       in-process simple search stub.

  Async queue responses return metadata describing the job and run id. Legacy
  synchronous paths still return the historic contract with `:best_metric`,
  `:best_spec`, and a `:persisted` placeholder for compatibility.
  """
  require Logger
  alias Thunderline.EventBus
  alias Thunderline.Thunderbolt.Cerebros.{SimpleSearch, Artifacts, Telemetry}
  alias Thunderline.Thunderbolt.CerebrosBridge
  alias Thunderline.Thunderbolt.CerebrosBridge.Validator
  alias Thunderline.UUID

  @external_fun {:Cerebros, :run_search, 1}

  @doc "Submit a NAS spec. When the Cerebros bridge is enabled the run is enqueued asynchronously via Oban."
  def run_search(opts_or_spec, opts \\ []) do
    Telemetry.attach_logger()

    case normalize_input(opts_or_spec, opts) do
      {:error, reason} -> {:error, reason}
      {:legacy_opts, legacy_opts} -> run_legacy(legacy_opts)
      {:ok, spec, validation} -> dispatch_run(spec, opts, validation)
    end
  end

  @doc "Backward-compatible wrapper that delegates to run_search/2."
  def run_and_record(opts_or_spec, opts \\ []), do: run_search(opts_or_spec, opts)

  @doc "Load an artifact (delegates to Artifacts)."
  def load_artifact(path), do: Artifacts.load(path)

  @doc "Predict with an artifact path (stub)."
  def predict_with_artifact(path, samples) do
    with {:ok, art} <- Artifacts.load(path) do
      {:ok, Artifacts.predict_stub(art, samples)}
    end
  end

  ## Delegation ------------------------------------------------------------

  defp dispatch_run(spec, opts, validation) do
    cond do
      route_through_bridge?(opts) -> enqueue_via_bridge(spec, opts, validation)
      true -> run_hybrid(spec)
    end
  end

  defp route_through_bridge?(opts) do
    not Keyword.get(opts, :force_legacy, false) and CerebrosBridge.enabled?()
  end

  defp enqueue_via_bridge(spec, opts, validation) do
    spec = ensure_defaults(spec)
    run_id = Keyword.get(opts, :run_id) || Map.get(spec, "run_id") || UUID.v7()
    spec = Map.put(spec, "run_id", run_id)
    enqueue_opts = build_enqueue_opts(spec, opts, run_id)

    emit_progress(:queued, %{run_id: run_id, spec: spec})

    case CerebrosBridge.enqueue_run(spec, enqueue_opts) do
      {:ok, %Oban.Job{} = job} ->
        {:ok,
         %{
           status: :queued,
           mode: :async,
           run_id: run_id,
           job: job,
           job_id: job.id,
           queue: job.queue,
           priority: job.priority,
           scheduled_at: job.scheduled_at || job.inserted_at,
           validation: validation_summary(validation),
           persisted: %{model_run_id: nil, artifact_ids: []}
         }}

      {:error, reason} ->
        Logger.error("[Cerebros.Adapter] enqueue via Cerebros bridge failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_legacy(opts) when is_list(opts) do
    emit_progress(:start, %{mode: :legacy_opts})

    case simple_search(opts) do
      {:ok, result} = _ok ->
        emit_progress(:complete, result)
        {:ok, normalize_result(result)}

      {:error, _} = err ->
        emit_progress(:error, %{error: err})
        err
    end
  end

  defp run_hybrid(spec) do
    spec = ensure_defaults(spec)
    emit_progress(:start, spec)

    result =
      cond do
        external_available?() ->
          Logger.info("[Cerebros.Adapter] External library available – delegating in-process")
          external(atomize_keys(spec))

        cli_available?() ->
          Logger.info("[Cerebros.Adapter] CLI available – delegating to system executable")
          cli(spec)

        true ->
          Logger.info("[Cerebros.Adapter] Falling back to internal stub search")
          simple_search(spec_to_internal_opts(spec))
      end

    case result do
      {:ok, res} = _ok ->
        emit_progress(:complete, res)
        {:ok, normalize_result(res)}

      {:error, _} = err ->
        emit_progress(:error, %{error: err, spec: spec})
        err
    end
  end

  defp simple_search(opts) do
    case SimpleSearch.simple_search(opts) do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  defp external_available?,
    do: function_exported?(elem(@external_fun, 0), elem(@external_fun, 1), elem(@external_fun, 2))

  defp cli_available?, do: System.find_executable("cerebros") != nil

  defp external(spec) do
    try do
      {:ok, apply(elem(@external_fun, 0), elem(@external_fun, 1), [spec])}
    rescue
      e ->
        Logger.error("[Cerebros.Adapter] external failure #{Exception.message(e)}; falling back")
        simple_search(spec_to_internal_opts(spec))
    end
  end

  defp cli(spec) do
    json = Jason.encode!(spec)
    {out, exit} = System.cmd("cerebros", ["json", "--spec"], input: json, stderr_to_stdout: true)

    case exit do
      0 ->
        Jason.decode(out)

      _ ->
        Logger.error("[Cerebros.Adapter] CLI failed (code #{exit}): #{out}")
        simple_search(spec_to_internal_opts(spec))
    end
  rescue
    e ->
      Logger.error("[Cerebros.Adapter] CLI exception #{inspect(e)}; falling back")
      simple_search(spec_to_internal_opts(spec))
  end

  ## Spec Mapping ----------------------------------------------------------

  defp normalize_input(opts, _opts) when is_list(opts), do: {:legacy_opts, opts}

  defp normalize_input(spec, _opts) when is_binary(spec) do
    case Validator.validate_spec(spec) do
      %{status: :error, errors: errors} = validation ->
        {:error, {:invalid_spec, errors || validation}}

      validation ->
        spec_map = validation.spec || %{}
        {:ok, normalize_spec(spec_map), validation_summary(validation)}
    end
  end

  defp normalize_input(%{} = spec, opts) do
    if Keyword.get(opts, :validate?, false) do
      case Validator.validate_spec(spec) do
        %{status: :error, errors: errors} = validation ->
          {:error, {:invalid_spec, errors || validation}}

        validation ->
          {:ok, normalize_spec(validation.spec || spec), validation_summary(validation)}
      end
    else
      {:ok, normalize_spec(spec), nil}
    end
  end

  defp normalize_input(_other, _opts), do: {:error, :invalid_spec}

  defp normalize_spec(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      Map.put(acc, normalize_key(key), normalize_spec(val))
    end)
  end

  defp normalize_spec(list) when is_list(list), do: Enum.map(list, &normalize_spec/1)
  defp normalize_spec(other), do: other

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp ensure_defaults(spec) do
    spec
    |> Map.put_new("search_space_version", 1)
    |> Map.put_new("requested_trials", Map.get(spec, "trials", 3))
    |> Map.put_new("max_params", 2_000_000)
  end

  defp build_enqueue_opts(spec, opts, run_id) do
    base = [
      run_id: run_id,
      pulse_id: Keyword.get(opts, :pulse_id) || Map.get(spec, "pulse_id"),
      budget: Keyword.get(opts, :budget) || Map.get(spec, "budget"),
      parameters: Keyword.get(opts, :parameters) || Map.get(spec, "parameters"),
      tau: Keyword.get(opts, :tau) || Map.get(spec, "tau") || get_in(spec, ["pulse", "tau"]),
      correlation_id:
        Keyword.get(opts, :correlation_id) || Map.get(spec, "correlation_id") || run_id,
      extra: Keyword.get(opts, :extra) || Map.get(spec, "extra"),
      meta: Keyword.get(opts, :meta) || Map.get(spec, "metadata") || %{}
    ]

    Enum.reject(base, fn {_key, value} -> is_nil(value) end)
  end

  # Map external spec contract to internal simple search opts.
  defp spec_to_internal_opts(spec) do
    dataset = fetch_spec!(spec, :dataset)
    trials = fetch_spec(spec, :trials, fetch_spec(spec, :requested_trials, 3))
    max_params = fetch_spec(spec, :max_params, 2_000_000)
    seed = fetch_spec(spec, :seed)
    [dataset: dataset, trials: trials, max_params: max_params, seed: seed]
  end

  defp fetch_spec(spec, key, default \\ nil) do
    cond do
      Map.has_key?(spec, key) -> Map.get(spec, key)
      Map.has_key?(spec, Atom.to_string(key)) -> Map.get(spec, Atom.to_string(key))
      true -> default
    end
  end

  defp fetch_spec!(spec, key) do
    case fetch_spec(spec, key) do
      nil -> raise ArgumentError, "spec requires #{inspect(key)}"
      value -> value
    end
  end

  defp normalize_result(%{best_metric: _} = res),
    do: Map.put_new(res, :persisted, %{model_run_id: nil, artifact_ids: []})

  defp normalize_result(other), do: other

  defp validation_summary(nil), do: nil

  defp validation_summary(%{status: status} = validation) do
    Map.take(validation, [:status, :errors, :warnings])
    |> Map.put_new(:status, status)
  end

  defp atomize_keys(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      Map.put(acc, atomize_key(key), atomize_keys(val))
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other

  defp atomize_key(key) when is_atom(key), do: key

  defp atomize_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end

  defp atomize_key(key), do: key

  ## Progress Emission -----------------------------------------------------

  defp emit_progress(stage, data) do
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "ai.cerebros_search_progress",
             source: :bolt,
             payload: %{
               stage: stage,
               at: System.system_time(:millisecond),
               data: sanitize_progress(data)
             },
             meta: %{pipeline: :realtime},
             type: :cerebros_search_progress
           ),
         {:ok, _} <- EventBus.publish_event(ev) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("[Cerebros.Adapter] progress event publish failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  defp sanitize_progress(%{artifact: path} = data) when is_binary(path) do
    Map.put(data, :artifact, Path.basename(path))
  end

  defp sanitize_progress(data), do: data
end
