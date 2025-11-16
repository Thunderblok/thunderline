defmodule Thunderline.Thunderprism.Domain do
  @moduledoc """
  ThunderPrism Domain - DAG scratchpad for ML decision trails.

  This domain provides persistent "memory rails" that record ML decision nodes
  and their connections, enabling visualization and AI context querying.

  Resources:
  - PrismNode: Individual ML decision points (pac_id, iteration, model selection)
  - PrismEdge: Connections between nodes (sequential decisions, relationships)

  Phase 4.0 - November 15, 2025
  """
  use Ash.Domain

  resources do
    resource Thunderline.Thunderprism.PrismNode
    resource Thunderline.Thunderprism.PrismEdge
  end
end
