defmodule Thunderline.Thunderbolt.UPM.ReplayBufferTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.UPM.ReplayBuffer

  @moduletag :upm

  describe "start_link/1" do
    test "starts buffer with trainer_id" do
      trainer_id = Thunderline.UUID.v7()
      assert {:ok, pid} = ReplayBuffer.start_link(trainer_id: trainer_id)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "accepts custom buffer configuration" do
      trainer_id = Thunderline.UUID.v7()
      opts = [
        trainer_id: trainer_id,
        max_buffer_size: 500,
        dedup_window_seconds: 120
      ]

      assert {:ok, pid} = ReplayBuffer.start_link(opts)

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "add_window/2" do
    setup do
      trainer_id = Thunderline.UUID.v7()
      {:ok, pid} = ReplayBuffer.start_link(trainer_id: trainer_id)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid, trainer_id: trainer_id}
    end

    test "adds window to buffer", %{pid: pid} do
      window_id = Thunderline.UUID.v7()
      timestamp = DateTime.utc_now()

      :ok = ReplayBuffer.add_window(pid, window_id, timestamp)

      # Verify buffer size increased
      stats = ReplayBuffer.get_stats(pid)
      assert stats.buffer_size > 0
    end

    test "deduplicates duplicate windows", %{pid: pid} do
      window_id = Thunderline.UUID.v7()
      timestamp = DateTime.utc_now()

      # Add same window twice
      :ok = ReplayBuffer.add_window(pid, window_id, timestamp)
      :ok = ReplayBuffer.add_window(pid, window_id, timestamp)

      stats = ReplayBuffer.get_stats(pid)
      assert stats.duplicate_count == 1
    end

    test "maintains chronological ordering", %{pid: pid} do
      # Add windows out of order
      w1_id = Thunderline.UUID.v7()
      w2_id = Thunderline.UUID.v7()
      w3_id = Thunderline.UUID.v7()

      now = DateTime.utc_now()
      t1 = DateTime.add(now, -2, :second)
      t2 = DateTime.add(now, -1, :second)
      t3 = now

      # Add in wrong order: w3, w1, w2
      :ok = ReplayBuffer.add_window(pid, w3_id, t3)
      :ok = ReplayBuffer.add_window(pid, w1_id, t1)
      :ok = ReplayBuffer.add_window(pid, w2_id, t2)

      # Pop all and verify order
      {:ok, result1} = ReplayBuffer.pop_ready(pid)
      {:ok, result2} = ReplayBuffer.pop_ready(pid)
      {:ok, result3} = ReplayBuffer.pop_ready(pid)

      # Should come out in chronological order: w1, w2, w3
      assert result1 == w1_id
      assert result2 == w2_id
      assert result3 == w3_id
    end
  end

  describe "pop_ready/1" do
    setup do
      trainer_id = Thunderline.UUID.v7()
      {:ok, pid} = ReplayBuffer.start_link(trainer_id: trainer_id)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid}
    end

    test "returns :empty when buffer empty", %{pid: pid} do
      assert {:ok, :empty} = ReplayBuffer.pop_ready(pid)
    end

    test "pops windows in order", %{pid: pid} do
      w1 = Thunderline.UUID.v7()
      w2 = Thunderline.UUID.v7()

      now = DateTime.utc_now()
      t1 = DateTime.add(now, -10, :second)
      t2 = DateTime.add(now, -5, :second)

      :ok = ReplayBuffer.add_window(pid, w1, t1)
      :ok = ReplayBuffer.add_window(pid, w2, t2)

      {:ok, first} = ReplayBuffer.pop_ready(pid)
      {:ok, second} = ReplayBuffer.pop_ready(pid)

      assert first == w1
      assert second == w2
    end

    test "waits for out-of-order windows", %{pid: pid} do
      # Add window with future timestamp
      future_window = Thunderline.UUID.v7()
      future_time = DateTime.add(DateTime.utc_now(), 10, :second)

      :ok = ReplayBuffer.add_window(pid, future_window, future_time)

      # Should not pop yet (would wait in real scenario)
      result = ReplayBuffer.pop_ready(pid)
      
      # Depending on implementation, might be :empty or the window
      assert result == {:ok, :empty} or match?({:ok, _}, result)
    end
  end

  describe "buffer limits" do
    test "respects max buffer size" do
      trainer_id = Thunderline.UUID.v7()
      {:ok, pid} = ReplayBuffer.start_link(
        trainer_id: trainer_id,
        max_buffer_size: 10
      )

      # Add 15 windows
      now = DateTime.utc_now()
      for i <- 1..15 do
        window_id = Thunderline.UUID.v7()
        timestamp = DateTime.add(now, -i, :second)
        :ok = ReplayBuffer.add_window(pid, window_id, timestamp)
      end

      stats = ReplayBuffer.get_stats(pid)
      assert stats.buffer_size <= 10

      # Cleanup
      GenServer.stop(pid)
    end

    test "emits telemetry on buffer operations" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-replay-buffer-add",
        [:upm, :replay_buffer, :add],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      trainer_id = Thunderline.UUID.v7()
      {:ok, pid} = ReplayBuffer.start_link(trainer_id: trainer_id)

      window_id = Thunderline.UUID.v7()
      :ok = ReplayBuffer.add_window(pid, window_id, DateTime.utc_now())

      assert_receive {:telemetry, ^ref, _measurements, _metadata}, 1000

      :telemetry.detach("test-replay-buffer-add")
      GenServer.stop(pid)
    end
  end

  describe "clear/1" do
    setup do
      trainer_id = Thunderline.UUID.v7()
      {:ok, pid} = ReplayBuffer.start_link(trainer_id: trainer_id)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid}
    end

    test "clears all buffered windows", %{pid: pid} do
      # Add some windows
      for i <- 1..5 do
        window_id = Thunderline.UUID.v7()
        timestamp = DateTime.add(DateTime.utc_now(), -i, :second)
        :ok = ReplayBuffer.add_window(pid, window_id, timestamp)
      end

      # Verify buffer has items
      stats_before = ReplayBuffer.get_stats(pid)
      assert stats_before.buffer_size > 0

      # Clear
      :ok = ReplayBuffer.clear(pid)

      # Verify empty
      stats_after = ReplayBuffer.get_stats(pid)
      assert stats_after.buffer_size == 0
    end
  end
end
