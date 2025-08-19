defmodule Thunderline.Thunderbolt.IsingMachine.Anneal do
  @moduledoc """
  Stub annealing process supervisor.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])
  def init(opts), do: {:ok, %{opts: opts, steps: 0}}
end
