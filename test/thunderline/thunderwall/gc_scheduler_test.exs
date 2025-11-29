defmodule Thunderline.Thunderwall.GCSchedulerTest do
  @moduledoc """
  Tests for the GCScheduler.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderwall.GCScheduler

  setup do
    name = :"gc_scheduler_test_#{System.unique_integer()}"
    {:ok, pid} = GCScheduler.start_link(name: name, interval_ms: 60_000)
    {:ok, name: name, pid: pid}
  end

  describe "stats/1" do
    test "returns initial stats", %{name: name} do
      stats = GCScheduler.stats(name)

      assert stats.total_runs == 0
      assert stats.total_collected == 0
      assert is_nil(stats.last_run)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses and resumes GC", %{name: name} do
      assert :ok = GCScheduler.pause(name)
      assert :ok = GCScheduler.resume(name)
    end
  end

  describe "set_interval/2" do
    test "updates interval", %{name: name} do
      assert :ok = GCScheduler.set_interval(120_000, name)
    end
  end
end
