defmodule Thunderline.Thunderbolt.IsingMachine.Temper do
  @moduledoc """
  Stub parallel tempering coordinator.
  """
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])
  def init(opts), do: {:ok, %{opts: opts, replicas: []}}
end
