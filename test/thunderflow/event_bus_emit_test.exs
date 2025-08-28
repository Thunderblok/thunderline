defmodule Thunderflow.EventBusEmitTest do
  use ExUnit.Case, async: true

  alias Thunderline.{Event, EventBus}

  test "emit returns {:ok, %Event{}} and preserves core fields" do
    {:ok, ev} = EventBus.emit(:ping, %{ok: true, domain: "thunderflow"})
    assert %Event{} = ev
    assert ev.type == :ping
    assert ev.source in [:flow, :unknown] # domain mapping may normalize
  end

  test "emit_batch enqueues events" do
    :ok = EventBus.emit_batch([{:alpha, %{domain: "thunderflow"}}, {:beta, %{domain: "thunderflow"}}])
    # We don't have direct queue introspection here; rely on no error return.
    # For structural verification, use emit_batch_with_events
  end

  test "emit_batch_with_events returns canonical events" do
    {:ok, events} = EventBus.emit_batch_with_events([{:alpha, %{domain: "thunderflow"}}, {:beta, %{domain: "thunderflow"}}])
    assert length(events) == 2
    assert Enum.all?(events, &match?(%Event{}, &1))
  end

  test "emit_batch_meta returns correlation and counts" do
    {:ok, meta} = EventBus.emit_batch_meta([{:alpha, %{domain: "thunderflow"}}, {:beta, %{domain: "thunderflow"}}])
    assert meta.count == 2
    assert meta.built == 2
    assert is_binary(meta.correlation_id)
    assert meta.pipeline == :general
  end

  test "ai_emit produces realtime-staged event with naming" do
    {:ok, ev} = EventBus.ai_emit(:tool_start, %{tool: "vector_search"})
    assert ev.type == :ai_event
    assert ev.name == "ai.tool_start"
    assert ev.payload[:ai_stage] == :tool_start
  end
end
