defmodule Thunderline.Thundervine.Domain do
  @moduledoc """
  ThunderVine Domain - Workflow orchestration and event-sourced DAG management.

  Owns workflow resources that model event-driven execution graphs:
  - Workflow: Root workflow instance anchored on correlation_id
  - WorkflowNode: Atomic step in a workflow (links to events & actions)
  - WorkflowEdge: Causal link between nodes (dependency graph)
  - WorkflowSnapshot: Immutable serialized workflow for replay

  These resources enable event-sourced workflow tracking, lineage analysis,
  and replay capabilities for distributed system observability.
  """
  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain]

  graphql do
    authorize? true

    queries do
      # Workflow queries
      get Thunderline.Thundervine.Resources.Workflow, :workflow, :read
      list Thunderline.Thundervine.Resources.Workflow, :workflows, :read
      get Thunderline.Thundervine.Resources.Workflow, :workflow_by_correlation, :by_correlation_id

      # WorkflowNode queries
      list Thunderline.Thundervine.Resources.WorkflowNode, :workflow_nodes, :read

      # WorkflowEdge queries (renamed type to workflow_link to avoid GraphQL collision)
      list Thunderline.Thundervine.Resources.WorkflowEdge, :workflow_edges, :read

      # WorkflowSnapshot queries
      get Thunderline.Thundervine.Resources.WorkflowSnapshot, :workflow_snapshot, :read
      list Thunderline.Thundervine.Resources.WorkflowSnapshot, :workflow_snapshots, :read
    end

    mutations do
      # Workflow mutations
      create Thunderline.Thundervine.Resources.Workflow, :start_workflow, :start
      update Thunderline.Thundervine.Resources.Workflow, :seal_workflow, :seal

      update Thunderline.Thundervine.Resources.Workflow,
             :update_workflow_metadata,
             :update_metadata

      # WorkflowNode mutations
      create Thunderline.Thundervine.Resources.WorkflowNode, :record_node_start, :record_start
      update Thunderline.Thundervine.Resources.WorkflowNode, :mark_node_success, :mark_success
      update Thunderline.Thundervine.Resources.WorkflowNode, :mark_node_error, :mark_error

      # WorkflowEdge mutations (type renamed to workflow_link to avoid GraphQL collision)
      create Thunderline.Thundervine.Resources.WorkflowEdge, :create_workflow_edge, :create

      # WorkflowSnapshot mutations
      create Thunderline.Thundervine.Resources.WorkflowSnapshot,
             :capture_workflow_snapshot,
             :capture
    end
  end

  resources do
    # Workflow resources
    resource Thunderline.Thundervine.Resources.Workflow
    resource Thunderline.Thundervine.Resources.WorkflowNode
    resource Thunderline.Thundervine.Resources.WorkflowEdge
    resource Thunderline.Thundervine.Resources.WorkflowSnapshot

    # TAK persistence resources
    resource Thundervine.TAKChunkEvent
    resource Thundervine.TAKChunkState
  end
end
