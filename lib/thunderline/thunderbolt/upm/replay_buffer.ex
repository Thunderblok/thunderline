defmodule Thunderline.Thunderbolt.UPM.ReplayBuffer do
  @moduledoc """
  Replay buffer for UPM trainer that handles out-of-order feature windows.

  De-duplicates events and enforces replay-safe training by buffering
  out-of-order windows and releasing them in sorted order based on
  window_start timestamp.

  ## Responsibilities

  - Buffer incoming feature windows
  - De-duplicate based on window_id
  - Sort by window_start timestamp
  - Release windows in order when contiguous sequence detected
  - Handle late-arriving windows (configurable tolerance)
  - Emit telemetry for buffer metrics

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.ReplayBuffer,
        max_buffer_size: 1000,
        release_delay_ms: 5000,
        late_window_tolerance_ms: 60_000

  ## Telemetry Events

  - `[:upm, :replay_buffer, :add]` - Window added to buffer
  - `[:upm, :replay_buffer, :release]` - Window released for processing
  - `[:upm, :replay_buffer, :duplicate]` - Duplicate window dropped
  - `[:upm, :replay_buffer, :late_arrival]` - Late window detected
  """

  use GenServer
  require Logger

  @type window_entry :: %{
          window_id: binary(),
          window_start: DateTime.t(),
          payload: map(),
          received_at: DateTime.t()
        }

  @type state :: %{
          trainer_id: binary(),
          buffer: %{binary() => window_entry()},
          processed: MapSet.t(binary()),
          max_buffer_size: pos_integer(),
          release_delay_ms: pos_integer(),
          late_tolerance_ms: pos_integer(),
          release_timer: reference() | nil
        }

  # Client API

  @doc """
  Starts the replay buffer.

  ## Options

  - `:trainer_id` - Associated trainer ID (required)
  - `:max_buffer_size` - Maximum windows to buffer (default: 1000)
  - `:release_delay_ms` - Delay before releasing windows (default: 5000)
  - `:late_window_tolerance_ms` - How late a window can arrive (default: 60000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    trainer_id = Keyword.fetch!(opts, :trainer_id)
    GenServer.start_link(__MODULE__, opts, name: via(trainer_id))
  end

  @doc """
  Adds a feature window to the replay buffer.
  """
  @spec add(GenServer.server(), binary(), map()) :: :ok
  def add(server, window_id, payload) do
    GenServer.cast(server, {:add, window_id, payload})
  end

  @doc """
  Gets current buffer statistics.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end

  @doc """
  Flushes buffer (for testing/debugging).
  """
  @spec flush(GenServer.server()) :: :ok
  def flush(server) do
    GenServer.call(server, :flush)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    trainer_id = Keyword.fetch!(opts, :trainer_id)
    max_buffer_size = Keyword.get(opts, :max_buffer_size, 1000)
    release_delay_ms = Keyword.get(opts, :release_delay_ms, 5000)
    late_tolerance_ms = Keyword.get(opts, :late_window_tolerance_ms, 60_000)

    state = %{
      trainer_id: trainer_id,
      buffer: %{},
      processed: MapSet.new(),
      max_buffer_size: max_buffer_size,
      release_delay_ms: release_delay_ms,
      late_tolerance_ms: late_tolerance_ms,
      release_timer: schedule_release(release_delay_ms)
    }

    Logger.info("""
    [UPM.ReplayBuffer] Initialized
      trainer_id: #{trainer_id}
      max_buffer_size: #{max_buffer_size}
      release_delay_ms: #{release_delay_ms}
    """)

    {:ok, state}
  end

  @impl true
  def handle_cast({:add, window_id, payload}, state) do
    cond do
      # Check for duplicate
      MapSet.member?(state.processed, window_id) or Map.has_key?(state.buffer, window_id) ->
        emit_telemetry(:duplicate, %{window_id: window_id}, state)
        Logger.debug("[UPM.ReplayBuffer] Duplicate window dropped: #{window_id}")
        {:noreply, state}

      # Check buffer capacity
      map_size(state.buffer) >= state.max_buffer_size ->
        Logger.warning("[UPM.ReplayBuffer] Buffer full, dropping window: #{window_id}")

        emit_telemetry(
          :buffer_full,
          %{window_id: window_id, buffer_size: map_size(state.buffer)},
          state
        )

        {:noreply, state}

      true ->
        # Extract window metadata
        window_start = parse_datetime(payload["window_start"])
        now = DateTime.utc_now()

        entry = %{
          window_id: window_id,
          window_start: window_start,
          payload: payload,
          received_at: now
        }

        # Check if late arrival
        expected_delay = DateTime.diff(now, window_start, :millisecond)

        if expected_delay > state.late_tolerance_ms do
          emit_telemetry(
            :late_arrival,
            %{
              window_id: window_id,
              delay_ms: expected_delay
            },
            state
          )

          Logger.warning(
            "[UPM.ReplayBuffer] Late window arrival: #{window_id} (#{expected_delay}ms)"
          )
        end

        # Add to buffer
        new_buffer = Map.put(state.buffer, window_id, entry)
        emit_telemetry(:add, %{window_id: window_id, buffer_size: map_size(new_buffer)}, state)

        {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      trainer_id: state.trainer_id,
      buffer_size: map_size(state.buffer),
      processed_count: MapSet.size(state.processed),
      max_buffer_size: state.max_buffer_size,
      oldest_buffered: oldest_buffered_timestamp(state.buffer)
    }

    {:reply, stats, state}
  end

  def handle_call(:flush, _from, state) do
    Logger.info("[UPM.ReplayBuffer] Flushing buffer (#{map_size(state.buffer)} windows)")

    # Release all buffered windows
    new_state = release_ready_windows(state, force: true)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:release_check, state) do
    # Release windows that are ready (in order)
    new_state = release_ready_windows(state)

    # Reschedule
    timer = schedule_release(state.release_delay_ms)

    {:noreply, %{new_state | release_timer: timer}}
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.ReplayBuffer] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp via(trainer_id) do
    {:via, Registry, {Thunderline.Registry, {__MODULE__, trainer_id}}}
  end

  defp schedule_release(delay_ms) do
    Process.send_after(self(), :release_check, delay_ms)
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  defp oldest_buffered_timestamp(buffer) when map_size(buffer) == 0, do: nil

  defp oldest_buffered_timestamp(buffer) do
    buffer
    |> Map.values()
    |> Enum.min_by(& &1.window_start, DateTime)
    |> then(& &1.window_start)
  end

  defp release_ready_windows(state, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    # Sort buffered windows by window_start
    sorted_windows =
      state.buffer
      |> Map.values()
      |> Enum.sort_by(& &1.window_start, DateTime)

    # If forcing, release all. Otherwise, release contiguous sequence
    {to_release, remaining} =
      if force do
        {sorted_windows, []}
      else
        find_contiguous_sequence(sorted_windows)
      end

    # Release windows to trainer
    Enum.each(to_release, fn entry ->
      send_to_trainer(state.trainer_id, entry)
      emit_telemetry(:release, %{window_id: entry.window_id}, state)
    end)

    # Update buffer and processed set
    released_ids = MapSet.new(to_release, & &1.window_id)

    new_buffer =
      Enum.reduce(to_release, state.buffer, fn entry, acc ->
        Map.delete(acc, entry.window_id)
      end)

    new_processed = MapSet.union(state.processed, released_ids)

    # Trim processed set if it gets too large (keep last 10k)
    new_processed =
      if MapSet.size(new_processed) > 10_000 do
        new_processed
        |> MapSet.to_list()
        |> Enum.drop(MapSet.size(new_processed) - 10_000)
        |> MapSet.new()
      else
        new_processed
      end

    %{state | buffer: new_buffer, processed: new_processed}
  end

  defp find_contiguous_sequence([]), do: {[], []}

  defp find_contiguous_sequence(sorted_windows) do
    # Release windows up to the first gap
    # A gap is defined as > 2 * expected window duration
    # 2 minutes
    window_duration_threshold_ms = 120_000

    {to_release, _} =
      Enum.reduce_while(sorted_windows, {[], nil}, fn entry, {acc, prev_time} ->
        case prev_time do
          nil ->
            # First window, always include
            {:cont, {[entry | acc], entry.window_start}}

          prev ->
            gap_ms = DateTime.diff(entry.window_start, prev, :millisecond)

            if gap_ms < window_duration_threshold_ms do
              # Contiguous, include
              {:cont, {[entry | acc], entry.window_start}}
            else
              # Gap detected, stop here
              {:halt, {acc, prev}}
            end
        end
      end)

    released = Enum.reverse(to_release)
    released_ids = MapSet.new(released, & &1.window_id)
    remaining = Enum.reject(sorted_windows, fn w -> MapSet.member?(released_ids, w.window_id) end)

    {released, remaining}
  end

  defp send_to_trainer(trainer_id, entry) do
    # Send to trainer via process message
    # Trainer registered via Registry
    case Registry.lookup(Thunderline.Registry, {:trainer, trainer_id}) do
      [{pid, _}] ->
        send(pid, {:replay_buffer, :ready, entry.window_id})

      [] ->
        Logger.warning("[UPM.ReplayBuffer] Trainer not found: #{trainer_id}")
    end
  end

  defp emit_telemetry(event, measurements, state) do
    :telemetry.execute(
      [:upm, :replay_buffer, event],
      Map.merge(%{count: 1}, measurements),
      %{trainer_id: state.trainer_id}
    )
  end
end
