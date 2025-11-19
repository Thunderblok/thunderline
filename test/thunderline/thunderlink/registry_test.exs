defmodule Thunderline.Thunderlink.RegistryTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderlink.Registry
  alias Thunderline.Thunderlink.Resources.{Node, Heartbeat, LinkSession}

  setup do
    # Future: Clear ETS cache before each test when implemented
    # :ets.delete_all_objects(Registry.cache_table())
    :ok
  end

  describe "ensure_node/1" do
    test "creates new node with minimal params" do
      params = %{
        name: "node-test-minimal@localhost",
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.name == "node-test-minimal@localhost"
      assert node.cluster_type == :in_cluster
      assert node.role == :worker
      assert node.domain == :thunderbolt
      assert node.status == :connecting
      assert node.meta == %{}
    end

    test "creates node with full params" do
      params = %{
        name: "node-test-2@localhost",
        cluster_type: :out_of_cluster,
        role: :gateway,
        domain: :thundergate,
        meta: %{
          region: "us-west-2",
          capabilities: ["websocket", "http"]
        }
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.name == "node-test-2@localhost"
      assert node.domain == :thundergate
      assert node.status == :connecting
      assert node.meta["capabilities"] == ["websocket", "http"]
      assert node.meta["region"] == "us-west-2"
    end

    test "updates existing node on subsequent calls" do
      params = %{
        name: "node-test-3@localhost",
        cluster_type: :in_cluster,
        role: :controller,
        domain: :thunderflow
      }

      {:ok, node1} = Registry.ensure_node(params)

      # Update with new capabilities in meta
      updated_params = Map.put(params, :meta, %{capabilities: ["ml", "analytics"]})
      {:ok, node2} = Registry.ensure_node(updated_params)

      assert node1.id == node2.id
      assert node2.meta["capabilities"] == ["ml", "analytics"]
    end

    test "caches node in ETS after creation" do
      params = %{
        name: "node-test-4@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Check ETS cache using cache_get helper
      {:ok, cached_node} = Registry.cache_get(node.id)
      assert cached_node.id == node.id
      assert cached_node.name == "node-test-4@localhost"
      assert cached_node.cluster_type == :in_cluster
      assert cached_node.role == :worker
    end

    test "emits cluster.node.registered event" do
      # Subscribe to events
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      params = %{
        name: "node-test-5@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, _node} = Registry.ensure_node(params)

      # Wait for event
      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.registered"
      assert event.source == :thunderlink
      assert event.payload.name == "node-test-5@localhost"
      assert event.payload.cluster_type == :in_cluster
    end

    test "validates required fields" do
      # Missing name (required field)
      params = %{
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
        name: "node-online-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "marks node as online and creates link session", %{node: node} do
      # Create a remote node first
      {:ok, remote_node} =
        Registry.ensure_node(%{
          name: "remote-node@localhost",
          role: :worker,
          domain: :thunderbolt
        })

      link_params = %{
        remote_node_id: remote_node.id,
        meta: %{
          local_peer_id: "local-peer-1",
          remote_peer_id: "remote-peer-1",
          connection_type: :direct,
          latency_ms: 50
        }
      }

      {:ok, {node_result, session}} = Registry.mark_online(node.id, link_params)

      assert node_result.status == :online
      assert node_result.id == node.id

      # Check link session created
      assert session.node_id == node.id
      assert session.remote_node_id == remote_node.id
      assert session.meta.local_peer_id == "local-peer-1"
      assert session.meta.remote_peer_id == "remote-peer-1"
      assert session.meta.connection_type == :direct
      assert session.established_at != nil
      assert session.meta.latency_ms == 50
    end

    test "updates ETS cache with online status", %{node: node} do
      # Create remote node for link
      {:ok, remote_node} =
        Registry.ensure_node(%{
          name: "remote-cache-test@localhost",
          role: :worker,
          domain: :thunderbolt
        })

      link_params = %{
        remote_node_id: remote_node.id,
        meta: %{
          local_peer_id: "local-peer-2",
          remote_peer_id: "remote-peer-2",
          connection_type: :websocket
        }
      }

      {:ok, _result} = Registry.mark_online(node.id, link_params)

      # Check ETS cache updated
      {:ok, cached_node} = Registry.cache_get(node.id)
      assert cached_node.status == :online
    end

    test "emits cluster.node.online and cluster.link.established events", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      link_params = %{
        local_peer_id: "local-peer-3",
        remote_peer_id: "remote-peer-3",
        connection_type: :direct
      }

      {:ok, _result} = Registry.mark_online(node.id, link_params)

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

      assert {:error, _} = Registry.mark_online("nonexistent-node", link_params)
    end
  end

  describe "mark_status/2" do
    setup do
      params = %{
        name: "node-status-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "updates node status to degraded", %{node: node} do
      {:ok, updated_node} = Registry.mark_status(node.id, :degraded)

      assert updated_node.status == :degraded
      assert updated_node.id == node.id
    end

    test "updates node status to offline", %{node: node} do
      {:ok, updated_node} = Registry.mark_status(node.id, :offline)

      assert updated_node.status == :offline
    end

    test "updates ETS cache with new status", %{node: node} do
      {:ok, _} = Registry.mark_status(node.id, :degraded)

      # Verify cache updated
      {:ok, cached_node} = Registry.cache_get(node.id)
      assert cached_node.status == :degraded
    end

    test "emits cluster.node.status_changed event", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      {:ok, _} = Registry.mark_status(node.id, :degraded)

      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.status_changed"
      assert event.payload.node_id == node.id
      assert event.payload.new_status == :degraded
    end

    test "emits cluster.node.offline when status changed to offline", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      {:ok, _} = Registry.mark_status(node.id, :offline)

      # Should receive both status_changed and offline events
      assert_receive {:event, event1}, 500
      assert_receive {:event, event2}, 500

      events = [event1, event2]
      event_names = Enum.map(events, & &1.name)

      assert "cluster.node.status_changed" in event_names
      assert "cluster.node.offline" in event_names
    end

    test "returns error for non-existent node" do
      assert {:error, _} = Registry.mark_status("nonexistent-node", :offline)
    end

    test "validates status values", %{node: node} do
      # Invalid status should fail validation
      assert {:error, _changeset} = Registry.mark_status(node.id, :invalid_status)
    end
  end

  describe "heartbeat/2" do
    setup do
      params = %{
        name: "node-heartbeat-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt,
        status: :online
      }

      {:ok, node} = Registry.ensure_node(params)
      %{node: node}
    end

    test "records heartbeat with metrics", %{node: node} do
      metrics = %{
        cpu_load: 0.455,
        mem_used_mb: 602,
        latency_ms: 12,
        meta: %{queue_depth: 100}
      }

      {:ok, heartbeat} = Registry.heartbeat(node.id, metrics)

      assert heartbeat.node_id == node.id
      assert heartbeat.cpu_load == 0.455
      assert heartbeat.mem_used_mb == 602
      assert heartbeat.latency_ms == 12
      assert heartbeat.meta["queue_depth"] == 100
    end

    test "updates node last_heartbeat_at", %{node: node} do
      metrics = %{cpu_load: 0.3}

      {:ok, _heartbeat} = Registry.heartbeat(node.id, metrics)

      # Fetch updated node
      updated_node = Ash.get!(Node, node.id)
      assert updated_node.last_heartbeat_at != nil
    end

    test "emits cluster.node.heartbeat event", %{node: node} do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:cluster")

      metrics = %{cpu_load: 0.25, mem_used_mb: 512}

      {:ok, _heartbeat} = Registry.heartbeat(node.id, metrics)

      assert_receive {:event, event}, 500

      assert event.name == "cluster.node.heartbeat"
      assert event.payload.node_id == node.id
      assert event.payload.metrics.cpu_load == 0.25
    end

    test "returns error for non-existent node" do
      metrics = %{cpu_load: 0.5}

      assert {:error, _} = Registry.heartbeat("nonexistent-node", metrics)
    end

    test "allows heartbeat with minimal metrics", %{node: node} do
      metrics = %{cpu_load: 0.1}

      {:ok, heartbeat} = Registry.heartbeat(node.id, metrics)

      assert heartbeat.cpu_load == 0.1
      assert heartbeat.mem_used_mb == nil
      assert heartbeat.latency_ms == nil
    end
  end

  describe "list_nodes/0" do
    setup do
      # Create multiple nodes with different attributes
      nodes = [
        %{
          name: "node-list-1@localhost",
          cluster_type: :in_cluster,
          role: :worker,
          domain: :thunderbolt,
          status: :online
        },
        %{
          name: "node-list-2",
          cluster_type: :out_of_cluster,
          role: :gateway,
          domain: :thundergate,
          status: :online
        },
        %{
          name: "node-list-3@localhost",
          cluster_type: :in_cluster,
          role: :controller,
          domain: :thunderflow,
          status: :offline
        },
        %{
          name: "node-list-4@localhost",
          cluster_type: :in_cluster,
          role: :worker,
          domain: :thunderbolt,
          status: :degraded
        }
      ]

      created_nodes =
        Enum.map(nodes, fn params ->
          {:ok, node} = Registry.ensure_node(params)
          node
        end)

      %{nodes: created_nodes}
    end

    test "returns all nodes when no filters provided", %{nodes: nodes} do
      result = Registry.list_nodes()

      assert length(result) >= length(nodes)
      node_names = Enum.map(result, & &1.name)

      Enum.each(nodes, fn node ->
        assert node.name in node_names
      end)
    end

    test "filters by status" do
      result = Registry.list_nodes(status: :online)

      assert length(result) >= 2

      if result != [] do
        Enum.each(result, fn node ->
          assert node.status == :online
        end)
      end
    end

    test "filters by role" do
      result = Registry.list_nodes(role: :worker)

      assert length(result) >= 2

      if result != [] do
        Enum.each(result, fn node ->
          assert node.role == :worker
        end)
      end
    end

    test "filters by domain" do
      result = Registry.list_nodes(domain: :thunderbolt)

      assert length(result) >= 2

      if result != [] do
        Enum.each(result, fn node ->
          assert node.domain == :thunderbolt
        end)
      end
    end

    test "filters by cluster_type" do
      result = Registry.list_nodes(cluster_type: :out_of_cluster)

      assert length(result) >= 1

      Enum.each(result, fn node ->
        assert node.cluster_type == :out_of_cluster
      end)
    end

    test "combines multiple filters" do
      result = Registry.list_nodes(domain: :thunderbolt, status: :online)

      assert length(result) >= 1

      if result != [] do
        Enum.each(result, fn node ->
          assert node.domain == :thunderbolt
          assert node.status == :online
        end)
      end
    end

    test "returns empty list when no matches" do
      result = Registry.list_nodes(domain: :nonexistent_domain)

      assert result == []
    end
  end

  describe "graph/0" do
    setup do
      # Create nodes
      {:ok, node1} =
        Registry.ensure_node(%{
          name: "graph-node-1@localhost",
          cluster_type: :in_cluster,
          role: :worker,
          domain: :thunderbolt
        })

      {:ok, node2} =
        Registry.ensure_node(%{
          name: "graph-node-2",
          cluster_type: :out_of_cluster,
          role: :gateway,
          domain: :thundergate
        })

      {:ok, node3} =
        Registry.ensure_node(%{
          name: "graph-node-3@localhost",
          cluster_type: :in_cluster,
          role: :controller,
          domain: :thunderflow
        })

      # Mark node1 online with link to node2
      {:ok, _} =
        Registry.mark_online(node1.id, %{
          local_peer_id: "local-1",
          remote_peer_id: node2.id,
          connection_type: :direct
        })

      # Mark node2 online with link to node3
      {:ok, _} =
        Registry.mark_online(node2.id, %{
          local_peer_id: "local-2",
          remote_peer_id: node3.id,
          connection_type: :websocket
        })

      %{node1: node1, node2: node2, node3: node3}
    end

    test "returns graph with nodes and edges", %{node1: n1, node2: n2, node3: n3} do
      graph = Registry.graph()

      assert is_map(graph)
      assert Map.has_key?(graph, :nodes)
      assert Map.has_key?(graph, :links)

      # Check nodes
      assert length(graph.nodes) >= 3
      node_ids = Enum.map(graph.nodes, & &1.id)
      assert n1.id in node_ids
      assert n2.id in node_ids
      assert n3.id in node_ids

      # Check links
      assert is_list(graph.links)
    end

    test "includes all node attributes in graph nodes", %{node1: n1} do
      graph = Registry.graph()

      graph_node = Enum.find(graph.nodes, fn node -> node.id == n1.id end)

      assert graph_node.cluster_type == :in_cluster
      assert graph_node.role == :worker
      assert graph_node.domain == :thunderbolt
    end

    test "includes link session attributes in links" do
      graph = Registry.graph()

      # Find a link
      if length(graph.links) > 0 do
        link = List.first(graph.links)

        assert Map.has_key?(link, :node_id)
        assert Map.has_key?(link, :peer_node_id)
        assert Map.has_key?(link, :connection_type)
        assert Map.has_key?(link, :established_at)
      end
    end

    test "handles nodes with no connections" do
      # Create isolated node
      {:ok, isolated_node} =
        Registry.ensure_node(%{
          name: "isolated-node@localhost",
          cluster_type: :in_cluster,
          role: :worker,
          domain: :thunderbolt
        })

      graph = Registry.graph()

      # Should still include isolated node
      node_ids = Enum.map(graph.nodes, & &1.id)
      assert isolated_node.id in node_ids
    end

    test "graph structure suitable for visualization" do
      graph = Registry.graph()

      # Each node should have required fields for UI
      if graph.nodes != [] do
        Enum.each(graph.nodes, fn node ->
          assert node.id != nil
          assert node.cluster_type != nil
          assert node.role != nil
          assert node.domain != nil
          assert node.status != nil
        end)
      end

      # Each edge should have source/target
      if graph.links != [] do
        Enum.each(graph.links, fn edge ->
          assert edge.node_id != nil
          assert edge.peer_node_id != nil
        end)
      end
    end
  end

  describe "ETS cache behavior" do
    test "cache persists across function calls" do
      params = %{
        name: "cache-test-1@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Check cache exists
      {:ok, cached1} = Registry.cache_get(node.id)
      assert cached1.id == node.id
      assert cached1.status == :unknown

      # Update node status
      {:ok, _} = Registry.mark_status(node.id, :degraded)

      # Cache should reflect update (invalidation + repopulation)
      {:ok, cached2} = Registry.cache_get(node.id)
      assert cached2.status == :degraded
    end

    test "cache invalidation on updates" do
      params = %{
        name: "cache-invalidation-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Verify initial cache
      {:ok, cached1} = Registry.cache_get(node.id)
      assert cached1.name == "cache-invalidation-test@localhost"

      # Update via mark_status should invalidate cache
      {:ok, _} = Registry.mark_status(node.id, :online)

      # Cache should reflect new status
      {:ok, cached2} = Registry.cache_get(node.id)
      assert cached2.status == :online
    end

    test "cache TTL mechanism" do
      params = %{
        name: "cache-ttl-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Verify cache entry exists with TTL
      {:ok, cached} = Registry.cache_get(node.id)
      assert cached.id == node.id

      # Verify cache entry exists in ETS
      assert :ets.member(Registry.cache_table(), node.id)
    end
  end

  describe "concurrent operations" do
    test "handles concurrent ensure_node calls" do
      params = %{
        name: "concurrent-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      # Spawn multiple concurrent ensure_node calls
      tasks =
        Enum.map(1..10, fn _ ->
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
        name: "heartbeat-concurrent-test@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt
      }

      {:ok, node} = Registry.ensure_node(params)

      # Spawn concurrent heartbeats
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            Registry.heartbeat(node.id, %{cpu_load: i * 0.1})
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _heartbeat} -> true
               _ -> false
             end)

      # Verify all heartbeats recorded
      {:ok, heartbeats} = Ash.read(Heartbeat)
      assert length(heartbeats) >= 5
    end
  end
end
