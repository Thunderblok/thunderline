defmodule Thunderline.Thundercore.SystemClock do
  @moduledoc """
  System-wide monotonic time service for Thunderline.

  The SystemClock provides consistent time references across the system,
  independent of wall-clock time. This is critical for:

  - Tick alignment and drift detection
  - Event ordering and causality
  - Timeout calculations
  - Performance measurement

  ## Time Sources

  - **Monotonic**: `System.monotonic_time/1` - Never goes backwards
  - **Wall clock**: `DateTime.utc_now/0` - Human-readable, can drift
  - **Epoch**: Time since SystemClock start

  ## Usage

      # Get current monotonic time
      Thunderline.Thundercore.SystemClock.now(:millisecond)

      # Get epoch (time since process start)
      Thunderline.Thundercore.SystemClock.epoch_ms()

      # Calculate deadline
      Thunderline.Thundercore.SystemClock.deadline(5000)

      # Check if deadline passed
      Thunderline.Thundercore.SystemClock.past_deadline?(deadline)
  """

  use GenServer
  require Logger

  @telemetry_prefix [:thunderline, :core, :clock]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc "Starts the SystemClock."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current monotonic time in the given unit.

  This is a direct passthrough to `System.monotonic_time/1` but
  provides a consistent interface for the Thunderline system.
  """
  @spec now(System.time_unit()) :: integer()
  def now(unit \\ :millisecond) do
    System.monotonic_time(unit)
  end

  @doc """
  Returns milliseconds since the SystemClock started.

  This is useful for relative time calculations within a single
  node's lifetime.
  """
  @spec epoch_ms(GenServer.server()) :: non_neg_integer()
  def epoch_ms(server \\ __MODULE__) do
    GenServer.call(server, :epoch_ms)
  end

  @doc """
  Returns a deadline timestamp (monotonic milliseconds).

  ## Examples

      deadline = SystemClock.deadline(5000)  # 5 seconds from now
      # ... do work ...
      if SystemClock.past_deadline?(deadline), do: :timeout
  """
  @spec deadline(non_neg_integer()) :: integer()
  def deadline(timeout_ms) do
    now(:millisecond) + timeout_ms
  end

  @doc "Returns true if the given deadline has passed."
  @spec past_deadline?(integer()) :: boolean()
  def past_deadline?(deadline_mono_ms) do
    now(:millisecond) >= deadline_mono_ms
  end

  @doc "Returns time remaining until deadline (may be negative if past)."
  @spec time_remaining(integer()) :: integer()
  def time_remaining(deadline_mono_ms) do
    deadline_mono_ms - now(:millisecond)
  end

  @doc """
  Returns time until a DateTime deadline in milliseconds.

  Useful for converting wall-clock deadlines to timeout values.
  Returns 0 if the deadline has already passed.

  ## Examples

      deadline = ~U[2025-01-01 12:00:00Z]
      timeout_ms = SystemClock.time_until_deadline(deadline)
  """
  @spec time_until_deadline(DateTime.t()) :: non_neg_integer()
  def time_until_deadline(%DateTime{} = deadline) do
    now = DateTime.utc_now()
    diff_ms = DateTime.diff(deadline, now, :millisecond)
    max(diff_ms, 0)
  end

  @doc """
  Returns the current UTC datetime.

  This is a wall-clock time and should only be used for logging,
  display, or external API timestamps. Not for internal timing.
  """
  @spec utc_now() :: DateTime.t()
  def utc_now do
    DateTime.utc_now()
  end

  @doc """
  Measures the execution time of a function.

  Returns `{result, duration_ms}`.

  ## Examples

      {result, ms} = SystemClock.measure(fn -> expensive_operation() end)
  """
  @spec measure((-> any())) :: {any(), non_neg_integer()}
  def measure(fun) when is_function(fun, 0) do
    start = now(:microsecond)
    result = fun.()
    elapsed = now(:microsecond) - start
    {result, div(elapsed, 1000)}
  end

  @doc """
  Returns the clock's startup information.
  """
  @spec info(GenServer.server()) :: map()
  def info(server \\ __MODULE__) do
    GenServer.call(server, :info)
  end

  @doc """
  Aligns a timestamp to the nearest tick boundary.

  Useful for snapping events to tick intervals.

  ## Examples

      # Align to 50ms tick boundaries
      aligned = SystemClock.align_to_tick(timestamp, 50)
  """
  @spec align_to_tick(integer(), pos_integer()) :: integer()
  def align_to_tick(timestamp_ms, tick_interval_ms) do
    div(timestamp_ms, tick_interval_ms) * tick_interval_ms
  end

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    start_mono = System.monotonic_time(:millisecond)
    start_wall = DateTime.utc_now()

    state = %{
      start_mono: start_mono,
      start_wall: start_wall
    }

    :telemetry.execute(
      @telemetry_prefix ++ [:started],
      %{start_mono: start_mono},
      %{start_wall: start_wall}
    )

    Logger.info("[Thundercore.SystemClock] Started at #{DateTime.to_iso8601(start_wall)}")

    {:ok, state}
  end

  @impl true
  def handle_call(:epoch_ms, _from, state) do
    epoch = System.monotonic_time(:millisecond) - state.start_mono
    {:reply, epoch, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      start_mono: state.start_mono,
      start_wall: state.start_wall,
      current_epoch_ms: System.monotonic_time(:millisecond) - state.start_mono,
      current_wall: DateTime.utc_now()
    }

    {:reply, info, state}
  end
end
