defmodule Thunderline.Thundercore.Supervisor do
  @moduledoc """
  Supervisor for Thundercore domain processes.

  Manages:
  - SystemClock - Monotonic time service
  - TickEmitter - System heartbeat generator
  - Clock - 4-Phase QCA-inspired clock (HC-88)
  - Reward.Supervisor - Edge-of-chaos reward loop subsystem

  ## Startup Order

  SystemClock starts first to provide time services, then TickEmitter
  starts to begin broadcasting heartbeat events, then Clock starts
  for phase-aware domain coordination, then Reward subsystem starts
  to enable automata tuning.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # SystemClock first - provides time services
      Thunderline.Thundercore.SystemClock,
      # TickEmitter second - broadcasts heartbeat
      Thunderline.Thundercore.TickEmitter,
      # Clock third - 4-phase QCA timing (HC-88)
      Thunderline.Thundercore.Clock,
      # Reward subsystem - edge-of-chaos tuning (HC TIGER LATTICE Thread 3)
      Thunderline.Thundercore.Reward.Supervisor
    ]

    Logger.info("[Thundercore.Supervisor] Starting with #{length(children)} children")

    Supervisor.init(children, strategy: :one_for_one)
  end
end
