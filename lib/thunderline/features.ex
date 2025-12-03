defmodule Thunderline.Features do
  @moduledoc """
  Features - Alias module for Thunderline.Feature.

  Some code references `Thunderline.Features` (plural), this module
  delegates to the canonical `Thunderline.Feature` implementation.
  """

  defdelegate enabled?(flag, opts \\ []), to: Thunderline.Feature
  defdelegate override(flag, value), to: Thunderline.Feature
  defdelegate clear_override(flag), to: Thunderline.Feature
  defdelegate all(), to: Thunderline.Feature
end
