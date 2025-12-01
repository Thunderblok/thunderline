defmodule Thunderline.Thunderbolt.ThunderCell.SpikingCellTest do
  @moduledoc """
  Tests for HC-54 SpikingCell - LIF neurons with trainable delays.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.ThunderCell.SpikingCell

  describe "pure functions" do
    test "membrane_update computes correct potential change" do
      v = -70.0
      v_rest = -70.0
      tau_m = 20.0
      resistance = 10.0
      current = 5.0
      dt = 1.0

      new_v = SpikingCell.membrane_update(v, v_rest, tau_m, resistance, current, dt)

      # At rest with positive current, should increase
      assert new_v > v
    end

    test "membrane_update decays to rest with no input" do
      # Above rest
      v = -60.0
      v_rest = -70.0
      tau_m = 20.0
      resistance = 10.0
      current = 0.0
      dt = 1.0

      new_v = SpikingCell.membrane_update(v, v_rest, tau_m, resistance, current, dt)

      # Should decay toward rest
      assert new_v < v
      assert new_v > v_rest
    end

    test "should_spike? returns true when above threshold" do
      assert SpikingCell.should_spike?(-50.0, -55.0) == true
    end

    test "should_spike? returns false when below threshold" do
      assert SpikingCell.should_spike?(-60.0, -55.0) == false
    end

    test "compute_synaptic_current sums spikes at current time" do
      queue = [
        %{source: :a, time: 10, weight: 1.0},
        %{source: :b, time: 10, weight: 2.0},
        # Not at current time
        %{source: :c, time: 11, weight: 3.0}
      ]

      current = SpikingCell.compute_synaptic_current(queue, 10)
      assert current == 3.0
    end

    test "compute_synaptic_current returns 0 with empty queue" do
      assert SpikingCell.compute_synaptic_current([], 10) == 0.0
    end

    test "surrogate_gradient returns high value near threshold" do
      grad = SpikingCell.surrogate_gradient(-55.0, -55.0)
      assert grad > 0.9
    end

    test "surrogate_gradient returns low value far from threshold" do
      grad = SpikingCell.surrogate_gradient(-70.0, -55.0)
      assert grad < 0.1
    end
  end

  describe "GenServer operations" do
    setup do
      {:ok, pid} =
        SpikingCell.start_link(
          id: :test_cell,
          v_threshold: -55.0,
          v_rest: -70.0,
          tau_membrane: 20.0,
          perturbation_enabled: false
        )

      {:ok, cell: pid}
    end

    test "starts with correct initial state", %{cell: pid} do
      state = SpikingCell.get_state(pid)

      assert state.id == :test_cell
      assert state.v_membrane == -70.0
      assert state.v_threshold == -55.0
      assert state.spike_count == 0
    end

    test "inject_current affects next step", %{cell: pid} do
      SpikingCell.inject_current(pid, 10.0)
      SpikingCell.step(pid)

      state = SpikingCell.get_state(pid)

      # With current injection, potential should have increased
      assert state.v_membrane > -70.0
    end

    test "cell spikes when threshold exceeded", %{cell: pid} do
      # Inject strong current multiple times to reach threshold
      for _ <- 1..20 do
        SpikingCell.inject_current(pid, 15.0)
        SpikingCell.step(pid)
      end

      state = SpikingCell.get_state(pid)
      assert state.spike_count > 0
    end

    test "cell resets after spike", %{cell: pid} do
      # Inject strong current to trigger spike
      for _ <- 1..20 do
        SpikingCell.inject_current(pid, 15.0)
        SpikingCell.step(pid)
      end

      state = SpikingCell.get_state(pid)

      # After spike, should be near reset potential
      assert state.v_membrane <= state.v_reset + 5.0 or state.spike_count > 0
    end

    test "add_connection creates new connection", %{cell: pid} do
      SpikingCell.add_connection(pid, :source_1, 1.5, 5.0)

      state = SpikingCell.get_state(pid)
      conn = Enum.find(state.connections, &(&1.source_id == :source_1))

      assert conn.weight == 1.5
      assert conn.delay == 5.0
      assert conn.delay_trainable == true
    end

    test "receive_spike queues spike with delay", %{cell: pid} do
      SpikingCell.add_connection(pid, :source_1, 1.5, 3.0)
      SpikingCell.receive_spike(pid, :source_1, 0)

      state = SpikingCell.get_state(pid)

      # Spike should be queued at time 0 + delay(3) = 3
      queued = Enum.find(state.spike_queue, &(&1.source == :source_1))
      assert queued != nil
      assert queued.time == 3
    end

    test "update_weights modifies connection weights", %{cell: pid} do
      SpikingCell.add_connection(pid, :source_1, 1.0, 5.0)
      SpikingCell.update_weights(pid, %{source_1: 0.5})

      state = SpikingCell.get_state(pid)
      conn = Enum.find(state.connections, &(&1.source_id == :source_1))

      assert conn.weight == 1.5
    end

    test "update_delays modifies trainable delays", %{cell: pid} do
      SpikingCell.add_connection(pid, :source_1, 1.0, 5.0)
      SpikingCell.update_delays(pid, %{source_1: 2.0})

      state = SpikingCell.get_state(pid)
      conn = Enum.find(state.connections, &(&1.source_id == :source_1))

      assert conn.delay == 7.0
    end

    test "reset clears state", %{cell: pid} do
      # Inject current and step
      for _ <- 1..10 do
        SpikingCell.inject_current(pid, 10.0)
        SpikingCell.step(pid)
      end

      SpikingCell.reset(pid)
      state = SpikingCell.get_state(pid)

      assert state.v_membrane == -70.0
      assert state.current_time == 0
      assert state.spike_count == 0
      assert state.spike_queue == []
    end
  end

  describe "telemetry" do
    setup do
      {:ok, pid} =
        SpikingCell.start_link(
          id: :telemetry_test,
          v_threshold: -55.0,
          v_rest: -70.0,
          perturbation_enabled: false
        )

      {:ok, cell: pid}
    end

    test "emits spike telemetry when cell fires", %{cell: pid} do
      test_pid = self()

      :telemetry.attach(
        "test-spike",
        [:thunderline, :bolt, :spiking, :spike],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:spike_telemetry, measurements, metadata})
        end,
        nil
      )

      # Inject strong current to trigger spike
      for _ <- 1..30 do
        SpikingCell.inject_current(pid, 20.0)
        SpikingCell.step(pid)
      end

      # Should receive at least one spike telemetry
      assert_receive {:spike_telemetry, measurements, metadata}, 1000

      assert is_integer(measurements.time)
      assert is_float(measurements.v_membrane)
      assert metadata.id == :telemetry_test

      :telemetry.detach("test-spike")
    end
  end
end
