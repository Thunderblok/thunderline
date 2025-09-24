defmodule Thunderline.Thunderbolt.CerebrosBridge.Invoker do
  @moduledoc """
  Executes Cerebros bridge calls as external subprocesses with retries,
  telemetry, and structured `%Thunderline.ErrorClass{}` mapping.
  """

  alias Thunderline.ErrorClass
  alias Thunderline.Thunderbolt.CerebrosBridge.Client

  require Logger

  @telemetry_base [:cerebros, :bridge, :invoke]

  @default_timeout_ms 15_000
  @default_max_retries 0
  @rescue_errors [RuntimeError, ArgumentError]

  @doc """
  Invoke the Cerebros bridge operation with retries and structured telemetry.

  ## Options

    * `:config` - bridge configuration map (defaults to `Client.config/0`)
    * `:meta` - telemetry metadata (default `%{}`)
    * `:timeout_ms` - per-attempt timeout override
    * `:max_retries` - override retry count
    * `:retry_backoff_ms` - override backoff interval
    * `:parser` - optional result parser (receives stdout) for custom decoding
  """
  @spec invoke(atom(), map(), keyword()) :: {:ok, map()} | {:error, ErrorClass.t()}
  def invoke(op, call_spec, opts \\ []) when is_atom(op) and is_map(call_spec) do
    if not Client.enabled?() do
      {:error, disabled_error(op)}
    else
      config = Keyword.get(opts, :config, Client.config())
      backoff = Keyword.get(opts, :retry_backoff_ms, config.invoke.retry_backoff_ms)
      max_retries = Keyword.get(opts, :max_retries, config.invoke.max_retries || @default_max_retries)
      timeout_ms = Keyword.get(opts, :timeout_ms, config.invoke.default_timeout_ms || @default_timeout_ms)
      meta = Keyword.get(opts, :meta, %{}) |> Map.merge(Map.get(call_spec, :meta, %{}))

      attempts = Enum.to_list(0..max_retries)

      do_invoke(op, call_spec, config,
        attempts: attempts,
        backoff: backoff,
        timeout_ms: timeout_ms,
        meta: meta,
        parser: Keyword.get(opts, :parser)
      )
    end
  end

  # -- internal helpers ------------------------------------------------------

  defp do_invoke(op, call_spec, config, opts) do
    Enum.reduce_while(opts[:attempts], nil, fn attempt, _acc ->
      invocation_meta = Map.merge(opts[:meta], %{op: op, attempt: attempt})
      :telemetry.execute(@telemetry_base ++ [:start], %{}, invocation_meta)

      t0 = System.monotonic_time()
      result = attempt_invoke(op, call_spec, config, opts, attempt)

      duration_ms = System.convert_time_unit(System.monotonic_time() - t0, :native, :millisecond)

      case result do
        {:ok, decoded} ->
          :telemetry.execute(@telemetry_base ++ [:stop], %{duration_ms: duration_ms}, Map.put(invocation_meta, :ok, true))
          {:halt, {:ok, Map.put(decoded, :duration_ms, duration_ms)}}

        {:error, error} ->
          telemetry_error = Map.merge(invocation_meta, %{error: Map.from_struct(error), duration_ms: duration_ms})
          :telemetry.execute(@telemetry_base ++ [:exception], %{}, telemetry_error)

          if attempt < List.last(opts[:attempts]) do
            maybe_backoff(opts[:backoff], attempt)
            {:cont, {:error, error}}
          else
            {:halt, {:error, error}}
          end
      end
    end)
  end

  defp attempt_invoke(op, call_spec, _config, opts, attempt) do
    command = Map.fetch!(call_spec, :command)
    args = Map.get(call_spec, :args, [])
    env = Map.get(call_spec, :env, %{})
    input = Map.get(call_spec, :input)
    working_dir = Map.get(call_spec, :working_dir)
    expect_json? = Map.get(call_spec, :expect_json?, true)
    timeout_ms = opts[:timeout_ms]
    parser = opts[:parser]

    task =
      Task.Supervisor.async_nolink(Thunderline.TaskSupervisor, fn ->
        run_system_cmd(command, args,
          env: env,
          input: input,
          cd: working_dir,
          timeout_ms: timeout_ms
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, raw}} ->
        decode_result(op, raw, expect_json?, parser, attempt)

      {:ok, {:error, reason}} ->
        {:error, system_error(op, reason, attempt)}

      nil ->
        {:error, timeout_error(op, timeout_ms, attempt)}
    end
  catch
    kind, value when kind in [:exit, :throw] ->
      {:error, unexpected_error(op, kind, value, attempt)}

    error ->
      {:error, unexpected_error(op, :error, error, attempt)}
  end

  defp decode_result(op, raw, expect_json?, parser, attempt) do
    stdout = Map.get(raw, :stdout, "")
    stderr = Map.get(raw, :stderr, "")
    returncode = Map.get(raw, :returncode, -1)
    stderr_excerpt = excerpt(stderr)
    stdout_excerpt = excerpt(stdout)

    parsed =
      cond do
        parser -> safe_parse(parser, stdout)
        expect_json? -> safe_parse(&Jason.decode/1, stdout)
        true -> {:ok, %{}}
      end

    result =
      case parsed do
        {:ok, decoded} ->
          {:ok,
           %{
             returncode: returncode,
             stdout: stdout,
             stderr: stderr,
             stdout_excerpt: stdout_excerpt,
             stderr_excerpt: stderr_excerpt,
             attempts: attempt + 1,
             parsed: decoded,
             raw: raw
           }}

        {:error, reason} ->
          {:error, parsing_error(op, reason, stdout, attempt, returncode)}
      end

    if returncode == 0 do
      result
    else
      {:error, exit_status_error(op, returncode, stdout, stderr, attempt)}
    end
  end

  defp run_system_cmd(command, args, opts) do
    env = format_env(opts[:env] || %{})

    System.cmd(command, args,
      env: env,
      cd: opts[:cd],
      input: opts[:input],
      stderr_to_stdout: false
    )
    |> wrap_cmd_result()
  rescue
    e ->
      {:error, {:command_failed, command, args, Exception.message(e)}}
  end

  defp wrap_cmd_result({stdout, exit_status}) do
    {:ok,
     %{
       stdout: stdout,
       stderr: "",
       returncode: exit_status
     }}
  end

  defp maybe_backoff(nil, _attempt), do: :ok
  defp maybe_backoff(backoff_ms, attempt) when backoff_ms <= 0, do: :ok
  defp maybe_backoff(backoff_ms, attempt) do
    scaled = trunc(backoff_ms * backoff_multiplier(attempt))
    Process.sleep(scaled)
  end

  defp backoff_multiplier(attempt), do: :math.pow(2, attempt)

  # -- error constructors -----------------------------------------------------

  defp disabled_error(op) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :dependency,
      severity: :error,
      visibility: :external,
      context: %{op: op, reason: :feature_disabled}
    }
  end

  defp timeout_error(op, timeout_ms, attempt) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :timeout,
      severity: :error,
      visibility: :external,
      context: %{op: op, timeout_ms: timeout_ms, attempt: attempt}
    }
  end

  defp exit_status_error(op, returncode, stdout, stderr, attempt) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :subprocess_exit,
      severity: :error,
      visibility: :external,
      context: %{
        op: op,
        returncode: returncode,
        attempt: attempt,
        stdout_excerpt: excerpt(stdout),
        stderr_excerpt: excerpt(stderr)
      }
    }
  end

  defp system_error(op, reason, attempt) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :system_error,
      severity: :error,
      visibility: :internal,
      context: %{op: op, attempt: attempt, reason: inspect(reason)}
    }
  end

  defp parsing_error(op, reason, stdout, attempt, returncode) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :parse_error,
      severity: :error,
      visibility: :internal,
      context: %{
        op: op,
        attempt: attempt,
        returncode: returncode,
        reason: inspect(reason),
        stdout_excerpt: excerpt(stdout)
      }
    }
  end

  defp unexpected_error(op, kind, value, attempt) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :exception,
      severity: :error,
      visibility: :internal,
      context: %{op: op, attempt: attempt, kind: kind, value: inspect(value)}
    }
  end

  defp safe_parse(parser, payload) do
    parser.(payload)
  rescue
    e -> {:error, e}
  end

  defp excerpt(nil), do: nil
  defp excerpt(text) when is_binary(text) do
    text |> String.slice(0, 1024) |> String.trim()
  end

  defp format_env(env) when is_map(env) do
    Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp format_env(env) when is_list(env) do
    Enum.map(env, fn
      {k, v} -> {to_string(k), to_string(v)}
      other -> other
    end)
  end

  defp format_env(_), do: []

end
