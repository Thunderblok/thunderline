defmodule Thunderline.Thunderprism.Supervisor do
  @moduledoc """
  Thunderprism domain supervisor with tick-based activation.

  PRISM is the visual intelligence layer - ML decision DAGs, visualization nodes, AI context trails.
  Activates on tick 7 after all data domains (Grid, Vine, Flow) are stable and queryable.
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
        Logger.error("[Thunderprism.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # ML decision trail visualization services
      # Future: PrismAnalyzer, DecisionGraphBuilder, MLTapProcessor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thunderprism"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 7

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info(
      "[Thunderprism] 🔮 PRISM AWAKENED - Visual intelligence & ML decision trails ONLINE at tick #{tick_count}"
    )

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      decision_graph_ready: true,
      ml_tap_ready: true,
      prism_nodes_count: 0,
      prism_edges_count: 0,
      tick_count: tick_count
    }

    # Emit custom telemetry
    :telemetry.execute(
      [:thunderline, :thunderprism, :activated],
      %{tick: tick_count},
      %{
        domain: "thunderprism",
        services: ["decision_graph", "ml_visualization", "context_trails"]
      }
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Health check every 45 ticks (45 seconds) - monitor ML decision graph health
    if rem(tick_count, 45) == 0 do
      Logger.debug(
        "[Thunderprism] 🔮 Visual pulse at tick #{tick_count} - Decision trails illuminated"
      )
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at

    Logger.info(
      "[Thunderprism] 🔮 Prism dimming after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
