defmodule Thunderline.Thunderbolt.Policy.Promotion do
  @moduledoc """
  Promotion rule for NAS trials based on metric threshold and step.
  """
  @metric "val_perplexity"
  @threshold 1.25
  @by_step 2000

  @spec promote?(map()) :: boolean()
  def promote?(%{metrics: m, step: s}) when is_map(m) and is_integer(s) do
    case Map.get(m, @metric) do
      nil -> false
      v when is_number(v) -> v <= @threshold and s >= @by_step
      _ -> false
    end
  end

  def promote?(_), do: false
end
