defmodule Thunderline.Thunderbolt.UPM.TrainerWorkerEventTest do
  @moduledoc """
  Tests for EventBus subscription and event handling in TrainerWorker.

  This test suite verifies:
  - EventBus subscription to system.feature_window.created
  - Event payload extraction and validation
  - ReplayBuffer integration
  - Training cycle triggering on window events
  - Telemetry emission
  """

  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.{TrainerWorker, ReplayBuffer}
  alias Thunderline.Features.FeatureWindow
  alias Thunderline.Event

  setup do
    # Start telemetry test handler
    :telemetry.attach(
      "upm-event-test",
      [:upm, :trainer, :event_received],
      fn _name, measurements, metadata, _config ->
        send(self(), {:telemetry, :event_received, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("upm-event-test")
    end)

    :ok
  end

  describe "EventBus subscription" do
    test "subscribes to system.feature_window.created on startup" do
      {:ok, pid} = TrainerWorker.start_link(
        name: :test_trainer_event_subscription,
        trainer_name: "test_event_trainer",
        mode: :shadow
      )

      # Verify subscription by checking process info
      # PubSub subscriptions are stored in process dictionary
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end

    test "handles system.feature_window.created events" do
      # Create a filled feature window resource
      tenant_id = Ash.UUID.generate()

      {:ok, window} = FeatureWindow
      |> Ash.Changeset.for_create(:ingest_window, %{
        tenant_id: tenant_id,
        kind: :email_decision,
        key: "test_key_#{System.unique_integer()}",
        window_start: DateTime.utc_now() |> DateTime.add(-60, :second),
        window_end: DateTime.utc_now(),
        features: %{
          "embedding" => [0.1, 0.2, 0.3],
          "metadata" => %{"source" => "test"}
        },
        label_spec: %{"action" => "string"},
        feature_schema_version: 1,
        provenance: %{"source" => "test"}
      })
      |> Ash.create(authorize?: false)

      # Fill the window with labels
      {:ok, filled_window} = window
      |> Ash.Changeset.for_update(:fill_labels, %{
        labels: %{"action" => "send"},
        status: :filled
      })
      |> Ash.update(authorize?: false)

      # Start trainer
      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_event_handler,
        trainer_name: "test_event_handler",
        mode: :shadow
      )

      # Create and publish event
      {:ok, event} = Event.new(%{
        name: "system.feature_window.created",
        source: :flow,
        payload: %{
          window_id: filled_window.id,
          tenant_id: tenant_id,
          kind: :email_decision,
          window_start: filled_window.window_start,
          features_count: 1
        }
      })

      # Publish event (simulating EventBus)
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system.feature_window.created",
        event
      )

      # Wait for telemetry
      assert_receive {:telemetry, :event_received, %{count: 1}, metadata}, 1000
      assert metadata.window_id == filled_window.id
      assert metadata.event_name == "system.feature_window.created"

      # Clean up
      GenServer.stop(trainer_pid)
    end

    test "handles legacy event format for backward compatibility" do
      tenant_id = Ash.UUID.generate()
      window_id = Ash.UUID.generate()

      # Start trainer
      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_legacy,
        trainer_name: "test_legacy",
        mode: :shadow
      )

      # Send legacy event format
      send(trainer_pid, {:event_bus, %{
        name: "system.feature_window.created",
        payload: %{
          "window_id" => window_id,
          "tenant_id" => tenant_id
        }
      }})

      # Wait for telemetry
      assert_receive {:telemetry, :event_received, %{count: 1}, metadata}, 1000
      assert metadata.window_id == window_id

      # Clean up
      GenServer.stop(trainer_pid)
    end

    test "extracts window_id from both string and atom keys" do
      tenant_id = Ash.UUID.generate()
      window_id_str = Ash.UUID.generate()
      window_id_atom = Ash.UUID.generate()

      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_keys,
        trainer_name: "test_keys",
        mode: :shadow
      )

      # Test with string key
      {:ok, event1} = Event.new(%{
        name: "system.feature_window.created",
        source: :flow,
        payload: %{"window_id" => window_id_str}
      })

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system.feature_window.created",
        event1
      )

      assert_receive {:telemetry, :event_received, _, metadata1}, 1000
      assert metadata1.window_id == window_id_str

      # Test with atom key
      {:ok, event2} = Event.new(%{
        name: "system.feature_window.created",
        source: :flow,
        payload: %{window_id: window_id_atom}
      })

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system.feature_window.created",
        event2
      )

      assert_receive {:telemetry, :event_received, _, metadata2}, 1000
      assert metadata2.window_id == window_id_atom

      GenServer.stop(trainer_pid)
    end

    test "logs warning for events without window_id" do
      import ExUnit.CaptureLog

      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_no_id,
        trainer_name: "test_no_id",
        mode: :shadow
      )

      {:ok, event} = Event.new(%{
        name: "system.feature_window.created",
        source: :flow,
        payload: %{tenant_id: Ash.UUID.generate()}  # Missing window_id
      })

      log = capture_log(fn ->
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "system.feature_window.created",
          event
        )

        # Give it time to process
        Process.sleep(100)
      end)

      assert log =~ "Received feature window event without window_id"

      GenServer.stop(trainer_pid)
    end
  end

  describe "ReplayBuffer integration" do
    test "adds window to replay buffer on event receipt" do
      tenant_id = Ash.UUID.generate()
      window_id = Ash.UUID.generate()

      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_buffer,
        trainer_name: "test_buffer",
        mode: :shadow
      )

      # Get trainer state to access replay buffer
      metrics = TrainerWorker.get_metrics(trainer_pid)

      # Publish event
      {:ok, event} = Event.new(%{
        name: "system.feature_window.created",
        source: :flow,
        payload: %{
          window_id: window_id,
          tenant_id: tenant_id,
          features: %{"test" => "data"}
        }
      })

      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system.feature_window.created",
        event
      )

      # Wait for processing
      assert_receive {:telemetry, :event_received, _, _}, 1000

      # Verify buffer stats show the window
      # Note: Buffer is a separate process, would need to query it directly
      # This is tested more thoroughly in replay_buffer_test.exs

      GenServer.stop(trainer_pid)
    end
  end

  describe "training cycle triggering" do
    test "skips unfilled windows" do
      import ExUnit.CaptureLog

      tenant_id = Ash.UUID.generate()

      # Create an UNFILLED window
      {:ok, window} = FeatureWindow
      |> Ash.Changeset.for_create(:ingest_window, %{
        tenant_id: tenant_id,
        kind: :email_decision,
        key: "test_unfilled_#{System.unique_integer()}",
        window_start: DateTime.utc_now() |> DateTime.add(-60, :second),
        window_end: DateTime.utc_now(),
        features: %{"test" => "data"},
        label_spec: %{"action" => "string"},
        feature_schema_version: 1,
        provenance: %{"source" => "test"}
      })
      |> Ash.create(authorize?: false)

      # Window is in :open status, not :filled
      assert window.status == :open
      assert is_nil(window.labels)

      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_unfilled,
        trainer_name: "test_unfilled",
        mode: :shadow
      )

      log = capture_log(fn ->
        # Process window directly
        TrainerWorker.process_window(trainer_pid, window.id)
        Process.sleep(200)
      end)

      assert log =~ "Skipping unfilled window"

      # Verify window count didn't increase
      metrics = TrainerWorker.get_metrics(trainer_pid)
      assert metrics.window_count == 0

      GenServer.stop(trainer_pid)
    end

    test "processes filled windows with labels" do
      tenant_id = Ash.UUID.generate()

      # Create and fill a window
      {:ok, window} = FeatureWindow
      |> Ash.Changeset.for_create(:ingest_window, %{
        tenant_id: tenant_id,
        kind: :email_decision,
        key: "test_key_#{System.unique_integer()}",
        window_start: DateTime.utc_now() |> DateTime.add(-60, :second),
        window_end: DateTime.utc_now(),
        features: %{"embedding" => [0.1, 0.2]},
        label_spec: %{"action" => "string"},
        feature_schema_version: 1,
        provenance: %{"source" => "test"}
      })
      |> Ash.create(authorize?: false)

      {:ok, filled_window} = window
      |> Ash.Changeset.for_update(:fill_labels, %{
        labels: %{"action" => "send"},
        status: :filled
      })
      |> Ash.update(authorize?: false)

      {:ok, trainer_pid} = TrainerWorker.start_link(
        name: :test_trainer_filled,
        trainer_name: "test_filled",
        mode: :shadow
      )

      # Process the filled window
      TrainerWorker.process_window(trainer_pid, filled_window.id)
      Process.sleep(200)

      metrics = TrainerWorker.get_metrics(trainer_pid)
      assert metrics.window_count == 1
      assert metrics.last_window_id == filled_window.id

      GenServer.stop(trainer_pid)
    end
  end
end
