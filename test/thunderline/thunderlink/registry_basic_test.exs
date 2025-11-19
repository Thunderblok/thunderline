defmodule Thunderline.Thunderlink.RegistryBasicTest do
  @moduledoc """
  Basic tests for Thunderline.Thunderlink.Registry
  Tests core node registration and status management functionality.
  """
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderlink.Registry

  describe "ensure_node/1" do
    test "registers a new node with minimal params" do
      params = %{
        name: "worker-1@localhost"
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.name == "worker-1@localhost"
      # default
      assert node.role == :worker
      # default
      assert node.domain == :thunderlink
      # default
      assert node.cluster_type == :in_cluster
      # set by :register action
      assert node.status == :connecting
      assert node.last_seen_at != nil
    end

    test "registers a node with all params" do
      params = %{
        name: "controller-1@localhost",
        role: :controller,
        domain: :thunderbolt,
        cluster_type: :in_cluster,
        meta: %{version: "1.0"}
      }

      {:ok, node} = Registry.ensure_node(params)

      assert node.name == "controller-1@localhost"
      assert node.role == :controller
      assert node.domain == :thunderbolt
      assert node.cluster_type == :in_cluster
      assert node.meta == %{version: "1.0"}
    end

    test "upserts existing node" do
      params = %{
        name: "upsert-test@localhost",
        role: :worker
      }

      {:ok, node1} = Registry.ensure_node(params)

      # Call again with same name
      {:ok, node2} = Registry.ensure_node(params)

      # Should return same node (upsert)
      assert node1.id == node2.id
      assert node2.name == "upsert-test@localhost"
    end
  end

  describe "mark_online/1" do
    test "marks a node as online" do
      {:ok, node} = Registry.ensure_node(%{name: "online-test@localhost"})

      {:ok, updated} = Registry.mark_online(node)

      assert updated.status == :online
      assert updated.last_seen_at > node.last_seen_at
    end
  end

  describe "mark_offline/1" do
    test "marks a node as offline" do
      {:ok, node} = Registry.ensure_node(%{name: "offline-test@localhost"})

      {:ok, updated} = Registry.mark_offline(node)

      assert updated.status == :offline
    end
  end

  describe "record_heartbeat/2" do
    test "records a heartbeat for a node" do
      {:ok, node} = Registry.ensure_node(%{name: "heartbeat-test@localhost"})

      metrics = %{
        cpu_load: 45.5,
        mem_used_mb: 1024,
        latency_ms: 10
      }

      {:ok, heartbeat} = Registry.record_heartbeat(node.id, :online, metrics)

      assert heartbeat.node_id == node.id
      assert heartbeat.status == :online
      assert heartbeat.cpu_load == 45.5
      assert heartbeat.mem_used_mb == 1024
    end
  end

  describe "recent_heartbeats/1" do
    test "retrieves recent heartbeats" do
      {:ok, node} = Registry.ensure_node(%{name: "recent-hb-test@localhost"})

      # Record a heartbeat
      {:ok, _hb} = Registry.record_heartbeat(node.id, :online, %{cpu_load: 50.0})

      # Get recent heartbeats (default 60 minutes)
      heartbeats = Registry.recent_heartbeats()

      assert is_list(heartbeats)
      assert length(heartbeats) >= 1
      assert Enum.any?(heartbeats, fn hb -> hb.node_id == node.id end)
    end

    test "retrieves heartbeats for specific time window" do
      {:ok, node} = Registry.ensure_node(%{name: "windowed-hb-test@localhost"})

      {:ok, _hb} = Registry.record_heartbeat(node.id, :online, %{cpu_load: 50.0})

      # Get heartbeats from last 5 minutes
      heartbeats = Registry.recent_heartbeats(5)

      assert is_list(heartbeats)
    end
  end

  describe "online_nodes/0" do
    test "lists all online nodes" do
      {:ok, node1} = Registry.ensure_node(%{name: "online-list-1@localhost"})
      {:ok, node2} = Registry.ensure_node(%{name: "online-list-2@localhost"})

      {:ok, _} = Registry.mark_online(node1)
      {:ok, _} = Registry.mark_online(node2)

      online_nodes = Registry.online_nodes()

      assert is_list(online_nodes)
      assert length(online_nodes) >= 2
      assert Enum.all?(online_nodes, fn n -> n.status == :online end)
    end
  end
end
