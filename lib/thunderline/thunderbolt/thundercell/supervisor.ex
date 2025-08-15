defmodule Thunderline.Thunderbolt.ThunderCell.Supervisor do
  @moduledoc """
  Top-level supervisor for the THUNDERCELL Elixir compute layer.
  Manages cell cluster supervisors and core infrastructure processes.
  """

  use Supervisor
  require Logger

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ====================================================================
  # Supervisor callbacks
  # ====================================================================

  @impl true
  def init(_opts) do
    Logger.info("Starting ThunderCell Supervisor...")

    children = [
      # Bridge to Thunderlane Elixir orchestration
      {
        Thunderline.Thunderbolt.ThunderCell.Bridge,
        []
      },

      # Telemetry and performance monitoring
      {
        Thunderline.Thunderbolt.ThunderCell.Telemetry,
        []
      },

      # CA Cell cluster supervisor
      {
        Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor,
        []
      },

      # CA computation engine manager
      {
        Thunderline.Thunderbolt.ThunderCell.CAEngine,
        []
      }
    ]

    # Use one_for_one strategy with reasonable restart limits
    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    ]

    Supervisor.init(children, opts)
  end
end
