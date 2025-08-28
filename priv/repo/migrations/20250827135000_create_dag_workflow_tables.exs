defmodule Thunderline.Repo.Migrations.CreateDagWorkflowTables do
  use Ecto.Migration

  @disable_ddl_transaction true

  def change do
    # Root workflow table
    create table(:dag_workflows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_domain, :string, null: false
      add :root_event_name, :string, null: false
      add :correlation_id, :string, null: false
      add :causation_id, :string
      add :status, :string, null: false, default: "building"
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: true, inserted_at: :inserted_at, type: :utc_datetime_usec)
    end

    create unique_index(:dag_workflows, [:correlation_id])

    # Node table
    create table(:dag_nodes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :workflow_id, :uuid, null: false
      add :event_name, :string, null: false
      add :resource_ref, :string
      add :action_name, :string
      add :status, :string, null: false, default: "pending"
      add :correlation_id, :string, null: false
      add :causation_id, :string
      add :payload, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:dag_nodes, [:workflow_id])
    create index(:dag_nodes, [:correlation_id])

    # Edge table
    create table(:dag_edges, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :workflow_id, :uuid, null: false
      add :from_node_id, :uuid, null: false
      add :to_node_id, :uuid, null: false
      add :edge_type, :string, null: false, default: "causal"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:dag_edges, [:workflow_id, :from_node_id, :to_node_id, :edge_type], name: :dag_edges_unique_edge)
    create index(:dag_edges, [:workflow_id])

    # Snapshot table
    create table(:dag_snapshots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :workflow_id, :uuid, null: false
      add :version, :integer, null: false, default: 1
      add :node_order, {:array, :uuid}, null: false, default: []
      add :nodes_payload, :map, null: false, default: %{}
      add :edges, {:array, :map}, null: false, default: []
      add :embedding_vector, {:array, :float}
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:dag_snapshots, [:workflow_id])
    create index(:dag_snapshots, [:version])
  end
end
