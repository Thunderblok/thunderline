defmodule Thunderline.Thunderbolt.Supervisor do
  @moduledoc """
  ThunderBolt domain supervisor with tick-based activation.

  BOLT is the orchestrator - cellular automata, lanes, workflows, DAG execution.
  Activates on tick 3 after Gate and Link are stable.
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
        Logger.error("[Thunderbolt.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    # Bolt children will be started post-activation if needed
    # For now, minimal supervision
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thunderbolt"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 3

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info(
      "[ThunderBolt] ⚡ BOLT CHARGED - Orchestration & CA Engine Online at tick #{tick_count}"
    )

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      ca_engine_ready: true,
      lanes_initialized: false,
      workflows_active: 0,
      tick_count: tick_count
    }

    :telemetry.execute(
      [:thunderline, :thunderbolt, :activated],
      %{tick: tick_count},
      %{domain: "thunderbolt", engines: ["ca", "dag", "lanes"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # CA evolution check every 15 ticks
    if rem(tick_count, 15) == 0 do
      Logger.debug("[ThunderBolt] ⚡ Evolution pulse at tick #{tick_count}")
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at

    Logger.info(
      "[ThunderBolt] ⚡ Bolt discharging after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
