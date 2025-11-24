defmodule Thunderline.Thunderlink.Supervisor do
  @moduledoc """
  ThunderLink domain supervisor with tick-based activation.
  
  LINK is the connector - presence, registry, real-time communications.
  Activates on tick 2 alongside ThunderGate.
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
        Logger.error("[Thunderlink.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # Registry was previously in infrastructure_early
      {Thunderline.Thunderlink.Registry, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thunderlink"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 2

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[ThunderLink] 🔗 LINK ESTABLISHED - Presence & Communications Online at tick #{tick_count}")

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      registry_ready: true,
      presence_enabled: true,
      active_connections: 0,
      tick_count: tick_count
    }

    :telemetry.execute(
      [:thunderline, :thunderlink, :activated],
      %{tick: tick_count},
      %{domain: "thunderlink", services: ["registry", "presence"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Presence heartbeat every 20 ticks
    if rem(tick_count, 20) == 0 do
      Logger.debug("[ThunderLink] 🔗 Presence pulse at tick #{tick_count}")
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at
    Logger.info(
      "[ThunderLink] 🔗 Link severing after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
