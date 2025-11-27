defmodule Thunderline.Thunderflow.DLQTest do
  @moduledoc """
  Tests for the DLQ (Dead Letter Queue) observability module (HC-09).
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thunderflow.DLQ

  describe "threshold/0" do
    test "returns default threshold" do
      assert is_integer(DLQ.threshold())
      assert DLQ.threshold() >= 1
    end
  end

  describe "tables/0" do
    test "returns list of atoms" do
      tables = DLQ.tables()
      assert is_list(tables)
      # All elements should be atoms (module names)
      assert Enum.all?(tables, &is_atom/1)
    end
  end

  describe "stats/1" do
    test "returns map with expected keys" do
      stats = DLQ.stats()

      assert Map.has_key?(stats, :count)
      assert Map.has_key?(stats, :threshold)
      assert Map.has_key?(stats, :recent)
      assert is_integer(stats.count)
      assert is_integer(stats.threshold)
      assert is_list(stats.recent)
    end
  end

  describe "emit_size/2" do
    setup do
      ref =
        :telemetry.attach(
          "test-dlq-size",
          [:thunderline, :event, :dlq, :size],
          fn event, measurements, metadata, _config ->
            send(self(), {:telemetry, event, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach("test-dlq-size") end)

      {:ok, ref: ref}
    end

    test "emits telemetry event with count" do
      DLQ.emit_size(42, %{source: :test})

      assert_receive {:telemetry, [:thunderline, :event, :dlq, :size], %{count: 42}, metadata}
      assert metadata.source == :test
      assert metadata.threshold == DLQ.threshold()
    end

    test "returns the count" do
      result = DLQ.emit_size(99, %{})

      assert result == 99
    end
  end

  describe "size/0" do
    test "returns non-negative integer" do
      size = DLQ.size()

      assert is_integer(size)
      assert size >= 0
    end
  end

  describe "recent/1" do
    test "returns list with limit" do
      recent = DLQ.recent(3)

      assert is_list(recent)
      assert length(recent) <= 3
    end
  end
end
