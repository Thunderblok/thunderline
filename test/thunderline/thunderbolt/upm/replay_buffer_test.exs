defmodule Thunderline.Thunderbolt.Upm.ReplayBufferTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.ReplayBuffer
  alias Thunderline.Thunderbolt.Resources.UpmTrainer
  alias Thunderline.Thunderflow.Features.FeatureWindow

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

    {:ok, trainer: trainer, tenant_id: tenant_id}
  end

  describe "initialization" do
    test "initializes with correct capacity", %{trainer: trainer} do
      {:ok, buffer} =
        ReplayBuffer.start_link(
          trainer_id: trainer.id,
          max_buffer_size: 500,
          release_delay_ms: 1000
        )

      stats = ReplayBuffer.get_stats(buffer)

      assert stats.trainer_id == trainer.id
      assert stats.max_buffer_size == 500
      assert stats.buffer_size == 0
      assert stats.processed_count == 0
    end

    test "starts empty buffer", %{trainer: trainer} do
      {:ok, buffer} = ReplayBuffer.start_link(trainer_id: trainer.id)

      stats = ReplayBuffer.get_stats(buffer)

      assert stats.buffer_size == 0
      assert stats.oldest_buffered == nil
    end
  end

  describe "window storage" do
    test "stores window in buffer", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} = ReplayBuffer.start_link(trainer_id: trainer.id)

      # Create a feature window
      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      # Add to buffer
      payload = %{
        "window_id" => window.id,
        "window_start" => DateTime.to_iso8601(window.window_start),
        "tenant_id" => tenant_id
      }

      :ok = ReplayBuffer.add(buffer, window.id, payload)

      # Give async cast time to process
      Process.sleep(50)

      stats = ReplayBuffer.get_stats(buffer)
      assert stats.buffer_size == 1
    end

    test "retrieves stored windows in order", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} =
        ReplayBuffer.start_link(
          trainer_id: trainer.id,
          release_delay_ms: 10_000
        )

      # Register trainer to receive messages
      Registry.register(Thunderline.Registry, {:trainer, trainer.id}, nil)

      # Create 3 windows with different timestamps
      base_time = DateTime.utc_now()

      windows =
        for i <- [0, 1, 2] do
          {:ok, window} =
            Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
              tenant_id: tenant_id,
              kind: :training,
              key: "window_#{i}_#{UUID.uuid4()}",
              window_start: DateTime.add(base_time, i * 60, :second),
              window_end: DateTime.add(base_time, (i + 1) * 60, :second),
              features: %{},
              label_spec: %{count: 100},
              feature_schema_version: 1,
              provenance: %{source: "test"}
            })
            |> Ash.create(tenant: tenant_id)

          window
        end

      # Add windows out of order (2, 0, 1)
      for window <- Enum.shuffle(windows) do
        payload = %{
          "window_id" => window.id,
          "window_start" => DateTime.to_iso8601(window.window_start),
          "tenant_id" => tenant_id
        }

        ReplayBuffer.add(buffer, window.id, payload)
      end

      # Flush to trigger release
      :ok = ReplayBuffer.flush(buffer)

      # Should receive windows in order
      received_ids =
        for _ <- 1..3 do
          receive do
            {:replay_buffer, :ready, window_id} -> window_id
          after
            1000 -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      # Verify we got all windows
      assert length(received_ids) == 3

      # Verify they came in chronological order
      expected_order = Enum.map(windows, & &1.id)
      assert received_ids == expected_order
    end

    test "handles buffer capacity limit", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} =
        ReplayBuffer.start_link(
          trainer_id: trainer.id,
          max_buffer_size: 2
        )

      # Try to add 3 windows
      for i <- 1..3 do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "window_#{i}_#{UUID.uuid4()}",
            window_start: DateTime.utc_now(),
            window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
            features: %{},
            label_spec: %{count: 100},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        payload = %{
          "window_id" => window.id,
          "window_start" => DateTime.to_iso8601(window.window_start)
        }

        ReplayBuffer.add(buffer, window.id, payload)
      end

      Process.sleep(50)

      stats = ReplayBuffer.get_stats(buffer)
      # Should only have 2 windows (capacity limit)
      assert stats.buffer_size <= 2
    end

    test "de-duplicates windows by ID", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} = ReplayBuffer.start_link(trainer_id: trainer.id)

      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      payload = %{
        "window_id" => window.id,
        "window_start" => DateTime.to_iso8601(window.window_start)
      }

      # Add same window twice
      ReplayBuffer.add(buffer, window.id, payload)
      ReplayBuffer.add(buffer, window.id, payload)

      Process.sleep(50)

      stats = ReplayBuffer.get_stats(buffer)
      # Should only have 1 window (deduplicated)
      assert stats.buffer_size == 1
    end
  end

  describe "release mechanism" do
    test "releases windows on timer", %{trainer: trainer, tenant_id: tenant_id} do
      # Short release delay for testing
      {:ok, buffer} =
        ReplayBuffer.start_link(
          trainer_id: trainer.id,
          release_delay_ms: 100
        )

      Registry.register(Thunderline.Registry, {:trainer, trainer.id}, nil)

      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      payload = %{
        "window_id" => window.id,
        "window_start" => DateTime.to_iso8601(window.window_start)
      }

      ReplayBuffer.add(buffer, window.id, payload)

      # Wait for timer to trigger
      window_id = window.id
      assert_receive {:replay_buffer, :ready, ^window_id}, 500
    end

    test "releases windows on manual flush", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} =
        ReplayBuffer.start_link(
          trainer_id: trainer.id,
          release_delay_ms: 10_000
        )

      Registry.register(Thunderline.Registry, {:trainer, trainer.id}, nil)

      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      payload = %{
        "window_id" => window.id,
        "window_start" => DateTime.to_iso8601(window.window_start)
      }

      ReplayBuffer.add(buffer, window.id, payload)
      Process.sleep(50)

      # Force flush
      :ok = ReplayBuffer.flush(buffer)

      # Should receive window immediately
      window_id = window.id
      assert_receive {:replay_buffer, :ready, ^window_id}, 100
    end
  end

  describe "error handling" do
    test "handles invalid datetime formats gracefully", %{trainer: trainer} do
      {:ok, buffer} = ReplayBuffer.start_link(trainer_id: trainer.id)

      payload = %{
        "window_id" => UUID.uuid4(),
        "window_start" => "invalid-datetime"
      }

      # Should not crash
      assert :ok = ReplayBuffer.add(buffer, UUID.uuid4(), payload)
      Process.sleep(50)

      # Buffer should handle gracefully
      stats = ReplayBuffer.get_stats(buffer)
      assert stats.buffer_size == 1
    end

    test "recovers from missing trainer registration", %{trainer: trainer, tenant_id: tenant_id} do
      {:ok, buffer} = ReplayBuffer.start_link(trainer_id: trainer.id)

      # Don't register trainer - messages will be dropped with warning

      {:ok, window} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      payload = %{
        "window_id" => window.id,
        "window_start" => DateTime.to_iso8601(window.window_start)
      }

      ReplayBuffer.add(buffer, window.id, payload)

      # Flush (will log warning but not crash)
      :ok = ReplayBuffer.flush(buffer)

      # Buffer should be empty after flush attempt
      stats = ReplayBuffer.get_stats(buffer)
      assert stats.buffer_size == 0
    end
  end
end
