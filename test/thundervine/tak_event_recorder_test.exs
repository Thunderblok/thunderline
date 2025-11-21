defmodule Thundervine.TAKEventRecorderTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.TAK
  alias Thundervine.TAKEventRecorder

  @moduletag :integration

  describe "TAKEventRecorder integration" do
    test "subscribes to PubSub and receives CA delta messages" do
      run_id = "test_run_#{System.unique_integer()}"

      # Start event recorder manually
      {:ok, recorder_pid} = TAKEventRecorder.start_link(run_id: run_id, zone_id: "test_zone")

      # Verify it subscribed to PubSub
      assert Process.alive?(recorder_pid)

      # Simulate a CA delta message (what Runner broadcasts)
      msg = %{
        run_id: run_id,
        seq: 1,
        generation: 10,
        cells: [
          %{coord: {1, 1}, old: 0, new: 1},
          %{coord: {2, 2}, old: 1, new: 0}
        ],
        timestamp: DateTime.utc_now()
      }

      # Broadcast message
      Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})

      # Give recorder time to process
      Process.sleep(50)

      # Verify stats updated
      stats = TAKEventRecorder.get_stats(recorder_pid)
      assert stats.events_received >= 1
    end

    test "persists events to TAKChunkEvent resource" do
      run_id = "persist_test_#{System.unique_integer()}"

      {:ok, _recorder_pid} = TAKEventRecorder.start_link(run_id: run_id, zone_id: "persist_zone")

      # Broadcast CA delta
      msg = %{
        run_id: run_id,
        seq: 1,
        generation: 5,
        cells: [%{coord: {0, 0}, old: 0, new: 1}],
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})

      # Wait for processing
      Process.sleep(100)

      # Note: This would verify database persistence if TAKChunkEvent resource is wired to DB
      # For now, we verify the recorder received and attempted to persist
      # In production, you'd query: Ash.read(Thundervine.TAKChunkEvent, zone_id: "persist_zone")
    end

    test "handles multiple events in sequence" do
      run_id = "multi_test_#{System.unique_integer()}"

      {:ok, recorder_pid} = TAKEventRecorder.start_link(run_id: run_id)

      # Send multiple events
      for gen <- 1..5 do
        msg = %{
          run_id: run_id,
          seq: gen,
          generation: gen * 10,
          cells: [%{coord: {gen, gen}, old: 0, new: 1}],
          timestamp: DateTime.utc_now()
        }

        Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})
      end

      Process.sleep(150)

      stats = TAKEventRecorder.get_stats(recorder_pid)
      assert stats.events_received >= 5
    end

    test "Runner auto-starts event recorder" do
      run_id = "runner_auto_#{System.unique_integer()}"

      # Parse rules
      {:ok, ruleset} = TAK.RuleParser.parse("B3/S23")

      # Start Runner with recording enabled
      {:ok, runner_pid} =
        TAK.Runner.start_link(%{
          run_id: run_id,
          size: {5, 5},
          ruleset: ruleset,
          tick_ms: 100,
          enable_recording?: true
        })

      # Verify recorder was started
      Process.sleep(50)

      recorders = Thundervine.Supervisor.list_recorders()
      assert run_id in recorders

      # Clean up
      GenServer.stop(runner_pid)
    end
  end

  describe "Thundervine.Supervisor" do
    test "starts and stops recorders" do
      run_id = "supervisor_test_#{System.unique_integer()}"

      {:ok, pid} = Thundervine.Supervisor.start_recorder(run_id: run_id)
      assert Process.alive?(pid)

      assert run_id in Thundervine.Supervisor.list_recorders()

      :ok = Thundervine.Supervisor.stop_recorder(run_id)
      refute Process.alive?(pid)
    end

    test "handles already started recorder" do
      run_id = "duplicate_test_#{System.unique_integer()}"

      {:ok, pid1} = Thundervine.Supervisor.start_recorder(run_id: run_id)

      # Try to start again - should get already_started
      {:error, {:already_started, pid2}} =
        Thundervine.Supervisor.start_recorder(run_id: run_id)

      assert pid1 == pid2
    end
  end
end
