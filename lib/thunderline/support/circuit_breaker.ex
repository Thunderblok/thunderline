defmodule Thunderline.Support.CircuitBreaker do
  @moduledoc """
  Simple ETS-based circuit breaker for protecting against failing external services.

  States:
  - `:closed` - Normal operation, calls pass through
  - `:open` - Service is failing, calls are rejected immediately
  - `:half_open` - Testing if service has recovered

  ## Usage

      # Wrap external service calls
      case CircuitBreaker.call({:domain, "thundercore"}, fn ->
        create_domain_job("thundercore", params)
      end) do
        {:ok, result} -> handle_success(result)
        {:error, :circuit_open} -> handle_circuit_open()
        {:error, reason} -> handle_failure(reason)
      end

  ## Configuration

  - `@failure_threshold`: Number of failures before opening circuit (default: 5)
  - `@cooldown_ms`: Time to wait before testing recovery (default: 30 seconds)
  - `@success_threshold`: Successes needed to close circuit from half-open (default: 3)
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderflow.Telemetry.Jobs, as: JobTelemetry

  @failure_threshold 5
  @cooldown_ms 30_000
  @success_threshold 3
  @table_name :thunderline_circuit_breakers

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a function with circuit breaker protection.

  Returns:
  - `{:ok, result}` - Function executed successfully
  - `{:error, :circuit_open}` - Circuit is open, call rejected
  - `{:error, reason}` - Function failed, circuit updated
  """
  @spec call(term(), (() -> any())) :: {:ok, any()} | {:error, :circuit_open} | {:error, term()}
  def call(service_key, fun) when is_function(fun, 0) do
    case get_state(service_key) do
      {:open, until_ms} ->
        now = System.monotonic_time(:millisecond)
        if until_ms > now do
          # Circuit is open and cooldown hasn't expired
            emit_call_telemetry(service_key, :rejected)
            {:error, :circuit_open}
        else
          # Circuit was open but cooldown expired, move to half-open
          set_state(service_key, :half_open, %{attempts: 0, successes: 0})
          emit_state_change_telemetry(service_key, :open, :half_open)
          execute_call(service_key, fun)
        end

      _state ->
        # Circuit is closed or half-open, attempt the call
        execute_call(service_key, fun)
    end
  end

  @doc """
  Get the current state of a circuit breaker.
  """
  def get_circuit_state(service_key) do
    case get_state(service_key) do
      {:closed, _} -> :closed
      {:open, until_ms} ->
        if until_ms > System.monotonic_time(:millisecond), do: :open, else: :half_open
      {:half_open, _} -> :half_open
    end
  end

  @doc """
  Reset a circuit breaker to closed state (for testing/emergency).
  """
  def reset(service_key) do
    old_state = get_circuit_state(service_key)
    set_state(service_key, :closed, %{failures: 0})
    emit_state_change_telemetry(service_key, old_state, :closed)
    :ok
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{table: table}}
  end

  # Private functions

  defp execute_call(service_key, fun) do
    try do
      result = fun.()
      handle_success(service_key, result)
    rescue
      error -> handle_failure(service_key, error)
    catch
      :exit, reason -> handle_failure(service_key, reason)
      :throw, reason -> handle_failure(service_key, reason)
    end
  end

  defp handle_success(service_key, result) do
    case get_state(service_key) do
      {:half_open, %{successes: successes}} when successes + 1 >= @success_threshold ->
        # Enough successes to close the circuit
        set_state(service_key, :closed, %{failures: 0})
        emit_state_change_telemetry(service_key, :half_open, :closed)

      {:half_open, meta} ->
        # Increment success count but stay half-open
        set_state(service_key, :half_open, Map.update(meta, :successes, 1, &(&1 + 1)))

      _ ->
        # Circuit is closed, ensure failure count is reset
        set_state(service_key, :closed, %{failures: 0})
    end

    emit_call_telemetry(service_key, :success)
    {:ok, result}
  end

  defp handle_failure(service_key, reason) do
    case get_state(service_key) do
      {:closed, %{failures: failures}} when failures + 1 >= @failure_threshold ->
        # Too many failures, open the circuit
        until_ms = System.monotonic_time(:millisecond) + @cooldown_ms
        set_state(service_key, :open, until_ms)
        emit_state_change_telemetry(service_key, :closed, :open)

      {:closed, meta} ->
        # Increment failure count but stay closed
        set_state(service_key, :closed, Map.update(meta, :failures, 1, &(&1 + 1)))

      {:half_open, _} ->
        # Failure during half-open, go back to open
        until_ms = System.monotonic_time(:millisecond) + @cooldown_ms
        set_state(service_key, :open, until_ms)
        emit_state_change_telemetry(service_key, :half_open, :open)

      _ ->
        # Circuit is already open, no state change needed
        :ok
    end

    emit_call_telemetry(service_key, :failure)
    {:error, reason}
  end

  defp get_state(service_key) do
    case :ets.lookup(@table_name, service_key) do
      [{^service_key, state}] -> state
      [] -> {:closed, %{failures: 0}}
    end
  end

  defp set_state(service_key, state_name, metadata) do
    :ets.insert(@table_name, {service_key, {state_name, metadata}})
  end

  defp emit_state_change_telemetry(service_key, from_state, to_state) do
    JobTelemetry.emit_circuit_breaker_state_change(service_key, from_state, to_state)

    Logger.info("Circuit breaker #{inspect(service_key)}: #{from_state} -> #{to_state}")
  end

  defp emit_call_telemetry(service_key, result) do
    JobTelemetry.emit_circuit_breaker_call(service_key, result)
  end
end
