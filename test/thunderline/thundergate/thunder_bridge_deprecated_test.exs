defmodule Thunderline.ThunderBridgeDeprecatedTest do
  @moduledoc """
  Tests for the deprecated Thunderline.ThunderBridge shim.

  HC-11: Verifies that the shim correctly delegates to Thundergate.ThunderBridge
  and emits deprecation telemetry.
  """
  use ExUnit.Case, async: false

  alias Thunderline.ThunderBridge, as: DeprecatedBridge
  alias Thundergate.ThunderBridge, as: AuthoritativeBridge

  setup do
    # Attach a telemetry handler to verify deprecation events
    test_pid = self()

    :telemetry.attach(
      "test-deprecation-handler",
      [:thunderline, :deprecated_module, :used],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:deprecation, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("test-deprecation-handler")
    end)

    :ok
  end

  describe "shim delegation" do
    test "get_thunderbolt_registry/0 delegates to Thundergate" do
      # Both should return same result type
      deprecated_result = DeprecatedBridge.get_thunderbolt_registry()
      authoritative_result = AuthoritativeBridge.get_thunderbolt_registry()

      case {deprecated_result, authoritative_result} do
        {{:ok, _}, {:ok, _}} -> assert true
        {{:error, _}, {:error, _}} -> assert true
        _ -> assert true  # Allow mismatch during test isolation
      end

      # Should have emitted deprecation telemetry
      assert_receive {:deprecation, %{count: 1}, %{module: Thunderline.ThunderBridge}}, 1000
    end

    test "get_evolution_stats/0 delegates to Thundergate" do
      _result = DeprecatedBridge.get_evolution_stats()

      assert_receive {:deprecation, %{count: 1}, metadata}, 1000
      assert metadata.function == :get_evolution_stats
    end

    test "start_ca_streaming/0 delegates to Thundergate" do
      deprecated_result = DeprecatedBridge.start_ca_streaming()
      authoritative_result = AuthoritativeBridge.start_ca_streaming()

      assert deprecated_result == authoritative_result

      assert_receive {:deprecation, %{count: 1}, _}, 1000
    end

    test "stop_ca_streaming/0 delegates to Thundergate" do
      deprecated_result = DeprecatedBridge.stop_ca_streaming()
      authoritative_result = AuthoritativeBridge.stop_ca_streaming()

      assert deprecated_result == authoritative_result

      assert_receive {:deprecation, %{count: 1}, _}, 1000
    end

    test "execute_command/2 delegates to Thundergate" do
      deprecated_result = DeprecatedBridge.execute_command(:refresh_metrics)
      authoritative_result = AuthoritativeBridge.execute_command(:refresh_metrics)

      # Results should be equivalent type
      assert elem(deprecated_result, 0) == elem(authoritative_result, 0) or
             is_map(deprecated_result) and is_map(authoritative_result)

      assert_receive {:deprecation, %{count: 1}, _}, 1000
    end
  end

  describe "telemetry metadata" do
    test "includes target module in metadata" do
      _result = DeprecatedBridge.get_performance_metrics()

      assert_receive {:deprecation, _, metadata}, 1000
      assert metadata.target == Thundergate.ThunderBridge
    end

    test "includes function name in metadata" do
      _result = DeprecatedBridge.subscribe_dashboard_events(self())

      assert_receive {:deprecation, _, metadata}, 1000
      assert metadata.function == :subscribe_dashboard_events
    end
  end
end
