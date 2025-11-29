defmodule Thunderline.Thunderwall.EntropyMetricsTest do
  @moduledoc """
  Tests for the EntropyMetrics collector.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderwall.EntropyMetrics

  setup do
    name = :"entropy_metrics_test_#{System.unique_integer()}"
    {:ok, pid} = EntropyMetrics.start_link(name: name, collect_interval_ms: 100)
    {:ok, name: name, pid: pid}
  end

  describe "snapshot/1" do
    test "returns metrics map", %{name: name} do
      snapshot = EntropyMetrics.snapshot(name)
      
      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :decay_rate)
      assert Map.has_key?(snapshot, :overflow_rate)
      assert Map.has_key?(snapshot, :gc_rate)
      assert Map.has_key?(snapshot, :memory_mb)
      assert Map.has_key?(snapshot, :process_count)
    end
  end

  describe "get/2" do
    test "returns specific metric", %{name: name} do
      assert is_number(EntropyMetrics.get(:memory_mb, name))
      assert is_integer(EntropyMetrics.get(:process_count, name))
    end

    test "returns nil for unknown metric", %{name: name} do
      assert is_nil(EntropyMetrics.get(:unknown_metric, name))
    end
  end

  describe "topic/0" do
    test "returns correct topic" do
      assert EntropyMetrics.topic() == "wall:metrics"
    end
  end

  describe "record_decay/1" do
    test "accepts decay recording", %{name: name} do
      assert :ok = EntropyMetrics.record_decay(name)
    end
  end

  describe "record_overflow/1" do
    test "accepts overflow recording", %{name: name} do
      assert :ok = EntropyMetrics.record_overflow(name)
    end
  end

  describe "record_gc/2" do
    test "accepts gc recording", %{name: name} do
      assert :ok = EntropyMetrics.record_gc(10, name)
    end
  end
end
