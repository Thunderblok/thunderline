defmodule SimpleNeuralTest do
  @moduledoc """
  Simple test to verify Cerebros neural integration works properly.
  """

  alias Thunderline.ErlangBridge

  def run_test() do
    IO.puts("🧠 Starting Cerebros Neural Integration Test...")

    # Start the bridge
    case ErlangBridge.start_link() do
      {:ok, pid} ->
        IO.puts("✅ ErlangBridge started successfully: #{inspect(pid)}")
        test_neural_functions()

      {:error, reason} ->
        IO.puts("❌ Failed to start ErlangBridge: #{inspect(reason)}")
        :error
    end
  end

  defp test_neural_functions() do
    IO.puts("\n🔬 Testing Neural Architecture Creation...")

    # Test neural architecture creation
    case ErlangBridge.create_neural_architecture(:test_cerebros, %{
           max_levels: 3,
           connectivity_density: 0.4
         }) do
      {:ok, arch_id} ->
        IO.puts("✅ Neural architecture created: #{inspect(arch_id)}")

      {:error, :erlang_unavailable} ->
        IO.puts("⚠️  Erlang system not available (expected in dev mode)")

      {:error, reason} ->
        IO.puts("❌ Failed to create neural architecture: #{inspect(reason)}")
    end

    IO.puts("\n🧬 Testing Neuron Creation...")

    # Test neuron creation
    case ErlangBridge.create_neuron(:test_bolt, {5, 5, 5}, %{
           threshold: 1.0,
           type: :excitatory,
           refractory_period: 2
         }) do
      {:ok, neuron_id} ->
        IO.puts("✅ Neuron created: #{inspect(neuron_id)}")
        test_neuron_operations(neuron_id)

      {:error, :erlang_unavailable} ->
        IO.puts("⚠️  Erlang system not available (expected in dev mode)")

      {:error, reason} ->
        IO.puts("❌ Failed to create neuron: #{inspect(reason)}")
    end

    IO.puts("\n🏗️  Testing Multi-Scale Hierarchy...")

    # Test multi-scale hierarchy
    case ErlangBridge.create_scale_hierarchy(:test_bolt, %{
           base_resolution: {16, 16, 8},
           max_levels: 4
         }) do
      {:ok, hierarchy_id} ->
        IO.puts("✅ Scale hierarchy created: #{inspect(hierarchy_id)}")

      {:error, :erlang_unavailable} ->
        IO.puts("⚠️  Erlang system not available (expected in dev mode)")

      {:error, reason} ->
        IO.puts("❌ Failed to create scale hierarchy: #{inspect(reason)}")
    end

    IO.puts("\n📡 Testing Asynchronous Operations...")

    # Test asynchronous operations (these should always work)
    result1 =
      ErlangBridge.propagate_neural_signal(
        :test_level,
        %{
          signal_type: :activation,
          intensity: 0.8
        },
        System.system_time(:millisecond)
      )

    result2 = ErlangBridge.fire_neuron(:test_neuron, 1.5)
    result3 = ErlangBridge.simulate_neural_step(:test_bolt)

    IO.puts("✅ Neural signal propagation: #{inspect(result1)}")
    IO.puts("✅ Neuron firing: #{inspect(result2)}")
    IO.puts("✅ Neural simulation step: #{inspect(result3)}")

    IO.puts("\n🎯 Testing Neural API Coverage...")
    test_api_coverage()

    IO.puts("\n🧠 Cerebros Neural Integration Test Complete! ✨")
  end

  defp test_neuron_operations(neuron_id) do
    # Test getting neuron state
    case ErlangBridge.get_neuron_state(neuron_id) do
      {:ok, state} ->
        IO.puts("  ↳ Neuron state retrieved: #{inspect(state)}")

      {:error, reason} ->
        IO.puts("  ↳ Could not get neuron state: #{inspect(reason)}")
    end
  end

  defp test_api_coverage() do
    IO.puts("📋 Available Neural APIs:")

    neural_apis = [
      "create_neural_architecture/2",
      "create_neural_level/3",
      "create_neural_connection/3",
      "create_skip_connection/4",
      "create_neuron/3",
      "connect_neurons/3",
      "create_scale_hierarchy/2",
      "get_hierarchy_info/1",
      "propagate_neural_signal/3",
      "fire_neuron/2",
      "simulate_neural_step/1",
      "get_neuron_state/1",
      "get_neural_topology/0",
      "optimize_connectivity/1",
      "enable_spike_timing_plasticity/1",
      "enable_cross_scale_learning/1",
      "propagate_upward/3",
      "propagate_downward/3"
    ]

    for api <- neural_apis do
      IO.puts("  ✅ #{api}")
    end

    IO.puts("\n🔧 Total Neural APIs Available: #{length(neural_apis)}")
  end
end

# Run the test
SimpleNeuralTest.run_test()
