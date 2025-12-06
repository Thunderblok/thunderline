defmodule Thunderline.Thunderprism.PrismEdge do
  @moduledoc """
  PrismEdge - DEPRECATED, use Thunderline.Thundergrid.Prism.PrismEdge

  This module is an alias for backward compatibility.
  """

  # Delegate struct and type to new location
  defdelegate __struct__(), to: Thunderline.Thundergrid.Prism.PrismEdge
  defdelegate __struct__(kv), to: Thunderline.Thundergrid.Prism.PrismEdge
end
