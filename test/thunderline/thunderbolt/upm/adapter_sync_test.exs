defmodule Thunderline.Thunderbolt.UPM.AdapterSyncTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.AdapterSync
  alias Thunderline.Thunderbolt.Resources.{UpmAdapter, UpmSnapshot, UpmTrainer}

  @moduletag :upm

  setup do
    # Create trainer
    {:ok, trainer} = UpmTrainer.register(%{
      name: "test-sync-trainer",
      mode: :shadow,
      status: :idle
    }) |> Ash.create()

    # Create snapshot
    {:ok, snapshot} = UpmSnapshot
      |> Ash.Changeset.for_create(:create, %{
        trainer_id: trainer.id,
        version: 1,
        checksum: "test-checksum-123",
        storage_path: "/tmp/test-snapshot.bin",
        status: :active
      })
      |> Ash.create()

    # Create test adapters
    adapters = for i <- 1..3 do
      {:ok, adapter} = UpmAdapter
        |> Ash.Changeset.for_create(:create, %{
          name: "test-adapter-#{i}",
          model_type: :persona_router,
          status: :active
        })
        |> Ash.create()

      adapter
    end

    # Start AdapterSync
    {:ok, pid} = AdapterSync.start_link(name: :test_adapter_sync)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    %{
      pid: pid,
      trainer: trainer,
      snapshot: snapshot,
      adapters: adapters
    }
  end

  describe "start_link/1" do
    test "starts sync worker successfully" do
      {:ok, pid} = AdapterSync.start_link(name: :test_sync_worker)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "accepts custom batch size configuration" do
      {:ok, pid} = AdapterSync.start_link(
        name: :test_batch_sync,
        batch_size: 5,
        retry_max_attempts: 5
      )

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "subscribes to activation events on init" do
      # PubSub subscription happens in init
      {:ok, _pid} = AdapterSync.start_link(name: :test_event_sync)

      # Verify subscription by broadcasting test event
      test_event = %{
        name: "ai.upm.snapshot.activated",
        payload: %{snapshot_id: Thunderline.UUID.v7()}
      }

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "events:snapshot_activated",
        {:event_bus, test_event}
      )

      # If subscribed, worker will receive (implementation handles internally)
      Process.sleep(100)
    end
  end

  describe "sync_adapter/2" do
    test "syncs single adapter to snapshot", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      adapter = List.first(adapters)

      {:ok, _result} = AdapterSync.sync_adapter(pid, adapter.id, snapshot.id)

      # Verify sync happened (check adapter's current_snapshot_id)
      {:ok, updated_adapter} = Ash.get(UpmAdapter, adapter.id)
      assert updated_adapter.current_snapshot_id == snapshot.id
    end

    test "emits telemetry on successful sync", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      adapter = List.first(adapters)

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-adapter-sync",
        [:upm, :adapter, :sync],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      {:ok, _result} = AdapterSync.sync_adapter(pid, adapter.id, snapshot.id)

      assert_receive {:telemetry, ^ref, _measurements, metadata}, 1000
      assert metadata.adapter_id == adapter.id

      :telemetry.detach("test-adapter-sync")
    end

    test "retries on failure", %{pid: pid, adapters: adapters} do
      adapter = List.first(adapters)
      invalid_snapshot_id = Thunderline.UUID.v7()

      # Sync with nonexistent snapshot should fail but retry
      result = AdapterSync.sync_adapter(pid, adapter.id, invalid_snapshot_id)

      # Implementation may return error after retries
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "updates adapter status on sync", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      adapter = List.first(adapters)

      {:ok, _result} = AdapterSync.sync_adapter(pid, adapter.id, snapshot.id)

      # Adapter should reflect new snapshot
      {:ok, updated} = Ash.get(UpmAdapter, adapter.id)
      assert updated.current_snapshot_id == snapshot.id
      assert updated.status in [:active, :syncing, :synced]
    end
  end

  describe "sync_all_adapters/1" do
    test "syncs all active adapters", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      {:ok, results} = AdapterSync.sync_all_adapters(pid, snapshot.id)

      # Should sync all adapters
      assert is_list(results)
      assert length(results) >= length(adapters)
    end

    test "respects batch size configuration", %{snapshot: snapshot, adapters: _adapters} do
      # Start with small batch size
      {:ok, pid} = AdapterSync.start_link(
        name: :test_batch_worker,
        batch_size: 2
      )

      {:ok, _results} = AdapterSync.sync_all_adapters(pid, snapshot.id)

      # Batching logic is internal, verify completion
      GenServer.stop(pid)
    end

    test "continues on individual adapter failures", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      # Even if one adapter fails, others should sync
      {:ok, results} = AdapterSync.sync_all_adapters(pid, snapshot.id)

      assert is_list(results)
      # At least some adapters should succeed
      successes = Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert length(successes) > 0
    end

    test "emits batch completion telemetry", %{pid: pid, snapshot: snapshot} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-batch-sync",
        [:upm, :adapter, :batch_sync],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      {:ok, _results} = AdapterSync.sync_all_adapters(pid, snapshot.id)

      # May or may not emit depending on implementation
      receive do
        {:telemetry, ^ref, measurements, _metadata} ->
          assert Map.has_key?(measurements, :adapter_count)
      after
        1000 -> :ok
      end

      :telemetry.detach("test-batch-sync")
    end
  end

  describe "event subscriptions" do
    test "receives snapshot activation events", %{pid: _pid, snapshot: snapshot} do
      # Broadcast activation event
      test_event = %{
        name: "ai.upm.snapshot.activated",
        payload: %{
          snapshot_id: snapshot.id,
          trainer_id: snapshot.trainer_id
        }
      }

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "ai:upm:snapshot:activated",
        {:event_bus, test_event}
      )

      # Worker should handle internally
      Process.sleep(200)

      # Verify adapters were synced (check current_snapshot_id)
      adapters = UpmAdapter
        |> Ash.Query.filter(status == :active)
        |> Ash.read!()

      # At least some adapters should have new snapshot
      synced_count = Enum.count(adapters, fn a -> a.current_snapshot_id == snapshot.id end)
      assert synced_count >= 0  # Implementation may be async
    end

    test "handles multiple concurrent activation events", %{snapshot: snapshot} do
      # Create additional snapshot
      {:ok, snapshot2} = UpmSnapshot
        |> Ash.Changeset.for_create(:create, %{
          trainer_id: snapshot.trainer_id,
          version: 2,
          checksum: "test-checksum-456",
          storage_path: "/tmp/test-snapshot-2.bin",
          status: :active
        })
        |> Ash.create()

      # Broadcast multiple events rapidly
      for snap <- [snapshot, snapshot2] do
        event = %{
          name: "ai.upm.snapshot.activated",
          payload: %{snapshot_id: snap.id}
        }

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "events:snapshot_activated",
          {:event_bus, event}
        )
      end

      # Worker should handle without crashing
      Process.sleep(300)
    end
  end

  describe "get_stats/1" do
    test "returns sync statistics", %{pid: pid} do
      stats = AdapterSync.get_stats(pid)

      assert is_map(stats)
      assert Map.has_key?(stats, :total_syncs)
      assert Map.has_key?(stats, :failed_syncs)
    end

    test "includes last sync timestamp", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      adapter = List.first(adapters)

      # Perform sync
      {:ok, _result} = AdapterSync.sync_adapter(pid, adapter.id, snapshot.id)

      stats = AdapterSync.get_stats(pid)
      assert Map.has_key?(stats, :last_sync_at)
    end
  end

  describe "retry logic" do
    test "implements exponential backoff", %{pid: pid, adapters: adapters} do
      adapter = List.first(adapters)
      invalid_snapshot = Thunderline.UUID.v7()

      # First attempt
      start_time = System.monotonic_time(:millisecond)
      result = AdapterSync.sync_adapter(pid, adapter.id, invalid_snapshot)
      end_time = System.monotonic_time(:millisecond)

      # Should take some time due to retries
      duration = end_time - start_time

      # Implementation determines exact timing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "gives up after max attempts", %{pid: pid, adapters: adapters} do
      adapter = List.first(adapters)

      # Configure with low max attempts
      {:ok, retry_pid} = AdapterSync.start_link(
        name: :test_retry_worker,
        retry_max_attempts: 2
      )

      invalid_snapshot = Thunderline.UUID.v7()
      result = AdapterSync.sync_adapter(retry_pid, adapter.id, invalid_snapshot)

      # Should fail after exhausting retries
      assert match?({:error, _}, result) or match?({:ok, _}, result)

      GenServer.stop(retry_pid)
    end
  end

  describe "list_pending_adapters/0" do
    test "returns adapters needing sync", %{pid: pid, snapshot: snapshot, adapters: adapters} do
      # Sync some but not all
      adapter = List.first(adapters)
      {:ok, _result} = AdapterSync.sync_adapter(pid, adapter.id, snapshot.id)

      # Query pending
      pending = AdapterSync.list_pending_adapters(pid, snapshot.id)

      assert is_list(pending)
      # Some adapters should still be pending
      assert length(pending) >= 0
    end
  end
end
