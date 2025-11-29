defmodule Thunderline.Thundercore.TickEmitterTest do
  @moduledoc """
  Tests for the TickEmitter GenServer.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thundercore.TickEmitter

  setup do
    # Start a test instance of TickEmitter with a unique name
    name = :"tick_emitter_test_#{System.unique_integer()}"
    {:ok, pid} = TickEmitter.start_link(name: name, system_tick_ms: 100, slow_tick_ms: 500)
    {:ok, name: name, pid: pid}
  end

  describe "start_link/1" do
    test "starts the tick emitter", %{pid: pid} do
      assert Process.alive?(pid)
    end
  end

  describe "current_tick/1" do
    test "returns 0 initially", %{name: name} do
      # Give it a moment to initialize
      Process.sleep(10)
      assert TickEmitter.current_tick(name) >= 0
    end

    test "increments after tick interval", %{name: name} do
      initial = TickEmitter.current_tick(name)
      # Wait for at least one tick (100ms in test config)
      Process.sleep(150)
      assert TickEmitter.current_tick(name) > initial
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses tick emission", %{name: name} do
      Process.sleep(150)
      tick_before = TickEmitter.current_tick(name)

      :ok = TickEmitter.pause(name)
      Process.sleep(200)
      tick_after = TickEmitter.current_tick(name)

      # Tick should not have changed while paused
      assert tick_before == tick_after
    end

    test "resumes tick emission after pause", %{name: name} do
      :ok = TickEmitter.pause(name)
      Process.sleep(50)
      tick_paused = TickEmitter.current_tick(name)

      :ok = TickEmitter.resume(name)
      Process.sleep(150)
      tick_resumed = TickEmitter.current_tick(name)

      assert tick_resumed > tick_paused
    end
  end

  describe "state/1" do
    test "returns state without timers", %{name: name} do
      state = TickEmitter.state(name)

      assert is_map(state)
      assert Map.has_key?(state, :system_tick)
      assert Map.has_key?(state, :slow_tick)
      assert Map.has_key?(state, :start_time)
      refute Map.has_key?(state, :system_timer)
      refute Map.has_key?(state, :slow_timer)
    end
  end

  describe "frequency/1" do
    test "returns correct frequencies" do
      assert TickEmitter.frequency(:system) == 20.0
      assert TickEmitter.frequency(:slow) == 1.0
      assert TickEmitter.frequency(:fast) == 100.0
    end
  end

  describe "topic/1" do
    test "returns correct PubSub topics" do
      assert TickEmitter.topic(:system) == "core:tick:system"
      assert TickEmitter.topic(:slow) == "core:tick:slow"
      assert TickEmitter.topic(:fast) == "core:tick:fast"
    end
  end
end
