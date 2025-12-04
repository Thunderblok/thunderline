defmodule Thunderline.Thundervine.FieldChannels.Mood do
  @moduledoc """
  Mood field channel - emotional/social field.

  ## Semantics

  - Values near 1.0: Positive mood (happiness, excitement, cooperation)
  - Values near 0.5: Neutral mood
  - Values near 0.0: Negative mood (sadness, anxiety, conflict)

  ## Parameters

  - Default: 0.5 (neutral)
  - Decay rate: 0.15 (moderate decay - moods fade over time)
  - Diffusion rate: 0.10 (moderate spreading - moods are contagious)

  ## Use Cases

  - Social dynamics simulation
  - Emotional contagion modeling
  - Group behavior influence
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :mood,
    default: 0.5,
    decay_rate: 0.15,
    diffusion_rate: 0.10

  @doc """
  Mood decays toward neutral (0.5) rather than zero.
  """
  def apply_decay_to_value(value) when is_number(value) do
    neutral = 0.5
    decay_rate = 0.15

    # Decay toward neutral
    value + (neutral - value) * decay_rate
  end

  @doc """
  Mood values are clamped to [0, 1].
  """
  def combine_writes(values) when is_list(values) do
    # Average rather than sum for mood
    if Enum.empty?(values) do
      0.5
    else
      avg = Enum.sum(values) / length(values)
      # clamp is inherited from Base
      avg |> max(0.0) |> min(1.0)
    end
  end
end
