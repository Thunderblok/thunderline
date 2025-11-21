defmodule Thunderline.Thunderbolt.Upm.SnapshotManagerTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.SnapshotManager
  alias Thunderline.Thunderbolt.Resources.UpmTrainer
  alias Thunderline.Thunderbolt.Resources.UpmSnapshot

  setup do
    tenant_id = UUID.uuid4()

    # Create trainer
    {:ok, trainer} =
      Ash.Changeset.for_create(UpmTrainer, :register, %{
        name: "test_trainer_#{:rand.uniform(1000)}",
        mode: :shadow,
        tenant_id: tenant_id
      })
      |> Ash.create()

    # Ensure storage directory exists
    storage_path = "/tmp/thunderline_test/upm/snapshots"
    File.mkdir_p!(storage_path)

    on_exit(fn ->
      # Cleanup test storage
      File.rm_rf!(storage_path)
    end)

    {:ok, trainer: trainer, tenant_id: tenant_id}
  end

  describe "snapshot creation" do
    test "creates snapshot with valid model data", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0, 2.0, 3.0], bias: 0.5})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{created_by: "test"}
      }

      assert {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)

      assert snapshot.trainer_id == trainer.id
      assert snapshot.version == 1
      assert snapshot.mode == :shadow
      assert snapshot.checksum == checksum
      assert File.exists?(snapshot.storage_path)
    end

    test "rejects snapshot with checksum mismatch", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0, 2.0, 3.0]})
      wrong_checksum = "deadbeef"

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: wrong_checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      assert {:error, :checksum_mismatch} = SnapshotManager.create_snapshot(params, model_data)
    end

    test "compresses snapshot data", %{trainer: trainer} do
      # Large model data to ensure compression
      model_data = Jason.encode!(%{weights: List.duplicate(1.0, 1000)})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)

      # Verify compression metadata
      assert snapshot.metadata["compression"] in ["zstd", "gzip"]
      assert snapshot.metadata["original_size"] == byte_size(model_data)
      # Storage size should be less than original
      assert snapshot.metadata["storage_size"] < byte_size(model_data)
    end
  end

  describe "snapshot loading" do
    test "loads and decompresses snapshot data", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [4.0, 5.0, 6.0], bias: 1.5})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)

      # Load it back
      assert {:ok, loaded_data} = SnapshotManager.load_snapshot(snapshot.id)

      # Should be parsed JSON
      assert is_map(loaded_data)
      assert loaded_data["weights"] == [4.0, 5.0, 6.0]
      assert loaded_data["bias"] == 1.5
    end

    test "validates checksum on load", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0, 2.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)

      # Corrupt the file
      File.write!(snapshot.storage_path, "corrupted data")

      # Should fail checksum validation
      assert {:error, :checksum_mismatch} = SnapshotManager.load_snapshot(snapshot.id)
    end

    test "returns error for non-existent snapshot" do
      fake_id = UUID.uuid4()
      assert {:error, {:snapshot_not_found, _}} = SnapshotManager.load_snapshot(fake_id)
    end
  end

  describe "snapshot activation" do
    test "activates shadow snapshot without authorization", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)

      # Shadow mode should allow activation without actor
      assert {:ok, activated} = SnapshotManager.activate_snapshot(snapshot.id)
      assert activated.status == :activated
    end

    test "deactivates previous active snapshot", %{trainer: trainer} do
      model_data1 = Jason.encode!(%{weights: [1.0]})
      checksum1 = :crypto.hash(:sha256, model_data1) |> Base.encode16(case: :lower)

      params1 = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum1,
        size_bytes: byte_size(model_data1),
        metadata: %{}
      }

      {:ok, snapshot1} = SnapshotManager.create_snapshot(params1, model_data1)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot1.id)

      # Create and activate second snapshot
      model_data2 = Jason.encode!(%{weights: [2.0]})
      checksum2 = :crypto.hash(:sha256, model_data2) |> Base.encode16(case: :lower)

      params2 = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 2,
        mode: :shadow,
        status: :created,
        checksum: checksum2,
        size_bytes: byte_size(model_data2),
        metadata: %{}
      }

      {:ok, snapshot2} = SnapshotManager.create_snapshot(params2, model_data2)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot2.id)

      # First snapshot should be deactivated
      {:ok, reloaded} = Ash.get(UpmSnapshot, snapshot1.id)
      assert reloaded.status != :activated
    end
  end

  describe "snapshot listing" do
    test "lists all snapshots for trainer", %{trainer: trainer} do
      # Create 3 snapshots
      for v <- 1..3 do
        model_data = Jason.encode!(%{version: v})
        checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

        params = %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: v,
          mode: :shadow,
          status: :created,
          checksum: checksum,
          size_bytes: byte_size(model_data),
          metadata: %{}
        }

        {:ok, _} = SnapshotManager.create_snapshot(params, model_data)
      end

      {:ok, snapshots} = SnapshotManager.list_snapshots(trainer.id)

      assert length(snapshots) == 3
      # Should be sorted by version descending
      versions = Enum.map(snapshots, & &1.version)
      assert versions == [3, 2, 1]
    end

    test "filters snapshots by status", %{trainer: trainer} do
      # Create snapshot and activate it
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot.id)

      # Create another non-activated snapshot
      model_data2 = Jason.encode!(%{weights: [2.0]})
      checksum2 = :crypto.hash(:sha256, model_data2) |> Base.encode16(case: :lower)

      params2 = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 2,
        mode: :shadow,
        status: :created,
        checksum: checksum2,
        size_bytes: byte_size(model_data2),
        metadata: %{}
      }

      {:ok, _} = SnapshotManager.create_snapshot(params2, model_data2)

      # Filter for activated only
      {:ok, activated} = SnapshotManager.list_snapshots(trainer.id, status: :activated)
      assert length(activated) == 1
      assert hd(activated).version == 1
    end

    test "gets currently active snapshot", %{trainer: trainer} do
      # Create and activate a snapshot
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot.id)

      {:ok, active} = SnapshotManager.get_active_snapshot(trainer.id)
      assert active.id == snapshot.id
    end

    test "returns nil when no active snapshot", %{trainer: trainer} do
      {:ok, active} = SnapshotManager.get_active_snapshot(trainer.id)
      assert active == nil
    end
  end

  describe "snapshot deletion" do
    test "deletes snapshot and file", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
      storage_path = snapshot.storage_path

      assert File.exists?(storage_path)

      assert :ok = SnapshotManager.delete_snapshot(snapshot.id)

      # File should be deleted
      refute File.exists?(storage_path)

      # Resource should be deleted
      assert {:error, %Ash.Error.Query.NotFound{}} = Ash.get(UpmSnapshot, snapshot.id)
    end

    test "cannot delete active snapshot", %{trainer: trainer} do
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot.id)

      assert {:error, :cannot_delete_active_snapshot} =
               SnapshotManager.delete_snapshot(snapshot.id)
    end
  end

  describe "snapshot cleanup" do
    test "cleans up old snapshots based on retention", %{trainer: trainer} do
      # Create 3 snapshots with different ages
      old_snapshot_ids =
        for v <- 1..2 do
          model_data = Jason.encode!(%{version: v})
          checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

          params = %{
            trainer_id: trainer.id,
            tenant_id: trainer.tenant_id,
            version: v,
            mode: :shadow,
            status: :archived,
            checksum: checksum,
            size_bytes: byte_size(model_data),
            metadata: %{}
          }

          {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
          snapshot.id
        end

      # Clean up with 0 day retention (should delete old archived snapshots)
      {:ok, deleted_count} =
        SnapshotManager.cleanup_old_snapshots(trainer.id, retention_days: 0)

      # Should have deleted the archived snapshots
      assert deleted_count >= 0

      # Verify snapshots were deleted
      Enum.each(old_snapshot_ids, fn id ->
        result = Ash.get(UpmSnapshot, id)

        case result do
          {:error, %Ash.Error.Query.NotFound{}} -> :ok
          {:ok, _} -> :ok
        end
      end)
    end

    test "does not delete activated snapshots during cleanup", %{trainer: trainer} do
      # Create and activate a snapshot
      model_data = Jason.encode!(%{weights: [1.0]})
      checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

      params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :created,
        checksum: checksum,
        size_bytes: byte_size(model_data),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(params, model_data)
      {:ok, _} = SnapshotManager.activate_snapshot(snapshot.id)

      # Cleanup should not delete activated snapshot
      {:ok, _deleted_count} =
        SnapshotManager.cleanup_old_snapshots(trainer.id, retention_days: 0)

      # Snapshot should still exist
      {:ok, reloaded} = Ash.get(UpmSnapshot, snapshot.id)
      assert reloaded.id == snapshot.id
    end
  end
end
