defmodule Thunderline.Thunderchief.PlanTreeTest do
  @moduledoc """
  End-to-end tests for PlanTree integration.

  Tests the full lifecycle:
  1. Create plan tree
  2. Expand nodes
  3. Schedule ready nodes
  4. Execute via DomainProcessor (or direct)
  5. Apply results
  6. Verify completion
  """

  use ExUnit.Case, async: true

  alias Thunderline.RoseTree
  alias Thunderline.Thunderchief.PlanTree
  alias Thunderline.Thunderchief.ChiefBehaviour
  alias Thunderline.Thunderchief.Chiefs.PlanChief

  describe "RoseTree" do
    test "creates a tree with root node" do
      tree = RoseTree.new(:root, %{goal: "test"})

      assert %{id: :root, value: %{goal: "test"}} = RoseTree.root(tree)
      assert RoseTree.children(tree) == []
    end

    test "adds children to root" do
      tree =
        RoseTree.new(:root, %{goal: "test"})
        |> RoseTree.add_child(:child1, %{step: 1})
        |> RoseTree.add_child(:child2, %{step: 2})

      children = RoseTree.children(tree)
      assert length(children) == 2
    end

    test "inserts child under specific parent" do
      tree =
        RoseTree.new(:root, %{goal: "test"})
        |> RoseTree.add_child(:child1, %{step: 1})

      {:ok, tree} = RoseTree.insert_child(tree, :child1, :grandchild, %{step: 1.1})

      {:ok, child1_tree} = RoseTree.find(tree, :child1)
      grandchildren = RoseTree.children(child1_tree)
      assert length(grandchildren) == 1
    end

    test "finds nodes by id" do
      tree =
        RoseTree.new(:root, %{goal: "test"})
        |> RoseTree.add_child(:child1, %{step: 1})

      assert {:ok, _} = RoseTree.find(tree, :child1)
      assert {:error, :not_found} = RoseTree.find(tree, :nonexistent)
    end

    test "folds over tree" do
      tree =
        RoseTree.new(:root, %{count: 1})
        |> RoseTree.add_child(:child1, %{count: 2})
        |> RoseTree.add_child(:child2, %{count: 3})

      total = RoseTree.fold(tree, 0, fn node, acc -> acc + node.value.count end)
      assert total == 6
    end

    test "maps over tree" do
      tree =
        RoseTree.new(:root, %{visited: false})
        |> RoseTree.add_child(:child1, %{visited: false})

      updated =
        RoseTree.map(tree, fn node ->
          %{node | value: Map.put(node.value, :visited, true)}
        end)

      all_visited =
        RoseTree.fold(updated, true, fn node, acc ->
          acc && node.value.visited
        end)

      assert all_visited
    end

    test "calculates depth and count" do
      tree =
        RoseTree.new(:root, %{})
        |> RoseTree.add_child(:child1, %{})

      {:ok, tree} = RoseTree.insert_child(tree, :child1, :grandchild, %{})

      assert RoseTree.depth(tree) == 3
      assert RoseTree.count(tree) == 3
    end

    test "serializes to/from map" do
      tree =
        RoseTree.new(:root, %{goal: "test"})
        |> RoseTree.add_child(:child1, %{step: 1})

      map = RoseTree.to_map(tree)
      rebuilt = RoseTree.from_map(map)

      assert RoseTree.root(rebuilt).id == :root
      assert length(RoseTree.children(rebuilt)) == 1
    end
  end

  describe "PlanTree" do
    test "creates a new plan tree" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "test goal", domain: :plan)

      assert PlanTree.id(plan) == "test_plan"
      assert PlanTree.status(plan) == :pending
      assert PlanTree.node_count(plan) == 1
    end

    test "expands root into children" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, domain: :plan}},
          {"step2", %{action: :transform, domain: :plan}}
        ])

      assert PlanTree.node_count(plan) == 3
      assert PlanTree.depth(plan) == 2
    end

    test "schedules ready leaf nodes" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}},
          {"step2", %{action: :transform, kind: :leaf}}
        ])

      ready = PlanTree.schedule_ready_nodes(plan)
      assert length(ready) == 2
    end

    test "schedules sequence nodes in order" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :first, kind: :leaf}},
          {"step2", %{action: :second, kind: :leaf}}
        ])

      # Update root to be a sequence
      {:ok, plan} = update_node_kind(plan, "test_plan", :sequence)

      ready = PlanTree.schedule_ready_nodes(plan)
      # Only first node should be ready
      assert length(ready) == 1
      [{node_id, _}] = ready
      assert node_id == "step1"
    end

    test "applies node results" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}}
        ])

      {:ok, plan} =
        PlanTree.apply_node_result(plan, "step1", %{
          status: :succeeded,
          output: %{data: "fetched"}
        })

      {:ok, {_, node_value}} = PlanTree.get_node(plan, "step1")
      assert node_value.status == :succeeded
      assert node_value.output == %{data: "fetched"}
    end

    test "propagates status to root on completion" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}}
        ])

      {:ok, plan} = PlanTree.apply_node_result(plan, "step1", %{status: :succeeded})

      assert PlanTree.complete?(plan)
      assert PlanTree.status(plan) == :succeeded
    end

    test "propagates failure status" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}}
        ])

      {:ok, plan} =
        PlanTree.apply_node_result(plan, "step1", %{
          status: :failed,
          error: "connection timeout"
        })

      assert PlanTree.complete?(plan)
      assert PlanTree.status(plan) == :failed
    end

    test "cancels node and descendants" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}},
          {"step2", %{action: :transform, kind: :leaf}}
        ])

      {:ok, plan} = PlanTree.cancel(plan, "step1", :user_cancelled)

      {:ok, {_, node_value}} = PlanTree.get_node(plan, "step1")
      assert node_value.status == :cancelled
    end

    test "tick returns ready nodes and updates metadata" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync", tick: 0)

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}}
        ])

      {:ok, plan, ready} = PlanTree.tick(plan)

      assert plan.metadata.tick == 1
      assert length(ready) == 1
    end

    test "serializes to/from map" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync", domain: :plan)

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :fetch, kind: :leaf}}
        ])

      map = PlanTree.to_map(plan)
      {:ok, rebuilt} = PlanTree.from_map(map)

      assert PlanTree.id(rebuilt) == "test_plan"
      assert PlanTree.node_count(rebuilt) == 2
    end

    test "status_summary counts nodes by status" do
      {:ok, plan} = PlanTree.new("test_plan", goal: "sync")

      {:ok, plan} =
        PlanTree.expand(plan, "test_plan", [
          {"step1", %{action: :a, kind: :leaf}},
          {"step2", %{action: :b, kind: :leaf}},
          {"step3", %{action: :c, kind: :leaf}}
        ])

      {:ok, plan} = PlanTree.apply_node_result(plan, "step1", %{status: :succeeded})
      {:ok, plan} = PlanTree.apply_node_result(plan, "step2", %{status: :failed})

      summary = PlanTree.status_summary(plan)
      assert summary[:succeeded] == 1
      assert summary[:failed] == 1
      assert summary[:pending] == 1
    end
  end

  describe "ChiefBehaviour" do
    test "PlanChief implements full behaviour" do
      assert ChiefBehaviour.valid_chief?(PlanChief)
      assert ChiefBehaviour.supports_plans?(PlanChief)
    end

    test "PlanChief returns capabilities" do
      capabilities = ChiefBehaviour.get_capabilities(PlanChief)
      assert is_list(capabilities)
      assert length(capabilities) > 0

      actions = Enum.map(capabilities, & &1.action)
      assert :fetch_data in actions
      assert :transform in actions
    end

    test "PlanChief observes state" do
      context = %{tick: 42, pending_plan: true}
      {:ok, state} = PlanChief.observe_state(context)

      assert state.features.has_pending_plan == true
      assert state.features.tick == 42
    end

    test "PlanChief chooses action based on state" do
      context = %{pending_plan: true}
      {:ok, state} = PlanChief.observe_state(context)
      {:ok, action} = PlanChief.choose_action(state)

      assert action == :expand_node
    end

    test "PlanChief expands nodes" do
      {:ok, children} = PlanChief.expand_node("node1", %{action: :fetch_data}, %{})

      assert is_list(children)
      assert length(children) > 0
    end

    test "PlanChief performs steps" do
      {:ok, result} = PlanChief.perform_step("node1", %{action: :validate}, %{})

      assert result.status == :succeeded
      assert result.output == %{valid: true}
    end

    test "PlanChief estimates priority" do
      persist_priority = PlanChief.estimate_priority(%{action: :persist})
      notify_priority = PlanChief.estimate_priority(%{action: :notify})

      assert persist_priority > notify_priority
    end
  end

  describe "Integration" do
    test "full lifecycle: create -> expand -> execute -> complete" do
      # 1. Create plan
      {:ok, plan} = PlanTree.new("sync_plan", goal: "sync data", domain: :plan)

      # 2. Expand into steps
      {:ok, plan} =
        PlanTree.expand(plan, "sync_plan", [
          {"fetch", %{action: :fetch_data, kind: :leaf, domain: :plan}},
          {"transform", %{action: :transform, kind: :leaf, domain: :plan}}
        ])

      assert PlanTree.node_count(plan) == 3
      assert PlanTree.status(plan) == :pending

      # 3. Schedule ready nodes
      ready = PlanTree.schedule_ready_nodes(plan)
      assert length(ready) == 2

      # 4. Execute each node via PlanChief
      plan =
        Enum.reduce(ready, plan, fn {node_id, node_value}, acc_plan ->
          # Mark as running
          {:ok, acc_plan} = PlanTree.mark_running(acc_plan, node_id)

          # Perform step
          {:ok, result} = PlanChief.perform_step(node_id, node_value, %{})

          # Apply result
          {:ok, acc_plan} = PlanTree.apply_node_result(acc_plan, node_id, result)
          acc_plan
        end)

      # 5. Verify completion
      assert PlanTree.complete?(plan)
      assert PlanTree.status(plan) == :succeeded

      summary = PlanTree.status_summary(plan)
      # root + 2 leaves
      assert summary[:succeeded] == 3
    end

    test "handles failure in execution" do
      {:ok, plan} = PlanTree.new("fail_plan", goal: "will fail", domain: :plan)

      {:ok, plan} =
        PlanTree.expand(plan, "fail_plan", [
          {"step1", %{action: :unknown_action, kind: :leaf, domain: :plan}}
        ])

      ready = PlanTree.schedule_ready_nodes(plan)
      [{node_id, node_value}] = ready

      {:ok, plan} = PlanTree.mark_running(plan, node_id)
      {:ok, result} = PlanChief.perform_step(node_id, node_value, %{})

      # Unknown action results in :skipped, not failure
      assert result.status == :skipped
    end

    test "hierarchical expansion" do
      {:ok, plan} = PlanTree.new("deep_plan", goal: "multi-level", domain: :plan)

      # First level expansion
      {:ok, plan} =
        PlanTree.expand(plan, "deep_plan", [
          {"level1", %{action: :fetch_data, kind: :sequence, domain: :plan}}
        ])

      # Second level expansion via Chief
      {:ok, children} = PlanChief.expand_node("level1", %{action: :fetch_data}, %{})

      {:ok, plan} =
        Enum.reduce(children, {:ok, plan}, fn {child_id, child_value}, {:ok, acc} ->
          PlanTree.expand(acc, "level1", [{child_id, child_value}])
        end)

      # Should have root + level1 + expanded children
      assert PlanTree.depth(plan) >= 2
    end
  end

  # Helper to update node kind (for testing sequence behavior)
  defp update_node_kind(%PlanTree{tree: tree} = plan, node_id, kind) do
    case Thunderline.RoseTree.update_value(tree, node_id, fn value ->
           Map.put(value, :kind, kind)
         end) do
      {:ok, updated_tree} -> {:ok, %{plan | tree: updated_tree}}
      error -> error
    end
  end
end
