defmodule Thunderline.Thundercrown.Supervisor do
  @moduledoc """
  ThunderCrown domain supervisor with tick-based activation.

  CROWN is the sovereign - orchestration, permissions, AI coordination, MCP.
  Activates on tick 4 after core domains are stable.
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
        Logger.error("[Thundercrown.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    # Crown orchestration services
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thundercrown"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 4

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[ThunderCrown] 👑 CROWN ASCENDED - AI Orchestration & MCP Online at tick #{tick_count}")

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      mcp_servers_ready: false,
      ai_orchestration_enabled: true,
      active_agents: 0,
      tick_count: tick_count
    }

    :telemetry.execute(
      [:thunderline, :thundercrown, :activated],
      %{tick: tick_count},
      %{domain: "thundercrown", services: ["mcp", "ai_orchestration", "permissions"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # AI agent health every 25 ticks
    if rem(tick_count, 25) == 0 do
      Logger.debug("[ThunderCrown] 👑 Sovereign pulse at tick #{tick_count}")
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at
    Logger.info(
      "[ThunderCrown] 👑 Crown descending after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
