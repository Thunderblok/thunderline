defmodule Thunderline.Thundercore.Reward.Supervisor do
  @moduledoc """
  Supervisor for the Thundercore Reward subsystem.

  Manages:
  - RewardController — Processes metrics and maintains tuning state
  - Registry — Tracks active RewardLoop processes per run

  ## Usage

  Started automatically as part of Thundercore.Supervisor.

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for RewardLoop processes
      {Registry, keys: :unique, name: Thunderline.Thundercore.Reward.Registry},

      # The central RewardController
      {Thunderline.Thundercore.Reward.RewardController, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
