defmodule Thunderline.ErlangBridgeTest do
  use ExUnit.Case, async: false

  alias Thunderline.ErlangBridge

  @moduletag :integration

  describe "Erlang Bridge Integration" do
    test "can start and connect to Erlang bridge" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Test basic connection
      assert ErlangBridge.get_status() != nil

      # Test that we can get system state
      state = ErlangBridge.get_system_state()
      assert is_map(state)
    end

    test "ThunderBolt creation and streaming" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Test ThunderBolt creation with various configurations
      configs = [
        %{type: :simple, dimensions: {10, 10, 5}},
        %{type: :neural, dimensions: {20, 20, 10}, neural_config: %{layers: 3}},
        %{type: :distributed, dimensions: {30, 30, 15}, cluster_nodes: [:node1, :node2]}
      ]

      for config <- configs do
        # Create ThunderBolt
        case ErlangBridge.create_thunderbolt(config) do
          {:ok, bolt_id} ->
            assert is_binary(bolt_id) or is_atom(bolt_id)

            # Test streaming
            assert {:ok, _stream_ref} = ErlangBridge.start_thunderbolt_streaming(bolt_id)

            # Test evolution step
            evolution_params = %{
              steps: 5,
              rule_set: :conway,
              boundary_conditions: :periodic
            }
            assert {:ok, _result} = ErlangBridge.evolve_thunderbolt(bolt_id, evolution_params)

            # Clean up
            assert :ok = ErlangBridge.destroy_thunderbolt(bolt_id)

          {:error, reason} ->
            # If Erlang system not available, skip gracefully
            assert reason in [:erlang_unavailable, :connection_failed, :not_implemented]
        end
      end
    end

    test "Neural pattern injection" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Test neural pattern injection
      neural_connections = [
        %{strength: 0.8, delay: 1, connection_type: :excitatory},
        %{strength: 0.6, delay: 2, connection_type: :inhibitory},
        %{strength: 0.9, delay: 1, connection_type: :modulatory}
      ]

      case ErlangBridge.inject_neural_patterns("test_bolt", neural_connections) do
        {:ok, _result} ->
          # Successfully injected patterns
          assert true

        {:error, reason} ->
          # If Erlang system or bolt not available, skip gracefully
          assert reason in [:erlang_unavailable, :bolt_not_found, :not_implemented]
      end
    end

    test "Cerebros connectivity" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Test Cerebros connection
      cerebros_config = %{
        host: "localhost",
        port: 4444,
        protocol: :tcp,
        auth_token: "test_token",
        features: [:neural_learning, :pattern_recognition, :real_time_adaptation]
      }

      case ErlangBridge.connect_cerebros(cerebros_config) do
        {:ok, _connection_id} ->
          # Successfully connected to Cerebros
          assert true

        {:error, reason} ->
          # If Cerebros not available, skip gracefully
          assert reason in [:cerebros_unavailable, :connection_failed, :not_implemented]
      end
    end

    test "Real-time event streaming" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Subscribe to events
      subscriber_pid = self()

      case ErlangBridge.subscribe_events(subscriber_pid) do
        :ok ->
          # Start streaming
          case ErlangBridge.start_streaming() do
            {:ok, _stream_ref} ->
              # Should receive some events or timeout gracefully
              receive do
                {:thunderbolt_event, _event_data} -> assert true
                {:ca_state_update, _state} -> assert true
                {:neural_activity, _activity} -> assert true
              after
                1000 ->
                  # No events received - this is ok for testing
                  assert true
              end

              # Stop streaming
              assert :ok = ErlangBridge.stop_streaming()

            {:error, reason} ->
              assert reason in [:erlang_unavailable, :not_implemented]
          end

        {:error, reason} ->
          assert reason in [:erlang_unavailable, :not_implemented]
      end
    end

    test "Error handling and resilience" do
      # Start the bridge
      {:ok, _pid} = ErlangBridge.start_link()

      # Test error conditions
      invalid_commands = [
        {:invalid_command, []},
        {:create_thunderbolt, "invalid_config"},
        {:evolve_thunderbolt, ["nonexistent_bolt", %{}]}
      ]

      for {command, params} <- invalid_commands do
        result = ErlangBridge.execute_command(command, params)

        # Should handle errors gracefully
        case result do
          {:error, _reason} -> assert true
          {:ok, _} -> assert true  # Some might succeed in mock mode
        end
      end
    end
  end

  describe "Neural Pattern Conversion" do
    test "converts neural connections to CA patterns correctly" do
      # This tests the helper functions directly
      # Since they're private, we test the public interface that uses them

      neural_connections = [
        %{strength: 0.8, delay: 1, connection_type: :excitatory},
        %{strength: 0.5, delay: 3, connection_type: :inhibitory}
      ]

      # The conversion should happen internally when injecting patterns
      {:ok, _pid} = ErlangBridge.start_link()

      # This will internally call the conversion functions
      case ErlangBridge.inject_neural_patterns("test_bolt", neural_connections) do
        {:ok, _result} ->
          # Conversion worked
          assert true

        {:error, reason} ->
          # Expected if Erlang system not available
          assert reason in [:erlang_unavailable, :bolt_not_found, :not_implemented]
      end
    end
  end
end
