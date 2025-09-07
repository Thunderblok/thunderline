defmodule ThunderlineTest.MnesiaBroadwayTest do
  @moduledoc """
  Tests for Mnesia Broadway integration to validate the implementation.
  """

  use ExUnit.Case, async: false
    @moduletag :skip
  alias Thunderline.EventBus
  alias Thunderflow.MnesiaProducer

  setup do
    # Start fresh in-memory mnesia (per test module)
    :mnesia.stop()
    # Use Memento convenience; create schema for current node
    :ok = Memento.Schema.create([node()])
    :ok = Memento.start()
    Enum.each([Thunderflow.MnesiaProducer, Thunderflow.CrossDomainEvents, Thunderflow.RealTimeEvents], fn table ->
      _ = Memento.Table.create(table)
    end)
    :ok
  end

  describe "EventBus with Mnesia" do
    test "publish_event/1 enqueues events to general table" do
      {:ok, ev} = Thunderline.Event.new(name: "system.test.general", type: :test_general_event, payload: %{data: "test_payload"}, source: :flow)
      assert {:ok, _} = EventBus.publish_event(ev)
      Process.sleep(50)
      stats = MnesiaProducer.queue_stats(Thunderflow.MnesiaProducer)
      assert stats.total > 0
    end

    test "cross-domain event routes to cross-domain table" do
      {:ok, ev} = Thunderline.Event.new(name: "system.chief.cross", type: :test_cross_domain, payload: %{from_domain: "thunderchief", to_domain: "thundercom", data: "x"}, source: :flow, target_domain: "thundercom")
      assert {:ok, _} = EventBus.publish_event(ev)
      Process.sleep(50)
      stats = MnesiaProducer.queue_stats(Thunderflow.CrossDomainEvents)
      assert stats.total > 0
    end

    test "high priority event infers realtime pipeline" do
      {:ok, ev} = Thunderline.Event.new(name: "system.flow.high", type: :test_realtime_event, payload: %{data: "rt"}, source: :flow, priority: :high)
      assert {:ok, _} = EventBus.publish_event(ev)
      Process.sleep(50)
      stats = MnesiaProducer.queue_stats(Thunderflow.RealTimeEvents)
      assert stats.total > 0
    end

    test "multiple publish_event calls increase queue" do
      for i <- 1..3 do
        {:ok, ev} = Thunderline.Event.new(name: "system.flow.batch#{i}", type: :batch_event, payload: %{i: i}, source: :flow)
        assert {:ok, _} = EventBus.publish_event(ev)
      end
      Process.sleep(50)
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

  # Legacy compatibility tests removed (deprecated APIs purged); guardrails enforce absence.
end
