defmodule Thunderline.Thunderbolt.Upm.DriftMonitorTest do
  use Thunderline.DataCase, async: false

  require Ash.Query

  alias Thunderline.Thunderbolt.UPM.{DriftMonitor, SnapshotManager}
  alias Thunderline.Thunderbolt.Resources.{UpmTrainer, UpmDriftWindow}

  setup do
    start_supervised!({Registry, keys: :unique, name: Thunderline.Registry})
    tenant_id = UUID.uuid4()

    # Create trainer
    {:ok, trainer} =
      Ash.Changeset.for_create(UpmTrainer, :register, %{
        name: "test_trainer_#{:rand.uniform(1000)}",
        mode: :shadow,
        tenant_id: tenant_id
      })
      |> Ash.create()

    # Create a snapshot for drift monitoring
    model_data = Jason.encode!(%{weights: [1.0, 2.0]})
    checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

    {:ok, snapshot} =
      SnapshotManager.create_snapshot(
        %{
          trainer_id: trainer.id,
          tenant_id: tenant_id,
          version: 1,
          mode: :shadow,
          status: :created,
          checksum: checksum,
          size_bytes: byte_size(model_data),
          metadata: %{}
        },
        model_data
      )

    {:ok, trainer: trainer, snapshot: snapshot, tenant_id: tenant_id}
  end

  describe "initialization" do
    test "starts with empty comparisons", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.2,
          sample_size: 100,
          window_duration_ms: 60_000
        )

      stats = DriftMonitor.get_stats(monitor)

      assert stats.trainer_id == trainer.id
      assert stats.snapshot_id == snapshot.id
      assert stats.sample_count == 0
      assert stats.drift_mean == 0.0
      assert stats.drift_p95 == 0.0
    end

    test "configures thresholds correctly", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.15,
          sample_size: 500
        )

      stats = DriftMonitor.get_stats(monitor)

      assert stats.drift_threshold == 0.15
      assert stats.sample_size == 500
    end
  end

  describe "drift calculation" do
    test "calculates numeric drift accurately", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5
        )

      # Record comparison with numeric values
      comparison = %{
        shadow_prediction: 1.0,
        ground_truth: 1.5,
        metadata: %{test: "numeric"}
      }

      :ok = DriftMonitor.record_comparison(monitor, comparison)
      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # Drift = abs(1.0 - 1.5) = 0.5
      assert stats.sample_count == 1
      assert stats.drift_mean == 0.5
    end

    test "calculates map-based drift", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5
        )

      # Record comparison with map values
      comparison = %{
        shadow_prediction: %{a: 1, b: 2, c: 3},
        ground_truth: %{a: 1, b: 999, c: 3},
        metadata: %{}
      }

      :ok = DriftMonitor.record_comparison(monitor, comparison)
      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # Drift = 1 mismatch / 3 keys = 0.33...
      assert stats.sample_count == 1
      assert_in_delta stats.drift_mean, 0.33, 0.05
    end

    test "calculates binary drift", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5
        )

      # Record comparison with binary values (strings)
      comparison1 = %{
        shadow_prediction: "class_a",
        ground_truth: "class_a",
        metadata: %{}
      }

      comparison2 = %{
        shadow_prediction: "class_a",
        ground_truth: "class_b",
        metadata: %{}
      }

      :ok = DriftMonitor.record_comparison(monitor, comparison1)
      :ok = DriftMonitor.record_comparison(monitor, comparison2)
      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # Drift1 = 0.0 (match), Drift2 = 1.0 (mismatch), mean = 0.5
      assert stats.sample_count == 2
      assert stats.drift_mean == 0.5
    end

    test "tracks multiple comparisons", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.3
        )

      # Record multiple comparisons with varying drift
      comparisons = [
        %{shadow_prediction: 1.0, ground_truth: 1.0, metadata: %{}},
        %{shadow_prediction: 2.0, ground_truth: 2.2, metadata: %{}},
        %{shadow_prediction: 3.0, ground_truth: 3.5, metadata: %{}},
        %{shadow_prediction: 4.0, ground_truth: 4.1, metadata: %{}}
      ]

      Enum.each(comparisons, fn comp ->
        :ok = DriftMonitor.record_comparison(monitor, comp)
      end)

      Process.sleep(100)

      stats = DriftMonitor.get_stats(monitor)
      assert stats.sample_count == 4
      # Mean drift = (0.0 + 0.2 + 0.5 + 0.1) / 4 = 0.2
      assert_in_delta stats.drift_mean, 0.2, 0.01
      assert stats.drift_max == 0.5
    end
  end

  describe "statistics calculation" do
    test "calculates P95 correctly", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 1.0,
          sample_size: 20
        )

      # Record 20 comparisons with known drift values
      for i <- 1..20 do
        comparison = %{
          shadow_prediction: i * 1.0,
          ground_truth: (i + 1) * 1.0,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(100)

      {:ok, result} = DriftMonitor.evaluate_now(monitor)

      # P95 should be around the 19th value (95% of 20)
      assert result.drift_p95 >= 0.9
      assert result.sample_count == 20
    end

    test "calculates mean and max accurately", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 1.0
        )

      # Known values: 0.1, 0.2, 0.3, 0.4, 0.5
      drift_values = [0.1, 0.2, 0.3, 0.4, 0.5]

      for drift <- drift_values do
        comparison = %{
          shadow_prediction: 0.0,
          ground_truth: drift,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # Mean = (0.1 + 0.2 + 0.3 + 0.4 + 0.5) / 5 = 0.3
      assert_in_delta stats.drift_mean, 0.3, 0.01
      assert stats.drift_max == 0.5
    end

    test "indicates quarantine risk when P95 exceeds threshold", %{
      trainer: trainer,
      snapshot: snapshot
    } do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.2,
          sample_size: 10
        )

      # Record comparisons with high drift
      for _ <- 1..10 do
        comparison = %{
          shadow_prediction: 1.0,
          ground_truth: 1.5,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # All drifts are 0.5, P95 = 0.5, threshold = 0.2
      assert stats.quarantine_risk == true
    end

    test "no quarantine risk when below threshold", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5,
          sample_size: 10
        )

      # Record comparisons with low drift
      for _ <- 1..10 do
        comparison = %{
          shadow_prediction: 1.0,
          ground_truth: 1.1,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      # All drifts are 0.1, P95 = 0.1, threshold = 0.5
      assert stats.quarantine_risk == false
    end
  end

  describe "window evaluation" do
    test "evaluates window with sufficient samples", %{
      trainer: trainer,
      snapshot: snapshot,
      tenant_id: tenant_id
    } do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.3,
          sample_size: 5,
          window_duration_ms: 60_000
        )

      # Record 5 comparisons (meets sample_size)
      for i <- 1..5 do
        comparison = %{
          shadow_prediction: i * 1.0,
          ground_truth: (i + 0.2) * 1.0,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      {:ok, result} = DriftMonitor.evaluate_now(monitor)

      assert result.sample_count == 5
      assert result.status == :completed

      # Verify UpmDriftWindow was created
      {:ok, windows} =
        UpmDriftWindow
        |> Ash.Query.filter(trainer_id == ^trainer.id)
        |> Ash.read(tenant: tenant_id)

      assert length(windows) >= 1
    end

    test "skips evaluation with insufficient samples", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.3,
          sample_size: 100,
          window_duration_ms: 60_000
        )

      # Record only 5 comparisons (< sample_size)
      for i <- 1..5 do
        comparison = %{
          shadow_prediction: i * 1.0,
          ground_truth: (i + 0.2) * 1.0,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      {:ok, result} = DriftMonitor.evaluate_now(monitor)

      # Should indicate insufficient samples
      assert result.sample_count == 5
      assert result.status == :insufficient_samples
    end

    test "triggers quarantine on threshold exceeded", %{
      trainer: trainer,
      snapshot: snapshot,
      tenant_id: tenant_id
    } do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.1,
          sample_size: 10,
          quarantine_enabled: true
        )

      # Record comparisons with high drift
      for _ <- 1..10 do
        comparison = %{
          shadow_prediction: 1.0,
          ground_truth: 2.0,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      {:ok, result} = DriftMonitor.evaluate_now(monitor)

      # Drift = 1.0, threshold = 0.1, should trigger quarantine
      assert result.status == :quarantined

      # Verify UpmDriftWindow has quarantined status
      {:ok, windows} =
        UpmDriftWindow
        |> Ash.Query.filter(trainer_id == ^trainer.id and status == :quarantined)
        |> Ash.read(tenant: tenant_id)

      assert length(windows) >= 1
    end

    test "continues evaluation when quarantine disabled", %{
      trainer: trainer,
      snapshot: snapshot
    } do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.1,
          sample_size: 10,
          quarantine_enabled: false
        )

      # Record comparisons with high drift
      for _ <- 1..10 do
        comparison = %{
          shadow_prediction: 1.0,
          ground_truth: 2.0,
          metadata: %{}
        }

        :ok = DriftMonitor.record_comparison(monitor, comparison)
      end

      Process.sleep(50)

      {:ok, result} = DriftMonitor.evaluate_now(monitor)

      # Even with high drift, should not quarantine
      assert result.status == :completed
    end
  end

  describe "error handling" do
    test "handles nil predictions gracefully", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5
        )

      comparison = %{
        shadow_prediction: nil,
        ground_truth: 1.0,
        metadata: %{}
      }

      # Should not crash
      assert :ok = DriftMonitor.record_comparison(monitor, comparison)
      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      assert stats.sample_count >= 0
    end

    test "handles mismatched types in comparison", %{trainer: trainer, snapshot: snapshot} do
      {:ok, monitor} =
        DriftMonitor.start_link(
          trainer_id: trainer.id,
          snapshot_id: snapshot.id,
          drift_threshold: 0.5
        )

      comparison = %{
        shadow_prediction: "string_value",
        ground_truth: 123,
        metadata: %{}
      }

      # Should handle type mismatch gracefully
      assert :ok = DriftMonitor.record_comparison(monitor, comparison)
      Process.sleep(50)

      stats = DriftMonitor.get_stats(monitor)
      assert stats.sample_count == 1
    end
  end
end
