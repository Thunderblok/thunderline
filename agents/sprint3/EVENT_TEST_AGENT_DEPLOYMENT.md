# 🎯 Event Test Agent Deployment Plan

**Agent ID:** `event-test-agent`  
**Epic:** 3.3 Event System Validation  
**Priority:** 🟡 MEDIUM  
**Duration:** 2.5 hours  
**Can Run Parallel With:** security-agent, session-agent, event-doc-agent  

## Mission
Write comprehensive tests for event system reliability.

## Tasks

### Task 1: EventBus Operation Tests (60 min)

**File:** `test/thunderline/thunderflow/event_bus_test.exs`

```elixir
defmodule Thunderline.Thunderflow.EventBusTest do
  use Thunderline.DataCase
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event

  describe "publish_event/1" do
    test "publishes valid event successfully" do
      event = Event.new!(
        name: "test.event",
        source: :test,
        payload: %{data: "test"}
      )
      
      assert {:ok, published_event} = EventBus.publish_event(event)
      assert published_event.id
    end

    test "rejects invalid event structure" do
      assert {:error, _reason} = EventBus.publish_event(%{invalid: true})
    end

    test "validates event taxonomy" do
      invalid_event = Event.new!(
        name: "InvalidName",  # Must be lowercase with dots
        source: :test,
        payload: %{}
      )
      
      assert {:error, :invalid_taxonomy} = EventBus.publish_event(invalid_event)
    end
  end

  describe "event routing" do
    test "routes event to correct pipeline" do
      realtime_event = Event.new!(
        name: "ui.command.click",
        source: :test,
        payload: %{},
        meta: %{pipeline: :realtime}
      )
      
      {:ok, event} = EventBus.publish_event(realtime_event)
      assert event.meta.pipeline == :realtime
    end
  end
end
```

---

### Task 2: Event Retry Logic Tests (60 min)

**File:** `test/thunderline/thunderflow/event_processor_test.exs`

```elixir
defmodule Thunderline.Thunderflow.EventProcessorTest do
  use Thunderline.DataCase
  alias Thunderline.Thunderflow.EventProcessor

  describe "retry mechanism" do
    test "retries transient failures with backoff" do
      event = create_event()
      
      # Simulate transient failure
      processor_state = %{failures: 0}
      
      {:retry, new_state} = EventProcessor.handle_error(
        :transient, 
        event, 
        processor_state
      )
      
      assert new_state.failures == 1
      assert new_state.next_retry_at > DateTime.utc_now()
    end

    test "gives up after max retries" do
      event = create_event()
      processor_state = %{failures: 5}  # Max retries exceeded
      
      {:failed, _state} = EventProcessor.handle_error(
        :transient, 
        event, 
        processor_state
      )
    end

    test "classifies errors correctly" do
      assert EventProcessor.classify_error(%DBConnection.ConnectionError{}) == :transient
      assert EventProcessor.classify_error(%ArgumentError{}) == :permanent
    end
  end

  describe "backoff calculation" do
    test "exponential backoff with jitter" do
      backoff1 = EventProcessor.calculate_backoff(1)
      backoff2 = EventProcessor.calculate_backoff(2)
      backoff3 = EventProcessor.calculate_backoff(3)
      
      assert backoff2 > backoff1
      assert backoff3 > backoff2
    end
  end
end
```

---

### Task 3: Telemetry Tests (30 min)

**File:** `test/thunderline/thunderflow/event_telemetry_test.exs`

```elixir
defmodule Thunderline.Thunderflow.EventTelemetryTest do
  use Thunderline.DataCase
  
  setup do
    # Capture telemetry events
    :telemetry.attach_many(
      "test-handler",
      [
        [:thunderline, :event, :enqueue],
        [:thunderline, :event, :publish],
        [:thunderline, :event, :dropped]
      ],
      &capture_telemetry/4,
      %{test_pid: self()}
    )
    
    on_exit(fn -> :telemetry.detach("test-handler") end)
  end

  test "emits enqueue telemetry" do
    event = Event.new!(name: "test.event", source: :test, payload: %{})
    EventBus.publish_event(event)
    
    assert_receive {:telemetry, [:thunderline, :event, :enqueue], _measurements, _metadata}
  end

  test "emits publish latency telemetry" do
    event = Event.new!(name: "test.event", source: :test, payload: %{})
    EventBus.publish_event(event)
    
    assert_receive {:telemetry, [:thunderline, :event, :publish], %{duration: duration}, _}
    assert duration > 0
  end

  test "emits dropped telemetry for invalid events" do
    EventBus.publish_event(%{invalid: true})
    
    assert_receive {:telemetry, [:thunderline, :event, :dropped], _, %{reason: _}}
  end
  
  defp capture_telemetry(event, measurements, metadata, %{test_pid: pid}) do
    send(pid, {:telemetry, event, measurements, metadata})
  end
end
```

---

## Deliverables

- [ ] `event_bus_test.exs` - EventBus operations (8+ tests)
- [ ] `event_processor_test.exs` - Retry logic (6+ tests)
- [ ] `event_telemetry_test.exs` - Telemetry emission (5+ tests)
- [ ] All tests passing
- [ ] Event system coverage > 90%

## Success Criteria
✅ EventBus operations fully tested  
✅ Retry logic proven reliable  
✅ Error classification working  
✅ Telemetry verified  
✅ Coverage > 90%  

## Blockers
- ❌ Event system incomplete → Test what exists, note gaps
- ❌ Telemetry not instrumented → Add instrumentation
- ❌ Retry logic not implemented → Document requirement

## Communication
**Report When:**
- EventBus tests complete (60 min mark)
- Retry tests complete (120 min mark)
- Telemetry tests complete (150 min mark)
- All verified (final check)

**Estimated Completion:** 2.5 hours  
**Status:** 🟢 READY TO DEPLOY
