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
    resource Thunderline.Thunderprism.PrismNode do
      define :create_prism_node,
        action: :create,
        args: [
          :pac_id,
          :iteration,
          :chosen_model,
          :model_probabilities,
          :model_distances,
          :meta,
          :timestamp
        ]

      define :get_prism_node, action: :read, get_by: [:id]
      define :list_prism_nodes, action: :read
    end

    resource Thunderline.Thunderprism.PrismEdge do
      define :create_prism_edge,
        action: :create,
        args: [
          :from_id,
          :to_id,
          :relation_type,
          :meta
        ]

      define :get_prism_edge, action: :read, get_by: [:id]
      define :list_prism_edges, action: :read
    end
  end
end
