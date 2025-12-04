defmodule Thunderline.Thunderbolt.NLP.Port do
  @moduledoc """
  Supervised Port bridge to Python spaCy NLP CLI.

  Provides safe subprocess-based NLP without polluting BEAM heap.
  Implements exponential backoff retry on crashes.

  ## Usage

      # Start under supervision tree
      children = [
        {Thunderline.Thunderbolt.NLP.Port, [python_path: "python3", cli_path: "python/services/nlp_cli.py"]}
      ]

      # Analyze text
      {:ok, result} = Thunderline.Thunderbolt.NLP.Port.analyze("Apple Inc. in Cupertino")
      # => {:ok, %{entities: [...], tokens: [...]}}

  ## Contract

  The Python CLI must accept line-delimited JSON on stdin and emit
  line-delimited JSON on stdout. Schema version must match "1.0".
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderflow.Telemetry

  @max_retries 3
  @backoff_base_ms 1000
  @request_timeout_ms 30_000
  @schema_version "1.0"

  defstruct [
    :port,
    :python_path,
    :cli_path,
    requests: %{},
    retry_count: 0,
    total_requests: 0,
    total_errors: 0
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Analyze text with spaCy NLP.

  ## Options

    * `:lang` - Language code (default: "en")
    * `:timeout` - Request timeout in ms (default: 30_000)

  ## Returns

    * `{:ok, %{entities: [...], tokens: [...]}}`
    * `{:error, reason}`
  """
  def analyze(text, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @request_timeout_ms)
    lang = Keyword.get(opts, :lang, "en")

    GenServer.call(__MODULE__, {:analyze, text, lang}, timeout)
  end

  @doc """
  Get port statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    python_path = Keyword.get(opts, :python_path, "python3")
    cli_path = Keyword.get(opts, :cli_path, "python/services/nlp_cli.py")

    state = %__MODULE__{
      python_path: python_path,
      cli_path: cli_path
    }

    {:ok, state, {:continue, :start_port}}
  end

  @impl true
  def handle_continue(:start_port, state) do
    case open_port(state) do
      {:ok, port} ->
        Logger.info("NLP Port started successfully",
          python: state.python_path,
          cli: state.cli_path
        )

        {:noreply, %{state | port: port}}

      {:error, reason} ->
        Logger.error("Failed to start NLP Port", error: reason)
        {:stop, {:port_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:analyze, text, lang}, from, state) do
    req_id = Thunderline.UUID.v7()
    start_time = System.monotonic_time(:microsecond)

    request = %{
      op: "analyze",
      text: text,
      lang: lang,
      schema_version: @schema_version,
      _req_id: req_id
    }

    case Jason.encode(request) do
      {:ok, json} ->
        Port.command(state.port, json <> "\n")

        request_meta = {from, start_time, text, lang}
        requests = Map.put(state.requests, req_id, request_meta)

        {:noreply, %{state | requests: requests, total_requests: state.total_requests + 1}}

      {:error, err} ->
        {:reply, {:error, {:json_encode_error, err}}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_requests: state.total_requests,
      total_errors: state.total_errors,
      pending_requests: map_size(state.requests),
      retry_count: state.retry_count
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, %{"_req_id" => req_id} = response} ->
        handle_response(req_id, response, state)

      {:ok, response} ->
        Logger.warning("NLP Port: response missing _req_id", response: response)
        {:noreply, state}

      {:error, err} ->
        Logger.error("NLP Port: malformed JSON response",
          error: err,
          line: String.slice(line, 0, 200)
        )

        {:noreply, %{state | total_errors: state.total_errors + 1}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("NLP Port crashed", exit_status: status, retry_count: state.retry_count)

    # Fail all pending requests
    Enum.each(state.requests, fn {_req_id, {from, _start, _text, _lang}} ->
      GenServer.reply(from, {:error, :port_crashed})
    end)

    # Attempt restart with backoff
    if state.retry_count < @max_retries do
      backoff_ms = backoff_delay(state.retry_count)
      Logger.info("Restarting NLP Port", backoff_ms: backoff_ms, attempt: state.retry_count + 1)

      Process.sleep(backoff_ms)

      case open_port(state) do
        {:ok, new_port} ->
          {:noreply,
           %{
             state
             | port: new_port,
               retry_count: state.retry_count + 1,
               requests: %{}
           }}

        {:error, reason} ->
          {:stop, {:port_restart_failed, reason}, state}
      end
    else
      {:stop, :max_retries_exceeded, state}
    end
  end

  # Private helpers

  defp open_port(state) do
    cli_full_path = Path.join(File.cwd!(), state.cli_path)

    if not File.exists?(cli_full_path) do
      {:error, {:cli_not_found, cli_full_path}}
    else
      port =
        Port.open(
          {:spawn_executable, System.find_executable(state.python_path)},
          [
            :binary,
            :exit_status,
            :use_stdio,
            {:line, 10_000},
            {:args, [cli_full_path]},
            {:env, [{"PYTHONUNBUFFERED", "1"}]}
          ]
        )

      {:ok, port}
    end
  end

  defp handle_response(req_id, response, state) do
    case Map.pop(state.requests, req_id) do
      {{from, start_time, text, lang}, remaining_requests} ->
        duration_us = System.monotonic_time(:microsecond) - start_time

        case parse_response(response) do
          {:ok, result} ->
            GenServer.reply(from, {:ok, result})

            # Emit telemetry
            Telemetry.nlp_analyze_complete(duration_us, %{
              lang: lang,
              entity_count: length(result[:entities] || []),
              token_count: length(result[:tokens] || []),
              text_length: String.length(text)
            })

            {:noreply,
             %{
               state
               | requests: remaining_requests,
                 retry_count: 0
             }}

          {:error, reason} ->
            GenServer.reply(from, {:error, reason})

            Telemetry.nlp_analyze_error(duration_us, %{
              lang: lang,
              error_type: classify_error(reason)
            })

            {:noreply,
             %{
               state
               | requests: remaining_requests,
                 total_errors: state.total_errors + 1
             }}
        end

      {nil, _} ->
        Logger.warning("NLP Port: orphaned response", req_id: req_id)
        {:noreply, state}
    end
  end

  defp parse_response(%{"ok" => true, "entities" => entities, "tokens" => tokens} = resp) do
    result = %{
      entities: entities,
      tokens: tokens
    }

    result =
      if Map.has_key?(resp, "vector") do
        Map.put(result, :vector, resp["vector"])
      else
        result
      end

    {:ok, result}
  end

  defp parse_response(%{"ok" => false, "error" => error}) do
    {:error, {:nlp_error, error}}
  end

  defp parse_response(%{"error" => error}) do
    # Legacy format
    {:error, {:nlp_error, error}}
  end

  defp parse_response(resp) do
    {:error, {:invalid_response, resp}}
  end

  defp classify_error({:nlp_error, msg}) when is_binary(msg) do
    cond do
      String.contains?(msg, "not available") -> :model_unavailable
      String.contains?(msg, "Schema version") -> :schema_mismatch
      true -> :unknown
    end
  end

  defp classify_error(_), do: :unknown

  defp backoff_delay(retry_count) do
    # Exponential backoff with jitter
    base_delay = @backoff_base_ms * :math.pow(2, retry_count)
    jitter = :rand.uniform(trunc(base_delay * 0.3))
    trunc(base_delay + jitter)
  end
end
