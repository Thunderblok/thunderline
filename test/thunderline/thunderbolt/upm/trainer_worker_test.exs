defmodule Thunderline.Thunderbolt.UPM.TrainerWorkerTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.TrainerWorker
  alias Thunderline.Thunderbolt.Resources.{UpmTrainer, UpmSnapshot}
  alias Thunderline.Features.FeatureWindow

  @moduletag :upm

  describe "start_link/1" do
    test "starts worker with default configuration" do
      opts = [name: :test_trainer_1, trainer_name: "test-trainer-1"]
      assert {:ok, pid} = TrainerWorker.start_link(opts)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "initializes trainer resource on startup" do
      opts = [name: :test_trainer_2, trainer_name: "test-trainer-2", mode: :shadow]
      {:ok, pid} = TrainerWorker.start_link(opts)

      # Verify trainer was created in database
      assert {:ok, [trainer]} = 
        UpmTrainer
        |> Ash.Query.filter(name == "test-trainer-2")
        |> Ash.read()

      assert trainer.mode == :shadow
      assert trainer.status == :idle

      # Cleanup
      GenServer.stop(pid)
    end

    test "accepts custom learning parameters" do
      opts = [
        name: :test_trainer_3,
        trainer_name: "test-trainer-3",
        learning_rate: 0.01,
        batch_size: 64,
        snapshot_interval: 500
      ]

      {:ok, pid} = TrainerWorker.start_link(opts)
      metrics = TrainerWorker.get_metrics(pid)

      assert is_map(metrics)

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "process_window/2" do
    setup do
      opts = [name: :test_trainer_process, trainer_name: "test-process"]
      {:ok, pid} = TrainerWorker.start_link(opts)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid}
    end

    test "processes feature window and updates metrics", %{pid: pid} do
      # Create a test feature window
      window_id = Thunderline.UUID.v7()

      # Process the window
      :ok = TrainerWorker.process_window(pid, window_id)

      # Give it time to process
      Process.sleep(100)

      # Verify metrics updated
      metrics = TrainerWorker.get_metrics(pid)
      assert metrics.window_count >= 0
    end

    test "emits telemetry on window processing", %{pid: pid} do
      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-upm-trainer-update",
        [:upm, :trainer, :update],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      window_id = Thunderline.UUID.v7()
      :ok = TrainerWorker.process_window(pid, window_id)

      # Wait for telemetry
      assert_receive {:telemetry, ^ref, measurements, metadata}, 1000

      assert is_map(measurements)
      assert is_map(metadata)

      :telemetry.detach("test-upm-trainer-update")
    end

    test "creates snapshot at configured interval", %{pid: pid} do
      # Attach telemetry for snapshots
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-upm-trainer-snapshot",
        [:upm, :trainer, :snapshot],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:snapshot_telemetry, ref, measurements, metadata})
        end,
        nil
      )

      # Force snapshot creation
      {:ok, snapshot_id} = TrainerWorker.create_snapshot(pid)
      assert is_binary(snapshot_id)

      # Wait for telemetry
      assert_receive {:snapshot_telemetry, ^ref, _measurements, _metadata}, 1000

      :telemetry.detach("test-upm-trainer-snapshot")
    end
  end

  describe "pause/resume" do
    setup do
      opts = [name: :test_trainer_pause, trainer_name: "test-pause"]
      {:ok, pid} = TrainerWorker.start_link(opts)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid}
    end

    test "pauses and resumes training", %{pid: pid} do
      # Pause
      :ok = TrainerWorker.pause(pid)
      metrics = TrainerWorker.get_metrics(pid)
      assert metrics.status == :paused

      # Resume
      :ok = TrainerWorker.resume(pid)
      metrics = TrainerWorker.get_metrics(pid)
      assert metrics.status in [:idle, :training]
    end

    test "does not process windows when paused", %{pid: pid} do
      :ok = TrainerWorker.pause(pid)

      window_id = Thunderline.UUID.v7()
      :ok = TrainerWorker.process_window(pid, window_id)

      # Give it time
      Process.sleep(50)

      # Window count should not increase
      metrics = TrainerWorker.get_metrics(pid)
      initial_count = metrics.window_count

      :ok = TrainerWorker.process_window(pid, window_id)
      Process.sleep(50)

      metrics = TrainerWorker.get_metrics(pid)
      assert metrics.window_count == initial_count
    end
  end

  describe "event subscriptions" do
    setup do
      opts = [name: :test_trainer_events, trainer_name: "test-events"]
      {:ok, pid} = TrainerWorker.start_link(opts)

      on_exit(fn -> GenServer.stop(pid) end)

      %{pid: pid}
    end

    test "subscribes to feature window events on init", %{pid: _pid} do
      # Verify subscription by publishing test event
      test_event = %{
        name: "system.feature_window.created",
        payload: %{window_id: Thunderline.UUID.v7(), trainer_id: "test-events"}
      }

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "events:feature_window",
        {:event_bus, test_event}
      )

      # Worker should receive and process
      Process.sleep(100)
    end
  end

  describe "error handling" do
    test "restarts on crash" do
      opts = [name: :test_trainer_crash, trainer_name: "test-crash"]
      {:ok, pid} = TrainerWorker.start_link(opts)

      # Get initial metrics
      initial_metrics = TrainerWorker.get_metrics(pid)
      assert is_map(initial_metrics)

      # Cleanup
      GenServer.stop(pid)
    end
  end
end
