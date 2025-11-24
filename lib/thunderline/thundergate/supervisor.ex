defmodule Thunderline.Thundergate.Supervisor do
  @moduledoc """
  ThunderGate domain supervisor with tick-based activation.

  GATE is the guardian - authentication, authorization, service registry, health.
  Activates on tick 2 after core infrastructure is stable.
  """

  use Supervisor
  @behaviour Thunderline.Thunderblock.DomainActivation

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    |> tap(fn
      {:ok, _pid} ->
        Thunderline.Thunderblock.DomainActivation.Helpers.maybe_activate(__MODULE__)

      {:error, reason} ->
        Logger.error("[Thundergate.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # Health monitoring starts after activation
      {Thunderline.Thundergate.ServiceRegistry.HealthMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thundergate"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 2

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[ThunderGate] 🛡️  GATE ONLINE - Authentication & Services Active at tick #{tick_count}")

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      health_monitor_ready: true,
      service_registry_ready: true,
      authenticated_sessions: 0,
      tick_count: tick_count
    }

    # Emit custom telemetry
    :telemetry.execute(
      [:thunderline, :thundergate, :activated],
      %{tick: tick_count},
      %{domain: "thundergate", services: ["health_monitor", "service_registry"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Health check every 30 ticks (30 seconds)
    if rem(tick_count, 30) == 0 do
      Logger.debug("[ThunderGate] 🛡️  Guardian pulse at tick #{tick_count}")
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at
    Logger.info(
      "[ThunderGate] 🛡️  Gate closing after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
