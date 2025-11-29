defmodule Thunderline.Thundercore.Supervisor do
  @moduledoc """
  Supervisor for Thundercore domain processes.

  Manages:
  - SystemClock - Monotonic time service
  - TickEmitter - System heartbeat generator

  ## Startup Order

  SystemClock starts first to provide time services, then TickEmitter
  starts to begin broadcasting heartbeat events.
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
      Thunderline.Thundercore.TickEmitter
    ]

    Logger.info("[Thundercore.Supervisor] Starting with #{length(children)} children")

    Supervisor.init(children, strategy: :one_for_one)
  end
end
