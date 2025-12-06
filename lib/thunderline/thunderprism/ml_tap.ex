defmodule Thunderline.Thunderprism.MLTap do
  @moduledoc """
  MLTap - DEPRECATED, use Thunderline.Thundergrid.Prism.MLTap

  This module delegates to the new Prism location for backward compatibility.

  ## Migration

  Old:
      Thunderline.Thunderprism.MLTap.log_node(attrs)

  New:
      Thunderline.Thundergrid.Prism.MLTap.log_node(attrs)
      # or
      Thunderline.Thundergrid.Prism.log_decision(attrs)
  """

  # Delegate all functions to new location
  defdelegate log_node(attrs), to: Thunderline.Thundergrid.Prism.MLTap
  defdelegate log_edge(attrs), to: Thunderline.Thundergrid.Prism.MLTap
  defdelegate log_with_edge(attrs, prev_node_id \\ nil), to: Thunderline.Thundergrid.Prism.MLTap
end
