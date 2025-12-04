defmodule Thunderline.Thundervine.FieldChannels.Reward do
  @moduledoc """
  Reward field channel - reinforcement learning signal.

  ## Semantics

  - Positive values: Positive reinforcement, beneficial location
  - Zero: Neutral
  - Negative values: Negative reinforcement, penalty zone

  ## Parameters

  - Default: 0.0 (neutral)
  - Decay rate: 0.10 (moderate decay - rewards persist but fade)
  - Diffusion rate: 0.08 (moderate spreading - rewards have area of effect)

  ## Use Cases

  - Reinforcement learning integration
  - Path optimization
  - Behavior shaping
  - Credit assignment
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :reward,
    default: 0.0,
    decay_rate: 0.10,
    diffusion_rate: 0.08

  @doc """
  Rewards decay toward zero but maintain sign.
  """
  def apply_decay_to_value(value) when is_number(value) do
    value * 0.90
  end

  @doc """
  Rewards must be significant to matter.
  """
  def significant?(value) when is_number(value), do: abs(value) > 0.005

  @doc """
  Rewards use temporal difference-like combination.
  More recent rewards weighted higher.
  """
  def combine_writes(values) when is_list(values) do
    if Enum.empty?(values) do
      0.0
    else
      # Exponentially weighted average (recent values matter more)
      {weighted_sum, weight_total} =
        values
        |> Enum.reverse()
        |> Enum.with_index()
        |> Enum.reduce({0.0, 0.0}, fn {value, idx}, {sum, total} ->
          weight = :math.pow(0.9, idx)
          {sum + value * weight, total + weight}
        end)

      avg = if weight_total > 0, do: weighted_sum / weight_total, else: 0.0
      # Inline clamp - inherited version has different range
      avg |> max(-1.0) |> min(1.0)
    end
  end
end
