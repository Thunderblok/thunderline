defmodule Thunderline.Thundervine.FieldChannels.Intent do
  @moduledoc """
  Intent field channel - directional intent vectors.

  ## Semantics

  Unlike scalar channels, Intent stores directional information:
  - `:neutral` - No directed intent
  - `{dx, dy, dz}` - Directional vector indicating intended movement/focus
  - `:attract` - Generic attraction intent
  - `:repel` - Generic repulsion intent

  ## Parameters

  - Default: :neutral
  - Decay rate: 0.25 (moderately fast decay - intent is temporary)
  - Diffusion rate: 0.0 (no spreading - intent is personal)

  ## Use Cases

  - Movement planning
  - Attention direction
  - Goal-oriented behavior coordination
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :intent,
    default: :neutral,
    decay_rate: 0.25,
    diffusion_rate: 0.0

  @doc """
  Intent decays to neutral.
  """
  def apply_decay_to_value(:neutral), do: :neutral

  def apply_decay_to_value({dx, dy, dz} = _vector) when is_number(dx) do
    decay_rate = 0.25

    new_dx = dx * (1.0 - decay_rate)
    new_dy = dy * (1.0 - decay_rate)
    new_dz = dz * (1.0 - decay_rate)

    # If vector is too small, collapse to neutral
    if abs(new_dx) < 0.01 and abs(new_dy) < 0.01 and abs(new_dz) < 0.01 do
      :neutral
    else
      {new_dx, new_dy, new_dz}
    end
  end

  def apply_decay_to_value(_other), do: :neutral

  @doc """
  Only neutral intent is insignificant.
  """
  def significant?(:neutral), do: false
  def significant?(_value), do: true

  @doc """
  Intent doesn't diffuse - it's personal to each location.
  """
  def neighbor_offsets, do: []

  @doc """
  Combine intents by vector averaging.
  """
  def combine_writes(values) when is_list(values) do
    vectors = Enum.filter(values, &is_tuple/1)

    if Enum.empty?(vectors) do
      # Check for special intents
      cond do
        :attract in values -> :attract
        :repel in values -> :repel
        true -> :neutral
      end
    else
      # Average all vectors
      {sum_x, sum_y, sum_z} =
        Enum.reduce(vectors, {0.0, 0.0, 0.0}, fn {dx, dy, dz}, {ax, ay, az} ->
          {ax + dx, ay + dy, az + dz}
        end)

      count = length(vectors)
      avg = {sum_x / count, sum_y / count, sum_z / count}

      # Normalize if too large
      {nx, ny, nz} = avg
      magnitude = :math.sqrt(nx * nx + ny * ny + nz * nz)

      if magnitude > 1.0 do
        {nx / magnitude, ny / magnitude, nz / magnitude}
      else
        avg
      end
    end
  end
end
