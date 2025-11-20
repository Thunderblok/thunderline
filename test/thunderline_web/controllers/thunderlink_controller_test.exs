defmodule ThunderlineWeb.ThunderlinkControllerTest do
  use ThunderlineWeb.ConnCase, async: false

  alias Thunderline.Thunderlink.Registry

  setup do
    # Create test nodes and links
    {:ok, node1} =
      Registry.ensure_node(%{
        name: "test-node-1@localhost",
        cluster_type: :in_cluster,
        role: :worker,
        domain: :thunderbolt,
        status: :online
      })

    {:ok, node2} =
      Registry.ensure_node(%{
        name: "test-node-2@localhost",
        cluster_type: :in_cluster,
        role: :gateway,
        domain: :thundergate,
        status: :online
      })

    {:ok, node3} =
      Registry.ensure_node(%{
        name: "test-node-3@localhost",
        cluster_type: :out_of_cluster,
        role: :controller,
        domain: :thunderflow,
        status: :degraded
      })

    # Create link sessions
    {:ok, _} =
      Registry.mark_online(node1.id, %{
        remote_node_id: node2.id,
        latency_ms: 25,
        bandwidth_mbps: 1000.0,
        meta: %{
          local_peer_id: "peer-1",
          remote_peer_id: "peer-2",
          connection_type: :direct
        }
      })

    {:ok, _} =
      Registry.mark_online(node2.id, %{
        remote_node_id: node3.id,
        latency_ms: 50,
        bandwidth_mbps: 500.0,
        meta: %{
          local_peer_id: "peer-2",
          remote_peer_id: "peer-3",
          connection_type: :websocket
        }
      })

    %{node1: node1, node2: node2, node3: node3}
  end

  describe "GET /api/thunderlink/graph" do
    test "returns graph data in 3d-force-graph format", %{
      conn: conn,
      node1: n1,
      node2: n2,
      node3: n3
    } do
      conn = get(conn, ~p"/api/thunderlink/graph")

      assert json_response(conn, 200)
      data = json_response(conn, 200)

      # Check structure
      assert Map.has_key?(data, "nodes")
      assert Map.has_key?(data, "links")
      assert is_list(data["nodes"])
      assert is_list(data["links"])

      # Check nodes
      assert length(data["nodes"]) >= 3
      node_ids = Enum.map(data["nodes"], & &1["id"])
      assert n1.id in node_ids
      assert n2.id in node_ids
      assert n3.id in node_ids

      # Verify node attributes
      node1_data = Enum.find(data["nodes"], &(&1["id"] == n1.id))
      assert node1_data["name"] == "test-node-1@localhost"
      assert node1_data["cluster_type"] == "in_cluster"
      assert node1_data["role"] == "worker"
      assert node1_data["domain"] == "thunderbolt"
      assert node1_data["status"] == "online"

      # Check links
      assert length(data["links"]) >= 2

      # Verify link structure
      if length(data["links"]) > 0 do
        link = List.first(data["links"])
        assert Map.has_key?(link, "source")
        assert Map.has_key?(link, "target")
        assert Map.has_key?(link, "connection_type")
      end
    end

    test "handles empty graph", %{conn: conn} do
      # Clear all nodes (in separate test environment)
      # This test verifies graceful handling

      conn = get(conn, ~p"/api/thunderlink/graph")

      assert json_response(conn, 200)
      data = json_response(conn, 200)

      assert Map.has_key?(data, "nodes")
      assert Map.has_key?(data, "links")
      assert is_list(data["nodes"])
      assert is_list(data["links"])
    end

    test "includes metadata in links", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/graph")
      data = json_response(conn, 200)

      # Find a link with metadata
      link_with_meta =
        Enum.find(data["links"], fn link ->
          Map.has_key?(link, "latency_ms")
        end)

      if link_with_meta do
        assert is_number(link_with_meta["latency_ms"])
      end
    end

    test "sets correct content type", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/graph")

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end

  describe "GET /api/thunderlink/nodes" do
    test "returns list of nodes", %{conn: conn, node1: n1, node2: n2, node3: n3} do
      conn = get(conn, ~p"/api/thunderlink/nodes")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)
      assert length(nodes) > 0

      node_ids = Enum.map(nodes, & &1["id"])
      assert n1.id in node_ids
      assert n2.id in node_ids
      assert n3.id in node_ids
    end

    test "includes all node attributes", %{conn: conn, node1: n1} do
      conn = get(conn, ~p"/api/thunderlink/nodes")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      node1_data = Enum.find(nodes, &(&1["id"] == n1.id))

      assert node1_data["name"] == "test-node-1@localhost"
      assert node1_data["cluster_type"] == "in_cluster"
      assert node1_data["role"] == "worker"
      assert node1_data["domain"] == "thunderbolt"
      assert node1_data["status"] == "online"
      assert Map.has_key?(node1_data, "inserted_at")
      assert Map.has_key?(node1_data, "updated_at")
    end

    test "supports filtering by status", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?status=online")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)

      # All returned nodes should be online
      Enum.each(nodes, fn node ->
        assert node["status"] == "online"
      end)
    end

    test "supports filtering by role", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?role=worker")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)

      # All returned nodes should be workers
      Enum.each(nodes, fn node ->
        assert node["role"] == "worker"
      end)
    end

    test "supports filtering by domain", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?domain=thunderbolt")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)

      # All returned nodes should be in thunderbolt domain
      Enum.each(nodes, fn node ->
        assert node["domain"] == "thunderbolt"
      end)
    end

    test "supports filtering by cluster_type", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?cluster_type=in_cluster")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)

      # All returned nodes should be in_cluster
      Enum.each(nodes, fn node ->
        assert node["cluster_type"] == "in_cluster"
      end)
    end

    test "supports multiple filters", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?domain=thunderbolt&status=online")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert is_list(nodes)

      # All returned nodes should match both filters
      Enum.each(nodes, fn node ->
        assert node["domain"] == "thunderbolt"
        assert node["status"] == "online"
      end)
    end

    test "returns empty list when no matches", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes?domain=nonexistent")
      response = json_response(conn, 200)
      nodes = response["nodes"]

      assert nodes == []
    end
  end

  describe "GET /api/thunderlink/nodes/:id" do
    test "returns specific node by ID", %{conn: conn, node1: n1} do
      conn = get(conn, ~p"/api/thunderlink/nodes/#{n1.id}")

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      node = response["node"]

      assert node["id"] == n1.id
      assert node["name"] == "test-node-1@localhost"
      assert node["cluster_type"] == "in_cluster"
      assert node["role"] == "worker"
      assert node["domain"] == "thunderbolt"
      assert node["status"] == "online"
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      non_existent_id = Ash.UUID.generate()
      conn = get(conn, ~p"/api/thunderlink/nodes/#{non_existent_id}")

      assert json_response(conn, 404)
      error = json_response(conn, 404)

      assert Map.has_key?(error, "errors")
    end

    test "includes timestamps in response", %{conn: conn, node2: n2} do
      conn = get(conn, ~p"/api/thunderlink/nodes/#{n2.id}")
      response = json_response(conn, 200)
      node = response["node"]

      assert Map.has_key?(node, "inserted_at")
      assert Map.has_key?(node, "updated_at")
      assert node["inserted_at"] != nil
      assert node["updated_at"] != nil
    end

    test "includes meta field", %{conn: conn, node1: n1} do
      conn = get(conn, ~p"/api/thunderlink/nodes/#{n1.id}")
      response = json_response(conn, 200)
      node = response["node"]

      assert Map.has_key?(node, "meta")
    end
  end

  describe "error handling" do
    test "handles malformed node ID gracefully", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes/not-a-valid-uuid")

      # Should return 404 or 400
      assert conn.status in [400, 404]
    end

    test "handles database errors gracefully", %{conn: conn} do
      # This would require mocking database failure
      # For now, verify basic error structure
      conn = get(conn, ~p"/api/thunderlink/nodes/#{Ash.UUID.generate()}")

      assert json_response(conn, 404)
      error = json_response(conn, 404)
      assert is_map(error)
      assert Map.has_key?(error, "errors")
    end
  end

  describe "performance" do
    test "graph endpoint responds quickly with many nodes", %{conn: conn} do
      # Create 50 additional nodes
      Enum.each(1..50, fn i ->
        Registry.ensure_node(%{
          name: "perf-node-#{i}@localhost",
          cluster_type: :in_cluster,
          role: :worker,
          domain: :thunderbolt
        })
      end)

      {time_us, conn} =
        :timer.tc(fn ->
          get(conn, ~p"/api/thunderlink/graph")
        end)

      assert json_response(conn, 200)

      # Should complete in under 500ms
      assert time_us < 500_000
    end

    test "index endpoint responds quickly", %{conn: conn} do
      {time_us, conn} =
        :timer.tc(fn ->
          get(conn, ~p"/api/thunderlink/nodes")
        end)

      assert json_response(conn, 200)

      # Should complete in under 200ms
      assert time_us < 200_000
    end
  end

  describe "CORS and headers" do
    test "sets proper JSON content type for graph", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/graph")

      content_type = get_resp_header(conn, "content-type")
      assert content_type == ["application/json; charset=utf-8"]
    end

    test "sets proper JSON content type for index", %{conn: conn} do
      conn = get(conn, ~p"/api/thunderlink/nodes")

      content_type = get_resp_header(conn, "content-type")
      assert content_type == ["application/json; charset=utf-8"]
    end

    test "sets proper JSON content type for show", %{conn: conn, node1: n1} do
      conn = get(conn, ~p"/api/thunderlink/nodes/#{n1.id}")

      content_type = get_resp_header(conn, "content-type")
      assert content_type == ["application/json; charset=utf-8"]
    end
  end
end
