defmodule Thunderline.Repo.Migrations.AddIndexesForDagNodesAndEdges do
  use Ecto.Migration

  def change do
    # Efficient latest-node lookup within a workflow (sort by inserted_at DESC with index scan)
    create index(:dag_nodes, [:workflow_id, :inserted_at])

    # Edge traversal helpers (from_node_id / to_node_id pattern)
    create index(:dag_edges, [:workflow_id, :from_node_id])
    create index(:dag_edges, [:workflow_id, :to_node_id])
  end
end
