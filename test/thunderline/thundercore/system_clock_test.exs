defmodule Thunderline.Thundercore.SystemClockTest do
  @moduledoc """
  Tests for the SystemClock service.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thundercore.SystemClock

  setup do
    name = :"system_clock_test_#{System.unique_integer()}"
    {:ok, pid} = SystemClock.start_link(name: name)
    {:ok, name: name, pid: pid}
  end

  describe "now/1" do
    test "returns monotonic time" do
      t1 = SystemClock.now(:millisecond)
      t2 = SystemClock.now(:millisecond)

      assert is_integer(t1)
      assert t2 >= t1
    end

    test "time never goes backward" do
      times = for _ <- 1..100, do: SystemClock.now(:microsecond)

      assert times == Enum.sort(times)
    end
  end

  describe "epoch_ms/1" do
    test "returns time since clock start", %{name: name} do
      # Small delay to ensure some time has passed
      Process.sleep(10)

      epoch = SystemClock.epoch_ms(name)
      assert is_integer(epoch)
      assert epoch >= 0
    end

    test "increases over time", %{name: name} do
      e1 = SystemClock.epoch_ms(name)
      Process.sleep(50)
      e2 = SystemClock.epoch_ms(name)

      assert e2 > e1
    end
  end

  describe "deadline/1" do
    test "returns future timestamp" do
      now = SystemClock.now(:millisecond)
      deadline = SystemClock.deadline(1000)

      assert deadline > now
      assert deadline - now >= 1000
    end
  end

  describe "past_deadline?/1" do
    test "returns false for future deadline" do
      deadline = SystemClock.deadline(1000)
      refute SystemClock.past_deadline?(deadline)
    end

    test "returns true for past deadline" do
      deadline = SystemClock.deadline(10)
      Process.sleep(20)
      assert SystemClock.past_deadline?(deadline)
    end
  end

  describe "time_remaining/1" do
    test "returns positive for future deadline" do
      deadline = SystemClock.deadline(1000)
      remaining = SystemClock.time_remaining(deadline)

      assert remaining > 0
      assert remaining <= 1000
    end

    test "returns negative for past deadline" do
      deadline = SystemClock.deadline(10)
      Process.sleep(50)
      remaining = SystemClock.time_remaining(deadline)

      assert remaining < 0
    end
  end

  describe "utc_now/0" do
    test "returns UTC datetime" do
      dt = SystemClock.utc_now()

      assert %DateTime{} = dt
      assert dt.time_zone == "Etc/UTC"
    end
  end

  describe "measure/1" do
    test "measures function execution time" do
      {result, duration} =
        SystemClock.measure(fn ->
          Process.sleep(10)
          :done
        end)

      assert result == :done
      assert is_integer(duration)
      assert duration >= 10
    end
  end

  describe "align_to_tick/2" do
    test "aligns timestamp to tick boundary" do
      assert SystemClock.align_to_tick(123, 50) == 100
      assert SystemClock.align_to_tick(150, 50) == 150
      assert SystemClock.align_to_tick(99, 50) == 50
    end
  end

  describe "info/1" do
    test "returns clock info", %{name: name} do
      info = SystemClock.info(name)

      assert Map.has_key?(info, :start_mono)
      assert Map.has_key?(info, :start_wall)
      assert Map.has_key?(info, :current_epoch_ms)
      assert Map.has_key?(info, :current_wall)
    end
  end
end
