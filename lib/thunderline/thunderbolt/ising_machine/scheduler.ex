defmodule Thunderline.Thunderbolt.IsingMachine.Scheduler do
  @moduledoc """
  Stub distributed scheduler for Ising optimization.
  """
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])
  def init(opts), do: {:ok, %{opts: opts, tiles: []}}
end
