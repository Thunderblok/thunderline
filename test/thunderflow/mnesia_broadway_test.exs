defmodule ThunderlineTest.MnesiaBroadwayTest do
  @moduledoc """
  Tests for Mnesia Broadway integration to validate the implementation.
  """

  use ExUnit.Case, async: false
  alias Thunderline.EventBus
  alias Thunderflow.MnesiaProducer

  setup do
    # Ensure Mnesia is running and tables are created
    :ok = Memento.stop()
    :ok = Memento.Schema.create()
    :ok = Memento.start()

    # Create test tables
    {:ok, _} = Memento.Table.create(Thunderflow.MnesiaProducer)
    {:ok, _} = Memento.Table.create(Thunderflow.CrossDomainEvents)
    {:ok, _} = Memento.Table.create(Thunderflow.RealTimeEvents)

    :ok
  end

  describe "EventBus with Mnesia" do
    test "emit/2 enqueues events to general table" do
      # Emit a test event
      :ok = EventBus.emit(:test_general_event, %{data: "test_payload"})

      # Wait a moment for processing
      Process.sleep(100)

      # Check that event was enqueued
      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.total > 0
    end

    test "emit_cross_domain/2 enqueues events to cross-domain table" do
      # Emit a cross-domain event
      :ok =
        EventBus.emit_cross_domain(:test_cross_domain, %{
          from_domain: "thunderchief",
          to_domain: "thundercom",
          data: "cross_domain_payload"
        })

      # Wait a moment for processing
      Process.sleep(100)

      # Check that event was enqueued
      stats = MnesiaProducer.queue_stats(Thunderflow.CrossDomainEvents)
      assert stats.total > 0
    end

    test "emit_realtime/2 enqueues events to realtime table" do
      # Emit a real-time event
      :ok =
        EventBus.emit_realtime(:test_realtime_event, %{
          priority: :high,
          data: "realtime_payload"
        })

      # Wait a moment for processing
      Process.sleep(100)

      # Check that event was enqueued
      stats = MnesiaProducer.queue_stats(Thunderflow.RealTimeEvents)
      assert stats.total > 0
    end

    test "emit_batch/2 enqueues multiple events efficiently" do
      # Prepare batch events
      events = [
        {:batch_event_1, %{data: "batch_1"}},
        {:batch_event_2, %{data: "batch_2"}},
        {:batch_event_3, %{data: "batch_3"}}
      ]

  # Emit batch (now returns :ok on success)
  :ok = EventBus.emit_batch(events, :general)

      # Wait a moment for processing
      Process.sleep(100)

      # Check that events were enqueued
      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.total >= 3
    end
  end

  describe "MnesiaProducer operations" do
    test "enqueue_event/3 stores event with correct metadata" do
      test_data = %{message: "test", timestamp: DateTime.utc_now()}

      :ok =
        MnesiaProducer.enqueue_event(
          Thunderflow.MnesiaProducer,
          test_data,
          pipeline_type: :general,
          priority: :high
        )

      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.pending == 1
    end

    test "enqueue_events/3 stores multiple events in single transaction" do
      events = [
        %{message: "event_1"},
        %{message: "event_2"},
        %{message: "event_3"}
      ]

      :ok =
        MnesiaProducer.enqueue_events(
          Thunderflow.MnesiaProducer,
          events,
          pipeline_type: :general,
          priority: :normal
        )

      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.pending >= 3
    end

    test "queue_stats/1 returns accurate queue information" do
      # Enqueue some test events
      :ok = MnesiaProducer.enqueue_event(Thunderflow.MnesiaProducer, %{test: 1})
      :ok = MnesiaProducer.enqueue_event(Thunderflow.MnesiaProducer, %{test: 2})

      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)

      assert is_integer(stats.pending)
      assert is_integer(stats.processing)
      assert is_integer(stats.failed)
      assert is_integer(stats.total)
      assert stats.total == stats.pending + stats.processing + stats.failed
    end
  end

  describe "Legacy compatibility" do
    test "legacy_broadcast/2 routes to appropriate pipeline" do
      # Test real-time topic routing
      :ok = EventBus.legacy_broadcast("agent:status:update", %{agent_id: "123", status: "online"})

      # Test cross-domain topic routing
      :ok =
        EventBus.legacy_broadcast("domain:thunderchief:thundercom", %{message: "cross domain"})

      # Test general topic routing
      :ok = EventBus.legacy_broadcast("general:event:topic", %{data: "general event"})

      # Wait for processing
      Process.sleep(200)

      # Verify events were routed to appropriate tables
      realtime_stats = MnesiaProducer.queue_stats(Thunderflow.RealTimeEvents)
      general_stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)

      # At least some events should be processed
      assert realtime_stats.total + general_stats.total > 0
    end

    test "broadcast_via_eventbus/3 maintains backward compatibility" do
      :ok =
        EventBus.broadcast_via_eventbus(
          "test:topic:name",
          :test_event_type,
          %{data: "compatibility_test"}
        )

      # Wait for processing
      Process.sleep(100)

      # Verify event was processed
      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.total > 0
    end
  end
end
