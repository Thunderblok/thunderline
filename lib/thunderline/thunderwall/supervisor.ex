defmodule Thunderline.Thunderwall.Supervisor do
  @moduledoc """
  Supervisor for Thunderwall domain processes.

  Manages:
  - EntropyMetrics - System decay telemetry
  - OverflowHandler - Reject stream management
  - GCScheduler - Garbage collection coordination

  ## Startup Order

  EntropyMetrics starts first to begin collecting, then OverflowHandler
  and GCScheduler start to handle cleanup operations.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # EntropyMetrics first - collects decay stats
      Thunderline.Thunderwall.EntropyMetrics,
      # OverflowHandler - handles domain overflows
      Thunderline.Thunderwall.OverflowHandler,
      # GCScheduler last - coordinates cleanup
      Thunderline.Thunderwall.GCScheduler
    ]

    Logger.info("[Thunderwall.Supervisor] Starting with #{length(children)} children")

    Supervisor.init(children, strategy: :one_for_one)
  end
end
