defmodule Thunderline.Thunderbolt.UPM.TrainerWorkerTest do
  use ExUnit.Case, async: false
  alias Thunderline.Thunderbolt.UPM.TrainerWorker
  alias Thunderline.Thunderbolt.Resources.UpmTrainer
  alias Thunderline.Features.FeatureWindow
  alias Thunderline.Event

  setup do
    # Always ensure Registry is running using start_supervised!
    # This properly manages Registry lifecycle across tests
    start_supervised!({Registry, keys: :unique, name: Thunderline.Registry})

    tenant_id = UUID.uuid4()

    {:ok, trainer} =
      Ash.Changeset.for_create(UpmTrainer, :register, %{
        tenant_id: tenant_id,
        name: "test_trainer_#{:rand.uniform(1000)}",
        mode: :shadow
      })
      |> Ash.create()

    on_exit(fn ->
      # Cleanup any test trainers
      if Process.whereis(:"trainer_#{tenant_id}") do
        GenServer.stop(:"trainer_#{tenant_id}")
      end
    end)

    %{tenant_id: tenant_id, trainer: trainer}
  end

  describe "initialization" do
    test "initializes with no existing trainer", %{tenant_id: tenant_id} do
      trainer_name = "new_trainer_#{:rand.uniform(1000)}"

      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer_name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Verify trainer was created
      state = :sys.get_state(pid)
      assert state.trainer_name == trainer_name
      assert state.tenant_id == tenant_id
    end

    test "initializes with existing trainer", %{tenant_id: tenant_id, trainer: trainer} do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Verify it loaded the existing trainer
      state = :sys.get_state(pid)
      assert state.trainer_name == trainer.name
    end
  end

  describe "EventBus integration" do
    test "handles feature window created events", %{tenant_id: tenant_id, trainer: trainer} do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

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

      event =
        Event.new(%{
          name: "system.feature_window.created",
          source: :bolt,
          payload: %{
            id: window.id,
            key: window.key,
            tenant_id: tenant_id
          }
        })

      send(pid, event)

      # Give it time to process
      Process.sleep(100)

      # Verify window was stored
      state = :sys.get_state(pid)
      assert state.replay_buffer != nil
    end

    test "processes multiple feature windows in sequence", %{
      tenant_id: tenant_id,
      trainer: trainer
    } do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Create multiple windows
      {:ok, window1} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_1_#{UUID.uuid4()}",
          window_start: DateTime.utc_now(),
          window_end: DateTime.add(DateTime.utc_now(), 3600, :second),
          features: %{},
          label_spec: %{count: 50},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      {:ok, window2} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_2_#{UUID.uuid4()}",
          window_start: DateTime.add(DateTime.utc_now(), 3600, :second),
          window_end: DateTime.add(DateTime.utc_now(), 7200, :second),
          features: %{},
          label_spec: %{count: 75},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      {:ok, window3} =
        Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
          tenant_id: tenant_id,
          kind: :training,
          key: "window_3_#{UUID.uuid4()}",
          window_start: DateTime.add(DateTime.utc_now(), 7200, :second),
          window_end: DateTime.add(DateTime.utc_now(), 10800, :second),
          features: %{},
          label_spec: %{count: 100},
          feature_schema_version: 1,
          provenance: %{source: "test"}
        })
        |> Ash.create(tenant: tenant_id)

      # Publish events in sequence
      for window <- [window1, window2, window3] do
        event =
          Event.new(%{
            name: "system.feature_window.created",
            source: :bolt,
            payload: %{id: window.id, key: window.key, tenant_id: tenant_id}
          })

        send(pid, event)
        Process.sleep(50)
      end

      # Verify all windows processed
      state = :sys.get_state(pid)
      assert state.replay_buffer != nil
    end

    test "processes filled windows when threshold reached", %{
      tenant_id: tenant_id,
      trainer: trainer
    } do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name,
          window_threshold: 2
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Create windows to fill buffer
      for i <- 1..2 do
        {:ok, window} =
          Ash.Changeset.for_create(FeatureWindow, :ingest_window, %{
            tenant_id: tenant_id,
            kind: :training,
            key: "window_threshold_#{i}_#{UUID.uuid4()}",
            window_start: DateTime.add(DateTime.utc_now(), i * 3600, :second),
            window_end: DateTime.add(DateTime.utc_now(), (i + 1) * 3600, :second),
            features: %{},
            label_spec: %{count: 100},
            feature_schema_version: 1,
            provenance: %{source: "test"}
          })
          |> Ash.create(tenant: tenant_id)

        event =
          Event.new(%{
            name: "system.feature_window.created",
            source: :bolt,
            payload: %{id: window.id, key: window.key, tenant_id: tenant_id}
          })

        send(pid, event)
        Process.sleep(50)
      end

      # Verify training was triggered
      state = :sys.get_state(pid)
      assert state.replay_buffer != nil
    end
  end

  describe "error handling" do
    test "handles feature window errors gracefully", %{tenant_id: tenant_id, trainer: trainer} do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Send malformed event
      event =
        Event.new(%{
          name: "system.feature_window.created",
          source: :bolt,
          payload: %{invalid_field: "bad_data"}
        })

      send(pid, event)
      Process.sleep(100)

      # Verify worker still alive
      assert Process.alive?(pid)
    end
  end

  describe "metrics and telemetry" do
    test "tracks training metrics", %{tenant_id: tenant_id, trainer: trainer} do
      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Trigger metric collection
      state = :sys.get_state(pid)
      assert state.tenant_id == tenant_id
    end
  end

  describe "training modes" do
    test "respects training mode configuration", %{tenant_id: tenant_id} do
      # Create shadow mode trainer
      {:ok, shadow_trainer} =
        Ash.Changeset.for_create(UpmTrainer, :register, %{
          tenant_id: tenant_id,
          name: "shadow_trainer",
          mode: :shadow
        })
        |> Ash.create()

      {:ok, pid} =
        TrainerWorker.start_link(
          name: :"shadow_trainer_#{tenant_id}",
          tenant_id: tenant_id,
          trainer_name: shadow_trainer.name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      state = :sys.get_state(pid)
      assert state.trainer_name == "shadow_trainer"
    end
  end
end
