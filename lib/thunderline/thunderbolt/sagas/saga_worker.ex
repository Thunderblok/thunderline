defmodule Thunderline.Thunderbolt.Sagas.SagaWorker do
  @moduledoc """
  Oban worker for executing Reactor sagas with timeout, retry, and state tracking.

  This worker bridges Reactor sagas with Oban's job processing infrastructure,
  providing:
  - Reliable background execution with retries
  - Timeout enforcement via Thundercore SystemClock
  - State persistence for saga recovery
  - Decay registration via Thunderwall for stale cleanup
  - Telemetry integration

  ## Usage

      # Schedule a saga for background execution
      SagaWorker.enqueue(
        UserProvisioningSaga,
        %{email: "user@example.com"},
        correlation_id: Thunderline.UUID.v7(),
        timeout_ms: 30_000
      )

  ## Job Args Structure

      %{
        "saga_module" => "Elixir.Thunderline.Thunderbolt.Sagas.UserProvisioningSaga",
        "inputs" => %{"email" => "user@example.com"},
        "correlation_id" => "01JXYZ...",
        "causation_id" => "01JXYZ...",
        "timeout_ms" => 30000,
        "started_at" => ~U[2024-01-01 00:00:00Z]
      }
  """

  use Oban.Worker,
    queue: :sagas,
    max_attempts: 3,
    tags: ["saga", "reactor"]

  require Logger

  alias Thunderline.Thundercore.SystemClock
  alias Thunderline.Thunderwall.DecayProcessor
  alias Thunderline.Thunderbolt.Sagas.SagaState

  @default_timeout_ms 60_000
  @telemetry_prefix [:thunderline, :saga, :worker]

  @type saga_opts :: [
          correlation_id: String.t(),
          causation_id: String.t() | nil,
          timeout_ms: pos_integer(),
          priority: integer(),
          actor: map() | nil
        ]

  @doc """
  Enqueue a Reactor saga for background execution.

  ## Options

  - `:correlation_id` - Unique ID to track this saga execution (default: auto-generated)
  - `:causation_id` - ID of the event that caused this saga
  - `:timeout_ms` - Maximum execution time in milliseconds (default: 60_000)
  - `:priority` - Oban job priority (default: 0)
  - `:actor` - Actor context for the saga
  """
  @spec enqueue(module(), map(), saga_opts()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(saga_module, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id, Thunderline.UUID.v7())
    causation_id = Keyword.get(opts, :causation_id)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    priority = Keyword.get(opts, :priority, 0)

    args = %{
      "saga_module" => to_string(saga_module),
      "inputs" => serialize_inputs(inputs),
      "correlation_id" => correlation_id,
      "causation_id" => causation_id,
      "timeout_ms" => timeout_ms,
      "started_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    args
    |> new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Enqueue a saga with a deadline based on Thundercore SystemClock.

  The deadline is converted to a timeout and the saga will be canceled
  if it exceeds the deadline.
  """
  @spec enqueue_with_deadline(module(), map(), DateTime.t(), saga_opts()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_with_deadline(saga_module, inputs, deadline, opts \\ []) do
    timeout_ms = SystemClock.time_until_deadline(deadline)

    if timeout_ms > 0 do
      opts = Keyword.put(opts, :timeout_ms, timeout_ms)
      enqueue(saga_module, inputs, opts)
    else
      {:error, :deadline_exceeded}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    correlation_id = args["correlation_id"]
    saga_module = String.to_existing_atom(args["saga_module"])
    inputs = deserialize_inputs(args["inputs"])
    timeout_ms = args["timeout_ms"] || @default_timeout_ms
    causation_id = args["causation_id"]

    # Emit telemetry start
    emit_start_telemetry(saga_module, correlation_id, attempt)

    # Create or update saga state
    {:ok, saga_state} = ensure_saga_state(saga_module, correlation_id, inputs)

    # Set deadline for timeout enforcement
    deadline = SystemClock.deadline(timeout_ms)

    # Execute saga with timeout
    result =
      execute_with_timeout(saga_module, inputs, correlation_id, causation_id, deadline, timeout_ms)

    # Handle result
    case result do
      {:ok, output} ->
        complete_saga_state(saga_state, output)
        emit_complete_telemetry(saga_module, correlation_id, output)
        :ok

      {:error, :timeout} ->
        fail_saga_state(saga_state, :timeout, attempt, max_attempts)
        emit_timeout_telemetry(saga_module, correlation_id, timeout_ms)
        register_for_decay(saga_state, :timeout)
        {:error, :timeout}

      {:error, reason} ->
        fail_saga_state(saga_state, reason, attempt, max_attempts)
        emit_error_telemetry(saga_module, correlation_id, reason)

        if attempt >= max_attempts do
          register_for_decay(saga_state, reason)
        end

        {:error, reason}

      {:halted, state} ->
        # Saga was halted - can be resumed
        pause_saga_state(saga_state, state)
        emit_halted_telemetry(saga_module, correlation_id, state)
        :ok
    end
  end

  @impl Oban.Worker
  def timeout(%Oban.Job{args: args}) do
    # Use the saga-specific timeout or default
    args["timeout_ms"] || @default_timeout_ms
  end

  # Private functions

  defp execute_with_timeout(saga_module, inputs, correlation_id, causation_id, deadline, timeout_ms) do
    # Add correlation/causation to inputs
    enriched_inputs =
      inputs
      |> Map.put(:correlation_id, correlation_id)
      |> Map.put_new(:causation_id, causation_id || correlation_id)

    # Create task for saga execution
    task =
      Task.async(fn ->
        try do
          Reactor.run(saga_module, enriched_inputs, %{
            deadline: deadline,
            correlation_id: correlation_id
          })
        rescue
          e -> {:error, {:exception, Exception.format(:error, e, __STACKTRACE__)}}
        end
      end)

    # Wait with timeout
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        {:error, :timeout}
    end
  end

  defp ensure_saga_state(saga_module, correlation_id, inputs) do
    case Ash.get(SagaState, correlation_id) do
      {:ok, state} ->
        # Update existing state to running
        Ash.update(state, %{status: :running, last_attempt_at: DateTime.utc_now()})

      {:error, %Ash.Error.Query.NotFound{}} ->
        # Create new state
        Ash.create(SagaState, %{
          id: correlation_id,
          saga_module: to_string(saga_module),
          inputs: inputs,
          status: :running,
          attempt_count: 1,
          last_attempt_at: DateTime.utc_now()
        })

      {:error, reason} ->
        Logger.warning("Failed to ensure saga state: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  defp complete_saga_state(nil, _output), do: :ok

  defp complete_saga_state(saga_state, output) do
    Ash.update(saga_state, %{
      status: :completed,
      output: safe_serialize(output),
      completed_at: DateTime.utc_now()
    })
  end

  defp fail_saga_state(nil, _reason, _attempt, _max), do: :ok

  defp fail_saga_state(saga_state, reason, attempt, max_attempts) do
    status = if attempt >= max_attempts, do: :failed, else: :retrying

    Ash.update(saga_state, %{
      status: status,
      error: inspect(reason),
      attempt_count: attempt,
      last_attempt_at: DateTime.utc_now()
    })
  end

  defp pause_saga_state(nil, _state), do: :ok

  defp pause_saga_state(saga_state, reactor_state) do
    Ash.update(saga_state, %{
      status: :halted,
      checkpoint: safe_serialize(reactor_state),
      last_attempt_at: DateTime.utc_now()
    })
  end

  defp register_for_decay(nil, _reason), do: :ok

  defp register_for_decay(saga_state, reason) do
    DecayProcessor.register_decayable(%{
      resource_type: :saga_state,
      resource_id: saga_state.id,
      domain: :bolt,
      reason: reason,
      ttl_seconds: 86_400
    })
  end

  defp serialize_inputs(inputs) when is_map(inputs) do
    inputs
    |> Enum.map(fn {k, v} -> {to_string(k), safe_serialize(v)} end)
    |> Map.new()
  end

  defp deserialize_inputs(inputs) when is_map(inputs) do
    inputs
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.new()
  rescue
    ArgumentError -> inputs
  end

  defp safe_serialize(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end

  # Telemetry helpers

  defp emit_start_telemetry(saga_module, correlation_id, attempt) do
    :telemetry.execute(
      @telemetry_prefix ++ [:start],
      %{system_time: System.system_time()},
      %{
        saga_module: saga_module,
        correlation_id: correlation_id,
        attempt: attempt
      }
    )
  end

  defp emit_complete_telemetry(saga_module, correlation_id, _output) do
    :telemetry.execute(
      @telemetry_prefix ++ [:complete],
      %{system_time: System.system_time()},
      %{
        saga_module: saga_module,
        correlation_id: correlation_id,
        status: :success
      }
    )
  end

  defp emit_error_telemetry(saga_module, correlation_id, reason) do
    :telemetry.execute(
      @telemetry_prefix ++ [:error],
      %{system_time: System.system_time()},
      %{
        saga_module: saga_module,
        correlation_id: correlation_id,
        error: reason
      }
    )
  end

  defp emit_timeout_telemetry(saga_module, correlation_id, timeout_ms) do
    :telemetry.execute(
      @telemetry_prefix ++ [:timeout],
      %{system_time: System.system_time(), timeout_ms: timeout_ms},
      %{
        saga_module: saga_module,
        correlation_id: correlation_id
      }
    )
  end

  defp emit_halted_telemetry(saga_module, correlation_id, _state) do
    :telemetry.execute(
      @telemetry_prefix ++ [:halted],
      %{system_time: System.system_time()},
      %{
        saga_module: saga_module,
        correlation_id: correlation_id
      }
    )
  end
end
