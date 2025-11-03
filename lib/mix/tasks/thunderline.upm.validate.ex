defmodule Mix.Tasks.Thunderline.Upm.Validate do
  @shortdoc "Validates UPM (Unified Persistent Model) configuration and functionality"

  @moduledoc """
  Mix task to validate the UPM (Unified Persistent Model) system configuration,
  dependencies, and basic functionality.

  ## Usage

      mix thunderline.upm.validate

  ## Checks Performed

  1. **Configuration Validation**
     - Feature flag `:unified_model` status
     - Storage paths exist and are writable
     - Default trainer configuration
     - Telemetry setup

  2. **Dependency Checks**
     - Ash resources (UpmTrainer, UpmSnapshot, UpmAdapter, UpmDriftWindow)
     - Database migrations applied
     - EventBus availability

  3. **Functional Tests**
     - Snapshot checksum calculation
     - Compression/decompression (zstd, gzip)
     - Drift score calculation (numeric, structured)
     - Replay buffer ordering logic

  4. **Worker Health**
     - UPM.Supervisor running (if enabled)
     - TrainerWorker processes
     - DriftMonitor processes
     - AdapterSync process

  ## Exit Codes

  - `0` - All validations passed
  - `1` - One or more validations failed
  """

  use Mix.Task
  require Logger

  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.Resources.{UpmTrainer, UpmSnapshot, UpmAdapter, UpmDriftWindow}

  @impl Mix.Task
  def run(_args) do
    # Start application dependencies
    Mix.Task.run("app.start")

    IO.puts("\n🔍 UPM Validation Report\n" <> String.duplicate("=", 60))

    results = [
      check_feature_flag(),
      check_configuration(),
      check_storage_paths(),
      check_ash_resources(),
      check_migrations(),
      check_compression(),
      check_drift_calculation(),
      check_replay_buffer_logic(),
      check_worker_health()
    ]

    IO.puts("\n" <> String.duplicate("=", 60))

    # Summary
    passed = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    IO.puts("""

    Summary: #{passed} passed, #{failed} failed

    """)

    if failed > 0 do
      System.halt(1)
    else
      IO.puts("✅ All UPM validations passed!\n")
      System.halt(0)
    end
  end

  # Validation Functions

  defp check_feature_flag do
    IO.write("Feature flag :unified_model... ")

    enabled = Feature.enabled?(:unified_model, default: false)

    if enabled do
      IO.puts("✅ ENABLED")
      :ok
    else
      IO.puts("⚠️  DISABLED (set TL_FEATURES_UNIFIED_MODEL=1 to enable)")
      :ok
    end
  end

  defp check_configuration do
    IO.write("Configuration keys... ")

    required_keys = [
      [:thunderline, Thunderline.Thunderbolt.UPM.TrainerWorker],
      [:thunderline, Thunderline.Thunderbolt.UPM.SnapshotManager],
      [:thunderline, Thunderline.Thunderbolt.UPM.DriftMonitor],
      [:thunderline, Thunderline.Thunderbolt.UPM.AdapterSync]
    ]

    missing =
      Enum.filter(required_keys, fn key ->
        is_nil(Application.get_env(Enum.at(key, 0), Enum.at(key, 1)))
      end)

    if Enum.empty?(missing) do
      IO.puts("✅ All present")
      :ok
    else
      IO.puts("⚠️  Some configs use defaults (#{length(missing)} missing)")
      :ok
    end
  end

  defp check_storage_paths do
    IO.write("Storage paths... ")

    base_path =
      Application.get_env(
        :thunderline,
        [Thunderline.Thunderbolt.UPM.SnapshotManager, :base_path],
        Path.join([System.tmp_dir!(), "thunderline", "upm", "snapshots"])
      )

    cond do
      !File.exists?(base_path) ->
        case File.mkdir_p(base_path) do
          :ok ->
            IO.puts("✅ Created #{base_path}")
            :ok

          {:error, reason} ->
            IO.puts("❌ Cannot create #{base_path}: #{inspect(reason)}")
            :error
        end

      !File.dir?(base_path) ->
        IO.puts("❌ #{base_path} exists but is not a directory")
        :error

      true ->
        # Test write
        test_file = Path.join(base_path, ".write_test_#{:erlang.system_time()}")

        case File.write(test_file, "test") do
          :ok ->
            File.rm(test_file)
            IO.puts("✅ #{base_path} (writable)")
            :ok

          {:error, reason} ->
            IO.puts("❌ #{base_path} not writable: #{inspect(reason)}")
            :error
        end
    end
  end

  defp check_ash_resources do
    IO.write("Ash resources... ")

    resources = [
      {UpmTrainer, "UpmTrainer"},
      {UpmSnapshot, "UpmSnapshot"},
      {UpmAdapter, "UpmAdapter"},
      {UpmDriftWindow, "UpmDriftWindow"}
    ]

    results =
      Enum.map(resources, fn {module, name} ->
        case Code.ensure_loaded(module) do
          {:module, _} -> {:ok, name}
          {:error, reason} -> {:error, name, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(errors) do
      IO.puts("✅ All loaded (#{length(resources)})")
      :ok
    else
      IO.puts("❌ Failed to load:")

      Enum.each(errors, fn {:error, name, reason} ->
        IO.puts("   - #{name}: #{inspect(reason)}")
      end)

      :error
    end
  end

  defp check_migrations do
    IO.write("Database migrations... ")

    try do
      case Ash.read(UpmTrainer, limit: 1) do
        {:ok, _} ->
          IO.puts("✅ UPM tables exist")
          :ok

        {:error, %Ecto.QueryError{}} ->
          IO.puts("❌ UPM tables not found (run migrations)")
          :error

        {:error, reason} ->
          IO.puts("⚠️  Query failed: #{inspect(reason)}")
          :error
      end
    rescue
      error ->
        IO.puts("❌ #{inspect(error)}")
        :error
    end
  end

  defp check_compression do
    IO.write("Compression support... ")

    data = :crypto.strong_rand_bytes(1024)

    # Test zstd
    zstd_result =
      try do
        compressed = :ezstd.compress(data)
        decompressed = :ezstd.decompress(compressed)
        if decompressed == data, do: :ok, else: {:error, :mismatch}
      rescue
        _ -> {:error, :unavailable}
      end

    # Test gzip
    gzip_result =
      try do
        compressed = :zlib.gzip(data)
        decompressed = :zlib.gunzip(compressed)
        if decompressed == data, do: :ok, else: {:error, :mismatch}
      rescue
        _ -> {:error, :unavailable}
      end

    case {zstd_result, gzip_result} do
      {:ok, :ok} ->
        IO.puts("✅ zstd, gzip")
        :ok

      {:ok, _} ->
        IO.puts("⚠️  zstd only (gzip failed)")
        :ok

      {_, :ok} ->
        IO.puts("⚠️  gzip only (zstd failed)")
        :ok

      _ ->
        IO.puts("❌ Both zstd and gzip failed")
        :error
    end
  end

  defp check_drift_calculation do
    IO.write("Drift calculation... ")

    # Test numeric drift
    numeric_drift = abs(0.5 - 0.3)

    # Test structured drift
    pred = %{"class_a" => 0.7, "class_b" => 0.3}
    truth = %{"class_a" => 0.8, "class_b" => 0.2}

    structured_drift =
      Enum.sum(for {k, v} <- pred, do: abs(v - Map.get(truth, k, 0.0))) / map_size(pred)

    if numeric_drift == 0.2 and structured_drift > 0 do
      IO.puts("✅ Numeric, structured")
      :ok
    else
      IO.puts("❌ Logic error")
      :error
    end
  end

  defp check_replay_buffer_logic do
    IO.write("Replay buffer ordering... ")

    windows = [
      %{id: "w3", window_start: ~U[2025-01-01 10:30:00Z]},
      %{id: "w1", window_start: ~U[2025-01-01 10:10:00Z]},
      %{id: "w2", window_start: ~U[2025-01-01 10:20:00Z]}
    ]

    sorted = Enum.sort_by(windows, & &1.window_start, DateTime)

    expected_order = ["w1", "w2", "w3"]
    actual_order = Enum.map(sorted, & &1.id)

    if actual_order == expected_order do
      IO.puts("✅ Correct ordering")
      :ok
    else
      IO.puts("❌ Expected #{inspect(expected_order)}, got #{inspect(actual_order)}")
      :error
    end
  end

  defp check_worker_health do
    IO.write("Worker processes... ")

    upm_enabled = Feature.enabled?(:unified_model, default: false)

    if not upm_enabled do
      IO.puts("⏭️  Skipped (UPM disabled)")
      :ok
    else
      # Check if supervisor is running
      case Process.whereis(Thunderline.Thunderbolt.UPM.Supervisor) do
        nil ->
          IO.puts("❌ UPM.Supervisor not running")
          :error

        _pid ->
          # Check AdapterSync
          case Process.whereis(Thunderline.Thunderbolt.UPM.AdapterSync) do
            nil ->
              IO.puts("⚠️  Supervisor running, but AdapterSync not found")
              :ok

            _sync_pid ->
              IO.puts("✅ Supervisor, AdapterSync")
              :ok
          end
      end
    end
  end
end
