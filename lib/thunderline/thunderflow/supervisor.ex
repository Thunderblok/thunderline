defmodule Thunderline.Thunderflow.Supervisor do
  @moduledoc """
  Supervisor for Thunderflow domain with tick-based activation.

  Implements the DomainActivation behavior to coordinate startup
  with the tick system. Activates on tick 1 as a core infrastructure domain.

  ## Responsibilities

  - Supervise EventBuffer and Blackboard processes
  - Listen for tick broadcasts
  - Activate domain on first tick
  - Register activation with DomainRegistry
  """

  use Supervisor
  @behaviour Thunderline.Thunderblock.DomainActivation

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    |> tap(fn
      {:ok, _pid} ->
        # Subscribe to tick system and set up activation
        Thunderline.Thunderblock.DomainActivation.Helpers.maybe_activate(__MODULE__)

      {:error, reason} ->
        Logger.error("[Thunderflow.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # These were previously started in infrastructure_early
      {Thunderline.Thunderflow.EventBuffer, []},
      {Thunderline.Thunderflow.Blackboard, []},
      # Near-critical dynamics monitoring (Cinderforge Lab paper)
      {Thunderline.Thunderflow.Telemetry.LoopMonitor, [name: Thunderline.Thunderflow.Telemetry.LoopMonitor]},
      {Thunderline.Thunderflow.Telemetry.TickObserver,
       [
         name: Thunderline.Thunderflow.Telemetry.TickObserver,
         loop_monitor: Thunderline.Thunderflow.Telemetry.LoopMonitor,
         observe_interval: 5,
         auto_irope: true
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thunderflow"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 1

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[Thunderflow] Domain activated at tick #{tick_count}")

    # Initialize pipeline telemetry ETS table
    Thunderline.Thunderflow.PipelineTelemetry.init()

    # Attach default telemetry handlers (log failures at :warning level)
    Thunderline.Thunderflow.PipelineTelemetry.attach_default_handlers(
      log_level: :debug,
      log_throughput?: true,
      log_failures?: true,
      log_health?: false
    )

    # Perform any activation-specific setup here
    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      event_buffer_ready: true,
      blackboard_ready: true,
      tick_count: tick_count,
      pipeline_telemetry_initialized: true
    }

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Log every 10 ticks for visibility
    if rem(tick_count, 10) == 0 do
      Logger.debug("[Thunderflow] Health check at tick #{tick_count}")

      # Get LoopMonitor summary if available
      if Process.whereis(Thunderline.Thunderflow.Telemetry.LoopMonitor) do
        summary = Thunderline.Thunderflow.Telemetry.LoopMonitor.summary()

        :telemetry.execute(
          [:thunderline, :thunderflow, :health_check],
          %{
            tick: tick_count,
            healthy_domains: summary.healthy_count,
            total_domains: summary.total_count,
            health_ratio: summary.health_ratio
          },
          %{domain: "thunderflow"}
        )
      end
    end

    # Update state with current tick
    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    Logger.info(
      "[Thunderflow] Domain deactivated after #{state.tick_count - state.activated_at} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
