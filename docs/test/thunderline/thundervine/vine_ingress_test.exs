defmodule Thunderline.Thundervine.VineIngressTest do
  use Thunderline.DataCase, async: false
  @moduletag :skip

  alias Thunderline.Thunderflow.Pipelines.VineIngress
  alias Thunderline.Thunderblock.Resources.{DAGWorkflow, DAGNode}

  test "process rule command persists workflow & node" do
    meta = %{correlation_id: UUID.uuid4(), source_domain: :bolt}
    assert {:ok, :rule_committed} = VineIngress.process(%{line: "B3/S23", meta: meta})
    assert {:ok, wf} = Ash.read_first(DAGWorkflow, filter: [correlation_id: meta.correlation_id])
    assert {:ok, node} = Ash.read_first(DAGNode, filter: [workflow_id: wf.id])
    assert node.event_name == "evt.action.ca.rule_parsed" or node.event_name == "workflow.spec"
  end

  test "process spec command persists workflow & node" do
    spec = "workflow W\n  node a kind=task\n"
    meta = %{correlation_id: UUID.uuid4(), source_domain: :bolt}
    assert {:ok, :workflow_committed} = VineIngress.process(%{spec: spec, meta: meta})
    assert {:ok, wf} = Ash.read_first(DAGWorkflow, filter: [correlation_id: meta.correlation_id])
    assert {:ok, node} = Ash.read_first(DAGNode, filter: [workflow_id: wf.id])
    assert node.event_name == "workflow.spec"
  end
end
