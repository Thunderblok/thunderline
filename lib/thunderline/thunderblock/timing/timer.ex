defmodule Thunderline.Thunderblock.Timing.Timer do
  @moduledoc """
  In-memory timer management for Thunderline.

  Provides high-level API for creating and managing timers using Process.send_after.
  Automatically tracks active timers and provides query capabilities.

  ## Usage

      # Create a one-shot timer
      {:ok, timer_ref} = Timer.create(5_000, fn ->
        IO.puts("Timer fired!")
      end)

      # Cancel a timer
      :ok = Timer.cancel(timer_ref)

      # List all active timers
      {:ok, timers} = Timer.list_active()
  """

  use GenServer
  require Logger

  @table_name :thunderline_timers
  @cleanup_interval_ms 60_000

  # Client API

  @doc """
  Starts the Timer GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a timer that executes a callback after the specified delay.

  ## Options

    * `:metadata` - Map of arbitrary metadata to attach to timer
    * `:name` - Optional name for the timer (must be unique)

  ## Returns

    * `{:ok, timer_ref}` - Timer created successfully
    * `{:error, :name_taken}` - Timer with that name already exists
  """
  def create(delay_ms, callback, opts \\ []) when is_integer(delay_ms) and delay_ms > 0 do
    metadata = Keyword.get(opts, :metadata, %{})
    name = Keyword.get(opts, :name)

    # Validate unique name
    if name && timer_exists?(name) do
      {:error, :name_taken}
    else
      timer_ref = make_ref()
      expires_at = System.monotonic_time(:millisecond) + delay_ms

      # Schedule the callback
      process_ref = Process.send_after(self(), {:timer_fire, timer_ref}, delay_ms)

      # Store timer metadata
      timer = %{
        ref: timer_ref,
        process_ref: process_ref,
        callback: callback,
        delay_ms: delay_ms,
        created_at: DateTime.utc_now(),
        expires_at: expires_at,
        metadata: metadata,
        name: name
      }

      :ets.insert(@table_name, {timer_ref, timer})

      if name do
        :ets.insert(@table_name, {{:name, name}, timer_ref})
      end

      Logger.debug("Created timer",
        ref: inspect(timer_ref),
        delay_ms: delay_ms,
        name: name
      )

      :telemetry.execute(
        [:thunderline, :timing, :timer_created],
        %{count: 1, delay_ms: delay_ms},
        %{name: name}
      )

      {:ok, timer_ref}
    end
  end

  @doc """
  Cancels an active timer.

  Returns `:ok` if timer was cancelled, `{:error, :not_found}` if timer doesn't exist.
  """
  def cancel(timer_ref) do
    case :ets.lookup(@table_name, timer_ref) do
      [{^timer_ref, timer}] ->
        # Cancel the Process.send_after
        Process.cancel_timer(timer.process_ref)

        # Remove from ETS
        :ets.delete(@table_name, timer_ref)

        if timer.name do
          :ets.delete(@table_name, {:name, timer.name})
        end

        Logger.debug("Cancelled timer", ref: inspect(timer_ref), name: timer.name)

        :telemetry.execute(
          [:thunderline, :timing, :timer_cancelled],
          %{count: 1},
          %{name: timer.name}
        )

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets timer information by reference or name.
  """
  def get(timer_ref) when is_reference(timer_ref) do
    case :ets.lookup(@table_name, timer_ref) do
      [{^timer_ref, timer}] -> {:ok, timer}
      [] -> {:error, :not_found}
    end
  end

  def get(name) when is_atom(name) do
    case :ets.lookup(@table_name, {:name, name}) do
      [{{:name, ^name}, timer_ref}] ->
        get(timer_ref)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active timers.
  """
  def list_active do
    timers =
      :ets.foldl(fn
        {ref, timer}, acc when is_reference(ref) -> [timer | acc]
        _other, acc -> acc
      end, [], @table_name)

    {:ok, timers}
  end

  @doc """
  Counts active timers.
  """
  def count_active do
    count =
      :ets.foldl(fn
        {ref, _timer}, acc when is_reference(ref) -> acc + 1
        _other, acc -> acc
      end, 0, @table_name)

    count
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for timer storage
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("Timer manager started")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:timer_fire, timer_ref}, state) do
    case :ets.lookup(@table_name, timer_ref) do
      [{^timer_ref, timer}] ->
        # Execute callback
        try do
          timer.callback.()

          Logger.debug("Timer fired", ref: inspect(timer_ref), name: timer.name)

          :telemetry.execute(
            [:thunderline, :timing, :timer_fired],
            %{count: 1},
            %{name: timer.name}
          )
        rescue
          error ->
            Logger.error("Timer callback failed",
              ref: inspect(timer_ref),
              name: timer.name,
              error: Exception.format(:error, error, __STACKTRACE__)
            )

            :telemetry.execute(
              [:thunderline, :timing, :timer_error],
              %{count: 1},
              %{name: timer.name}
            )
        end

        # Clean up timer entry
        :ets.delete(@table_name, timer_ref)

        if timer.name do
          :ets.delete(@table_name, {:name, timer.name})
        end

      [] ->
        # Timer was cancelled before firing
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    # Find expired timers that didn't fire (edge case)
    expired =
      :ets.foldl(fn
        {ref, timer}, acc when is_reference(ref) ->
          if timer.expires_at < now do
            [ref | acc]
          else
            acc
          end

        _other, acc ->
          acc
      end, [], @table_name)

    # Clean up expired timers
    Enum.each(expired, fn ref ->
      case :ets.lookup(@table_name, ref) do
        [{^ref, timer}] ->
          :ets.delete(@table_name, ref)
          if timer.name, do: :ets.delete(@table_name, {:name, timer.name})

        [] ->
          :ok
      end
    end)

    if length(expired) > 0 do
      Logger.debug("Cleaned up expired timers", count: length(expired))
    end

    schedule_cleanup()

    {:noreply, state}
  end

  # Private functions

  defp timer_exists?(name) do
    case :ets.lookup(@table_name, {:name, name}) do
      [] -> false
      _ -> true
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
