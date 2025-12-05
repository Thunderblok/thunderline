defmodule Thunderline.Thundercore.TickStateTest do
  @moduledoc """
  Tests for the TickState Ash resource.

  HC-46 requirement: Validates that:
  - TickState can snapshot tick data
  - TickState can retrieve recent snapshots
  - TickState can filter by tick type
  - TickState can prune old entries (for Thunderwall decay)
  """
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercore.Resources.TickState

  @valid_attrs %{
    tick_id: 1,
    tick_type: :system,
    timestamp: DateTime.utc_now(),
    monotonic_ns: System.monotonic_time(:nanosecond),
    epoch_ms: 1000,
    metadata: %{}
  }

  describe "snapshot/1 (create tick state)" do
    test "creates a tick state with valid attributes" do
      {:ok, state} = TickState.snapshot(@valid_attrs)

      assert state.tick_id == 1
      assert state.tick_type == :system
      assert state.epoch_ms == 1000
    end

    test "supports all tick types" do
      for tick_type <- [:system, :slow, :fast] do
        {:ok, state} = TickState.snapshot(%{@valid_attrs | tick_type: tick_type, tick_id: :rand.uniform(100_000)})
        assert state.tick_type == tick_type
      end
    end

    test "accepts optional metadata" do
      attrs = Map.put(@valid_attrs, :metadata, %{node: "test-node", phase: :hold})

      {:ok, state} = TickState.snapshot(attrs)

      # Metadata is stored as JSON, so keys become strings
      assert state.metadata == %{"node" => "test-node", "phase" => "hold"}
    end

    test "requires tick_id" do
      attrs = Map.delete(@valid_attrs, :tick_id)

      assert {:error, _} = TickState.snapshot(attrs)
    end

    test "requires timestamp" do
      attrs = Map.delete(@valid_attrs, :timestamp)

      assert {:error, _} = TickState.snapshot(attrs)
    end

    test "requires monotonic_ns" do
      attrs = Map.delete(@valid_attrs, :monotonic_ns)

      assert {:error, _} = TickState.snapshot(attrs)
    end

    test "requires epoch_ms" do
      attrs = Map.delete(@valid_attrs, :epoch_ms)

      assert {:error, _} = TickState.snapshot(attrs)
    end
  end

  describe "recent/1 (get recent states)" do
    setup do
      # Create several tick states with different tick_ids
      for i <- 1..5 do
        {:ok, _} = TickState.snapshot(%{
          @valid_attrs |
          tick_id: i * 100,
          monotonic_ns: System.monotonic_time(:nanosecond) + i
        })
      end

      :ok
    end

    test "returns recent tick states" do
      {:ok, states} = TickState.recent()

      assert length(states) >= 5
    end

    test "respects limit parameter" do
      {:ok, states} = TickState.recent(3)

      assert length(states) <= 3
    end

    test "returns states in descending order by inserted_at" do
      {:ok, states} = TickState.recent(5)

      # States should be ordered newest first
      inserted_times = Enum.map(states, & &1.inserted_at)
      assert inserted_times == Enum.sort(inserted_times, {:desc, DateTime})
    end
  end

  describe "by_type/2 (filter by tick type)" do
    setup do
      # Create states of different types
      for {type, i} <- Enum.with_index([:system, :slow, :fast, :system, :system]) do
        {:ok, _} = TickState.snapshot(%{
          @valid_attrs |
          tick_id: 1000 + i,
          tick_type: type,
          monotonic_ns: System.monotonic_time(:nanosecond) + i
        })
      end

      :ok
    end

    test "filters by system type" do
      {:ok, states} = TickState.by_type(:system)

      assert Enum.all?(states, &(&1.tick_type == :system))
    end

    test "filters by slow type" do
      {:ok, states} = TickState.by_type(:slow)

      assert Enum.all?(states, &(&1.tick_type == :slow))
    end

    test "filters by fast type" do
      {:ok, states} = TickState.by_type(:fast)

      assert Enum.all?(states, &(&1.tick_type == :fast))
    end

    test "respects limit parameter" do
      {:ok, states} = TickState.by_type(:system, 2)

      assert length(states) <= 2
    end
  end

  describe "prune_before_tick/1 (cleanup old states)" do
    setup do
      # Create states with various tick_ids
      for i <- [10, 20, 30, 40, 50] do
        {:ok, _} = TickState.snapshot(%{
          @valid_attrs |
          tick_id: i,
          monotonic_ns: System.monotonic_time(:nanosecond) + i
        })
      end

      :ok
    end

    test "prunes states before given tick_id" do
      # Prune everything before tick 35
      {:ok, count} = TickState.prune_before_tick(35)

      # Should have pruned 10, 20, 30
      assert count >= 3

      # Remaining should be 40, 50
      {:ok, remaining} = TickState.recent(100)
      tick_ids = Enum.map(remaining, & &1.tick_id) |> Enum.filter(&(&1 in [10, 20, 30, 40, 50]))

      refute 10 in tick_ids
      refute 20 in tick_ids
      refute 30 in tick_ids
    end

    test "returns count of deleted records" do
      {:ok, count} = TickState.prune_before_tick(25)

      assert is_integer(count)
      assert count >= 0
    end

    test "returns 0 when nothing to prune" do
      {:ok, count} = TickState.prune_before_tick(1)

      assert count == 0
    end
  end

  describe "identity constraints" do
    test "tick_id + tick_type must be unique" do
      attrs = %{@valid_attrs | tick_id: 99999}

      {:ok, _} = TickState.snapshot(attrs)

      # Same tick_id and tick_type should fail
      result = TickState.snapshot(attrs)
      assert {:error, _} = result
    end

    test "same tick_id with different tick_type is allowed" do
      base_attrs = %{@valid_attrs | tick_id: 88888}

      {:ok, system} = TickState.snapshot(%{base_attrs | tick_type: :system})
      {:ok, slow} = TickState.snapshot(%{base_attrs | tick_type: :slow, monotonic_ns: System.monotonic_time(:nanosecond) + 1})

      assert system.tick_id == slow.tick_id
      assert system.tick_type != slow.tick_type
    end
  end
end
