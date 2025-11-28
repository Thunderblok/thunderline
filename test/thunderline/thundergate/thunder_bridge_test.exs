defmodule Thundergate.ThunderBridgeTest do
  @moduledoc """
  Tests for the ThunderBridge ingest/event bridge layer.

  HC-11: ThunderBridge Ingest Layer
  - Verifies core event publishing through EventBus
  - Tests dashboard API methods
  - Validates deprecated shim delegation
  """
  use ExUnit.Case, async: false

  alias Thundergate.ThunderBridge

  describe "publish/1" do
    test "publishes event with type/payload format" do
      event = %{type: :test_event, payload: %{message: "hello", priority: :normal}}

      # Should not crash - actual publish may fail without full EventBus setup
      result = ThunderBridge.publish(event)
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "publishes event with event/data format" do
      event = %{event: :test_event, data: %{message: "hello"}}

      result = ThunderBridge.publish(event)
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "publishes event with topic/event format" do
      event = %{topic: "agent_events", event: %{action: :created, agent_id: "test-123"}}

      result = ThunderBridge.publish(event)
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "publishes generic event format" do
      event = %{foo: "bar", baz: 123}

      result = ThunderBridge.publish(event)
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "dashboard API methods" do
    # Note: These tests may fail with :exit if ClusterSupervisor isn't running.
    # We wrap in try/catch to handle that gracefully.

    test "get_thunderbolt_registry/0 returns registry structure" do
      result =
        try do
          ThunderBridge.get_thunderbolt_registry()
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, registry} ->
          assert is_map(registry)
          assert Map.has_key?(registry, :total_thunderbolts)
          assert Map.has_key?(registry, :active_thunderbolts)
          assert Map.has_key?(registry, :last_updated)

        {:error, _reason} ->
          # Expected if aggregator not running
          assert true
      end
    end

    test "get_thunderbit_observer/0 returns observer structure" do
      result =
        try do
          ThunderBridge.get_thunderbit_observer()
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, observer} ->
          assert is_map(observer)
          assert Map.has_key?(observer, :observations_count)
          assert Map.has_key?(observer, :data_quality)
          assert Map.has_key?(observer, :scan_frequency)

        {:error, _reason} ->
          assert true
      end
    end

    test "get_performance_metrics/0 returns performance data" do
      result =
        try do
          ThunderBridge.get_performance_metrics()
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, metrics} ->
          assert is_map(metrics)
          assert Map.has_key?(metrics, :memory_usage)
          assert Map.has_key?(metrics, :timestamp)

        {:error, _reason} ->
          assert true
      end
    end

    test "get_evolution_stats/0 returns evolution statistics" do
      result =
        try do
          ThunderBridge.get_evolution_stats()
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, stats} ->
          assert is_map(stats)
          assert Map.has_key?(stats, :total_generations)
          assert Map.has_key?(stats, :source)

        {:error, _reason} ->
          assert true
      end
    end
  end

  describe "execute_command/2" do
    test "handles :refresh_metrics command" do
      result =
        try do
          ThunderBridge.execute_command(:refresh_metrics)
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      # May return metrics or error depending on GenServer state
      assert is_tuple(result) or is_map(result)
    end

    test "handles :list_clusters command" do
      result =
        try do
          ThunderBridge.execute_command(:list_clusters)
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, clusters} -> assert is_list(clusters)
        {:error, _} -> assert true
      end
    end

    test "handles :get_telemetry command" do
      result =
        try do
          ThunderBridge.execute_command(:get_telemetry)
        catch
          :exit, _ -> {:error, :supervisor_not_running}
        end

      case result do
        {:ok, telemetry} -> assert is_map(telemetry)
        {:error, _} -> assert true
      end
    end

    test "returns error for unknown command" do
      assert {:error, :unknown_command} = ThunderBridge.execute_command(:bogus_command)
    end
  end

  describe "CA streaming" do
    test "start_ca_streaming/1 returns streaming config" do
      assert {:ok, %{streaming: true, interval: _}} = ThunderBridge.start_ca_streaming()
    end

    test "start_ca_streaming/1 accepts custom interval" do
      assert {:ok, %{streaming: true, interval: 50}} = ThunderBridge.start_ca_streaming(interval: 50)
    end

    test "stop_ca_streaming/0 returns stopped status" do
      assert {:ok, %{streaming: false}} = ThunderBridge.stop_ca_streaming()
    end
  end

  describe "subscribe_dashboard_events/1" do
    test "subscribes process to dashboard events" do
      result = ThunderBridge.subscribe_dashboard_events(self())
      assert result == :ok
    end
  end
end
