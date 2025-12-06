defmodule Thunderline.Thunderprism.PrismNode do
  @moduledoc """
  PrismNode - DEPRECATED, use Thunderline.Thundergrid.Prism.PrismNode

  This module is an alias for backward compatibility.
  """

  # Delegate struct and type to new location
  defdelegate __struct__(), to: Thunderline.Thundergrid.Prism.PrismNode
  defdelegate __struct__(kv), to: Thunderline.Thundergrid.Prism.PrismNode
end
