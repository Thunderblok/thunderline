defmodule Thunderline.Thunderbolt.CerebrosBridge.Client do
  @moduledoc """
  Feature-gated facade for Cerebros execution.

  Responsibilities:
    * Honor the `:ml_nas` feature flag before any invocation
    * Materialize configuration from `config :thunderline, :cerebros_bridge`
    * Marshal contracts through the translator
    * Call the invoker with retry/timeout semantics
    * Maintain optional result caching
    * Emit canonical `%Thunderline.Event{}` telemetry for run lifecycle milestones
  """

  alias Thunderline.Thunderflow.ErrorClass
  alias Thunderline.Event
  alias Thunderline.EventBus
  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.CerebrosBridge.{Cache, Contracts, Invoker, Translator}

  require Logger

  @app :thunderline
  @feature_flag :ml_nas

  @doc """
  Returns true when the `:ml_nas` feature flag and runtime configuration both enable the bridge.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    feature?() and config().enabled?
  end

  @doc """
  Returns the current Cerebros bridge configuration map.
  """
  @spec config() :: %{
          enabled?: boolean(),
          repo_path: Path.t() | nil,
          script_path: Path.t() | nil,
          python_executable: String.t(),
          working_dir: Path.t() | nil,
          env: map(),
          invoke: %{default_timeout_ms: pos_integer(), max_retries: non_neg_integer(), retry_backoff_ms: non_neg_integer()},
          cache: %{enabled?: boolean(), ttl_ms: non_neg_integer(), max_entries: non_neg_integer() | nil}
        }
  def config do
    raw = Application.get_env(@app, :cerebros_bridge, [])
    invoke = Keyword.get(raw, :invoke, [])
    cache = Keyword.get(raw, :cache, [])
    env = normalize_env(Keyword.get(raw, :env, %{}))

    %{
      enabled?: truthy?(Keyword.get(raw, :enabled, false)),
      repo_path: Keyword.get(raw, :repo_path),
      script_path: Keyword.get(raw, :script_path),
      python_executable: Keyword.get(raw, :python_executable, "python3"),
      working_dir: Keyword.get(raw, :working_dir),
      env: env,
      invoke: %{
        default_timeout_ms: Keyword.get(invoke, :default_timeout_ms, 15_000),
        max_retries: Keyword.get(invoke, :max_retries, 2),
        retry_backoff_ms: Keyword.get(invoke, :retry_backoff_ms, 750)
      },
      cache: %{
        enabled?: truthy?(Keyword.get(cache, :enabled, true)),
        ttl_ms: Keyword.get(cache, :ttl_ms, 30_000),
        max_entries: Keyword.get(cache, :max_entries, 512)
      }
    }
  end

  @doc """
  Discover the Cerebros repository VERSION file when available.
  """
  @spec version(Path.t()) :: {:ok, String.t()} | {:error, :version_unavailable}
  def version(repo_path \\ config().repo_path) do
    path = Path.join(repo_path || ".", "VERSION")

    with true <- File.exists?(path),
         {:ok, v} <- File.read(path) do
      {:ok, String.trim(v)}
    else
      _ -> {:error, :version_unavailable}
    end
  end

  @doc """
  Invoke the Cerebros bridge start-run contract. Emits canonical ML run events.
  """
  @spec start_run(Contracts.RunStartedV1.t(), keyword()) ::
          {:ok, map()} | {:error, ErrorClass.t()}
  def start_run(%Contracts.RunStartedV1{} = contract, opts \\ []) do
    with_bridge(fn config ->
      encoded = Translator.encode(:start_run, contract, config, opts)
      meta = Map.get(encoded, :meta, %{})
      emit_run_event(:start, contract, meta)

      result =
        maybe_cache(encoded.cache_key, opts, config, fn ->
          with {:ok, raw} <- Invoker.invoke(:start_run, encoded, config: config, meta: meta) do
            {:ok, Translator.decode(:start_run, contract, raw, config)}
          end
        end)

      case result do
        {:ok, decoded} ->
          emit_run_event(:stop, contract, Map.merge(meta, Map.take(decoded, [:returncode, :stdout_excerpt, :duration_ms])))
          {:ok, decoded}

        {:error, error} ->
          emit_run_event(:exception, contract, Map.merge(meta, %{error: error_to_map(error)}))
          {:error, error}
      end
    end)
  end

  @doc """
  Invoke the Cerebros bridge trial reporting contract.
  """
  @spec record_trial(Contracts.TrialReportedV1.t(), keyword()) ::
          {:ok, map()} | {:error, ErrorClass.t()}
  def record_trial(%Contracts.TrialReportedV1{} = contract, opts \\ []) do
    with_bridge(fn config ->
      encoded = Translator.encode(:record_trial, contract, config, opts)
      meta = Map.get(encoded, :meta, %{})

      result =
        maybe_cache(encoded.cache_key, opts, config, fn ->
          with {:ok, raw} <- Invoker.invoke(:record_trial, encoded, config: config, meta: meta) do
            {:ok, Translator.decode(:record_trial, contract, raw, config)}
          end
        end)

      case result do
        {:ok, decoded} ->
          emit_trial_event(contract, Map.merge(meta, Map.take(decoded, [:returncode, :stdout_excerpt, :duration_ms])))
          {:ok, decoded}

        {:error, error} ->
          emit_trial_event(contract, Map.merge(meta, %{error: error_to_map(error)}))
          {:error, error}
      end
    end)
  end

  @doc """
  Invoke the Cerebros bridge finalize-run contract. Emits stop/exception events.
  """
  @spec finalize_run(Contracts.RunFinalizedV1.t(), keyword()) ::
          {:ok, map()} | {:error, ErrorClass.t()}
  def finalize_run(%Contracts.RunFinalizedV1{} = contract, opts \\ []) do
    with_bridge(fn config ->
      encoded = Translator.encode(:finalize_run, contract, config, opts)
      meta = Map.get(encoded, :meta, %{})

      result =
        maybe_cache(encoded.cache_key, opts, config, fn ->
          with {:ok, raw} <- Invoker.invoke(:finalize_run, encoded, config: config, meta: meta) do
            {:ok, Translator.decode(:finalize_run, contract, raw, config)}
          end
        end)

      case result do
        {:ok, decoded} ->
          emit_run_event(:stop, contract, Map.merge(meta, Map.take(decoded, [:returncode, :stdout_excerpt, :duration_ms])))
          {:ok, decoded}

        {:error, error} ->
          emit_run_event(:exception, contract, Map.merge(meta, %{error: error_to_map(error)}))
          {:error, error}
      end
    end)
  end

  @doc """
  Generic bridge invocation helper for ad-hoc payloads.
  """
  @spec invoke(atom(), term(), keyword()) :: {:ok, map()} | {:error, ErrorClass.t()}
  def invoke(op, payload, opts \\ []) when is_atom(op) do
    with_bridge(fn config ->
      encoded = Translator.encode(op, payload, config, opts)
      meta = Map.get(encoded, :meta, %{})

      maybe_cache(encoded.cache_key, opts, config, fn ->
        with {:ok, raw} <- Invoker.invoke(op, encoded, config: config, meta: meta) do
          {:ok, Translator.decode(op, payload, raw, config)}
        end
      end)
    end)
  end

  # -- internal helpers ------------------------------------------------------

  defp with_bridge(fun) when is_function(fun, 1) do
    cond do
      not feature?() ->
        {:error, disabled_error(:feature_flag_disabled)}

      true ->
        config = config()

        if config.enabled? do
          fun.(config)
        else
          {:error, disabled_error(:config_disabled)}
        end
    end
  end

  defp maybe_cache(nil, _opts, _config, fun), do: fun.()

  defp maybe_cache(cache_key, opts, config, fun) do
    ttl_ms = Keyword.get(opts, :cache_ttl_ms, config.cache.ttl_ms || 30_000)

    if config.cache.enabled? and Cache.enabled?() do
      case Cache.get(cache_key, ttl_ms) do
        {:hit, value} ->
          {:ok, value}

        {:miss, _} ->
          case fun.() do
            {:ok, value} = success ->
              Cache.put(cache_key, value, ttl_ms)
              success

            error ->
              error
          end
      end
    else
      fun.()
    end
  end

  defp emit_run_event(stage, contract, extra) do
    name =
      case stage do
        :start -> "ml.run.start"
        :stop -> "ml.run.stop"
        :exception -> "ml.run.exception"
        other -> "ml.run.#{other}"
      end

    payload =
      %{
        run_id: contract.run_id,
        correlation_id: contract.correlation_id || contract.run_id,
        pulse_id: Map.get(contract, :pulse_id)
      }
      |> Map.merge(normalize_map(extra))

    publish_event(name, payload)
  end

  defp emit_trial_event(contract, extra) do
    payload =
      %{
        run_id: contract.run_id,
        trial_id: contract.trial_id,
        status: contract.status,
        correlation_id: Map.get(extra, :correlation_id, contract.run_id)
      }
      |> Map.merge(normalize_map(extra))

    publish_event("ml.run.trial", payload)
  end

  defp publish_event(name, payload) do
    attrs = [name: name, source: :bolt, payload: payload, meta: %{pipeline: :realtime}]

    case Event.new(attrs) do
      {:ok, event} ->
        _ = EventBus.publish_event(event)
        :ok

      {:error, reason} ->
        Logger.warning("[CerebrosBridge.Client] failed to publish #{name} event: #{inspect(reason)}")
        :ok
    end
  end

  defp feature? do
    Feature.enabled?(@feature_flag, default: false)
  end

  defp disabled_error(reason) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :dependency,
      severity: :error,
      visibility: :external,
      context: %{reason: reason}
    }
  end

  defp error_to_map(%ErrorClass{} = error), do: Map.from_struct(error)
  defp error_to_map(value), do: normalize_value(value)

  defp normalize_map(nil), do: %{}
  defp normalize_map(%{} = map), do: Map.new(map, fn {k, v} -> {k, normalize_value(v)} end)
  defp normalize_map(other), do: %{value: normalize_value(other)}

  defp normalize_value(%ErrorClass{} = error), do: Map.from_struct(error)
  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_value(%{} = map), do: normalize_map(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_env(env) when is_map(env) do
    env
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), normalize_env_value(v))
    end)
  end

  defp normalize_env(env) when is_list(env) do
    env
    |> Enum.reduce(%{}, fn
      {k, v}, acc -> Map.put(acc, to_string(k), normalize_env_value(v))
      _other, acc -> acc
    end)
  end

  defp normalize_env(_), do: %{}

  defp normalize_env_value(nil), do: ""
  defp normalize_env_value(value) when is_binary(value), do: value
  defp normalize_env_value(value), do: to_string(value)

  defp truthy?(value) when value in [false, "false", "FALSE", 0, "0", nil], do: false
  defp truthy?(_), do: true
end
