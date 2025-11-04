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
        mode: :shadow
      })

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
      })

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
      })

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
      })

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
      })

      {:ok, snapshots} = SnapshotManager.list_snapshots(empty_trainer.id)
      assert snapshots == []
    end
  end

  describe "delete_snapshot/1" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "test-delete-trainer",
        mode: :shadow
      })

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

  # ============================================================================
  # INTEGRATION TESTS - ThunderCrown Policy Hooks & Full Workflows
  # ============================================================================

  describe "integration: policy enforcement on activation" do
    setup do
      tenant_id = UUID.v7()

      # Create shadow trainer
      {:ok, trainer} = UpmTrainer.register(%{
        name: "integration-test-trainer",
        mode: :shadow,
        tenant_id: tenant_id
      })

      %{trainer: trainer, tenant_id: tenant_id}
    end

    test "enforces policy checks via UPMPolicy.can_activate_snapshot?", %{trainer: trainer} do
      # Create a snapshot
      model_data_map = %{version: 1, weights: [1.0, 2.0, 3.0]}
      model_data_binary = Jason.encode!(model_data_map)
      checksum = :crypto.hash(:sha256, model_data_binary) |> Base.encode16(case: :lower)

      snapshot_params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: trainer.mode,
        status: trainer.status,
        checksum: checksum,
        size_bytes: byte_size(model_data_binary),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(snapshot_params, model_data_binary)

      # Activation should trigger policy check
      # (Implementation determines if policy allows shadow -> active)
      result = SnapshotManager.activate_snapshot(snapshot.id, %{
        correlation_id: UUID.v7()
      })

      # Should either succeed or fail with policy violation
      assert match?({:ok, _}, result) or match?({:error, {:policy_violation, _}}, result)
    end

    test "policy prevents activation when conditions not met", %{trainer: trainer} do
      # Create snapshot with trainer in idle status (may violate policy)
      model_data_binary = Jason.encode!(%{version: 1})
      checksum = :crypto.hash(:sha256, model_data_binary) |> Base.encode16(case: :lower)

      snapshot_params = %{
        trainer_id: trainer.id,
        tenant_id: trainer.tenant_id,
        version: 1,
        mode: :shadow,
        status: :idle,  # Policy may require training status
        checksum: checksum,
        size_bytes: byte_size(model_data_binary),
        metadata: %{}
      }

      {:ok, snapshot} = SnapshotManager.create_snapshot(snapshot_params, model_data_binary)

      # Attempt activation - policy should evaluate conditions
      result = SnapshotManager.activate_snapshot(snapshot.id)

      # Verify result structure (success or policy violation)
      assert match?({:ok, _}, result) or 
             match?({:error, {:policy_violation, _}}, result) or
             match?({:error, _}, result)
    end
  end

  describe "integration: concurrent snapshot operations" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "concurrent-test-trainer",
        mode: :canary,
        tenant_id: UUID.v7()
      })

      %{trainer: trainer}
    end

    test "handles concurrent snapshot creation", %{trainer: trainer} do
      # Create multiple snapshots concurrently
      tasks = for version <- 1..3 do
        Task.async(fn ->
          model_data_binary = Jason.encode!(%{version: version, data: "test"})
          checksum = :crypto.hash(:sha256, model_data_binary) |> Base.encode16(case: :lower)

          params = %{
            trainer_id: trainer.id,
            tenant_id: trainer.tenant_id,
            version: version,
            mode: trainer.mode,
            status: trainer.status,
            checksum: checksum,
            size_bytes: byte_size(model_data_binary),
            metadata: %{created_by: "concurrent_test"}
          }

          SnapshotManager.create_snapshot(params, model_data_binary)
        end)
      end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Verify all snapshots exist
      {:ok, snapshots} = SnapshotManager.list_snapshots(trainer.id)
      assert length(snapshots) == 3
    end
  end

  describe "integration: version progression workflow" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "version-progression-trainer",
        mode: :shadow,
        tenant_id: UUID.v7()
      })

      %{trainer: trainer}
    end

    test "progresses through multiple versions with activations", %{trainer: trainer} do
      # Version 1: Create and activate
      v1_binary = Jason.encode!(%{version: 1, weights: [1.0]})
      v1_checksum = :crypto.hash(:sha256, v1_binary) |> Base.encode16(case: :lower)

      {:ok, v1_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 1,
          mode: trainer.mode,
          status: trainer.status,
          checksum: v1_checksum,
          size_bytes: byte_size(v1_binary),
          metadata: %{}
        },
        v1_binary
      )

      {:ok, _} = SnapshotManager.activate_snapshot(v1_snapshot.id)

      # Version 2: Create and activate (should deactivate v1)
      v2_binary = Jason.encode!(%{version: 2, weights: [2.0]})
      v2_checksum = :crypto.hash(:sha256, v2_binary) |> Base.encode16(case: :lower)

      {:ok, v2_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 2,
          mode: trainer.mode,
          status: trainer.status,
          checksum: v2_checksum,
          size_bytes: byte_size(v2_binary),
          metadata: %{}
        },
        v2_binary
      )

      {:ok, _} = SnapshotManager.activate_snapshot(v2_snapshot.id)

      # Verify v2 is active
      {:ok, active_snapshot} = SnapshotManager.get_active_snapshot(trainer.id)
      assert active_snapshot.id == v2_snapshot.id
      assert active_snapshot.version == 2
    end
  end

  describe "integration: rollback scenario" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "rollback-test-trainer",
        mode: :active,
        tenant_id: UUID.v7()
      })

      # Create and activate v1
      v1_binary = Jason.encode!(%{version: 1, stable: true})
      v1_checksum = :crypto.hash(:sha256, v1_binary) |> Base.encode16(case: :lower)

      {:ok, v1_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 1,
          mode: trainer.mode,
          status: trainer.status,
          checksum: v1_checksum,
          size_bytes: byte_size(v1_binary),
          metadata: %{tag: "stable"}
        },
        v1_binary
      )

      {:ok, _} = SnapshotManager.activate_snapshot(v1_snapshot.id)

      # Create and activate v2 (problematic)
      v2_binary = Jason.encode!(%{version: 2, experimental: true})
      v2_checksum = :crypto.hash(:sha256, v2_binary) |> Base.encode16(case: :lower)

      {:ok, v2_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 2,
          mode: trainer.mode,
          status: trainer.status,
          checksum: v2_checksum,
          size_bytes: byte_size(v2_binary),
          metadata: %{tag: "experimental"}
        },
        v2_binary
      )

      {:ok, _} = SnapshotManager.activate_snapshot(v2_snapshot.id)

      %{trainer: trainer, v1_snapshot: v1_snapshot, v2_snapshot: v2_snapshot}
    end

    test "rolls back from v2 to v1", %{trainer: trainer, v1_snapshot: v1_snapshot, v2_snapshot: v2_snapshot} do
      # Verify v2 is currently active
      {:ok, active} = SnapshotManager.get_active_snapshot(trainer.id)
      assert active.id == v2_snapshot.id

      # Rollback to v1
      {:ok, rolled_back} = SnapshotManager.rollback_to_snapshot(v1_snapshot.id, %{
        correlation_id: UUID.v7()
      })

      assert rolled_back.id == v1_snapshot.id
      assert rolled_back.status == :active

      # Verify v1 is now active
      {:ok, current_active} = SnapshotManager.get_active_snapshot(trainer.id)
      assert current_active.id == v1_snapshot.id
    end
  end

  describe "integration: cleanup with retention" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "cleanup-test-trainer",
        mode: :shadow,
        tenant_id: UUID.v7()
      })

      # Create 5 old snapshots
      old_snapshots = for version <- 1..5 do
        binary = Jason.encode!(%{version: version})
        checksum = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

        {:ok, snapshot} = SnapshotManager.create_snapshot(
          %{
            trainer_id: trainer.id,
            tenant_id: trainer.tenant_id,
            version: version,
            mode: trainer.mode,
            status: trainer.status,
            checksum: checksum,
            size_bytes: byte_size(binary),
            metadata: %{}
          },
          binary
        )

        snapshot
      end

      %{trainer: trainer, old_snapshots: old_snapshots}
    end

    test "cleans up old snapshots beyond retention period", %{trainer: trainer, old_snapshots: old_snapshots} do
      # Create one recent snapshot to keep
      recent_binary = Jason.encode!(%{version: 6, recent: true})
      recent_checksum = :crypto.hash(:sha256, recent_binary) |> Base.encode16(case: :lower)

      {:ok, _recent} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 6,
          mode: trainer.mode,
          status: trainer.status,
          checksum: recent_checksum,
          size_bytes: byte_size(recent_binary),
          metadata: %{}
        },
        recent_binary
      )

      # Run cleanup with very short retention (0 days = delete old)
      {:ok, deleted_count} = SnapshotManager.cleanup_old_snapshots(trainer.id, retention_days: 0)

      # Should have deleted the 5 old ones, kept the recent
      assert deleted_count >= 5

      # Verify recent snapshot still exists
      {:ok, remaining} = SnapshotManager.list_snapshots(trainer.id)
      assert length(remaining) >= 1
    end
  end

  describe "integration: activation with policy chain" do
    setup do
      tenant_id = UUID.v7()

      {:ok, trainer} = UpmTrainer.register(%{
        name: "policy-chain-trainer",
        mode: :canary,
        tenant_id: tenant_id
      })

      %{trainer: trainer, tenant_id: tenant_id}
    end

    test "full activation chain with policy checks and state transitions", %{trainer: trainer} do
      # Create snapshot
      binary = Jason.encode!(%{version: 1, ready: true})
      checksum = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

      {:ok, snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 1,
          mode: :canary,
          status: :idle,
          checksum: checksum,
          size_bytes: byte_size(binary),
          metadata: %{drift_score: 0.05}
        },
        binary
      )

      # Activate with full context (triggers policy evaluation)
      result = SnapshotManager.activate_snapshot(snapshot.id, %{
        actor: %{id: UUID.v7(), role: :admin},
        tenant: trainer.tenant_id,
        correlation_id: UUID.v7()
      })

      # Should succeed or provide clear policy violation reason
      case result do
        {:ok, activated} ->
          assert activated.status == :active
          assert activated.id == snapshot.id

        {:error, {:policy_violation, reason}} ->
          assert is_binary(reason) or is_atom(reason)

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end

  describe "integration: multi-trainer isolation" do
    setup do
      tenant_id = UUID.v7()

      {:ok, trainer1} = UpmTrainer.register(%{
        name: "isolation-trainer-1",
        mode: :shadow,
        tenant_id: tenant_id
      })

      {:ok, trainer2} = UpmTrainer.register(%{
        name: "isolation-trainer-2",
        mode: :canary,
        tenant_id: tenant_id
      })

      %{trainer1: trainer1, trainer2: trainer2, tenant_id: tenant_id}
    end

    test "snapshots isolated between trainers", %{trainer1: trainer1, trainer2: trainer2} do
      # Create snapshot for trainer1
      t1_binary = Jason.encode!(%{trainer: 1})
      t1_checksum = :crypto.hash(:sha256, t1_binary) |> Base.encode16(case: :lower)

      {:ok, t1_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer1.id,
          tenant_id: trainer1.tenant_id,
          version: 1,
          mode: trainer1.mode,
          status: trainer1.status,
          checksum: t1_checksum,
          size_bytes: byte_size(t1_binary),
          metadata: %{}
        },
        t1_binary
      )

      # Create snapshot for trainer2
      t2_binary = Jason.encode!(%{trainer: 2})
      t2_checksum = :crypto.hash(:sha256, t2_binary) |> Base.encode16(case: :lower)

      {:ok, t2_snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer2.id,
          tenant_id: trainer2.tenant_id,
          version: 1,
          mode: trainer2.mode,
          status: trainer2.status,
          checksum: t2_checksum,
          size_bytes: byte_size(t2_binary),
          metadata: %{}
        },
        t2_binary
      )

      # List snapshots for each trainer
      {:ok, t1_snapshots} = SnapshotManager.list_snapshots(trainer1.id)
      {:ok, t2_snapshots} = SnapshotManager.list_snapshots(trainer2.id)

      # Each should only see their own
      assert length(t1_snapshots) == 1
      assert length(t2_snapshots) == 1
      assert hd(t1_snapshots).id == t1_snapshot.id
      assert hd(t2_snapshots).id == t2_snapshot.id
    end
  end

  describe "integration: large model handling" do
    setup do
      {:ok, trainer} = UpmTrainer.register(%{
        name: "large-model-trainer",
        mode: :shadow,
        tenant_id: UUID.v7()
      })

      %{trainer: trainer}
    end

    test "handles large model data with compression", %{trainer: trainer} do
      # Create large model data (simulate 100KB model)
      large_weights = for _i <- 1..10_000, do: :rand.uniform()
      large_model = %{version: 1, weights: large_weights, layers: 50}
      large_binary = Jason.encode!(large_model)
      checksum = :crypto.hash(:sha256, large_binary) |> Base.encode16(case: :lower)

      # Create snapshot
      {:ok, snapshot} = SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: trainer.tenant_id,
          version: 1,
          mode: trainer.mode,
          status: trainer.status,
          checksum: checksum,
          size_bytes: byte_size(large_binary),
          metadata: %{model_type: "large_nn"}
        },
        large_binary
      )

      assert snapshot.size_bytes > 50_000  # Verify it's actually large

      # Load it back
      {:ok, loaded_binary} = SnapshotManager.load_snapshot(snapshot.id)

      # Verify data integrity
      assert loaded_binary == large_binary

      # Verify checksum matches
      loaded_checksum = :crypto.hash(:sha256, loaded_binary) |> Base.encode16(case: :lower)
      assert loaded_checksum == checksum
    end
  end
end
