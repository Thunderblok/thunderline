defmodule Thunderline.Thunderlink.TickGenerator do
  @moduledoc """
  Generates heartbeat ticks that flow through all domains.
  Domains only become active after receiving first tick.

  ## Tick Flow Architecture

  The TickGenerator is the heartbeat of the Thunderline system:
  1. Starts with application supervision tree
  2. Emits tick every interval (default 1 second)
  3. Broadcasts to "system:domain_tick" PubSub topic
  4. Domains subscribe and activate on first tick
  5. DomainRegistry tracks which domains are active

  ## Tick Event Format

      {:domain_tick, tick_count, timestamp, metadata}

  Where:
  - `tick_count` - Monotonic counter starting at 1
  - `timestamp` - System.monotonic_time() when tick was generated
  - `metadata` - Map with additional context (active_domains count, etc.)

  ## Configuration

      config :thunderline, Thunderline.Thunderlink.TickGenerator,
        interval: 1_000,  # milliseconds
        enabled: true     # set to false to disable

  ## Telemetry

  Emits `[:thunderline, :tick_generator, :tick]` event with measurements:
  - `count` - Current tick count
  - `latency_ns` - Tick processing time in nanoseconds
  - `active_domains` - Number of active domains (from registry)

  ## Example Usage

      # Get current tick count
      Thunderline.Thunderlink.TickGenerator.current_tick()
      #=> 42

      # Get tick statistics
      Thunderline.Thunderlink.TickGenerator.stats()
      #=> %{tick_count: 42, uptime_ms: 42000, started_at: ~U[...]}
  """
  use GenServer
  require Logger

  @tick_interval 1_000  # 1 second default
  @pubsub_topic "system:domain_tick"

  # Client API

  @doc """
  Starts the TickGenerator GenServer.

  ## Options

  - `:interval` - Tick interval in milliseconds (default: 1000)
  - `:name` - Process name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current tick count.
  """
  @spec current_tick() :: non_neg_integer()
  def current_tick do
    GenServer.call(__MODULE__, :current_tick)
  end

  @doc """
  Returns tick generator statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @tick_interval)
    schedule_tick(interval)

    Logger.info("[TickGenerator] Started with #{interval}ms interval")

    {:ok, %{
      tick_count: 0,
      interval: interval,
      started_at: System.monotonic_time(),
      last_tick_at: nil
    }}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_start = System.monotonic_time()
    tick_count = state.tick_count + 1

    # Get active domain count from registry (if available)
    active_count = get_active_domain_count()

    # Broadcast tick event
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      @pubsub_topic,
      {:domain_tick, tick_count, tick_start, %{active_domains: active_count}}
    )

    # Emit telemetry
    tick_latency = System.monotonic_time() - tick_start
    :telemetry.execute(
      [:thunderline, :tick_generator, :tick],
      %{count: tick_count, latency_ns: tick_latency, active_domains: active_count},
      %{interval: state.interval}
    )

    # Log first tick and every 60 ticks (1 minute at default interval)
    if tick_count == 1 or rem(tick_count, 60) == 0 do
      Logger.debug("[TickGenerator] Tick #{tick_count}, active domains: #{active_count}")
    end

    schedule_tick(state.interval)

    {:noreply, %{state | tick_count: tick_count, last_tick_at: tick_start}}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_count, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    uptime_ns = System.monotonic_time() - state.started_at
    uptime_ms = System.convert_time_unit(uptime_ns, :native, :millisecond)

    stats = %{
      tick_count: state.tick_count,
      uptime_ms: uptime_ms,
      interval: state.interval,
      started_at: System.system_time(:second) - div(uptime_ms, 1000),
      last_tick_at: state.last_tick_at
    }

    {:reply, stats, state}
  end

  # Private Functions

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end

  defp get_active_domain_count do
    # Try to get count from DomainRegistry, fallback to 0 if not available
    try do
      if Process.whereis(Thunderline.Thunderblock.DomainRegistry) do
        Thunderline.Thunderblock.DomainRegistry.active_count()
      else
        0
      end
    rescue
      _ -> 0
    end
  end
end
