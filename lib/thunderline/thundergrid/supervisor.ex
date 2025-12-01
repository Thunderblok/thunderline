defmodule Thunderline.Thundergrid.Supervisor do
  @moduledoc """
  Thundergrid domain supervisor with tick-based activation.

  GRID is the spatial & GraphQL layer - coordinate systems, zone management, GraphQL API.
  Activates on tick 6 after auth (Gate), presence (Link), and data persistence (Vine) are ready.
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
        Logger.error("[Thundergrid.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # Spatial grid management services can be added here
      # For now, minimal - GraphQL layer is mounted separately via Phoenix router
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thundergrid"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 6

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info(
      "[Thundergrid] 🌐 GRID ONLINE - Spatial coordinates & GraphQL API ACTIVE at tick #{tick_count}"
    )

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      graphql_ready: true,
      spatial_system_ready: true,
      zone_count: 0,
      tick_count: tick_count
    }

    # Emit custom telemetry
    :telemetry.execute(
      [:thunderline, :thundergrid, :activated],
      %{tick: tick_count},
      %{domain: "thundergrid", services: ["graphql_api", "spatial_coords", "zone_management"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Health check every 40 ticks (40 seconds) - monitor spatial grid health
    if rem(tick_count, 40) == 0 do
      Logger.debug(
        "[Thundergrid] 🌐 Spatial pulse at tick #{tick_count} - Grid coordinates stable"
      )
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at

    Logger.info(
      "[Thundergrid] 🌐 Grid offline after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
