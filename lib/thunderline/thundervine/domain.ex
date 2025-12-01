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

      # BehaviorGraph queries (HC-Δ-1)
      get Thunderline.Thundervine.Resources.BehaviorGraph, :behavior_graph, :read
      list Thunderline.Thundervine.Resources.BehaviorGraph, :behavior_graphs, :read
      list Thunderline.Thundervine.Resources.BehaviorGraph, :active_behavior_graphs, :active
      get Thunderline.Thundervine.Resources.BehaviorGraph, :behavior_graph_by_name, :by_name

      # GraphExecution queries (HC-Δ-1)
      get Thunderline.Thundervine.Resources.GraphExecution, :graph_execution, :read
      list Thunderline.Thundervine.Resources.GraphExecution, :graph_executions, :read
      list Thunderline.Thundervine.Resources.GraphExecution, :recent_graph_executions, :recent

      # Thunderoll queries (HC-Δ-7)
      get Thunderline.Thundervine.Thunderoll.Resources.Experiment, :thunderoll_experiment, :read
      list Thunderline.Thundervine.Thunderoll.Resources.Experiment, :thunderoll_experiments, :read

      list Thunderline.Thundervine.Thunderoll.Resources.Experiment,
           :thunderoll_experiments_running,
           :running

      list Thunderline.Thundervine.Thunderoll.Resources.Generation,
           :thunderoll_generations,
           :for_experiment
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

      # BehaviorGraph mutations (HC-Δ-1)
      create Thunderline.Thundervine.Resources.BehaviorGraph, :create_behavior_graph, :create

      create Thunderline.Thundervine.Resources.BehaviorGraph,
             :create_behavior_graph_from_struct,
             :create_from_struct

      update Thunderline.Thundervine.Resources.BehaviorGraph, :update_behavior_graph, :update
      update Thunderline.Thundervine.Resources.BehaviorGraph, :archive_behavior_graph, :archive
      destroy Thunderline.Thundervine.Resources.BehaviorGraph, :delete_behavior_graph, :destroy

      # GraphExecution mutations (HC-Δ-1)
      create Thunderline.Thundervine.Resources.GraphExecution, :start_graph_execution, :start

      update Thunderline.Thundervine.Resources.GraphExecution,
             :complete_graph_execution,
             :complete

      update Thunderline.Thundervine.Resources.GraphExecution, :fail_graph_execution, :fail
      update Thunderline.Thundervine.Resources.GraphExecution, :cancel_graph_execution, :cancel

      # Thunderoll mutations (HC-Δ-7)
      create Thunderline.Thundervine.Thunderoll.Resources.Experiment,
             :start_thunderoll_experiment,
             :start

      update Thunderline.Thundervine.Thunderoll.Resources.Experiment,
             :begin_thunderoll_experiment,
             :begin_running

      update Thunderline.Thundervine.Thunderoll.Resources.Experiment,
             :complete_thunderoll_experiment,
             :complete

      update Thunderline.Thundervine.Thunderoll.Resources.Experiment,
             :fail_thunderoll_experiment,
             :fail

      update Thunderline.Thundervine.Thunderoll.Resources.Experiment,
             :abort_thunderoll_experiment,
             :abort

      create Thunderline.Thundervine.Thunderoll.Resources.Generation,
             :record_thunderoll_generation,
             :record
    end
  end

  resources do
    # Workflow resources
    resource Thunderline.Thundervine.Resources.Workflow
    resource Thunderline.Thundervine.Resources.WorkflowNode
    resource Thunderline.Thundervine.Resources.WorkflowEdge
    resource Thunderline.Thundervine.Resources.WorkflowSnapshot

    # TAK persistence resources
    resource Thunderline.Thundervine.Resources.TAKChunkEvent
    resource Thunderline.Thundervine.Resources.TAKChunkState

    # Behavior DAG resources (HC-Δ-1)
    resource Thunderline.Thundervine.Resources.BehaviorGraph
    resource Thunderline.Thundervine.Resources.GraphExecution

    # Thunderoll resources (HC-Δ-7)
    resource Thunderline.Thundervine.Thunderoll.Resources.Experiment
    resource Thunderline.Thundervine.Thunderoll.Resources.Generation
  end
end
