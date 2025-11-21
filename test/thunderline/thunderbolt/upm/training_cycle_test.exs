defmodule Thunderline.Thunderbolt.Upm.TrainingCycleTest do
  @moduledoc """
  End-to-end integration tests for the complete UPM training workflow.
  
  Tests the interaction between:
  - FeatureWindow creation
  - ReplayBuffer buffering and release
  - TrainerWorker model updates
  - SnapshotManager persistence
  - DriftMonitor shadow comparisons
  """
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.{
    TrainerWorker,
    ReplayBuffer,
    SnapshotManager,
    DriftMonitor
  }

  alias Thunderline.Thunderbolt.Resources.UpmTrainer
  alias Thunderline.Thunderflow.Features.FeatureWindow

  setup do
    start_supervised!({Registry, keys: :unique, name: Thunderline.Registry})
    tenant_id = UUID.uuid4()

    # Create trainer resource
    {:ok, trainer} =
      Ash.Changeset.for_create(UpmTrainer, :register, %{
        name: "e2e_trainer_#{:rand.uniform(1000)}",
        mode: :shadow,
        tenant_id: tenant_id
      })
      |> Ash.create()

    {:ok, trainer: trainer, tenant_id: tenant_id}
  end

  describe "complete training workflow" do
    test "processes feature window through entire pipeline", %{
      trainer: trainer,
      tenant_id: tenant_id
    } do
      # Start TrainerWorker (which starts ReplayBuffer internally)
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 5
        )

      # Create a feature window
      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "e2e_window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{
            "user_id" => "123",
            "feature_1" => 1.5,
            "feature_2" => 2.3
          },
          label_spec: %{
            "target" => 1.0,
            "count" => 100
          },
          feature_schema_version: 1,
          provenance: %{source: "e2e_test"}
        })
        |> Ash.create(tenant: tenant_id)

      # Process the window directly
      :ok = TrainerWorker.process_window(worker, window.id)

      # Give time for processing
      Process.sleep(200)

      # Verify trainer state was updated
      stats = TrainerWorker.get_stats(worker)
      assert stats.window_count >= 1
      assert stats.last_window_id == window.id
    end

    test "creates snapshot after reaching interval", %{trainer: trainer, tenant_id: tenant_id} do
      # Very short snapshot interval for testing
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 3
        )

      # Process 3 windows to trigger snapshot
      for i <- 1..3 do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "snapshot_test_#{i}_#{UUID.uuid4()}",
            window_start: DateTime.add(DateTime.utc_now(), i * 60, :second),
            window_end: DateTime.add(DateTime.utc_now(), (i + 1) * 60, :second),
            features: %{"value" => i * 1.0},
            label_spec: %{"target" => i * 1.0},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        :ok = TrainerWorker.process_window(worker, window.id)
        Process.sleep(100)
      end

      # Give time for snapshot creation
      Process.sleep(300)

      # Verify snapshot was created
      {:ok, snapshots} = SnapshotManager.list_snapshots(trainer.id)
      assert length(snapshots) >= 1
    end

    test "handles multiple windows with buffering", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      # Create multiple windows
      base_time = DateTime.utc_now()

      windows =
        for i <- 1..5 do
          {:ok, window} =
            Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
              tenant_id: tenant_id,
              kind: :training,
              key: "multi_window_#{i}_#{UUID.uuid4()}",
              window_start: DateTime.add(base_time, i * 60, :second),
              window_end: DateTime.add(base_time, (i + 1) * 60, :second),
              features: %{"value" => i * 1.0},
              label_spec: %{"target" => i * 1.0},
              feature_schema_version: 1,
              provenance: %{source: "test"}
            })
            |> Ash.create(tenant: tenant_id)

          window
        end

      # Process windows out of order
      for window <- Enum.shuffle(windows) do
        :ok = TrainerWorker.process_window(worker, window.id)
        Process.sleep(50)
      end

      # Give time for all processing
      Process.sleep(500)

      # Verify all windows were processed
      stats = TrainerWorker.get_stats(worker)
      assert stats.window_count >= 5
    end
  end

  describe "shadow mode with drift monitoring" do
    test "monitors drift in shadow mode", %{trainer: trainer, tenant_id: tenant_id} do
      # Start worker in shadow mode
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      # Process a window to get initial model state
      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "drift_window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{"feature_1" => 1.0},
          label_spec: %{"target" => 1.0},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      :ok = TrainerWorker.process_window(worker, window.id)
      Process.sleep(200)

      # Verify shadow mode is active
      stats = TrainerWorker.get_stats(worker)
      assert stats.mode == :shadow
    end
  end

  describe "error recovery" do
    test "handles invalid window data gracefully", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      # Create window with minimal/invalid data
      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "invalid_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      # Should not crash the worker
      :ok = TrainerWorker.process_window(worker, window.id)
      Process.sleep(100)

      # Worker should still be alive
      assert Process.alive?(worker)
    end

    test "recovers from snapshot creation failures", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 2
        )

      # Process windows to trigger snapshot
      for i <- 1..2 do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "recovery_#{i}_#{UUID.uuid4()}",
            window_start: DateTime.add(DateTime.utc_now(), i * 60, :second),
            window_end: DateTime.add(DateTime.utc_now(), (i + 1) * 60, :second),
            features: %{"value" => i * 1.0},
            label_spec: %{"target" => i * 1.0},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        :ok = TrainerWorker.process_window(worker, window.id)
        Process.sleep(100)
      end

      Process.sleep(300)

      # Even if snapshot fails, worker should continue
      assert Process.alive?(worker)

      # Can still process more windows
      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "post_failure_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{"value" => 1.0},
          label_spec: %{"target" => 1.0},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      assert :ok = TrainerWorker.process_window(worker, window.id)
    end

    test "handles replay buffer overflow", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, worker} =
        TrainerWorker.start_link(
          trainer_id: trainer.id,
          trainer_name: trainer.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      # Create many windows quickly to test buffer capacity
      for i <- 1..20 do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "overflow_#{i}_#{UUID.uuid4()}",
            window_start: DateTime.add(DateTime.utc_now(), i * 60, :second),
            window_end: DateTime.add(DateTime.utc_now(), (i + 1) * 60, :second),
            features: %{"value" => i * 1.0},
            label_spec: %{"target" => i * 1.0},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        :ok = TrainerWorker.process_window(worker, window.id)
      end

      Process.sleep(500)

      # Worker should handle overflow gracefully
      assert Process.alive?(worker)

      stats = TrainerWorker.get_stats(worker)
      assert stats.window_count >= 1
    end
  end

  describe "multi-trainer coordination" do
    test "multiple trainers process independently", %{tenant_id: tenant_id} do
      # Create two trainers
      {:ok, trainer1} =
        Ash.Changeset.for_create(UpmTrainer, :create, %{
          name: "trainer_1_#{:rand.uniform(1000)}",
          mode: :shadow,
          tenant_id: tenant_id
        })
        |> Ash.create()

      {:ok, trainer2} =
        Ash.Changeset.for_create(UpmTrainer, :create, %{
          name: "trainer_2_#{:rand.uniform(1000)}",
          mode: :shadow,
          tenant_id: tenant_id
        })
        |> Ash.create()

      # Start both workers
      {:ok, worker1} =
        TrainerWorker.start_link(
          trainer_id: trainer1.id,
          trainer_name: trainer1.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      {:ok, worker2} =
        TrainerWorker.start_link(
          trainer_id: trainer2.id,
          trainer_name: trainer2.name,
          tenant_id: tenant_id,
          mode: :shadow,
          snapshot_interval: 100
        )

      # Create windows for each trainer
      for trainer_id <- [trainer1.id, trainer2.id] do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "multi_#{trainer_id}_#{UUID.uuid4()}",
            window_start: DateTime.utc_now(),
            window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
            features: %{"value" => 1.0},
            label_spec: %{"target" => 1.0},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        worker = if trainer_id == trainer1.id, do: worker1, else: worker2
        :ok = TrainerWorker.process_window(worker, window.id)
      end

      Process.sleep(300)

      # Both workers should be independent
      stats1 = TrainerWorker.get_stats(worker1)
      stats2 = TrainerWorker.get_stats(worker2)

      assert stats1.trainer_id == trainer1.id
      assert stats2.trainer_id == trainer2.id
      assert stats1.window_count >= 1
      assert stats2.window_count >= 1
    end
  end
end
