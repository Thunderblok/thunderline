defmodule Thunderline.Thunderlink.RegistrySimpleTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderlink.Registry

  describe "ensure_node/1 - basic functionality" do
    test "creates a new node with required fields" do
      params = %{
        name: "test-node-1@localhost",
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.name == "test-node@localhost"
      assert node.node_id == "test-1"
      assert node.node_type == :beam
      assert node.role == :worker
      assert node.domain == :thunderlink
      assert node.status in [:registered, :disconnected]
    end

    test "updates existing node on subsequent calls" do
      params = %{
        name: "test-node-9@localhost",
        role: :controller,
        domain: :thunderbolt
      }

      {:ok, node1} = Registry.ensure_node(params)
      {:ok, node2} = Registry.ensure_node(Map.put(params, :status, :online))

      assert node1.id == node2.id
      assert node2.status == :online
    end
  end

  describe "mark_online/2" do
    test "marks node as online and creates link session" do
      {:ok, node} =
        Registry.ensure_node(%{
          name: "online-test@localhost",
          node_id: "online-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      link_params = %{
        peer_node_id: "peer-1",
        connection_type: :tcp
      }

      {:ok, result} = Registry.mark_online(node.node_id, link_params)

      assert result.node.status == :online
      assert result.link_session.peer_node_id == "peer-1"
      assert result.link_session.connection_type == :tcp
    end
  end

  describe "mark_status/2" do
    test "updates node status" do
      {:ok, node} =
        Registry.ensure_node(%{
          name: "status-test@localhost",
          node_id: "status-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      {:ok, updated} = Registry.mark_status(node.node_id, :degraded)

      assert updated.status == :degraded
    end
  end

  describe "heartbeat/2" do
    test "records heartbeat with metrics" do
      {:ok, node} =
        Registry.ensure_node(%{
          name: "heartbeat-test@localhost",
          node_id: "hb-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink,
          status: :online
        })

      metrics = %{
        cpu_usage: 45.5,
        memory_usage: 60.2,
        active_connections: 10
      }

      {:ok, heartbeat} = Registry.heartbeat(node.node_id, metrics)

      assert heartbeat.node_id == node.id
      assert heartbeat.metrics.cpu_usage == 45.5
      assert heartbeat.metrics.memory_usage == 60.2
    end
  end

  describe "list_nodes/0" do
    test "returns all nodes" do
      {:ok, _n1} =
        Registry.ensure_node(%{
          name: "list-1@localhost",
          node_id: "list-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      {:ok, _n2} =
        Registry.ensure_node(%{
          name: "list-2@localhost",
          node_id: "list-2",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      {:ok, nodes} = Registry.list_nodes()

      assert length(nodes) >= 2
      assert Enum.any?(nodes, fn n -> n.node_id == "list-1" end)
      assert Enum.any?(nodes, fn n -> n.node_id == "list-2" end)
    end
  end

  describe "graph/0" do
    test "returns topology graph with nodes and links" do
      {:ok, n1} =
        Registry.ensure_node(%{
          name: "graph-1@localhost",
          node_id: "graph-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      {:ok, n2} =
        Registry.ensure_node(%{
          name: "graph-2@localhost",
          node_id: "graph-2",
          node_type: :beam,
          role: :worker,
          domain: :thunderlink
        })

      # Create a link
      {:ok, _} =
        Registry.mark_online(n1.node_id, %{
          peer_node_id: n2.node_id,
          connection_type: :tcp
        })

      {:ok, graph} = Registry.graph()

      assert is_map(graph)
      assert Map.has_key?(graph, :nodes)
      assert Map.has_key?(graph, :links)
      assert length(graph.nodes) >= 2
      assert is_list(graph.links)
    end
  end
end
