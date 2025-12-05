defmodule Thunderline.Thundercore.ClockTest do
  @moduledoc """
  Tests for the 4-Phase Thunderclock (HC-88).

  Note: Clock is started by the application supervisor as a named GenServer,
  so tests use the already-running instance rather than starting new ones.
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thundercore.Clock

  describe "current_phase/0" do
    test "returns {phase, tick} tuple" do
      result = Clock.current_phase()
      assert {phase, tick} = result
      assert phase in [:switch, :hold, :release, :relax]
      assert is_integer(tick)
      assert tick >= 0
    end
  end

  describe "phase/0" do
    test "returns current phase atom" do
      phase = Clock.phase()
      assert phase in [:switch, :hold, :release, :relax]
    end
  end

  describe "tick/0" do
    test "returns current tick number" do
      tick = Clock.tick()
      assert is_integer(tick)
      assert tick >= 0
    end
  end

  describe "phases/0" do
    test "returns the correct 4-phase sequence" do
      sequence = Clock.phases()
      assert sequence == [:switch, :hold, :release, :relax]
    end
  end

  describe "next_phase/1" do
    test "switch -> hold" do
      assert Clock.next_phase(:switch) == :hold
    end

    test "hold -> release" do
      assert Clock.next_phase(:hold) == :release
    end

    test "release -> relax" do
      assert Clock.next_phase(:release) == :relax
    end

    test "relax -> switch (cycles back)" do
      assert Clock.next_phase(:relax) == :switch
    end
  end

  describe "phase_for_domain/1" do
    test "returns :switch for input domains" do
      assert Clock.phase_for_domain(:thundercore) == :switch
      assert Clock.phase_for_domain(:thundergate) == :switch
      assert Clock.phase_for_domain(:thunderflow) == :switch
    end

    test "returns :hold for compute domains" do
      assert Clock.phase_for_domain(:thunderbolt) == :hold
      assert Clock.phase_for_domain(:thundercrown) == :hold
      assert Clock.phase_for_domain(:thundervine) == :hold
    end

    test "returns :release for output domains" do
      assert Clock.phase_for_domain(:thunderlink) == :release
      assert Clock.phase_for_domain(:thundergrid) == :release
      assert Clock.phase_for_domain(:thunderprism) == :release
    end

    test "returns :relax for cleanup domains" do
      assert Clock.phase_for_domain(:thunderwall) == :relax
      assert Clock.phase_for_domain(:thunderpac) == :relax
      assert Clock.phase_for_domain(:thunderblock) == :relax
    end

    test "returns :hold for unknown domains (default)" do
      assert Clock.phase_for_domain(:unknown_domain) == :hold
    end
  end

  describe "subscribe_domain/1" do
    test "returns :ok for valid domain" do
      assert :ok = Clock.subscribe_domain(:thunderbolt)
    end

    test "accepts custom callback" do
      test_pid = self()
      callback = fn tick -> send(test_pid, {:phase_tick, tick}) end
      assert :ok = Clock.subscribe_domain(:thunderbolt, callback)
    end
  end

  describe "on_phase/2" do
    test "returns :ok for valid phase" do
      assert :ok = Clock.on_phase(:hold, fn _tick -> :ok end)
    end

    test "accepts callback for each phase" do
      for phase <- [:switch, :hold, :release, :relax] do
        assert :ok = Clock.on_phase(phase, fn _tick -> :ok end)
      end
    end
  end

  describe "pause/0 and resume/0" do
    test "pause stops phase transitions" do
      # Get initial tick
      initial_tick = Clock.tick()

      # Pause the clock
      assert :ok = Clock.pause()

      # Wait a bit
      Process.sleep(100)

      # Tick should not have advanced (or minimally)
      paused_tick = Clock.tick()

      # Resume the clock
      assert :ok = Clock.resume()

      # The tick difference while paused should be minimal
      # (allowing for 1 tick that might have been in flight)
      assert paused_tick - initial_tick <= 1
    end
  end

  describe "advance/0" do
    test "manually advances to next phase" do
      # Get current phase
      initial_phase = Clock.phase()

      # Advance
      assert :ok = Clock.advance()

      # Give it a moment to process
      Process.sleep(10)

      # Phase should have changed
      new_phase = Clock.phase()
      assert new_phase == Clock.next_phase(initial_phase)
    end
  end
end
