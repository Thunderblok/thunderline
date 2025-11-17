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
    validate_config_inclusion?: false

  resources do
    resource Thunderline.Thundervine.Resources.Workflow
    resource Thunderline.Thundervine.Resources.WorkflowNode
    resource Thunderline.Thundervine.Resources.WorkflowEdge
    resource Thunderline.Thundervine.Resources.WorkflowSnapshot
  end
end
