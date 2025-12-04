defmodule Thunderline.Thundervine.FieldChannels.Heat do
  @moduledoc """
  Heat field channel - activity and energy diffusion.

  ## Semantics

  - High values: High activity, intense processing, energy concentration
  - Low values: Low activity, dormant areas
  - Zero: Baseline/ambient temperature

  ## Parameters

  - Default: 0.0 (ambient)
  - Decay rate: 0.20 (fast decay - heat dissipates quickly)
  - Diffusion rate: 0.15 (high spreading - heat conducts well)

  ## Use Cases

  - Activity hotspots detection
  - Load balancing (move away from heat)
  - Resource allocation signals
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :heat,
    default: 0.0,
    decay_rate: 0.20,
    diffusion_rate: 0.15

  @doc """
  Heat diffuses quickly to all neighbors.
  Uses Moore neighborhood for better thermal conduction.
  """
  def neighbor_offsets do
    # Moore neighborhood (26 neighbors in 3D)
    for dx <- [-1, 0, 1],
        dy <- [-1, 0, 1],
        dz <- [-1, 0, 1],
        {dx, dy, dz} != {0, 0, 0} do
      {dx, dy, dz}
    end
  end

  @doc """
  Heat values sum but decay quickly.
  """
  def combine_writes(values) when is_list(values) do
    sum = Enum.sum(values)
    # Heat can accumulate higher than 1.0
    # Inline clamp - different range than base
    sum |> max(0.0) |> min(5.0)
  end
end
