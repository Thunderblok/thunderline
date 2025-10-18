defmodule Thunderline.Thunderbolt.Resources.ChunkTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thunderbolt.Resources.Chunk
  alias Thunderline.Thunderbolt.Domain

  describe "chunk creation" do
    test "creates a chunk with valid attributes" do
      assert {:ok, chunk} =
               Chunk
               |> Ash.Changeset.for_create(:create_for_region, %{
                 start_q: 0,
                 start_r: 0,
                 end_q: 10,
                 end_r: 10,
                 z_level: 0,
                 total_capacity: 144
               })
               |> Ash.create(domain: Domain)

      assert chunk.start_q == 0
      assert chunk.start_r == 0
      assert chunk.end_q == 10
      assert chunk.end_r == 10
      assert chunk.total_capacity == 144
      assert chunk.state == :initializing
      assert chunk.active_count == 0
      assert chunk.dormant_count == 0
      assert chunk.health_status == :unknown
    end

    test "creates a chunk for a specific region" do
      assert {:ok, chunk} =
               Chunk
               |> Ash.Changeset.for_create(:create_for_region, %{
                 start_q: 5,
                 start_r: 10,
                 end_q: 15,
                 end_r: 20,
                 z_level: 0,
                 total_capacity: 144
               })
               |> Ash.create(domain: Domain)

      assert chunk.start_q == 5
      assert chunk.start_r == 10
      assert chunk.state == :initializing
    end

    test "validates required fields" do
      assert {:error, %Ash.Error.Invalid{}} =
               Chunk
               |> Ash.Changeset.for_create(:create_for_region, %{
                 start_q: 0,
                 start_r: 0
                 # Missing required fields: end_q, end_r, z_level, total_capacity
               })
               |> Ash.create(domain: Domain)
    end

    test "requires minimum total capacity" do
      assert {:error, %Ash.Error.Invalid{}} =
               Chunk
               |> Ash.Changeset.for_create(:create, %{
                 hex_q: 0,
                 hex_r: 0,
                 hex_s: 0,
                 total_capacity: 50
               })
               |> Ash.create(domain: Domain)
    end
  end

  describe "state machine - initialization → dormant" do
    setup do
      {:ok, chunk} =
        Chunk
        |> Ash.Changeset.for_create(:create, %{
          hex_q: 1,
          hex_r: 2,
          hex_s: -3,
          total_capacity: 144
        })
        |> Ash.create(domain: Domain)

      %{chunk: chunk}
    end

    test "initializes chunk from initializing state", %{chunk: chunk} do
      assert chunk.state == :initializing

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:initialize)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end

    test "cannot initialize from non-initializing state", %{chunk: chunk} do
      # First transition to dormant
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:initialize)
        |> Ash.update(domain: Domain)

      # Try to initialize again
      assert {:error, %Ash.Error.Invalid{}} =
               chunk
               |> Ash.Changeset.for_update(:initialize)
               |> Ash.update(domain: Domain)
    end
  end

  describe "state machine - dormant → active" do
    setup do
      {:ok, chunk} = create_dormant_chunk()
      %{chunk: chunk}
    end

    test "activates chunk from dormant state", %{chunk: chunk} do
      assert chunk.state == :dormant

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:activate)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :active
    end

    test "cannot activate from non-dormant state", %{chunk: chunk} do
      # First activate
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:activate)
        |> Ash.update(domain: Domain)

      # Try to activate again
      assert {:error, %Ash.Error.Invalid{}} =
               chunk
               |> Ash.Changeset.for_update(:activate)
               |> Ash.update(domain: Domain)
    end
  end

  describe "state machine - active → deactivating → dormant" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "deactivates chunk from active state", %{chunk: chunk} do
      assert chunk.state == :active

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:deactivate)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :deactivating
    end

    test "completes deactivation to dormant state", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:deactivate)
        |> Ash.update(domain: Domain)

      assert chunk.state == :deactivating

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:deactivation_complete)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end
  end

  describe "state machine - active → optimizing" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "begins optimization from active state", %{chunk: chunk} do
      assert chunk.state == :active

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:begin_optimization)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :optimizing
    end

    test "completes optimization with high score → dormant", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_optimization)
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:optimization_complete, %{
                 optimization_score: Decimal.new("0.9")
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
      assert Decimal.compare(updated_chunk.optimization_score, Decimal.new("0.8")) == :gt
      assert updated_chunk.last_optimization != nil
    end

    test "completes optimization with low score → active", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_optimization)
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:optimization_complete, %{
                 optimization_score: Decimal.new("0.5")
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :active
      assert Decimal.compare(updated_chunk.optimization_score, Decimal.new("0.8")) == :lt
    end

    test "completes optimization with nil score → active", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_optimization)
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:optimization_complete, %{})
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :active
      # Score stays at default value since no new score was provided
      assert Decimal.compare(updated_chunk.optimization_score, Decimal.new("0.5")) == :eq
    end
  end

  describe "state machine - active → maintenance" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "enters maintenance from active state", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:enter_maintenance)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :maintenance
    end

    test "exits maintenance to dormant state", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:enter_maintenance)
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:exit_maintenance)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end
  end

  describe "state machine - active → scaling" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "begins scaling from active state", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:begin_scaling, %{
                 total_capacity: 288
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :scaling
      assert updated_chunk.total_capacity == 288
    end

    test "completes scaling with active chunks → active state", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_scaling, %{total_capacity: 288})
        |> Ash.update(domain: Domain)

      # Set active_count > 0
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:scaling_complete, %{
          total_capacity: 288,
          resource_allocation: %{active_count: 50}
        })
        |> Ash.update(domain: Domain)

      # Manually set active_count for test (since resource_allocation is a map)
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:update, %{active_count: 50})
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:scaling_complete, %{})
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :active
    end

    test "completes scaling with no active chunks → dormant state", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_scaling, %{total_capacity: 288})
        |> Ash.update(domain: Domain)

      # Ensure active_count is 0
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:update, %{active_count: 0})
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:scaling_complete, %{})
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end
  end

  describe "state machine - failure states" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "marks chunk as failed from various states", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:mark_failed, %{
                 error_info: %{reason: "test failure"}
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :failed
    end

    test "recovers from failed state to dormant", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:mark_failed, %{
          error_info: %{reason: "test failure"}
        })
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:recover)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end

    test "force resets chunk to initializing", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:force_reset)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :initializing
    end
  end

  describe "state machine - emergency and shutdown" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "emergency stops chunk from any state", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:emergency_stop, %{
                 error_info: %{reason: "emergency"}
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :emergency_stopped
    end

    test "recovers from emergency stop", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:emergency_stop, %{
          error_info: %{reason: "emergency"}
        })
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:emergency_recover)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :dormant
    end

    test "begins shutdown from active state", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:begin_shutdown)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :shutting_down
    end

    test "completes shutdown to destroyed", %{chunk: chunk} do
      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_shutdown)
        |> Ash.update(domain: Domain)

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:shutdown_complete)
               |> Ash.update(domain: Domain)

      assert updated_chunk.state == :destroyed
    end
  end

  describe "health monitoring" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "updates health status", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:update_health, %{
                 health_status: :healthy,
                 health_metrics: %{cpu: 50, memory: 60}
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.health_status == :healthy
      assert updated_chunk.health_metrics == %{cpu: 50, memory: 60}
    end

    test "tracks degraded health", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:update_health, %{
                 health_status: :degraded
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.health_status == :degraded
    end

    test "tracks unhealthy status", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:update_health, %{
                 health_status: :unhealthy
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.health_status == :unhealthy
    end
  end

  describe "resource allocation" do
    setup do
      {:ok, chunk} = create_active_chunk()
      %{chunk: chunk}
    end

    test "updates resource allocation", %{chunk: chunk} do
      allocation = %{
        cpu_cores: 4,
        memory_mb: 8192,
        active_count: 72
      }

      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:update, %{
                 resource_allocation: allocation
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.resource_allocation == allocation
    end

    test "tracks active and dormant counts", %{chunk: chunk} do
      assert {:ok, updated_chunk} =
               chunk
               |> Ash.Changeset.for_update(:update, %{
                 active_count: 72,
                 dormant_count: 72
               })
               |> Ash.update(domain: Domain)

      assert updated_chunk.active_count == 72
      assert updated_chunk.dormant_count == 72
      assert updated_chunk.active_count + updated_chunk.dormant_count == 144
    end
  end

  describe "pubsub notifications" do
    setup do
      # Subscribe to PubSub events (use the application PubSub name)
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbolt:chunk:created")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbolt:chunk:created")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbolt:chunk:activated")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbolt:chunk:optimized")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbolt:chunk:health_updated")

      :ok
    end

    test "publishes event on chunk creation" do
      {:ok, chunk} =
        Chunk
        |> Ash.Changeset.for_create(:create_for_region, %{
          start_q: 0,
          start_r: 0,
          end_q: 10,
          end_r: 10,
          z_level: 0,
          total_capacity: 144
        })
        |> Ash.create(domain: Domain)

      # Note: PubSub events are async, may need small delay
      assert_receive {:published, "thunderbolt:chunk:created", _}, 100
    end

    test "publishes event on chunk activation" do
      {:ok, chunk} = create_dormant_chunk()

      {:ok, _} =
        chunk
        |> Ash.Changeset.for_update(:activate)
        |> Ash.update(domain: Domain)

      assert_receive {:published, "thunderbolt:chunk:activated", _}, 100
    end

    test "publishes event on optimization complete" do
      {:ok, chunk} = create_active_chunk()

      {:ok, chunk} =
        chunk
        |> Ash.Changeset.for_update(:begin_optimization)
        |> Ash.update(domain: Domain)

      {:ok, _} =
        chunk
        |> Ash.Changeset.for_update(:optimization_complete, %{
          optimization_score: Decimal.new("0.9")
        })
        |> Ash.update(domain: Domain)

      assert_receive {:published, "thunderbolt:chunk:optimized", _}, 100
    end

    test "publishes event on health update" do
      {:ok, chunk} = create_active_chunk()

      {:ok, _} =
        chunk
        |> Ash.Changeset.for_update(:update_health, %{
          health_status: :healthy
        })
        |> Ash.update(domain: Domain)

      assert_receive {:published, "thunderbolt:chunk:health_updated", _}, 100
    end
  end

  describe "read actions" do
    test "lists all chunks" do
      # Create a few chunks
      {:ok, _} = create_dormant_chunk()
      {:ok, _} = create_dormant_chunk()

      assert {:ok, chunks} = Ash.read(Chunk, domain: Domain)
      assert length(chunks) >= 2
    end

    test "reads chunk by id" do
      {:ok, chunk} = create_dormant_chunk()

      assert {:ok, found_chunk} = Ash.get(Chunk, chunk.id, domain: Domain)
      assert found_chunk.id == chunk.id
    end
  end

  describe "validations" do
    test "validates total capacity is positive" do
      assert {:error, %Ash.Error.Invalid{}} =
               Chunk
               |> Ash.Changeset.for_create(:create, %{
                 hex_q: 0,
                 hex_r: 0,
                 hex_s: 0,
                 total_capacity: -100
               })
               |> Ash.create(domain: Domain)
    end

    test "validates active_count does not exceed total_capacity" do
      {:ok, chunk} = create_dormant_chunk()

      assert {:error, %Ash.Error.Invalid{}} =
               chunk
               |> Ash.Changeset.for_update(:update, %{
                 active_count: 200
               })
               |> Ash.update(domain: Domain)
    end

    test "validates health_status is valid value" do
      {:ok, chunk} = create_dormant_chunk()

      # This should fail because :invalid is not in the allowed values
      assert {:error, %Ash.Error.Invalid{}} =
               chunk
               |> Ash.Changeset.for_update(:update, %{
                 health_status: :invalid
               })
               |> Ash.update(domain: Domain)
    end
  end

  # Helper functions for creating chunks in specific states

  defp create_dormant_chunk do
    {:ok, chunk} =
      Chunk
      |> Ash.Changeset.for_create(:create_for_region, %{
        start_q: 0,
        start_r: 0,
        end_q: 10,
        end_r: 10,
        z_level: 0,
        total_capacity: 144
      })
      |> Ash.create(domain: Domain)

    chunk
    |> Ash.Changeset.for_update(:initialize)
    |> Ash.update(domain: Domain)
  end

  defp create_active_chunk do
    {:ok, chunk} = create_dormant_chunk()

    chunk
    |> Ash.Changeset.for_update(:activate)
    |> Ash.update(domain: Domain)
  end
end
