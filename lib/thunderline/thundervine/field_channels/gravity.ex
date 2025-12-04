defmodule Thunderline.Thundervine.FieldChannels.Gravity do
  @moduledoc """
  Gravity field channel - spatial attraction and repulsion.

  ## Semantics

  - Positive values: Attractive force (draws Thunderbits toward this location)
  - Negative values: Repulsive force (pushes Thunderbits away)
  - Zero: Neutral gravity

  ## Parameters

  - Default: 0.0 (neutral)
  - Decay rate: 0.05 (slow decay - gravity wells are persistent)
  - Diffusion rate: 0.02 (minimal spreading - gravity is localized)

  ## Use Cases

  - Resource concentration points (positive gravity)
  - Hazard zones (negative gravity)
  - Spatial organization and clustering
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :gravity,
    default: 0.0,
    decay_rate: 0.05,
    diffusion_rate: 0.02

  @doc """
  Gravity uses inverse-square falloff for diffusion.
  """
  def apply_decay_to_value(value) when is_number(value) do
    # Gravity decays slowly
    value * 0.95
  end

  @doc """
  Gravity values can range from -10.0 to 10.0 for stronger effects.
  """
  def combine_writes(values) when is_list(values) do
    sum = Enum.sum(values)
    # Inline clamp - different range than base
    sum |> max(-10.0) |> min(10.0)
  end
end
