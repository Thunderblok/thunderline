# Event Troubleshooting Guide

## Overview

This guide provides systematic approaches for debugging common event issues in Thunderline's event system. Use this document when events fail validation, processing times out, or the pipeline exhibits unexpected behavior.

## Table of Contents

1. [Common Event Issues](#common-event-issues)
2. [Debugging Techniques](#debugging-techniques)
3. [Event Validation Failures](#event-validation-failures)
4. [Pipeline Bottlenecks](#pipeline-bottlenecks)
5. [Dead Letter Queue Investigation](#dead-letter-queue-investigation)
6. [Telemetry Query Examples](#telemetry-query-examples)
7. [Quick Reference](#quick-reference)

---

## Common Event Issues

### Issue 1: Event Validation Failures

**Symptoms**:
- Events dropped with `:drop` mode
- Validation errors raised with `:raise` mode
- Warning logs with `:warn` mode
- Telemetry event: `[:thunderline, :event, :dropped]`

**Root Causes**:
1. **Short Event Name**: Name has < 2 segments (e.g., `"system"` instead of `"system.startup"`)
2. **Reserved Prefix Violation**: Using reserved prefix without proper domain (e.g., `"ml.custom"` from `:gate` domain)
3. **Missing correlation_id**: Required field not provided
4. **Invalid UUID v7 Format**: correlation_id or causation_id not proper UUID v7
5. **Invalid taxonomy_version**: Value < 1
6. **Invalid event_version**: Value < 1
7. **Invalid meta**: Not a map
8. **Invalid Payload**: Not a map

**Solution**:
```elixir
# Check event before publishing
case Thunderline.Event.new(%{
  name: "system.email.sent",  # ✅ 3 segments
  source: :gate,              # ✅ :gate allows system events
  payload: %{to: "user@example.com"},  # ✅ Map payload
  correlation_id: Thunderline.UUID.v7()  # ✅ UUID v7
}) do
  {:ok, event} -> Thunderline.EventBus.publish_event(event)
  {:error, errors} -> Logger.error("Invalid event: #{inspect(errors)}")
end
```

---

### Issue 2: Event Drops (Silent Failures)

**Symptoms**:
- Events not processed
- No error logs
- Telemetry event: `[:thunderline, :event, :dropped]` emitted
- Audit event: `audit.event_drop` published

**Root Causes**:
- EventValidator running in `:drop` mode (production default)
- Validation failures silently dropping events

**Solution**:
```elixir
# Switch to :warn mode temporarily for debugging
Application.put_env(:thunderline, :event_validation_mode, :warn)

# Restart application to apply config
# Now validation failures log warnings instead of dropping

# Query telemetry for dropped events
:telemetry.list_handlers(:any)
|> Enum.filter(fn %{id: id} -> String.contains?(to_string(id), "thunderline") end)

# Check audit logs for drop events
Thunderline.EventBus.subscribe("audit.event_drop")
```

**Prevention**:
```elixir
# Use :warn mode in development/staging
config :thunderline, :event_validation_mode, :warn  # dev.exs, test.exs

# Use :drop mode only in production
config :thunderline, :event_validation_mode, :drop  # prod.exs
```

---

### Issue 3: Idempotency Duplicate Detection

**Symptoms**:
- Event appears processed but effects not visible
- Telemetry event: `[:thunderline, :event, :dedup]` emitted
- Message marked as failed with `:duplicate` reason

**Root Causes**:
- Same `event_id` + `correlation_id` published multiple times
- Producer replaying unacknowledged messages
- Client retry logic republishing events

**Solution**:
```elixir
# Check idempotency table
:mnesia.dirty_match_object({:idempotency_keys, {:_, :_}, :_})
|> Enum.filter(fn {:idempotency_keys, {event_id, _}, _ts} ->
  event_id == "target_event_id"
end)

# Clear idempotency key (DANGEROUS - only for development)
:mnesia.dirty_delete({:idempotency_keys, {event_id, correlation_id}})

# Republish event with NEW event_id
event = %Thunderline.Event{
  event | id: Thunderline.UUID.v7()  # ✅ New ID
}
Thunderline.EventBus.publish_event(event)
```

**Prevention**:
```elixir
# Always generate new event_id for retries
def retry_event(original_event) do
  %Thunderline.Event{
    original_event |
    id: Thunderline.UUID.v7(),            # ✅ New ID
    correlation_id: original_event.correlation_id,  # ✅ Keep correlation
    causation_id: original_event.id       # ✅ Track causation
  }
end
```

---

### Issue 4: Batcher Bottlenecks

**Symptoms**:
- Events queued but not processing
- Increasing backlog in Mnesia table
- Telemetry: `[:thunderline, :pipeline, :domain_events, :stop]` duration > 2000ms
- Batch timeout errors

**Root Causes**:
1. **Low Concurrency**: Too few batch handlers (default: 5 for domain, 2 for critical)
2. **Small Batch Size**: Batches fill slowly (default: 25 for domain, 10 for critical)
3. **High Batch Timeout**: Waiting too long for batches to fill (default: 2000ms domain, 500ms critical)
4. **Slow Handler Logic**: Batch processing taking > timeout duration

**Solution**:
```elixir
# Query batch processing telemetry
:telemetry.attach(
  "batch-duration-handler",
  [:thunderline, :pipeline, :domain_events, :stop],
  fn _event_name, measurements, _metadata, _config ->
    IO.puts("Batch processed in #{measurements.duration}ms")
  end,
  nil
)

# Tune batcher configuration
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  batchers: [
    domain_events: [
      concurrency: 10,      # ↑ Increase from 5
      batch_size: 50,       # ↑ Increase from 25
      batch_timeout: 1_000  # ↓ Decrease from 2000ms
    ]
  ]

# Monitor backlog size
backlog_size = :mnesia.table_info(:thunderline_events, :size)
IO.puts("Backlog: #{backlog_size} events")
```

**Thresholds**:
- **Backlog < 100**: Normal operation
- **Backlog 100-1000**: Monitor, consider tuning
- **Backlog > 1000**: Urgent, increase concurrency or batch size

---

### Issue 5: Critical Event Delays

**Symptoms**:
- High-priority events delayed
- Critical events processed slower than expected
- Telemetry: `[:thunderline, :pipeline, :critical_events, :stop]` duration > 500ms

**Root Causes**:
- Event not marked with `:high` or `:critical` priority
- Critical batcher overwhelmed (only 2 concurrent handlers)
- Batch processing logic too slow

**Solution**:
```elixir
# Verify event priority
event = %Thunderline.Event{
  name: "system.alert.triggered",
  source: :gate,
  priority: :critical,  # ✅ Set priority explicitly
  payload: %{alert: "High CPU usage"}
}

# Check batcher selection
require Logger
Logger.info("Event #{event.id} routed to: #{if event.priority in [:high, :critical], do: :critical_events, else: :domain_events}")

# Monitor critical event processing time
:telemetry.attach(
  "critical-duration-handler",
  [:thunderline, :pipeline, :critical_events, :stop],
  fn _event_name, measurements, metadata, _config ->
    if measurements.duration > 500 do
      Logger.warning("Critical batch slow: #{measurements.duration}ms, count: #{metadata.count}")
    end
  end,
  nil
)

# Increase critical batcher concurrency
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  batchers: [
    critical_events: [
      concurrency: 5,       # ↑ Increase from 2
      batch_size: 5,        # ↓ Decrease from 10 (faster batches)
      batch_timeout: 250    # ↓ Decrease from 500ms
    ]
  ]
```

---

## Debugging Techniques

### 1. Enable Validation Warnings

**Temporary Mode Switch**:
```elixir
# In IEx console
Application.put_env(:thunderline, :event_validation_mode, :warn)

# Restart application
System.restart()

# Validation failures now log warnings instead of dropping
```

**Permanent Mode Change**:
```elixir
# config/dev.exs
config :thunderline, :event_validation_mode, :warn

# config/test.exs
config :thunderline, :event_validation_mode, :raise  # Catch errors in tests

# config/prod.exs
config :thunderline, :event_validation_mode, :drop   # Silent drops in production
```

---

### 2. EventValidator Manual Testing

**Test Event Validation**:
```elixir
# Valid event
event = Thunderline.Event.new!(%{
  name: "system.test.event",
  source: :gate,
  payload: %{test: true}
})

case Thunderline.Thunderflow.EventValidator.validate(event) do
  :ok -> IO.puts("✅ Event valid")
  {:error, errors} -> IO.inspect(errors, label: "❌ Validation errors")
end

# Invalid event (short name)
event = %Thunderline.Event{
  name: "test",  # ❌ Only 1 segment
  source: :gate,
  payload: %{}
}

Thunderline.Thunderflow.EventValidator.validate(event)
# => {:error, [{:invalid_name, "Event name must have at least 2 segments"}]}
```

---

### 3. Broadway Message Inspection

**Query Broadway Pipeline State**:
```elixir
# Get pipeline status
{:ok, pipeline_status} = Broadway.get_status(Thunderline.Thunderflow.Pipelines.EventPipeline)
IO.inspect(pipeline_status, label: "Pipeline status")

# Query processor state
processors = pipeline_status.processors
IO.inspect(processors, label: "Processor state")

# Query batcher state
batchers = pipeline_status.batchers
IO.inspect(batchers, label: "Batcher state")

# Check message queue length
queue_length = :erlang.process_info(self(), :message_queue_len)
IO.puts("Message queue length: #{elem(queue_length, 1)}")
```

---

### 4. Audit Trail Following

**Query Audit Events**:
```elixir
# Subscribe to audit events
Thunderline.EventBus.subscribe("audit.**")

# Publish test event
event = Thunderline.Event.new!(%{
  name: "system.test.event",
  source: :gate,
  payload: %{test: true}
})
Thunderline.EventBus.publish_event(event)

# Receive audit events
receive do
  {:event, %Thunderline.Event{name: "audit.event_drop"} = audit_event} ->
    IO.inspect(audit_event.payload, label: "Drop reason")
    
  {:event, %Thunderline.Event{name: "audit.event_validated"} = audit_event} ->
    IO.puts("✅ Event validated")
after
  1000 -> IO.puts("No audit events received")
end
```

---

### 5. Mnesia Table Inspection

**Query Event Backlog**:
```elixir
# Count events in Mnesia
backlog_size = :mnesia.table_info(:thunderline_events, :size)
IO.puts("Backlog: #{backlog_size} events")

# Query specific events
events = :mnesia.dirty_match_object({:thunderline_events, :_, :_})
IO.inspect(Enum.take(events, 5), label: "First 5 events")

# Query idempotency keys
idempotency_keys = :mnesia.dirty_match_object({:idempotency_keys, :_, :_})
IO.puts("Idempotency keys: #{length(idempotency_keys)}")

# Query DLQ
dlq_events = :mnesia.dirty_match_object({:event_dlq, :_, :_})
IO.puts("DLQ size: #{length(dlq_events)}")
```

---

## Event Validation Failures

### Validation Modes

| Mode | Behavior | Use Case | Error Handling |
|------|----------|----------|----------------|
| `:warn` | Log warning, continue | Development | Logs validation errors, processes event |
| `:raise` | Raise exception | Testing | Crashes on validation failure |
| `:drop` | Silent drop, emit telemetry | Production | Drops event, emits `[:thunderline, :event, :dropped]` |

### Validation Error Types

#### 1. Name Too Short

**Error**: `{:invalid_name, "Event name must have at least 2 segments"}`

**Cause**: Event name has < 2 segments

**Example**:
```elixir
# ❌ BAD: Only 1 segment
%Thunderline.Event{name: "error", source: :gate, payload: %{}}

# ✅ GOOD: 2+ segments
%Thunderline.Event{name: "system.error", source: :gate, payload: %{}}
```

#### 2. Reserved Prefix Violation

**Error**: `{:forbidden_category, {source, name}}`

**Cause**: Event name uses reserved prefix not allowed for source domain

**Example**:
```elixir
# ❌ BAD: :gate domain cannot publish ml.* events
%Thunderline.Event{name: "ml.run.started", source: :gate, payload: %{}}

# ✅ GOOD: :bolt domain can publish ml.* events
%Thunderline.Event{name: "ml.run.started", source: :bolt, payload: %{}}
```

**Domain → Event Category Matrix**:
| Domain | Allowed Prefixes |
|--------|------------------|
| `:gate` | `system.*`, `ui.command.*`, `presence.*`, `device.*` |
| `:flow` | `system.*`, `flow.reactor.*`, `ai.*` |
| `:bolt` | `system.*`, `ml.run.*`, `ml.trial.*`, `ai.*`, `pac.*`, `thundra.*` |
| `:link` | `system.*`, `ui.command.*`, `voice.signal.*`, `voice.room.*`, `device.*` |
| `:crown` | `system.*`, `ai.intent.*`, `ai.*`, `pac.*` |
| `:block` | `system.*`, `pac.*` |
| `:bridge` | `system.*`, `ui.command.*`, `ai.*` |

#### 3. Missing correlation_id

**Error**: `{:missing, :correlation_id}`

**Cause**: correlation_id field not provided (auto-generated if missing in `new/1`)

**Solution**: Always use `Thunderline.Event.new/1` which auto-generates correlation_id:
```elixir
# ✅ GOOD: new/1 auto-generates correlation_id
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{to: "user@example.com"}
})

# ❌ BAD: Manual struct creation without correlation_id
event = %Thunderline.Event{
  name: "system.email.sent",
  source: :gate,
  payload: %{to: "user@example.com"}
  # Missing correlation_id!
}
```

#### 4. Invalid UUID v7 Format

**Error**: `{:invalid, :correlation_id}` or `{:invalid, :causation_id}`

**Cause**: correlation_id or causation_id not proper UUID v7

**Solution**:
```elixir
# ✅ GOOD: Use Thunderline.UUID.v7/0
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  correlation_id: Thunderline.UUID.v7(),  # ✅ UUID v7
  causation_id: Thunderline.UUID.v7()     # ✅ UUID v7
})

# ❌ BAD: Random string
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  correlation_id: "random-string",  # ❌ Not UUID v7
  causation_id: "12345"            # ❌ Not UUID v7
})
```

#### 5. Invalid taxonomy_version

**Error**: `{:invalid, :taxonomy_version}`

**Cause**: taxonomy_version < 1

**Solution**:
```elixir
# ✅ GOOD: Default taxonomy_version = 1
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{}
})

# ❌ BAD: Setting taxonomy_version < 1
event = %Thunderline.Event{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  taxonomy_version: 0  # ❌ Must be >= 1
}
```

#### 6. Invalid event_version

**Error**: `{:invalid, :event_version}`

**Cause**: event_version < 1

**Solution**:
```elixir
# ✅ GOOD: Default event_version = 1
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{}
})

# ❌ BAD: Setting event_version < 1
event = %Thunderline.Event{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  event_version: 0  # ❌ Must be >= 1
}
```

#### 7. Invalid meta

**Error**: `{:invalid, :meta}`

**Cause**: meta field not a map

**Solution**:
```elixir
# ✅ GOOD: meta is a map
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  meta: %{reliability: :persistent}  # ✅ Map
})

# ❌ BAD: meta is not a map
event = %Thunderline.Event{
  name: "system.email.sent",
  source: :gate,
  payload: %{},
  meta: "persistent"  # ❌ Not a map
}
```

#### 8. Invalid Payload

**Error**: `{:invalid, :payload}`

**Cause**: payload field not a map

**Solution**:
```elixir
# ✅ GOOD: payload is a map
event = Thunderline.Event.new!(%{
  name: "system.email.sent",
  source: :gate,
  payload: %{to: "user@example.com", subject: "Welcome"}  # ✅ Map
})

# ❌ BAD: payload is not a map
event = %Thunderline.Event{
  name: "system.email.sent",
  source: :gate,
  payload: "email data"  # ❌ Not a map
}
```

---

## Pipeline Bottlenecks

### Identifying Bottlenecks

**Key Metrics**:
1. **Batch Processing Duration**: `[:thunderline, :pipeline, :domain_events, :stop]` measurement `duration`
2. **Batch Size**: `[:thunderline, :pipeline, :domain_events, :start]` metadata `count`
3. **Error Rate**: `[:thunderline, :pipeline, :domain_events, :error]` frequency
4. **Backlog Size**: `:mnesia.table_info(:thunderline_events, :size)`

**Telemetry Query**:
```elixir
# Attach handler to measure batch duration
:telemetry.attach(
  "batch-perf-handler",
  [:thunderline, :pipeline, :domain_events, :stop],
  fn _event_name, measurements, metadata, _config ->
    duration_ms = measurements.duration
    batch_count = metadata.count
    throughput = batch_count / (duration_ms / 1000)
    
    IO.puts("""
    Batch Stats:
      Duration: #{duration_ms}ms
      Count: #{batch_count} events
      Throughput: #{Float.round(throughput, 2)} events/sec
    """)
    
    if duration_ms > 2000 do
      Logger.warning("Batch processing slow: #{duration_ms}ms for #{batch_count} events")
    end
  end,
  nil
)
```

### Tuning Batcher Concurrency

**Problem**: Low throughput, increasing backlog

**Solution**: Increase batcher concurrency

**Configuration**:
```elixir
# config/config.exs or config/runtime.exs
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  batchers: [
    domain_events: [
      concurrency: 10,      # ↑ From 5 (default)
      batch_size: 25,
      batch_timeout: 2_000
    ]
  ]

# Restart application
System.restart()

# Monitor backlog reduction
backlog = :mnesia.table_info(:thunderline_events, :size)
IO.puts("Backlog: #{backlog} events")
```

**Guidelines**:
- **Low Throughput (<100 events/sec)**: Increase concurrency to 10-20
- **Medium Throughput (100-500 events/sec)**: Use concurrency 5-10
- **High Throughput (>500 events/sec)**: Consider partitioning or multiple pipelines

### Tuning Batch Size

**Problem**: Small batches, high overhead

**Solution**: Increase batch size

**Configuration**:
```elixir
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  batchers: [
    domain_events: [
      concurrency: 5,
      batch_size: 50,       # ↑ From 25 (default)
      batch_timeout: 2_000
    ]
  ]
```

**Guidelines**:
- **Small Batches (<10 events)**: Increase batch_size to 25-50
- **Medium Batches (10-50 events)**: Use batch_size 25-100
- **Large Batches (>50 events)**: May hit timeout, decrease batch_timeout or increase concurrency

### Tuning Batch Timeout

**Problem**: Waiting too long for batches to fill

**Solution**: Decrease batch timeout

**Configuration**:
```elixir
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  batchers: [
    domain_events: [
      concurrency: 5,
      batch_size: 25,
      batch_timeout: 1_000  # ↓ From 2000ms (default)
    ]
  ]
```

**Guidelines**:
- **High Latency (>2s)**: Decrease batch_timeout to 500-1000ms
- **Low Latency (<500ms)**: Use batch_timeout 100-500ms
- **Balance**: Timeout should be shorter than retry backoff delay

### Tuning MnesiaProducer Polling

**Problem**: Events not picked up quickly

**Solution**: Increase poll frequency

**Configuration**:
```elixir
config :thunderline, Thunderline.Thunderflow.Pipelines.EventPipeline,
  producer: [
    module: {Thunderline.Thunderflow.MnesiaProducer, [
      table: :thunderline_events,
      poll_interval: 500,    # ↓ From 1000ms (default)
      max_batch_size: 50
    ]},
    concurrency: 1
  ]
```

**Guidelines**:
- **High Latency**: Decrease poll_interval to 100-500ms
- **CPU Overhead**: Increase poll_interval to 2000-5000ms
- **Balance**: Poll frequently enough to maintain throughput without excessive CPU

---

## Dead Letter Queue Investigation

### Querying DLQ

**Get DLQ Size**:
```elixir
dlq_events = :mnesia.dirty_match_object({:event_dlq, :_, :_})
IO.puts("DLQ size: #{length(dlq_events)}")
```

**Inspect DLQ Event**:
```elixir
# Get first DLQ event
[{:event_dlq, event_id, record} | _] = dlq_events

IO.inspect(record, label: "DLQ Record")
# %{
#   event_id: "evt_abc123",
#   event: %Thunderline.Event{...},
#   reason: :max_retries_exceeded,
#   failed_at: ~U[2023-05-01 12:00:00Z],
#   attempts: 5
# }
```

### Failure Reason Analysis

**Query by Failure Reason**:
```elixir
# Group DLQ events by reason
dlq_events
|> Enum.group_by(fn {:event_dlq, _id, record} -> record.reason end)
|> Enum.map(fn {reason, events} -> {reason, length(events)} end)
|> IO.inspect(label: "DLQ by reason")

# Example output:
# [
#   {:max_retries_exceeded, 42},
#   {:timeout, 18},
#   {:invalid_schema, 5}
# ]
```

### Recovering DLQ Events

**Manual Recovery** (after fixing root cause):
```elixir
# Get DLQ event
[{:event_dlq, event_id, record}] = :mnesia.dirty_read(:event_dlq, event_id)

# Inspect event
IO.inspect(record.event, label: "Original event")

# Fix event (if needed)
fixed_event = %Thunderline.Event{
  record.event | 
  payload: Map.put(record.event.payload, :fixed, true)
}

# Reprocess event
Thunderline.EventBus.publish_event(fixed_event)

# Remove from DLQ
:mnesia.dirty_delete({:event_dlq, event_id})
```

**Automated Recovery** (for transient failures):
```elixir
# Retry all timeout failures
:mnesia.dirty_match_object({:event_dlq, :_, %{reason: :timeout}})
|> Enum.each(fn {:event_dlq, event_id, record} ->
  Thunderline.EventBus.publish_event(record.event)
  :mnesia.dirty_delete({:event_dlq, event_id})
  IO.puts("Retried event #{event_id}")
end)
```

---

## Telemetry Query Examples

### Event Lifecycle

**Event Validated**:
```elixir
:telemetry.attach(
  "event-validated-handler",
  [:thunderline, :event, :validated],
  fn _event_name, measurements, metadata, _config ->
    IO.puts("✅ Event validated: #{metadata.event_id}")
  end,
  nil
)
```

**Event Dropped**:
```elixir
:telemetry.attach(
  "event-dropped-handler",
  [:thunderline, :event, :dropped],
  fn _event_name, _measurements, metadata, _config ->
    Logger.warning("❌ Event dropped: #{metadata.event_id}, reason: #{inspect(metadata.reason)}")
  end,
  nil
)
```

**Event Deduplication**:
```elixir
:telemetry.attach(
  "event-dedup-handler",
  [:thunderline, :event, :dedup],
  fn _event_name, _measurements, metadata, _config ->
    Logger.info("🔁 Duplicate event: #{metadata.event_id}")
  end,
  nil
)
```

### Pipeline Processing

**Batch Start**:
```elixir
:telemetry.attach(
  "batch-start-handler",
  [:thunderline, :pipeline, :domain_events, :start],
  fn _event_name, _measurements, metadata, _config ->
    IO.puts("⏰ Batch started: #{metadata.count} events")
  end,
  nil
)
```

**Batch Stop**:
```elixir
:telemetry.attach(
  "batch-stop-handler",
  [:thunderline, :pipeline, :domain_events, :stop],
  fn _event_name, measurements, metadata, _config ->
    duration_ms = measurements.duration
    IO.puts("✅ Batch completed: #{metadata.count} events in #{duration_ms}ms")
  end,
  nil
)
```

**Batch Error**:
```elixir
:telemetry.attach(
  "batch-error-handler",
  [:thunderline, :pipeline, :domain_events, :error],
  fn _event_name, _measurements, metadata, _config ->
    Logger.error("❌ Batch failed: #{inspect(metadata.reason)}")
  end,
  nil
)
```

### Critical Events

**Critical Batch Start**:
```elixir
:telemetry.attach(
  "critical-start-handler",
  [:thunderline, :pipeline, :critical_events, :start],
  fn _event_name, _measurements, metadata, _config ->
    IO.puts("🚨 Critical batch started: #{metadata.count} events")
  end,
  nil
)
```

**Critical Batch Stop**:
```elixir
:telemetry.attach(
  "critical-stop-handler",
  [:thunderline, :pipeline, :critical_events, :stop],
  fn _event_name, measurements, metadata, _config ->
    duration_ms = measurements.duration
    IO.puts("✅ Critical batch completed: #{metadata.count} events in #{duration_ms}ms")
    
    if duration_ms > 500 do
      Logger.warning("⚠️ Critical batch slow: #{duration_ms}ms")
    end
  end,
  nil
)
```

### Retry & DLQ

**Retry Attempt**:
```elixir
:telemetry.attach(
  "retry-handler",
  [:thunderline, :event, :retry],
  fn _event_name, _measurements, metadata, _config ->
    IO.puts("🔁 Retry attempt #{metadata.attempt} for event #{metadata.event_id}, delay: #{metadata.delay_ms}ms")
  end,
  nil
)
```

**DLQ Routing**:
```elixir
:telemetry.attach(
  "dlq-handler",
  [:thunderline, :event, :dlq],
  fn _event_name, _measurements, metadata, _config ->
    Logger.error("💀 Event routed to DLQ: #{metadata.event_id}, reason: #{inspect(metadata.reason)}")
  end,
  nil
)
```

### Blackboard Operations

**Blackboard Put**:
```elixir
:telemetry.attach(
  "blackboard-put-handler",
  [:thunderline, :blackboard, :put],
  fn _event_name, _measurements, metadata, _config ->
    IO.puts("📝 Blackboard put: #{metadata.key} = #{inspect(metadata.value)}")
  end,
  nil
)
```

**Blackboard Fetch**:
```elixir
:telemetry.attach(
  "blackboard-fetch-handler",
  [:thunderline, :blackboard, :fetch],
  fn _event_name, _measurements, metadata, _config ->
    outcome = if metadata.outcome == :hit, do: "✅ HIT", else: "❌ MISS"
    IO.puts("📖 Blackboard fetch: #{metadata.key} → #{outcome}")
  end,
  nil
)
```

### List All Thunderline Telemetry Handlers

```elixir
:telemetry.list_handlers(:any)
|> Enum.filter(fn %{id: id} -> String.contains?(to_string(id), "thunderline") end)
|> Enum.each(fn handler ->
  IO.inspect(handler, label: "Handler")
end)
```

---

## Quick Reference

### Validation Mode Commands

```elixir
# Switch to warn mode (development)
Application.put_env(:thunderline, :event_validation_mode, :warn)

# Switch to raise mode (testing)
Application.put_env(:thunderline, :event_validation_mode, :raise)

# Switch to drop mode (production)
Application.put_env(:thunderline, :event_validation_mode, :drop)

# Restart application
System.restart()
```

### Common Queries

```elixir
# Backlog size
:mnesia.table_info(:thunderline_events, :size)

# DLQ size
length(:mnesia.dirty_match_object({:event_dlq, :_, :_}))

# Idempotency keys count
length(:mnesia.dirty_match_object({:idempotency_keys, :_, :_}))

# Pipeline status
Broadway.get_status(Thunderline.Thunderflow.Pipelines.EventPipeline)
```

### Emergency Commands

```elixir
# Clear idempotency cache (DANGEROUS - development only)
:mnesia.clear_table(:idempotency_keys)

# Clear DLQ (DANGEROUS - development only)
:mnesia.clear_table(:event_dlq)

# Clear event backlog (DANGEROUS - development only)
:mnesia.clear_table(:thunderline_events)

# Stop pipeline
Broadway.stop(Thunderline.Thunderflow.Pipelines.EventPipeline)

# Start pipeline
{:ok, _pid} = Broadway.start_link(Thunderline.Thunderflow.Pipelines.EventPipeline, [])
```

---

## Related Documentation

- [EVENT_FLOWS.md](./EVENT_FLOWS.md) - Event architecture and pipeline
- [EVENT_RETRY_STRATEGIES.md](./EVENT_RETRY_STRATEGIES.md) - Retry budgets and backoff
- [EVENT_TAXONOMY.md](./documentation/EVENT_TAXONOMY.md) - Event naming conventions
