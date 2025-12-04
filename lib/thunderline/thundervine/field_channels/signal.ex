defmodule Thunderline.Thundervine.FieldChannels.Signal do
  @moduledoc """
  Signal field channel - communication strength.

  ## Semantics

  - High values: Strong communication signal, message passing active
  - Low values: Weak signal, poor connectivity
  - Zero: No signal

  ## Parameters

  - Default: 0.0 (no signal)
  - Decay rate: 0.30 (very fast decay - signals are ephemeral)
  - Diffusion rate: 0.05 (minimal spreading - signals are directed)

  ## Use Cases

  - Message routing hints
  - Communication topology discovery
  - Broadcast patterns
  """

  use Thunderline.Thundervine.FieldChannels.Base,
    name: :signal,
    default: 0.0,
    decay_rate: 0.30,
    diffusion_rate: 0.05

  @doc """
  Signal is ephemeral - decays very quickly.
  """
  def apply_decay_to_value(value) when is_number(value) do
    value * 0.70
  end

  @doc """
  Signals below threshold are noise.
  """
  def significant?(value) when is_number(value), do: abs(value) > 0.01

  @doc """
  Signals don't accumulate - take max strength.
  """
  def combine_writes(values) when is_list(values) do
    if Enum.empty?(values) do
      0.0
    else
      # Take the strongest signal rather than summing
      Enum.max_by(values, &abs/1, fn -> 0.0 end)
    end
  end
end
