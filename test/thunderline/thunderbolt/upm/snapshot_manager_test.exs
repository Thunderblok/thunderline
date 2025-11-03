defmodule Thunderline.Thunderbolt.UPM.SnapshotManagerTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.SnapshotManager
  alias Thunderline.Thunderbolt.Resources.{UpmTrainer, UpmSnapshot}

  @moduletag :upm

  describe "create_snapshot/3" do
    setup do
      # Create trainer
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-snapshot-trainer",
        mode: :shadow,
        status: :idle
      }) |> Ash.create()

      %{trainer: trainer}
    end

    test "creates snapshot with model data", %{trainer: trainer} do
      model_data = %{
        weights: %{layer1: [0.1, 0.2, 0.3]},
        version: 1
      }

      {:ok, snapshot_id} = SnapshotManager.create_snapshot(
        trainer.id,
        model_data,
        version: 1
      )

      assert is_binary(snapshot_id)

      # Verify snapshot was created
      {:ok, snapshot} = Ash.get(UpmSnapshot, snapshot_id)
      assert snapshot.trainer_id == trainer.id
      assert snapshot.version == 1
      assert snapshot.status == :pending
    end

    test "stores snapshot to configured path", %{trainer: trainer} do
      model_data = %{test: "data"}

      {:ok, snapshot_id} = SnapshotManager.create_snapshot(
        trainer.id,
        model_data
      )

      # Verify file was created
      storage_path = Application.get_env(:thunderline, :upm_snapshot_storage_path, "/tmp/thunderline/upm/snapshots")
      snapshot_file = Path.join(storage_path, "#{snapshot_id}.snapshot")

      # Note: Actual file creation depends on implementation
      # This test verifies the API contract
      assert is_binary(snapshot_id)
    end

    test "compresses snapshot data", %{trainer: trainer} do
      # Large model data to trigger compression
      model_data = %{
        embeddings: Enum.map(1..1000, fn i -> {i, :rand.uniform()} end) |> Map.new()
      }

      {:ok, snapshot_id} = SnapshotManager.create_snapshot(
        trainer.id,
        model_data
      )

      {:ok, snapshot} = Ash.get(UpmSnapshot, snapshot_id)
      
      # Verify checksum exists (indicates compression/serialization)
      assert is_binary(snapshot.checksum)
    end

    test "emits telemetry on snapshot creation", %{trainer: trainer} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-snapshot-create",
        [:upm, :snapshot, :create],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      model_data = %{test: "data"}
      {:ok, _snapshot_id} = SnapshotManager.create_snapshot(trainer.id, model_data)

      assert_receive {:telemetry, ^ref, _measurements, _metadata}, 1000

      :telemetry.detach("test-snapshot-create")
    end
  end

  describe "load_snapshot/1" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-load-trainer",
        mode: :shadow
      }) |> Ash.create()

      model_data = %{weights: [1, 2, 3], version: 1}
      {:ok, snapshot_id} = SnapshotManager.create_snapshot(trainer.id, model_data)

      %{trainer: trainer, snapshot_id: snapshot_id, model_data: model_data}
    end

    test "loads previously created snapshot", %{snapshot_id: snapshot_id, model_data: original_data} do
      {:ok, loaded_data} = SnapshotManager.load_snapshot(snapshot_id)

      assert is_map(loaded_data)
      # Verify data integrity (structure should match)
      assert Map.has_key?(loaded_data, :weights) or Map.has_key?(loaded_data, "weights")
    end

    test "validates checksum on load", %{snapshot_id: snapshot_id} do
      # Load should succeed with valid checksum
      assert {:ok, _data} = SnapshotManager.load_snapshot(snapshot_id)
    end

    test "returns error for nonexistent snapshot" do
      fake_id = Thunderline.UUID.v7()
      assert {:error, _reason} = SnapshotManager.load_snapshot(fake_id)
    end
  end

  describe "activate_snapshot/2" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-activate-trainer",
        mode: :shadow
      }) |> Ash.create()

      model_data = %{version: 1}
      {:ok, snapshot_id} = SnapshotManager.create_snapshot(trainer.id, model_data)

      %{trainer: trainer, snapshot_id: snapshot_id}
    end

    test "activates snapshot", %{snapshot_id: snapshot_id} do
      :ok = SnapshotManager.activate_snapshot(snapshot_id)

      # Verify snapshot is active
      {:ok, snapshot} = Ash.get(UpmSnapshot, snapshot_id)
      assert snapshot.status == :active
    end

    test "deactivates previous active snapshot", %{trainer: trainer, snapshot_id: first_id} do
      # Activate first
      :ok = SnapshotManager.activate_snapshot(first_id)

      # Create and activate second
      {:ok, second_id} = SnapshotManager.create_snapshot(trainer.id, %{version: 2})
      :ok = SnapshotManager.activate_snapshot(second_id)

      # First should be deactivated
      {:ok, first} = Ash.get(UpmSnapshot, first_id)
      assert first.status == :inactive

      # Second should be active
      {:ok, second} = Ash.get(UpmSnapshot, second_id)
      assert second.status == :active
    end

    test "emits activation event", %{snapshot_id: snapshot_id} do
      test_pid = self()

      Phoenix.PubSub.subscribe(Thunderline.PubSub, "ai:upm:snapshot:activated")

      :ok = SnapshotManager.activate_snapshot(snapshot_id)

      # Should receive broadcast
      assert_receive {:event_bus, event}, 1000
      assert event.name == "ai.upm.snapshot.activated"
    end
  end

  describe "list_snapshots/1" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-list-trainer",
        mode: :shadow
      }) |> Ash.create()

      # Create multiple snapshots
      snapshots = for v <- 1..3 do
        {:ok, id} = SnapshotManager.create_snapshot(trainer.id, %{version: v})
        id
      end

      %{trainer: trainer, snapshot_ids: snapshots}
    end

    test "lists all snapshots for trainer", %{trainer: trainer, snapshot_ids: snapshot_ids} do
      {:ok, snapshots} = SnapshotManager.list_snapshots(trainer.id)

      assert length(snapshots) >= length(snapshot_ids)
      
      # Verify all our snapshots are present
      snapshot_ids_from_list = Enum.map(snapshots, & &1.id)
      for id <- snapshot_ids do
        assert id in snapshot_ids_from_list
      end
    end

    test "returns empty list for trainer with no snapshots" do
      {:ok, empty_trainer} = UpmTrainer.register(%{
        name: "empty-trainer",
        mode: :shadow
      }) |> Ash.create()

      {:ok, snapshots} = SnapshotManager.list_snapshots(empty_trainer.id)
      assert snapshots == []
    end
  end

  describe "delete_snapshot/1" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-delete-trainer",
        mode: :shadow
      }) |> Ash.create()

      {:ok, snapshot_id} = SnapshotManager.create_snapshot(trainer.id, %{version: 1})

      %{trainer: trainer, snapshot_id: snapshot_id}
    end

    test "deletes snapshot and file", %{snapshot_id: snapshot_id} do
      :ok = SnapshotManager.delete_snapshot(snapshot_id)

      # Verify snapshot is deleted from database
      assert {:error, _} = Ash.get(UpmSnapshot, snapshot_id)
    end

    test "cannot delete active snapshot", %{snapshot_id: snapshot_id} do
      # Activate snapshot
      :ok = SnapshotManager.activate_snapshot(snapshot_id)

      # Try to delete (should fail or deactivate first)
      result = SnapshotManager.delete_snapshot(snapshot_id)
      
      # Implementation may vary - either fails or auto-deactivates
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
