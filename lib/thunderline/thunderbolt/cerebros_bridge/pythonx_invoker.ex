defmodule Thunderline.Thunderbolt.CerebrosBridge.PythonxInvoker do
  @moduledoc """
  Pythonx-based Cerebros bridge invoker.

  This module replaces subprocess invocation with direct Python calls via Pythonx,
  providing much better performance and error handling.

  ## Configuration

  Add to config.exs:

      config :thunderline, :cerebros_bridge,
        invoker: :pythonx,  # or :subprocess (default)
        python_path: ["thunderhelm", "path/to/cerebros-core"]

  """

  alias Thunderline.Thunderflow.ErrorClass
  alias Thunderline.Thunderbolt.CerebrosBridge.Client

  require Logger

  @telemetry_base [:cerebros, :bridge, :pythonx]

  @doc """
  Initialize Pythonx Python runtime with Cerebros service module loaded.

  This should be called during application startup.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    config = Client.config()
    python_path = Application.get_env(:thunderline, :cerebros_bridge, [])
                  |> Keyword.get(:python_path, ["thunderhelm"])

    Logger.info("[CerebrosBridge.PythonxInvoker] Initializing Pythonx with paths: #{inspect(python_path)}")

    try do
      # Add paths to Python's sys.path
      Enum.each(python_path, fn path ->
        abs_path = Path.expand(path)
        if File.dir?(abs_path) do
          Pythonx.eval("import sys; sys.path.insert(0, '#{abs_path}')")
          Logger.info("[CerebrosBridge.PythonxInvoker] Added to sys.path: #{abs_path}")
        else
          Logger.warning("[CerebrosBridge.PythonxInvoker] Path not found: #{abs_path}")
        end
      end)

      # Try to import cerebros_service module
      case Pythonx.eval("import cerebros_service; 'ok'") do
        {:ok, "ok"} ->
          Logger.info("[CerebrosBridge.PythonxInvoker] Successfully loaded cerebros_service module")
          :ok
        {:error, reason} ->
          Logger.error("[CerebrosBridge.PythonxInvoker] Failed to load cerebros_service: #{inspect(reason)}")
          {:error, {:module_load_failed, reason}}
      end
    rescue
      error ->
        Logger.error("[CerebrosBridge.PythonxInvoker] Initialization error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Invoke Cerebros operation via Pythonx.

  This is the main entry point called by the Client module.
  """
  @spec invoke(atom(), map(), keyword()) :: {:ok, map()} | {:error, ErrorClass.t()}
  def invoke(op, call_spec, opts \\ []) when is_atom(op) do
    if not Client.enabled?() do
      {:error, disabled_error(op)}
    else
      config = Keyword.get(opts, :config, Client.config())
      timeout_ms = Keyword.get(opts, :timeout_ms, config.invoke.default_timeout_ms || 15_000)
      meta = Keyword.get(opts, :meta, %{}) |> Map.merge(Map.get(call_spec, :meta, %{}))

      invocation_meta = Map.merge(meta, %{op: op, invoker: :pythonx})
      :telemetry.execute(@telemetry_base ++ [:start], %{}, invocation_meta)

      t0 = System.monotonic_time()
      result = attempt_pythonx_invoke(op, call_spec, timeout_ms, invocation_meta)
      duration_ms = System.convert_time_unit(System.monotonic_time() - t0, :native, :millisecond)

      case result do
        {:ok, decoded} ->
          :telemetry.execute(
            @telemetry_base ++ [:stop],
            %{duration_ms: duration_ms},
            Map.put(invocation_meta, :ok, true)
          )
          {:ok, Map.put(decoded, :duration_ms, duration_ms)}

        {:error, error} ->
          telemetry_error = Map.merge(invocation_meta, %{
            error: error_to_map(error),
            duration_ms: duration_ms
          })
          :telemetry.execute(@telemetry_base ++ [:exception], %{}, telemetry_error)
          {:error, error}
      end
    end
  end

  # -- Internal Helpers ------------------------------------------------------

  defp attempt_pythonx_invoke(:start_run, call_spec, timeout_ms, meta) do
    # Extract spec and opts from call_spec
    spec = Map.get(call_spec, :spec, %{})
    opts = Map.get(call_spec, :opts, %{})

    Logger.info("[CerebrosBridge.PythonxInvoker] Calling cerebros_service.run_nas")
    Logger.debug("[CerebrosBridge.PythonxInvoker] Spec: #{inspect(spec)}")
    Logger.debug("[CerebrosBridge.PythonxInvoker] Opts: #{inspect(opts)}")

    # Call Python function with timeout
    task = Task.Supervisor.async_nolink(Thunderline.TaskSupervisor, fn ->
      call_python_run_nas(spec, opts)
    end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok, %{
          returncode: 0,
          stdout: Jason.encode!(result),
          stderr: "",
          stdout_excerpt: excerpt(result),
          stderr_excerpt: "",
          attempts: 1,
          parsed: result,
          raw: result
        }}

      {:ok, {:error, reason}} ->
        {:error, python_error(:start_run, reason, meta)}

      nil ->
        {:error, timeout_error(:start_run, timeout_ms, meta)}
    end
  rescue
    error ->
      {:error, unexpected_error(:start_run, :error, error, meta)}
  end

  defp attempt_pythonx_invoke(op, _call_spec, _timeout_ms, _meta) do
    {:error, unsupported_op_error(op)}
  end

  defp call_python_run_nas(spec, opts) do
    # Use Pythonx's proper data passing mechanism:
    # Pass Elixir data structures via globals, let Pythonx handle encoding
    python_code = """
    import cerebros_service

    # spec and opts are passed from Elixir via globals
    # Pythonx automatically converts them to Python dicts
    result = cerebros_service.run_nas(spec, opts)
    result
    """

    # Pass data through globals - Pythonx.Encoder protocol handles conversion
    globals = %{
      "spec" => normalize_for_python(spec),
      "opts" => normalize_for_python(opts)
    }

    case Pythonx.eval(python_code, globals) do
      {result_obj, _updated_globals} ->
        # Decode Python object back to Elixir
        decoded = Pythonx.decode(result_obj)
        {:ok, decoded}

      {:error, reason} ->
        {:error, {:pythonx_eval_failed, reason}}
    end
  rescue
    error ->
      {:error, {:pythonx_call_failed, error}}
  end

  # Normalize Elixir data for Python encoding
  # Converts atoms to strings, handles nil, datetime, etc.
  defp normalize_for_python(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), normalize_for_python(v)} end)
  end

  defp normalize_for_python(list) when is_list(list) do
    Enum.map(list, &normalize_for_python/1)
  end

  defp normalize_for_python(atom) when is_atom(atom) and not is_nil(atom) and atom not in [true, false] do
    to_string(atom)
  end

  defp normalize_for_python(value), do: value

  # -- Error Construction ------------------------------------------------------

  defp disabled_error(op) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :dependency,
      severity: :error,
      visibility: :external,
      context: %{
        reason: :bridge_disabled,
        op: op,
        invoker: :pythonx
      }
    }
  end

  defp python_error(op, reason, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :execution,
      severity: :error,
      visibility: :external,
      context: %{
        op: op,
        reason: :python_error,
        error: inspect(reason),
        invoker: :pythonx,
        meta: meta
      }
    }
  end

  defp timeout_error(op, timeout_ms, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :transient,
      severity: :warning,
      visibility: :internal,
      context: %{
        op: op,
        reason: :timeout,
        timeout_ms: timeout_ms,
        invoker: :pythonx,
        meta: meta
      }
    }
  end

  defp unexpected_error(op, kind, value, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :execution,
      severity: :error,
      visibility: :internal,
      context: %{
        op: op,
        reason: :unexpected_error,
        kind: kind,
        error: inspect(value),
        invoker: :pythonx,
        meta: meta
      }
    }
  end

  defp unsupported_op_error(op) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :validation,
      severity: :error,
      visibility: :external,
      context: %{
        reason: :unsupported_operation,
        op: op,
        invoker: :pythonx,
        supported_ops: [:start_run]
      }
    }
  end

  # -- Utility Functions ------------------------------------------------------

  defp excerpt(data) when is_binary(data) do
    if String.length(data) > 200 do
      String.slice(data, 0, 200) <> "..."
    else
      data
    end
  end

  defp excerpt(data) when is_map(data) do
    data
    |> Jason.encode!()
    |> excerpt()
  end

  defp excerpt(data), do: inspect(data) |> excerpt()

  defp error_to_map(%ErrorClass{} = error), do: Map.from_struct(error)
  defp error_to_map(value), do: %{error: inspect(value)}
end
