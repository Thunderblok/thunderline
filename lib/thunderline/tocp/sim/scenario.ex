defmodule Thunderline.TOCP.Sim.Scenario do
  @moduledoc """
  Scenario descriptor – defines parameter surface for simulation runs.
  """

  defstruct [:name, :nodes, :loss_pct, :churn_rate, :duration_ms]
end
