defmodule Thunderline.Thundercore.TickEmitter do
  @moduledoc """
  System heartbeat generator for Thunderline temporal coherence.

  The TickEmitter is the origin of time in Thunderline. It emits periodic
  tick events that all other domains can subscribe to for synchronization.

  ## Tick Hierarchy

  - **System tick**: ~50ms (20 Hz) - Base heartbeat for UI updates, CA steps
  - **Fast tick**: ~10ms (100 Hz) - High-frequency compute loops (optional)
  - **Slow tick**: ~1000ms (1 Hz) - Metrics aggregation, GC triggers

  ## Tick Event Structure

  ```elixir
  %{
    type: :core_tick,
    tick_id: integer,          # Monotonically increasing
    tick_type: :system | :fast | :slow,
    timestamp: DateTime.t,
    monotonic_ns: integer,     # System.monotonic_time(:nanosecond)
    epoch_ms: integer          # ms since process start
  }
  ```

  ## Usage

      # Subscribe to ticks
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "core:tick:system")

      # Get current tick
      Thunderline.Thundercore.TickEmitter.current_tick()

      # Get tick frequency
      Thunderline.Thundercore.TickEmitter.frequency(:system)
  """

  use GenServer
  require Logger

  @default_system_tick_ms 50
  @default_slow_tick_ms 1000

  @telemetry_prefix [:thunderline, :core, :tick]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts the TickEmitter.

  ## Options

  - `:system_tick_ms` - System tick interval (default: 50ms / 20 Hz)
  - `:slow_tick_ms` - Slow tick interval (default: 1000ms / 1 Hz)
  - `:name` - GenServer name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the current system tick count."
  @spec current_tick() :: non_neg_integer()
  def current_tick(server \\ __MODULE__) do
    GenServer.call(server, :current_tick)
  end

  @doc "Returns the tick frequency in Hz for a tick type."
  @spec frequency(atom()) :: float()
  def frequency(:system), do: 1000.0 / @default_system_tick_ms
  def frequency(:slow), do: 1000.0 / @default_slow_tick_ms
  def frequency(:fast), do: 100.0

  @doc "Returns the current state (for debugging)."
  @spec state(GenServer.server()) :: map()
  def state(server \\ __MODULE__) do
    GenServer.call(server, :state)
  end

  @doc "Pauses tick emission (for testing)."
  @spec pause(GenServer.server()) :: :ok
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @doc "Resumes tick emission."
  @spec resume(GenServer.server()) :: :ok
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  @doc "Returns the PubSub topic for a tick type."
  @spec topic(atom()) :: String.t()
  def topic(:system), do: "core:tick:system"
  def topic(:slow), do: "core:tick:slow"
  def topic(:fast), do: "core:tick:fast"

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    system_tick_ms = Keyword.get(opts, :system_tick_ms, @default_system_tick_ms)
    slow_tick_ms = Keyword.get(opts, :slow_tick_ms, @default_slow_tick_ms)

    state = %{
      system_tick_ms: system_tick_ms,
      slow_tick_ms: slow_tick_ms,
      system_tick: 0,
      slow_tick: 0,
      start_time: System.monotonic_time(:millisecond),
      paused: false,
      system_timer: nil,
      slow_timer: nil
    }

    # Schedule initial ticks
    state = schedule_ticks(state)

    Logger.info("[Thundercore.TickEmitter] Started: system=#{system_tick_ms}ms, slow=#{slow_tick_ms}ms")

    {:ok, state}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.system_tick, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, Map.delete(state, :system_timer) |> Map.delete(:slow_timer), state}
  end

  def handle_call(:pause, _from, state) do
    state = cancel_timers(state)
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, %{paused: true} = state) do
    state = schedule_ticks(%{state | paused: false})
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:system_tick, %{paused: true} = state) do
    {:noreply, state}
  end

  def handle_info(:system_tick, state) do
    new_tick = state.system_tick + 1
    now = DateTime.utc_now()
    mono = System.monotonic_time(:nanosecond)
    epoch_ms = System.monotonic_time(:millisecond) - state.start_time

    # Emit tick event
    event = %{
      type: :core_tick,
      tick_id: new_tick,
      tick_type: :system,
      timestamp: now,
      monotonic_ns: mono,
      epoch_ms: epoch_ms
    }

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(:system), {:core_tick, event})

    # Emit telemetry
    :telemetry.execute(
      @telemetry_prefix ++ [:system],
      %{tick_id: new_tick, epoch_ms: epoch_ms},
      %{tick_type: :system}
    )

    # Schedule next tick
    timer = Process.send_after(self(), :system_tick, state.system_tick_ms)

    {:noreply, %{state | system_tick: new_tick, system_timer: timer}}
  end

  def handle_info(:slow_tick, %{paused: true} = state) do
    {:noreply, state}
  end

  def handle_info(:slow_tick, state) do
    new_tick = state.slow_tick + 1
    now = DateTime.utc_now()
    mono = System.monotonic_time(:nanosecond)
    epoch_ms = System.monotonic_time(:millisecond) - state.start_time

    event = %{
      type: :core_tick,
      tick_id: new_tick,
      tick_type: :slow,
      timestamp: now,
      monotonic_ns: mono,
      epoch_ms: epoch_ms,
      system_tick_at: state.system_tick
    }

    Phoenix.PubSub.broadcast(Thunderline.PubSub, topic(:slow), {:core_tick, event})

    :telemetry.execute(
      @telemetry_prefix ++ [:slow],
      %{tick_id: new_tick, epoch_ms: epoch_ms, system_tick: state.system_tick},
      %{tick_type: :slow}
    )

    timer = Process.send_after(self(), :slow_tick, state.slow_tick_ms)

    {:noreply, %{state | slow_tick: new_tick, slow_timer: timer}}
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp schedule_ticks(%{paused: true} = state), do: state

  defp schedule_ticks(state) do
    system_timer = Process.send_after(self(), :system_tick, state.system_tick_ms)
    slow_timer = Process.send_after(self(), :slow_tick, state.slow_tick_ms)
    %{state | system_timer: system_timer, slow_timer: slow_timer}
  end

  defp cancel_timers(state) do
    if state.system_timer, do: Process.cancel_timer(state.system_timer)
    if state.slow_timer, do: Process.cancel_timer(state.slow_timer)
    %{state | system_timer: nil, slow_timer: nil}
  end
end
