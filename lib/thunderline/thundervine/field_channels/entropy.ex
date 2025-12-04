defmodule Thunderline.Thundervine.FieldChannels.Entropy do
  @moduledoc """
  Entropy field channel - local disorder measure.

  ## Semantics

  - Values near 1.0: High disorder, chaos, unpredictability
  - Values near 0.5: Moderate disorder, normal operation
  - Values near 0.0: High order, structure, predictability

  ## Parameters

  - Default: 0.5 (moderate disorder)
  - Decay rate: 0.08 (slow decay - entropy tends to increase naturally)
  - Diffusion rate: 0.12 (moderate spreading - disorder spreads)

  ## Use Cases

  - System stability monitoring
  - Garbage collection triggers
  - Resource reclamation zones
  - Wall domain integration
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :entropy,
    default: 0.5,
    decay_rate: 0.08,
    diffusion_rate: 0.12

  @doc """
  Entropy naturally tends to increase (second law of thermodynamics).
  Decay moves toward higher entropy, not zero.
  """
  def apply_decay_to_value(value) when is_number(value) do
    max_entropy = 1.0
    drift_rate = 0.02
    decay_rate = 0.08

    # Natural drift toward higher entropy
    drifted = value + (max_entropy - value) * drift_rate

    # But also some stabilization
    drifted * (1.0 - decay_rate) + 0.5 * decay_rate
  end

  @doc """
  Entropy is always significant - it's a fundamental property.
  """
  def significant?(_value), do: true

  @doc """
  Entropy averages rather than sums.
  """
  def combine_writes(values) when is_list(values) do
    if Enum.empty?(values) do
      0.5
    else
      avg = Enum.sum(values) / length(values)
      # Inline clamp
      avg |> max(0.0) |> min(1.0)
    end
  end
end
