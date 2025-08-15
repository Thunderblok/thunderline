defmodule Thunderline.TelemetrySeeder do
  @moduledoc """
  Seeds telemetry data for testing and demonstration purposes.
  """

  require Logger

  def seed_sample_data do
    Logger.info("Seeding telemetry snapshot data...")

    # Create several sample telemetry snapshots
    snapshots = [
      create_window_snapshot(1),
      create_window_snapshot(2),
      create_window_snapshot(3),
      create_burst_snapshot(),
      create_anomaly_snapshot()
    ]

    case Enum.reduce(snapshots, {:ok, []}, &create_snapshot/2) do
      {:ok, created_snapshots} ->
        Logger.info("Successfully created #{length(created_snapshots)} telemetry snapshots")
        {:ok, created_snapshots}

      {:error, reason} ->
        Logger.error("Failed to seed telemetry data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_snapshot(snapshot_params, {:ok, acc}) do
    case Thunderlane.Resources.TelemetrySnapshot.create(snapshot_params) |> Ash.create() do
      {:ok, snapshot} -> {:ok, [snapshot | acc]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_snapshot(_snapshot_params, {:error, reason}), do: {:error, reason}

  defp create_window_snapshot(index) do
    base_time = System.system_time(:millisecond) - index * 10000

    %{
      coordinator_id: "dashboard-#{index}",
      snapshot_type: :window,
      window_start_ms: base_time,
      window_end_ms: base_time + 10000,
      window_duration_ms: 10000,
      total_events: :rand.uniform(1000) + 500,
      event_rate_per_second: :rand.uniform(50) + 10.0,
      burst_count: :rand.uniform(5),
      anti_bunching_effectiveness: :rand.uniform() * 0.8 + 0.2,
      displacement_mean: :rand.uniform() * 10.0,
      displacement_variance: :rand.uniform() * 5.0,
      tail_exponent: :rand.uniform() * 2.0 + 1.0,
      tail_fit_quality: :rand.uniform() * 0.5 + 0.5,
      latency_mean_us: :rand.uniform(5000) + 1000.0,
      latency_median_us: :rand.uniform(3000) + 800.0,
      latency_p90_us: :rand.uniform(8000) + 2000,
      latency_p95_us: :rand.uniform(12000) + 3000,
      latency_p99_us: :rand.uniform(20000) + 5000,
      latency_p999_us: :rand.uniform(50000) + 10000,
      latency_max_us: :rand.uniform(100_000) + 20000,
      queue_depth_mean: :rand.uniform() * 50.0,
      queue_depth_max: :rand.uniform(200) + 50,
      backpressure_events: :rand.uniform(10),
      dropped_events: :rand.uniform(5),
      cpu_usage_mean: :rand.uniform(80.0) + 10.0,
      memory_usage_mean_mb: :rand.uniform(500) + 100,
      memory_usage_max_mb: :rand.uniform(800) + 200,
      gc_count: :rand.uniform(50) + 10,
      gc_total_time_ms: :rand.uniform(1000) + 100,
      network_bytes_in: :rand.uniform(1_000_000) + 100_000,
      network_bytes_out: :rand.uniform(800_000) + 80000,
      coordination_messages: :rand.uniform(200) + 50,
      coordination_latency_us: :rand.uniform(5000) + 500,
      error_count: :rand.uniform(3),
      anomaly_score: :rand.uniform() * 0.3,
      anomaly_features: %{
        "latency_spike" => :rand.uniform() > 0.8,
        "memory_leak" => :rand.uniform() > 0.9,
        "queue_buildup" => :rand.uniform() > 0.7
      },
      metadata: %{
        "environment" => "development",
        "node" => Node.self(),
        "version" => "2.0.0"
      }
    }
  end

  defp create_burst_snapshot do
    %{
      coordinator_id: "burst-detector",
      snapshot_type: :burst,
      burst_count: :rand.uniform(20) + 5,
      anti_bunching_effectiveness: :rand.uniform() * 0.6 + 0.4,
      displacement_mean: :rand.uniform() * 15.0,
      tail_exponent: :rand.uniform() * 1.5 + 2.0,
      error_count: :rand.uniform(2),
      metadata: %{
        "burst_pattern" => "exponential",
        "trigger_event" => "system_load_spike"
      }
    }
  end

  defp create_anomaly_snapshot do
    %{
      coordinator_id: "anomaly-detector",
      snapshot_type: :anomaly,
      anomaly_score: :rand.uniform() * 0.7 + 0.3,
      anomaly_features: %{
        "cpu_spike" => true,
        "memory_pressure" => :rand.uniform() > 0.5,
        "network_congestion" => :rand.uniform() > 0.6,
        "coordination_delay" => :rand.uniform() > 0.7
      },
      error_count: :rand.uniform(8) + 2,
      latency_max_us: :rand.uniform(200_000) + 50000,
      queue_depth_max: :rand.uniform(500) + 100,
      cpu_usage_mean: :rand.uniform(30.0) + 70.0,
      metadata: %{
        "detected_by" => "ml_anomaly_detector",
        "confidence" => :rand.uniform() * 0.4 + 0.6,
        "severity" => "medium"
      }
    }
  end
end
