defmodule Thunderline.Thunderbolt.StreamManagerTest do
  @moduledoc """
  ExUnit coverage for StreamManager ingest/drop behaviors.

  Guerrilla #20: Tests StreamManager's core APIs:
  - ingest/2 - data ingestion with telemetry
  - drop/1 - stream dropping with notifications
  - stats/1 - statistics retrieval from ETS
  - subscribe/1, unsubscribe/1 - PubSub subscription management
  - list_streams/0 - stream enumeration

  Uses async: false because of ETS table and PubSub side effects.
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.StreamManager

  @stats_table :thunderbolt_stream_stats

  setup do
    # Ensure ETS table is initialized
    StreamManager.init_stats()

    # Clear any existing entries from previous tests
    clear_stats_table()

    # Set up telemetry handlers
    test_pid = self()
    handler_id = make_ref() |> inspect()

    :telemetry.attach(
      "#{handler_id}-ingest",
      [:thunderline, :thunderbolt, :stream, :ingest],
      fn name, measurements, metadata, _config ->
        send(test_pid, {:telemetry, name, measurements, metadata})
      end,
      nil
    )

    :telemetry.attach(
      "#{handler_id}-drop",
      [:thunderline, :thunderbolt, :stream, :drop],
      fn name, measurements, metadata, _config ->
        send(test_pid, {:telemetry, name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("#{handler_id}-ingest")
      :telemetry.detach("#{handler_id}-drop")
      clear_stats_table()
    end)

    {:ok, handler_id: handler_id}
  end

  describe "init_stats/0" do
    test "creates ETS table if not exists" do
      # Table should exist from setup
      assert :ets.whereis(@stats_table) != :undefined
    end

    test "is idempotent when table exists" do
      # Should not raise when called multiple times
      assert :ok = StreamManager.init_stats()
      assert :ok = StreamManager.init_stats()
      assert :ets.whereis(@stats_table) != :undefined
    end
  end

  describe "ingest/2" do
    test "ingests data into a stream and emits telemetry" do
      stream_name = :test_ingest_stream
      data = %{event: "test_event", value: 123}

      assert :ok = StreamManager.ingest(stream_name, data)

      # Verify telemetry was emitted
      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :ingest],
                      %{count: 1, size: _size}, %{stream: ^stream_name}},
                     500
    end

    test "updates stats on ingest" do
      stream_name = :stats_ingest_stream

      assert :ok = StreamManager.ingest(stream_name, %{data: "first"})
      assert :ok = StreamManager.ingest(stream_name, %{data: "second"})
      assert :ok = StreamManager.ingest(stream_name, %{data: "third"})

      {:ok, stats} = StreamManager.stats(stream_name)

      assert stats.ingest_count == 3
      assert stats.drop_count == 0
      assert %DateTime{} = stats.last_activity
    end

    test "calculates size estimate for different data types" do
      stream_name = :size_estimate_stream

      # Map data
      StreamManager.ingest(stream_name, %{a: 1, b: 2})

      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :ingest],
                      %{count: 1, size: map_size}, %{stream: ^stream_name}}
                     when is_integer(map_size) and map_size > 0,
                     500

      # List data
      StreamManager.ingest(stream_name, [1, 2, 3, 4, 5])

      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :ingest],
                      %{count: 1, size: list_size}, %{stream: ^stream_name}}
                     when is_integer(list_size) and list_size > 0,
                     500

      # Binary data
      StreamManager.ingest(stream_name, "hello world")

      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :ingest],
                      %{count: 1, size: binary_size}, %{stream: ^stream_name}}
                     when is_integer(binary_size) and binary_size == 11,
                     500
    end

    test "broadcasts event to stream subscribers" do
      stream_name = :broadcast_ingest_stream
      data = %{test: true}

      # Subscribe to the stream
      :ok = StreamManager.subscribe(stream_name)

      # Ingest data
      :ok = StreamManager.ingest(stream_name, data)

      # Should receive the wrapped event
      assert_receive {:stream_event, event}, 500
      assert event.stream == stream_name
      assert event.data == data
      assert %DateTime{} = event.timestamp
      assert is_binary(event.id)
    end
  end

  describe "drop/1" do
    test "drops a stream and emits telemetry" do
      stream_name = :test_drop_stream

      # First ingest something
      :ok = StreamManager.ingest(stream_name, %{init: true})

      # Drain ingest telemetry
      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :ingest], _, _}, 500

      # Drop the stream
      assert :ok = StreamManager.drop(stream_name)

      # Verify drop telemetry was emitted
      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :drop], %{count: 1},
                      %{stream: ^stream_name}},
                     500
    end

    test "updates stats on drop" do
      stream_name = :stats_drop_stream

      :ok = StreamManager.ingest(stream_name, %{data: "test"})
      :ok = StreamManager.drop(stream_name)

      {:ok, stats} = StreamManager.stats(stream_name)

      assert stats.drop_count == 1
    end

    test "notifies subscribers on stream drop" do
      stream_name = :notify_drop_stream

      # Subscribe first
      :ok = StreamManager.subscribe(stream_name)

      # Ingest to create the stream
      :ok = StreamManager.ingest(stream_name, %{init: true})

      # Drain the ingest message
      assert_receive {:stream_event, _}, 500

      # Drop the stream
      :ok = StreamManager.drop(stream_name)

      # Should receive drop notification
      assert_receive {:stream_dropped, ^stream_name}, 500
    end

    test "succeeds even if stream doesn't exist" do
      # Should not raise for non-existent stream
      assert :ok = StreamManager.drop(:nonexistent_stream_xyz)

      # Telemetry should still be emitted
      assert_receive {:telemetry, [:thunderline, :thunderbolt, :stream, :drop], %{count: 1},
                      %{stream: :nonexistent_stream_xyz}},
                     500
    end
  end

  describe "stats/1" do
    test "returns stats for an existing stream" do
      stream_name = :existing_stats_stream

      :ok = StreamManager.ingest(stream_name, %{data: "test"})

      assert {:ok, stats} = StreamManager.stats(stream_name)
      assert is_map(stats)
      assert Map.has_key?(stats, :ingest_count)
      assert Map.has_key?(stats, :drop_count)
      assert Map.has_key?(stats, :last_activity)
    end

    test "returns error for non-existent stream" do
      assert {:error, :not_found} = StreamManager.stats(:nonexistent_stats_stream)
    end

    test "tracks cumulative statistics" do
      stream_name = :cumulative_stats_stream

      # Multiple ingests
      Enum.each(1..5, fn _ ->
        StreamManager.ingest(stream_name, %{data: "test"})
      end)

      # Multiple drops
      Enum.each(1..2, fn _ ->
        StreamManager.drop(stream_name)
      end)

      {:ok, stats} = StreamManager.stats(stream_name)

      assert stats.ingest_count == 5
      assert stats.drop_count == 2
    end
  end

  describe "list_streams/0" do
    test "returns empty list when no streams exist" do
      # Clear any existing streams from other tests
      clear_stats_table()

      assert [] = StreamManager.list_streams()
    end

    test "returns all active stream names" do
      clear_stats_table()

      :ok = StreamManager.ingest(:stream_a, %{})
      :ok = StreamManager.ingest(:stream_b, %{})
      :ok = StreamManager.ingest(:stream_c, %{})

      streams = StreamManager.list_streams()

      assert length(streams) == 3
      assert :stream_a in streams
      assert :stream_b in streams
      assert :stream_c in streams
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribe allows receiving stream events" do
      stream_name = :sub_stream

      :ok = StreamManager.subscribe(stream_name)
      :ok = StreamManager.ingest(stream_name, %{key: "value"})

      assert_receive {:stream_event, event}, 500
      assert event.stream == stream_name
    end

    test "unsubscribe stops receiving stream events" do
      stream_name = :unsub_stream

      :ok = StreamManager.subscribe(stream_name)
      :ok = StreamManager.unsubscribe(stream_name)
      :ok = StreamManager.ingest(stream_name, %{key: "value"})

      # Should not receive the event after unsubscribe
      refute_receive {:stream_event, _}, 200
    end

    test "can subscribe to multiple streams" do
      :ok = StreamManager.subscribe(:multi_stream_a)
      :ok = StreamManager.subscribe(:multi_stream_b)

      :ok = StreamManager.ingest(:multi_stream_a, %{source: :a})
      :ok = StreamManager.ingest(:multi_stream_b, %{source: :b})

      assert_receive {:stream_event, %{stream: :multi_stream_a}}, 500
      assert_receive {:stream_event, %{stream: :multi_stream_b}}, 500
    end
  end

  describe "broadcast/2" do
    test "broadcasts without updating metrics" do
      stream_name = :broadcast_only_stream

      :ok = StreamManager.subscribe(stream_name)
      :ok = StreamManager.broadcast(stream_name, %{ephemeral: true})

      # Should receive the broadcast
      assert_receive {:stream_broadcast, %{ephemeral: true}}, 500

      # Should NOT have stats (no ingest was called)
      assert {:error, :not_found} = StreamManager.stats(stream_name)
    end
  end

  ## Private helpers

  defp clear_stats_table do
    case :ets.whereis(@stats_table) do
      :undefined -> :ok
      _ref -> :ets.delete_all_objects(@stats_table)
    end
  end
end
