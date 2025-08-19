defmodule Thunderline.Thunderbolt.TopologyDistributor do
  @moduledoc """
  Stub distributor mapping partitions to THUNDERCELL nodes.

  Will later consider node capacity & locality metrics.
  """
  def distribute(_topology) do
    {:ok,
     %{
       load_balance: %{"node-1" => 1.0},
       locality_score: 1.0,
       communication_overhead: 0.0,
       memory_efficiency: 1.0,
       health_score: 1.0
     }}
  end
end
