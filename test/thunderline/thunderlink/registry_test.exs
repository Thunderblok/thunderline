defmodule Thunderline.Thunderlink.RegistryTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderlink.Registry
  alias Thunderline.Thunderblock.Resources.{ThunderlinkNode, ThunderlinkHeartbeat, ThunderlinkLinkSession}

  setup do
    # Future: Clear ETS cache before each test when implemented
    # :ets.delete_all_objects(Registry.cache_table())
    :ok
  end

  describe "ensure_node/1" do
    test "creates new node with minimal params" do
      params = %{
        name: "node-test-2@localhost",
        node_id: "node-test-2",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      } domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.node_id == "node-test-1"
      assert node.node_type == :beam
      assert node.role == :worker
      assert node.domain == :thunderbolt
      assert node.status == :registered
      assert node.capabilities == []
    end

    test "creates node with full params including capabilities" do
      params = %{
        node_id: "node-test-2",
        node_type: :edge,
        role: :gateway,
        domain: :thundergate,
        status: :online,
        capabilities: ["websocket", "http"],
        metadata: %{region: "us-west-2"}
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.node_id == "node-test-2"
      assert node.node_type == :edge
      assert node.role == :gateway
      assert node.domain == :thundergate
      assert node.status == :online
      assert node.capabilities == ["websocket", "http"]
      assert node.metadata.region == "us-west-2"
    end

    test "updates existing node on subsequent calls" do
      params = %{
        name: "node-test-3@localhost",
        node_id: "node-test-3",
        node_type: :beam,
        role: :controller,
        domain: :thunderflow
      }

      {:ok, node1} = Registry.ensure_node(params)

      # Update with new capabilities
      updated_params = Map.put(params, :capabilities, ["ml", "analytics"])
      {:ok, node2} = Registry.ensure_node(updated_params)

      assert node1.id == node2.id
      assert node2.capabilities == ["ml", "analytics"]
    end

    @tag :skip
    test "caches node in ETS after creation" do
      params = %{
        name: "node-test-4@localhost",
        node_id: "node-test-4",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Check ETS cache
      case :ets.lookup(Registry.cache_table(), "node-test-4") do
        [{_key, cached_node}] ->
          assert cached_node.id == node.id
          assert cached_node.node_id == "node-test-4"

        [] ->
          flunk("Node not found in ETS cache")
      end
    end

    test "emits cluster.node.registered event" do
      # Subscribe to events
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      params = %{
        name: "node-test-5@localhost",
        node_id: "node-test-5",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, _node} = Registry.ensure_node(params)

      # Wait for event
      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.registered"
      assert event.source == :thunderlink
      assert event.payload.node_id == "node-test-5"
      assert event.payload.node_type == :beam
    end

    test "validates required fields" do
      # Missing node_type
      params = %{
        node_id: "node-test-6",
        role: :worker,
        domain: :thunderbolt
      }

      assert {:error, _changeset} = Registry.ensure_node(params)
    end
  end

  describe "mark_online/2" do
    setup do
      # Create a registered node
      params = %{
        node_id: "node-online-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "marks node as online and creates link session", %{node: node} do
      link_params = %{
        peer_node_id: "peer-1",
        connection_type: :tcp,
        metadata: %{latency_ms: 50}
      }

      {:ok, result} = Registry.mark_online(node.node_id, link_params)

      assert result.node.status == :online
      assert result.node.node_id == node.node_id

      # Check link session created
      assert result.link_session.node_id == node.id
      assert result.link_session.peer_node_id == "peer-1"
      assert result.link_session.connection_type == :tcp
      assert result.link_session.established_at != nil
      assert result.link_session.metadata.latency_ms == 50
    end

    @tag :skip
    test "updates ETS cache with online status", %{node: node} do
      link_params = %{
        peer_node_id: "peer-2",
        connection_type: :websocket
      }

      {:ok, _result} = Registry.mark_online(node.node_id, link_params)

      # Check ETS cache
      case :ets.lookup(Registry.cache_table(), node.node_id) do
        [{_key, cached_node}] ->
          assert cached_node.status == :online

        [] ->
          flunk("Node not found in cache")
      end
    end

    test "emits cluster.node.online and cluster.link.established events", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      link_params = %{
        peer_node_id: "peer-3",
        connection_type: :tcp
      }

      {:ok, _result} = Registry.mark_online(node.node_id, link_params)

      # Should receive both events
      assert_receive {:event, event1}, 500
      assert_receive {:event, event2}, 500

      events = [event1, event2]
      event_names = Enum.map(events, & &1.name)

      assert "cluster.node.online" in event_names
      assert "cluster.link.established" in event_names
    end

    test "returns error for non-existent node" do
      link_params = %{
        peer_node_id: "peer-4",
        connection_type: :tcp
      }

      assert {:error, :node_not_found} = Registry.mark_online("nonexistent-node", link_params)
    end
  end

  describe "mark_status/2" do
    setup do
      params = %{
        node_id: "node-status-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "updates node status to degraded", %{node: node} do
      {:ok, updated_node} = Registry.mark_status(node.node_id, :degraded)

      assert updated_node.status == :degraded
      assert updated_node.id == node.id
    end

    test "updates node status to offline", %{node: node} do
      {:ok, updated_node} = Registry.mark_status(node.node_id, :offline)

      assert updated_node.status == :offline
    end

    @tag :skip
    test "updates ETS cache with new status", %{node: node} do
      {:ok, _} = Registry.mark_status(node.node_id, :degraded)

      case :ets.lookup(Registry.cache_table(), node.node_id) do
        [{_key, cached_node}] ->
          assert cached_node.status == :degraded

        [] ->
          flunk("Node not found in cache")
      end
    end

    test "emits cluster.node.status_changed event", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      {:ok, _} = Registry.mark_status(node.node_id, :degraded)

      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.status_changed"
      assert event.payload.node_id == node.node_id
      assert event.payload.new_status == :degraded
    end

    test "emits cluster.node.offline when status changed to offline", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      {:ok, _} = Registry.mark_status(node.node_id, :offline)

      # Should receive both status_changed and offline events
      assert_receive {:event, event1}, 500
      assert_receive {:event, event2}, 500

      events = [event1, event2]
      event_names = Enum.map(events, & &1.name)

      assert "cluster.node.status_changed" in event_names
      assert "cluster.node.offline" in event_names
    end

    test "returns error for non-existent node" do
      assert {:error, :node_not_found} = Registry.mark_status("nonexistent-node", :offline)
    end

    test "validates status values", %{node: node} do
      # Invalid status should fail validation
      assert {:error, _changeset} = Registry.mark_status(node.node_id, :invalid_status)
    end
  end

  describe "heartbeat/2" do
    setup do
      params = %{
        node_id: "node-heartbeat-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt,
        status: :online
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "records heartbeat with metrics", %{node: node} do
      metrics = %{
        cpu_usage: 45.5,
        memory_usage: 60.2,
        latency_ms: 12,
        custom_metrics: %{queue_depth: 100}
      }

      {:ok, heartbeat} = Registry.heartbeat(node.node_id, metrics)

      assert heartbeat.node_id == node.id
      assert heartbeat.cpu_usage == 45.5
      assert heartbeat.memory_usage == 60.2
      assert heartbeat.latency_ms == 12
      assert heartbeat.custom_metrics.queue_depth == 100
      assert heartbeat.recorded_at != nil
    end

    test "updates node last_heartbeat_at", %{node: node} do
      metrics = %{cpu_usage: 30.0}

      {:ok, _heartbeat} = Registry.heartbeat(node.node_id, metrics)

      # Fetch updated node
      updated_node = ThunderlinkNode |> Ash.get!(node.id)
      assert updated_node.last_heartbeat_at != nil
    end

    test "emits cluster.node.heartbeat event", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      metrics = %{cpu_usage: 25.0, memory_usage: 50.0}

      {:ok, _heartbeat} = Registry.heartbeat(node.node_id, metrics)

      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.heartbeat"
      assert event.payload.node_id == node.node_id
      assert event.payload.metrics.cpu_usage == 25.0
    end

    test "returns error for non-existent node" do
      metrics = %{cpu_usage: 50.0}

      assert {:error, :node_not_found} = Registry.heartbeat("nonexistent-node", metrics)
    end

    test "allows heartbeat with minimal metrics", %{node: node} do
      metrics = %{cpu_usage: 10.0}

      {:ok, heartbeat} = Registry.heartbeat(node.node_id, metrics)

      assert heartbeat.cpu_usage == 10.0
      assert heartbeat.memory_usage == nil
      assert heartbeat.latency_ms == nil
    end
  end

  describe "list_nodes/0" do
    setup do
      # Create multiple nodes with different attributes
      nodes = [
        %{
          node_id: "node-list-1",
          node_type: :beam,
          role: :worker,
          domain: :thunderbolt,
          status: :online
        },
        %{
          node_id: "node-list-2",
          node_type: :edge,
          role: :gateway,
          domain: :thundergate,
          status: :online
        },
        %{
          node_id: "node-list-3",
          node_type: :beam,
          role: :coordinator,
          domain: :thundervine,
          status: :offline
        },
        %{
          node_id: "node-list-4",
          node_type: :beam,
          role: :worker,
          domain: :thunderbolt,
          status: :degraded
        }
      ]

      created_nodes = Enum.map(nodes, fn params ->
        {:ok, node} = Registry.ensure_node(params)
        node
      end)

      %{nodes: created_nodes}
    end

    test "returns all nodes when no filters provided", %{nodes: nodes} do
      result = Registry.list_nodes()

      assert length(result) >= length(nodes)
      node_ids = Enum.map(result, & &1.node_id)

      Enum.each(nodes, fn node ->
        assert node.node_id in node_ids
      end)
    end

    test "filters by status" do
      result = Registry.list_nodes(status: :online)

      assert length(result) >= 2
      Enum.each(result, fn node ->
        assert node.status == :online
      end)
    end

    test "filters by role" do
      result = Registry.list_nodes(role: :worker)

      assert length(result) >= 2
      Enum.each(result, fn node ->
        assert node.role == :worker
      end)
    end

    test "filters by domain" do
      result = Registry.list_nodes(domain: :thunderbolt)

      assert length(result) >= 2
      Enum.each(result, fn node ->
        assert node.domain == :thunderbolt
      end)
    end

    test "filters by node_type" do
      result = Registry.list_nodes(node_type: :edge)

      assert length(result) >= 1
      Enum.each(result, fn node ->
        assert node.node_type == :edge
      end)
    end

    test "combines multiple filters" do
      result = Registry.list_nodes(domain: :thunderbolt, status: :online)

      assert length(result) >= 1
      Enum.each(result, fn node ->
        assert node.domain == :thunderbolt
        assert node.status == :online
      end)
    end

    test "returns empty list when no matches" do
      result = Registry.list_nodes(domain: :nonexistent_domain)

      assert result == []
    end
  end

  describe "graph/0" do
    setup do
      # Create nodes
      {:ok, node1} = Registry.ensure_node(%{
        node_id: "graph-node-1",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      })

      {:ok, node2} = Registry.ensure_node(%{
        node_id: "graph-node-2",
        node_type: :edge,
        role: :gateway,
        domain: :thundergate
      })

      {:ok, node3} = Registry.ensure_node(%{
        node_id: "graph-node-3",
        node_type: :beam,
        role: :coordinator,
        domain: :thundervine
      })

      # Mark node1 online with link to node2
      {:ok, _} = Registry.mark_online(node1.node_id, %{
        peer_node_id: node2.node_id,
        connection_type: :tcp
      })

      # Mark node2 online with link to node3
      {:ok, _} = Registry.mark_online(node2.node_id, %{
        peer_node_id: node3.node_id,
        connection_type: :websocket
      })

      %{node1: node1, node2: node2, node3: node3}
    end

    test "returns graph with nodes and edges", %{node1: n1, node2: n2, node3: n3} do
      graph = Registry.graph()

      assert is_map(graph)
      assert Map.has_key?(graph, :nodes)
      assert Map.has_key?(graph, :edges)

      # Check nodes
      assert length(graph.nodes) >= 3
      node_ids = Enum.map(graph.nodes, & &1.node_id)
      assert n1.node_id in node_ids
      assert n2.node_id in node_ids
      assert n3.node_id in node_ids

      # Check edges
      assert length(graph.links) >= 2
    end

    test "includes all node attributes in graph nodes", %{node1: n1} do
      graph = Registry.graph()

      graph_node = Enum.find(graph.nodes, fn node -> node.node_id == n1.node_id end)

      assert graph_node.node_type == :beam
      assert graph_node.role == :worker
      assert graph_node.domain == :thunderbolt
    end

    test "includes link session attributes in edges" do
      graph = Registry.graph()

      # Find an edge
      edge = List.first(graph.links)

      assert Map.has_key?(edge, :node_id)
      assert Map.has_key?(edge, :peer_node_id)
      assert Map.has_key?(edge, :connection_type)
      assert Map.has_key?(edge, :established_at)
    end

    test "handles nodes with no connections" do
      # Create isolated node
      {:ok, isolated_node} = Registry.ensure_node(%{
        node_id: "isolated-node",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      })

      graph = Registry.graph()

      # Should still include isolated node
      node_ids = Enum.map(graph.nodes, & &1.node_id)
      assert isolated_node.node_id in node_ids
    end

    test "graph structure suitable for visualization" do
      graph = Registry.graph()

      # Each node should have required fields for UI
      Enum.each(graph.nodes, fn node ->
        assert node.id != nil
        assert node.node_id != nil
        assert node.node_type != nil
        assert node.role != nil
        assert node.domain != nil
        assert node.status != nil
      end)

      # Each edge should have source/target
      Enum.each(graph.links, fn edge ->
        assert edge.node_id != nil
        assert edge.peer_node_id != nil
      end)
    end
  end

  describe "ETS cache behavior" do
    @tag :skip
    test "cache persists across function calls" do
      params = %{
        node_id: "cache-test-1",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Check cache
      [{_key, cached1}] = :ets.lookup(Registry.cache_table(), "cache-test-1")
      assert cached1.id == node.id

      # Update node
      {:ok, _} = Registry.mark_status(node.node_id, :degraded)

      # Cache should be updated
      [{_key, cached2}] = :ets.lookup(Registry.cache_table(), "cache-test-1")
      assert cached2.status == :degraded
    end

    @tag :skip
    test "cache lookup faster than database query" do
      params = %{
        node_id: "cache-perf-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, _node} = Registry.ensure_node(params)

      # Warm up cache
      Registry.ensure_node(params)

      # Time cache lookup
      {cache_time, _} = :timer.tc(fn ->
        :ets.lookup(Registry.cache_table(), "cache-perf-test")
      end)

      # Time database query
      {db_time, _} = :timer.tc(fn ->
        ThunderlinkNode
        |> Ash.Query.filter(node_id: "cache-perf-test")
        |> Ash.read_one!()
      end)

      # Cache should be significantly faster (at least 10x)
      assert cache_time < db_time / 10
    end
  end

  describe "concurrent operations" do
    test "handles concurrent ensure_node calls" do
      params = %{
        node_id: "concurrent-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt
      }

      # Spawn multiple concurrent ensure_node calls
      tasks = Enum.map(1..10, fn _ ->
        Task.async(fn -> Registry.ensure_node(params) end)
      end)

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _node} -> true
               _ -> false
             end)

      # All should reference same node
      node_ids = Enum.map(results, fn {:ok, node} -> node.id end)
      assert Enum.uniq(node_ids) |> length() == 1
    end

    test "handles concurrent heartbeats" do
      params = %{
        node_id: "heartbeat-concurrent-test",
        node_type: :beam,
        role: :worker,
        domain: :thunderbolt,
        status: :online
      }

      {:ok, _node} = Registry.ensure_node(params)

      # Spawn concurrent heartbeats
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          Registry.heartbeat("heartbeat-concurrent-test", %{cpu_usage: i * 10.0})
        end)
      end)

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _heartbeat} -> true
               _ -> false
             end)

      # Verify all heartbeats recorded
      heartbeats = ThunderlinkHeartbeat |> Ash.read!()
      assert length(heartbeats) >= 5
    end
  end
end
