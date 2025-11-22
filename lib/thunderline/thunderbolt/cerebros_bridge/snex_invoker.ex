defmodule Thunderline.Thunderbolt.CerebrosBridge.SnexInvoker do
  @moduledoc """
  Snex-based Cerebros bridge invoker - GIL-free Python interop!

  Uses Snex's sub-interpreter feature to run multiple Python jobs
  concurrently without GIL blocking. Perfect for parallel model training.

  ## Configuration

  Add to config.exs:

      config :thunderline, :cerebros_bridge,
        invoker: :snex,
        python_path: ["thunderhelm", "path/to/cerebros-core"]

  ## Advantages over Pythonx

  - **No GIL blocking**: Multiple training jobs run in parallel
  - **Shared memory**: Faster data passing
  - **Sub-interpreters**: Isolated Python contexts per job
  - **Better concurrency**: Native Elixir process per Python call

  """

  alias Thunderline.Thunderflow.ErrorClass
  alias Thunderline.Thunderbolt.CerebrosBridge.Client

  require Logger

  @telemetry_base [:cerebros, :bridge, :snex]

  @doc """
  Initialize Snex interpreter with Cerebros service module loaded.

  This should be called during application startup.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    python_paths = Application.get_env(:thunderline, :cerebros_bridge, [])
                   |> Keyword.get(:python_path, ["thunderhelm"])

    Logger.info("[CerebrosBridge.SnexInvoker] Initializing with paths: #{inspect(python_paths)}")

    # Convert relative paths to absolute
    abs_paths = Enum.map(python_paths, fn path ->
      if Path.absname(path) == path do
        path
      else
        Path.join(File.cwd!(), path)
      end
    end)

    # Add paths to Python sys.path
    for path <- abs_paths do
      if File.exists?(path) do
        Logger.info("[CerebrosBridge.SnexInvoker] Adding to sys.path: #{path}")

        # Use Snex to modify sys.path
        Snex.Interpreter.run("""
        import sys
        if '#{path}' not in sys.path:
            sys.path.insert(0, '#{path}')
        """)
      else
        Logger.warning("[CerebrosBridge.SnexInvoker] Path not found: #{path}")
      end
    end

    # Test loading cerebros_service
    case Snex.Interpreter.run("import cerebros_service; cerebros_service") do
      {:ok, _module} ->
        Logger.info("[CerebrosBridge.SnexInvoker] Successfully loaded cerebros_service module")
        :ok

      {:error, error} ->
        Logger.error("[CerebrosBridge.SnexInvoker] Failed to load cerebros_service: #{inspect(error)}")
        {:error, error}
    end
  rescue
    error ->
      Logger.error("[CerebrosBridge.SnexInvoker] Initialization error: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Invoke a Cerebros operation via Snex.

  ## Options

  - `:timeout_ms` - Max time to wait (default: 15000)
  - `:config` - Bridge config override
  - `:meta` - Additional telemetry metadata

  ## Returns

  - `{:ok, result_map}` - Success with parsed result
  - `{:error, error_class}` - Failure with error details
  """
  @spec invoke(atom(), map(), keyword()) :: {:ok, map()} | {:error, ErrorClass.t()}
  def invoke(op, call_spec, opts \\ []) when is_atom(op) do
    if not Client.enabled?() do
      {:error, disabled_error(op)}
    else
      config = Keyword.get(opts, :config, Client.config())
      timeout_ms = Keyword.get(opts, :timeout_ms, config.invoke.default_timeout_ms || 15_000)
      meta = Keyword.get(opts, :meta, %{}) |> Map.merge(Map.get(call_spec, :meta, %{}))

      invocation_meta = Map.merge(meta, %{op: op, invoker: :snex})
      :telemetry.execute(@telemetry_base ++ [:start], %{}, invocation_meta)

      t0 = System.monotonic_time()
      result = attempt_snex_invoke(op, call_spec, timeout_ms, invocation_meta)
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
          telemetry_error =
            Map.merge(invocation_meta, %{
              error: error_to_map(error),
              duration_ms: duration_ms
            })

          :telemetry.execute(@telemetry_base ++ [:exception], %{}, telemetry_error)
          {:error, error}
      end
    end
  end

  # -- Internal Helpers ------------------------------------------------------

  defp attempt_snex_invoke(:start_run, call_spec, timeout_ms, meta) do
    # Extract spec and opts from call_spec
    spec = Map.get(call_spec, :spec, %{})
    opts = Map.get(call_spec, :opts, %{})

    Logger.info("[CerebrosBridge.SnexInvoker] Calling cerebros_service.run_nas")
    Logger.debug("[CerebrosBridge.SnexInvoker] Spec: #{inspect(spec)}")
    Logger.debug("[CerebrosBridge.SnexInvoker] Opts: #{inspect(opts)}")

    # Call Python function with timeout using Snex
    task =
      Task.Supervisor.async_nolink(Thunderline.TaskSupervisor, fn ->
        call_snex_run_nas(spec, opts)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok,
         %{
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

  defp attempt_snex_invoke(op, _call_spec, _timeout_ms, _meta)
       when op in [
              :extract_entities,
              :tokenize,
              :analyze_sentiment,
              :analyze_syntax,
              :process_text
            ] do
    {:error,
     %ErrorClass{
       origin: :cerebros_bridge,
       class: :validation,
       severity: :error,
       visibility: :external,
       context: %{
         reason: :use_nlp_service_directly,
         op: op,
         hint: "Use Thunderline.Thunderbolt.CerebrosBridge.NLP module for NLP operations"
       }
     }}
  end

  defp attempt_snex_invoke(op, _call_spec, _timeout_ms, _meta) do
    {:error, unsupported_op_error(op)}
  end

  defp call_snex_run_nas(spec, opts) do
    # Snex.Interpreter.run allows passing variables and getting results
    # Much cleaner than Pythonx's eval approach!

    python_code = """
    import cerebros_service
    import json

    # Parse JSON strings to Python dicts
    spec_dict = json.loads(spec_json)
    opts_dict = json.loads(opts_json)

    # Call the training function
    result = cerebros_service.run_nas(spec_dict, opts_dict)

    # Return result as JSON string
    json.dumps(result)
    """

    # Prepare variables - Snex handles basic types well
    variables = %{
      "spec_json" => Jason.encode!(normalize_for_python(spec)),
      "opts_json" => Jason.encode!(normalize_for_python(opts))
    }

    # Run Python code with variables
    case Snex.Interpreter.run(python_code, variables) do
      {:ok, result_json} when is_binary(result_json) ->
        decoded = Jason.decode!(result_json)
        {:ok, decoded}

      {:ok, result} ->
        # If result is not JSON string, try to use it directly
        {:ok, result}

      {:error, error} ->
        {:error, {:snex_call_failed, error}}
    end
  rescue
    error ->
      {:error, {:snex_call_failed, error}}
  end

  # Normalize Elixir data for Python encoding
  defp normalize_for_python(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), normalize_for_python(v)} end)
  end

  defp normalize_for_python(list) when is_list(list) do
    Enum.map(list, &normalize_for_python/1)
  end

  defp normalize_for_python(atom) when is_atom(atom) and not is_nil(atom) and atom != true and atom != false do
    to_string(atom)
  end

  defp normalize_for_python(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp normalize_for_python(other), do: other

  defp excerpt(data) when is_map(data) or is_list(data) do
    Jason.encode!(data) |> String.slice(0, 200)
  end

  defp excerpt(data), do: inspect(data) |> String.slice(0, 200)

  # -- Error Constructors ----------------------------------------------------

  defp disabled_error(op) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :validation,
      severity: :warning,
      visibility: :external,
      context: %{reason: :bridge_disabled, op: op}
    }
  end

  defp python_error(op, reason, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :transient,
      severity: :error,
      visibility: :external,
      context: Map.merge(meta, %{op: op, reason: reason, invoker: :snex})
    }
  end

  defp timeout_error(op, timeout_ms, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :transient,
      severity: :error,
      visibility: :external,
      context: Map.merge(meta, %{op: op, timeout_ms: timeout_ms, reason: :timeout, invoker: :snex})
    }
  end

  defp unexpected_error(op, class, error, meta) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: class,
      severity: :error,
      visibility: :external,
      context: Map.merge(meta, %{op: op, error: inspect(error), invoker: :snex})
    }
  end

  defp unsupported_op_error(op) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :validation,
      severity: :error,
      visibility: :external,
      context: %{reason: :unsupported_operation, op: op, invoker: :snex}
    }
  end

  defp error_to_map(%ErrorClass{} = error) do
    Map.from_struct(error)
  end

  defp error_to_map(error), do: %{error: inspect(error)}
end
