defmodule Thunderline.Thunderflow.Support.CircuitBreaker do
  @moduledoc "ETS circuit breaker for event pipeline external calls."
  use GenServer
  require Logger
  alias Thunderline.Thunderflow.Telemetry.Jobs, as: JobTelemetry
  @failure_threshold 5
  @cooldown_ms 30_000
  @success_threshold 3
  @table_name :thunderline_circuit_breakers
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @spec call(term(), (-> any())) :: {:ok, any()} | {:error, :circuit_open} | {:error, term()}
  def call(key, fun) do
    case get_state(key) do
      {:open, until_ms} ->
        if until_ms > now() do
          emit_call_telemetry(key, :rejected)
          {:error, :circuit_open}
        else
          set_state(key, :half_open, %{successes: 0})
          emit_state_change_telemetry(key, :open, :half_open)
          exec(key, fun)
        end

      _ ->
        exec(key, fun)
    end
  end

  def get_circuit_state(key) do
    case get_state(key) do
      {:closed, _} -> :closed
      {:open, until_ms} -> if until_ms > now(), do: :open, else: :half_open
      {:half_open, _} -> :half_open
    end
  end

  def reset(key) do
    old = get_circuit_state(key)
    set_state(key, :closed, %{failures: 0})
    emit_state_change_telemetry(key, old, :closed)
    :ok
  end

  @impl GenServer
  def init(_),
    do:
      {:ok,
       %{table: :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])}}

  defp exec(key, fun) do
    try do
      res = fun.()
      success(key, res)
    rescue
      e -> failure(key, e)
    catch
      :exit, r -> failure(key, r)
      :throw, r -> failure(key, r)
    end
  end

  defp success(key, res) do
    case get_state(key) do
      {:half_open, %{successes: s}} when s + 1 >= @success_threshold ->
        set_state(key, :closed, %{failures: 0})
        emit_state_change_telemetry(key, :half_open, :closed)

      {:half_open, meta} ->
        set_state(key, :half_open, Map.update(meta, :successes, 1, &(&1 + 1)))

      _ ->
        set_state(key, :closed, %{failures: 0})
    end

    emit_call_telemetry(key, :success)
    {:ok, res}
  end

  defp failure(key, reason) do
    case get_state(key) do
      {:closed, %{failures: f}} when f + 1 >= @failure_threshold ->
        set_state(key, :open, now() + @cooldown_ms)
        emit_state_change_telemetry(key, :closed, :open)

      {:closed, meta} ->
        set_state(key, :closed, Map.update(meta, :failures, 1, &(&1 + 1)))

      {:half_open, _} ->
        set_state(key, :open, now() + @cooldown_ms)
        emit_state_change_telemetry(key, :half_open, :open)

      _ ->
        :ok
    end

    emit_call_telemetry(key, :failure)
    {:error, reason}
  end

  defp get_state(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, state}] -> state
      [] -> {:closed, %{failures: 0}}
    end
  end

  defp set_state(key, st, meta), do: :ets.insert(@table_name, {key, {st, meta}})
  defp now, do: System.monotonic_time(:millisecond)

  defp emit_state_change_telemetry(key, from, to) do
    JobTelemetry.emit_circuit_breaker_state_change(key, from, to)
    Logger.info("Circuit #{inspect(key)}: #{from}->#{to}")
  end

  defp emit_call_telemetry(key, result) do
    JobTelemetry.emit_circuit_breaker_call(key, result)
  end
end
