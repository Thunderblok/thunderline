defmodule Thunderline.Thundercore.Clock do
  @moduledoc """
  4-Phase Thunderclock - QCA-inspired timing for the Thunderline substrate.

  Implements the Switch → Hold → Release → Relax cycle inspired by
  Quantum-dot Cellular Automata clocking, mapping to domain phases:

  | Phase    | Duration | Activity              | Primary Domains               |
  |----------|----------|-----------------------|-------------------------------|
  | Switch   | ~200ms   | Sense inputs          | Thundergate, Thunderflow      |
  | Hold     | ~300ms   | Compute transitions   | Thunderbolt, Thundercrown     |
  | Release  | ~200ms   | Emit outputs          | Thunderlink, Thundergrid      |
  | Relax    | ~100ms   | Decay/cleanup         | Thunderwall, Thunderpac       |

  ## HC-88: 4-Phase Thunderclock

  The clock provides:
  - Phase-aware tick distribution
  - Domain-specific phase subscriptions
  - Configurable phase durations
  - Telemetry emission per phase

  ## Usage

      # Start (typically via Application supervisor)
      {:ok, _pid} = Clock.start_link(name: Clock)

      # Get current phase
      Clock.current_phase()
      # => {:switch, tick: 42}

      # Subscribe to a phase
      Clock.on_phase(:hold, fn t -> IO.puts("Hold phase at tick \#{t}") end)

      # Domain-aware subscription
      Clock.subscribe_domain(:thunderbolt)  # Gets :hold phase events

  ## Configuration

      config :thunderline, Thunderline.Thundercore.Clock,
        tick_interval_ms: 800,  # Full cycle duration
        phase_ratios: [switch: 0.25, hold: 0.375, release: 0.25, relax: 0.125]

  ## References

  - HC_QUANTUM_SUBSTRATE_SPEC.md §3 4-Phase Thunderclock Protocol
  - Lent & Tougaw QCA clocking papers
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderflow.EventBus

  # ═══════════════════════════════════════════════════════════════════════════
  # Types
  # ═══════════════════════════════════════════════════════════════════════════

  @type phase :: :switch | :hold | :release | :relax
  @type tick :: non_neg_integer()
  @type phase_callback :: (tick() -> any())

  @phases [:switch, :hold, :release, :relax]

  @default_tick_interval_ms 800
  @default_phase_ratios [switch: 0.25, hold: 0.375, release: 0.25, relax: 0.125]

  # Domain → Phase mappings (primary phase for each domain)
  @domain_phases %{
    thundercore: :switch,
    thundergate: :switch,
    thunderflow: :switch,
    thunderbolt: :hold,
    thundercrown: :hold,
    thundervine: :hold,
    thunderlink: :release,
    thundergrid: :release,
    thunderprism: :release,
    thunderwall: :relax,
    thunderpac: :relax,
    thunderblock: :relax
  }

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Starts the clock GenServer.

  ## Options

  - `:name` - GenServer name (default: __MODULE__)
  - `:tick_interval_ms` - Full cycle duration (default: 800ms)
  - `:phase_ratios` - Relative phase durations (default: QCA standard)
  - `:auto_start` - Start ticking immediately (default: true)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current phase and tick number.

  ## Examples

      iex> Clock.current_phase()
      {:hold, 42}
  """
  @spec current_phase(GenServer.server()) :: {phase(), tick()}
  def current_phase(server \\ __MODULE__) do
    GenServer.call(server, :current_phase)
  end

  @doc """
  Returns just the current phase atom.
  """
  @spec phase(GenServer.server()) :: phase()
  def phase(server \\ __MODULE__) do
    {phase, _tick} = current_phase(server)
    phase
  end

  @doc """
  Returns just the current tick number.
  """
  @spec tick(GenServer.server()) :: tick()
  def tick(server \\ __MODULE__) do
    {_phase, tick} = current_phase(server)
    tick
  end

  @doc """
  Subscribes a callback to a specific phase.

  The callback is invoked with the tick number when that phase begins.

  ## Examples

      Clock.on_phase(:hold, fn tick ->
        Logger.info("Hold phase started at tick \#{tick}")
      end)
  """
  @spec on_phase(phase(), phase_callback(), GenServer.server()) :: :ok
  def on_phase(phase, callback, server \\ __MODULE__) when phase in @phases do
    GenServer.cast(server, {:subscribe_phase, phase, callback})
  end

  @doc """
  Subscribes a callback to the primary phase for a domain.

  Uses the domain → phase mapping to determine which phase to subscribe to.

  ## Examples

      Clock.subscribe_domain(:thunderbolt)  # Subscribes to :hold phase
  """
  @spec subscribe_domain(atom(), phase_callback(), GenServer.server()) :: :ok
  def subscribe_domain(domain, callback \\ & &1, server \\ __MODULE__) do
    phase = Map.get(@domain_phases, domain, :hold)
    on_phase(phase, callback, server)
  end

  @doc """
  Manually advances to the next phase (for testing/debugging).
  """
  @spec advance(GenServer.server()) :: :ok
  def advance(server \\ __MODULE__) do
    GenServer.cast(server, :advance)
  end

  @doc """
  Pauses the clock (stops automatic phase transitions).
  """
  @spec pause(GenServer.server()) :: :ok
  def pause(server \\ __MODULE__) do
    GenServer.cast(server, :pause)
  end

  @doc """
  Resumes the clock after pausing.
  """
  @spec resume(GenServer.server()) :: :ok
  def resume(server \\ __MODULE__) do
    GenServer.cast(server, :resume)
  end

  @doc """
  Returns the primary phase for a given domain.

  ## Examples

      iex> Clock.phase_for_domain(:thunderbolt)
      :hold

      iex> Clock.phase_for_domain(:thunderwall)
      :relax
  """
  @spec phase_for_domain(atom()) :: phase()
  def phase_for_domain(domain) do
    Map.get(@domain_phases, domain, :hold)
  end

  @doc """
  Returns all phases in order.
  """
  @spec phases() :: [phase()]
  def phases, do: @phases

  @doc """
  Returns the next phase after the given phase.
  """
  @spec next_phase(phase()) :: phase()
  def next_phase(:switch), do: :hold
  def next_phase(:hold), do: :release
  def next_phase(:release), do: :relax
  def next_phase(:relax), do: :switch

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    tick_interval = Keyword.get(opts, :tick_interval_ms, @default_tick_interval_ms)
    phase_ratios = Keyword.get(opts, :phase_ratios, @default_phase_ratios)
    auto_start = Keyword.get(opts, :auto_start, true)

    # Calculate phase durations in ms
    phase_durations =
      Enum.map(@phases, fn phase ->
        ratio = Keyword.get(phase_ratios, phase, 0.25)
        {phase, round(tick_interval * ratio)}
      end)
      |> Map.new()

    state = %{
      tick: 0,
      phase: :switch,
      phase_index: 0,
      phase_durations: phase_durations,
      tick_interval: tick_interval,
      subscribers: %{switch: [], hold: [], release: [], relax: []},
      paused: false,
      timer_ref: nil
    }

    # Schedule first phase if auto_start
    state =
      if auto_start do
        schedule_next_phase(state)
      else
        state
      end

    Logger.info("[Clock] Started with #{tick_interval}ms cycle, phases: #{inspect(phase_durations)}")

    {:ok, state}
  end

  @impl true
  def handle_call(:current_phase, _from, state) do
    {:reply, {state.phase, state.tick}, state}
  end

  @impl true
  def handle_cast({:subscribe_phase, phase, callback}, state) do
    subscribers = Map.update!(state.subscribers, phase, &[callback | &1])
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_cast(:advance, state) do
    {:noreply, do_advance(state)}
  end

  @impl true
  def handle_cast(:pause, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    {:noreply, %{state | paused: true, timer_ref: nil}}
  end

  @impl true
  def handle_cast(:resume, state) do
    state = schedule_next_phase(%{state | paused: false})
    {:noreply, state}
  end

  @impl true
  def handle_info(:phase_tick, %{paused: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:phase_tick, state) do
    state = do_advance(state)
    {:noreply, schedule_next_phase(state)}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Clock] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════════════════

  defp do_advance(state) do
    # Move to next phase
    next_idx = rem(state.phase_index + 1, 4)
    next_phase = Enum.at(@phases, next_idx)

    # Increment tick on full cycle completion
    new_tick =
      if next_phase == :switch do
        state.tick + 1
      else
        state.tick
      end

    # Update state before notifications
    new_state = %{state | phase: next_phase, phase_index: next_idx, tick: new_tick}

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :core, :clock, :phase],
      %{tick: new_tick, duration_ms: Map.get(state.phase_durations, next_phase, 200)},
      %{phase: next_phase, previous_phase: state.phase}
    )

    # Emit event
    emit_phase_event(next_phase, new_tick)

    # Notify subscribers
    notify_subscribers(new_state, next_phase, new_tick)

    new_state
  end

  defp schedule_next_phase(%{paused: true} = state), do: state

  defp schedule_next_phase(state) do
    duration = Map.get(state.phase_durations, state.phase, 200)
    timer_ref = Process.send_after(self(), :phase_tick, duration)
    %{state | timer_ref: timer_ref}
  end

  defp notify_subscribers(state, phase, tick) do
    callbacks = Map.get(state.subscribers, phase, [])

    for callback <- callbacks do
      try do
        callback.(tick)
      rescue
        e ->
          Logger.warning("[Clock] Subscriber error in #{phase}: #{inspect(e)}")
      end
    end
  end

  defp emit_phase_event(phase, tick) do
    event_attrs = %{
      name: "system.core.clock.#{phase}",
      source: :clock,
      payload: %{
        phase: phase,
        tick: tick,
        timestamp: DateTime.utc_now()
      },
      meta: %{
        pipeline: :realtime,
        priority: :high
      }
    }

    # Fire and forget - clock should not block on event publishing
    Task.start(fn ->
      case EventBus.publish_event(event_attrs) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.debug("[Clock] Event publish failed: #{inspect(reason)}")
      end
    end)
  end
end
