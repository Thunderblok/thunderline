# Event Retry Strategies

## Overview

This document describes the retry strategies, backoff algorithms, and pipeline configuration for event processing in Thunderline. The event system uses configurable retry budgets with exponential and linear backoff to handle transient failures gracefully.

## Table of Contents

1. [Retry Policy Overview](#retry-policy-overview)
2. [Backoff Algorithms](#backoff-algorithms)
3. [Event-Specific Retry Budgets](#event-specific-retry-budgets)
4. [Pipeline Configuration](#pipeline-configuration)
5. [Dead Letter Queue Behavior](#dead-letter-queue-behavior)
6. [Configuration Options](#configuration-options)
7. [Best Practices](#best-practices)

---

## Retry Policy Overview

### Core Principles

The event system implements **per-event-type retry budgets** with configurable backoff strategies:

- **Retry Budget**: Maximum retry attempts per event type
- **Backoff Strategy**: Exponential (default) or linear delay calculation
- **Jitter**: ±20% randomness to prevent thundering herd
- **Max Delay**: Capped at 300 seconds (5 minutes)
- **Idempotency**: Duplicate detection prevents double-processing

### Retry Flow

```
Event Published
      ↓
EventBus.publish_event/1
      ↓
MnesiaProducer (Broadway)
      ↓
Idempotency Check (seen?)
      ↓
Processor (transform, validate)
      ↓
Batcher (domain_events or critical_events)
      ↓
Handler (process batch)
      ↓
   Success? ──YES──> ACK message
      ↓ NO
   Retry Budget?
      ↓ YES
   Calculate Backoff
      ↓
   Delay + Republish
      ↓ NO (exhausted)
   Route to DLQ
```

### Retry Budget by Event Type

| Event Type | Max Retries | Strategy | Min Delay | Max Delay | Use Case |
|-----------|-------------|----------|-----------|-----------|----------|
| ML runs (`ml.run.*`) | 5 | Exponential | 1s | 300s | Long-running compute tasks |
| ML trials (`ml.trial.*`) | 3 | Exponential | 1s | 300s | Hyperparameter tuning |
| UI commands (`ui.command.*`) | 2 | None | 0s | 0s | Fast-fail for user interactions |
| System events (`system.*`) | 3 | Exponential | 1s | 300s | Internal operations |
| Default (all others) | 3 | Exponential | 1s | 300s | Standard events |

---

## Backoff Algorithms

### Exponential Backoff (Default)

**Algorithm**: `base = min_ms * 2^(attempt-1)`, capped at `max_ms`

**Implementation**:
```elixir
defmodule Thunderline.Thunderflow.Support.Backoff do
  @min_ms 1_000
  @max_ms 300_000
  @jitter_pct 0.20

  def exp(attempt) when attempt <= 1, do: jitter(@min_ms)
  
  def exp(attempt) do
    base = trunc(@min_ms * :math.pow(2, attempt - 1)) |> min(@max_ms)
    jitter(base)
  end
  
  def jitter(delay) do
    j = round(delay * @jitter_pct)
    offset = :rand.uniform(2 * j + 1) - j - 1
    max(0, delay + offset)
  end
end
```

**Delay Progression** (with ±20% jitter):

| Attempt | Base Delay | Min Delay | Max Delay | Typical |
|---------|------------|-----------|-----------|---------|
| 1 | 1,000ms | 800ms | 1,200ms | 1,000ms |
| 2 | 2,000ms | 1,600ms | 2,400ms | 2,000ms |
| 3 | 4,000ms | 3,200ms | 4,800ms | 4,000ms |
| 4 | 8,000ms | 6,400ms | 9,600ms | 8,000ms |
| 5 | 16,000ms | 12,800ms | 19,200ms | 16,000ms |
| 6 | 32,000ms | 25,600ms | 38,400ms | 32,000ms |
| 7+ | 300,000ms | 240,000ms | 360,000ms | 300,000ms (capped) |

**Use Cases**:
- ML runs (compute failures, resource contention)
- System events (transient errors, network issues)
- Background processing (non-critical tasks)

### Linear Backoff

**Algorithm**: `base = attempt * step`, capped at `max_ms`

**Implementation**:
```elixir
def linear(attempt, step \\ 5_000) do
  base = max(@min_ms, attempt * step) |> min(@max_ms)
  jitter(base)
end
```

**Delay Progression** (step=5,000ms, with ±20% jitter):

| Attempt | Base Delay | Min Delay | Max Delay | Typical |
|---------|------------|-----------|-----------|---------|
| 1 | 5,000ms | 4,000ms | 6,000ms | 5,000ms |
| 2 | 10,000ms | 8,000ms | 12,000ms | 10,000ms |
| 3 | 15,000ms | 12,000ms | 18,000ms | 15,000ms |
| 4 | 20,000ms | 16,000ms | 24,000ms | 20,000ms |
| 5+ | 300,000ms | 240,000ms | 360,000ms | 300,000ms (capped) |

**Use Cases**:
- Predictable retry intervals
- Rate-limited APIs
- Quota-based services

### No Backoff (UI Commands)

**Algorithm**: Immediate retry (0ms delay)

**Rationale**: UI commands require fast failure feedback to users. No backoff ensures quick error detection and prevents user frustration from long delays.

**Example**:
```elixir
# UI command retry budget
def retry_budget(%{name: "ui.command." <> _}), do: {2, :none}
```

---

## Event-Specific Retry Budgets

### Default Retry Budget

**Configuration**:
```elixir
def retry_budget(_event), do: {3, :exponential}
```

- **Max Retries**: 3 attempts (initial + 2 retries)
- **Strategy**: Exponential backoff
- **Total Time**: ~7 seconds (1s + 2s + 4s)

### ML Run Events

**Configuration**:
```elixir
def retry_budget(%{name: "ml.run." <> _}), do: {5, :exponential}
```

- **Max Retries**: 5 attempts
- **Strategy**: Exponential backoff
- **Total Time**: ~31 seconds (1s + 2s + 4s + 8s + 16s)
- **Rationale**: Long-running compute tasks need more retry attempts for transient GPU/CPU failures

**Example Event**:
```elixir
%Thunderline.Event{
  name: "ml.run.started",
  source: :bolt,
  payload: %{
    run_id: "run_abc123",
    model: "gemma-2b",
    device: "cuda:0"
  }
}
```

### ML Trial Events

**Configuration**:
```elixir
def retry_budget(%{name: "ml.trial." <> _}), do: {3, :exponential}
```

- **Max Retries**: 3 attempts
- **Strategy**: Exponential backoff
- **Total Time**: ~7 seconds
- **Rationale**: Hyperparameter tuning trials fail fast to avoid wasting compute on bad configurations

### UI Command Events

**Configuration**:
```elixir
def retry_budget(%{name: "ui.command." <> _}), do: {2, :none}
```

- **Max Retries**: 2 attempts (initial + 1 retry)
- **Strategy**: No backoff (immediate retry)
- **Total Time**: ~0 milliseconds
- **Rationale**: Fast-fail for user interactions, prevent UI blocking

**Example Events**:
- `ui.command.message.send`
- `ui.command.room.create`
- `ui.command.profile.update`

---

## Pipeline Configuration

### Broadway Producer Settings

**Configuration**:
```elixir
{Broadway, [
  name: Thunderline.Thunderflow.Pipelines.EventPipeline,
  producer: [
    module: {MnesiaProducer, [
      table: :thunderline_events,
      poll_interval: 1_000,        # Poll every 1 second
      max_batch_size: 50           # Fetch up to 50 events per poll
    ]},
    concurrency: 1
  ],
  processors: [
    default: [
      concurrency: 10,               # 10 concurrent processors
      min_demand: 5,
      max_demand: 20
    ]
  ],
  batchers: [
    domain_events: [
      concurrency: 5,                # 5 concurrent batch handlers
      batch_size: 25,                # Process up to 25 events per batch
      batch_timeout: 2_000           # Wait max 2 seconds to fill batch
    ],
    critical_events: [
      concurrency: 2,                # 2 concurrent batch handlers
      batch_size: 10,                # Smaller batches for fast processing
      batch_timeout: 500             # Wait max 500ms to fill batch
    ]
  ]
]}
```

### Batcher Selection Logic

**Critical Events** (fast-path):
```elixir
def handle_message(_, message, _) do
  event = message.data
  
  batcher = if event.priority in [:high, :critical] do
    :critical_events    # Fast-path for urgent events
  else
    :domain_events      # Standard throughput processing
  end
  
  message
  |> Message.put_batcher(batcher)
  |> Message.put_batch_key(event.source)  # Batch by source domain
end
```

**Batch Processing**:
```elixir
# Domain events batch (standard throughput)
def handle_batch(:domain_events, messages, _batch_info, _context) do
  :telemetry.execute([:thunderline, :pipeline, :domain_events, :start], 
    %{count: length(messages)})
  
  events = Enum.map(messages, & &1.data)
  
  case process_domain_events_batch(events) do
    :ok ->
      :telemetry.execute([:thunderline, :pipeline, :domain_events, :stop], 
        %{count: length(messages)})
      messages  # ACK all messages
      
    {:error, failed_events} ->
      handle_batch_failures(messages, failed_events)
  end
end

# Critical events batch (fast-path)
def handle_batch(:critical_events, messages, _batch_info, _context) do
  :telemetry.execute([:thunderline, :pipeline, :critical_events, :start], 
    %{count: length(messages)})
  
  events = Enum.map(messages, & &1.data)
  
  case process_critical_events_batch(events) do
    :ok ->
      :telemetry.execute([:thunderline, :pipeline, :critical_events, :stop], 
        %{count: length(messages)})
      messages  # ACK all messages
      
    {:error, reason} ->
      # Alert on critical event failure
      Phoenix.PubSub.broadcast(Thunderline.PubSub, 
        "thunderline:alerts:critical", 
        {:critical_event_failed, reason})
      
      Enum.map(messages, &Broadway.Message.failed(&1, reason))
  end
end
```

### Idempotency & Deduplication

**Strategy**: Composite key (event ID + correlation ID) stored in Mnesia

**Implementation**:
```elixir
defmodule Thunderline.Thunderflow.Idempotency do
  def seen?(event_id, correlation_id) do
    key = {event_id, correlation_id}
    
    case :mnesia.dirty_read(:idempotency_keys, key) do
      [{:idempotency_keys, ^key, _timestamp}] -> 
        :telemetry.execute([:thunderline, :event, :dedup], %{event_id: event_id})
        true
        
      [] -> 
        false
    end
  end
  
  def mark!(event_id, correlation_id) do
    key = {event_id, correlation_id}
    record = {:idempotency_keys, key, System.os_time(:second)}
    :mnesia.dirty_write(record)
  end
end
```

**Usage in Pipeline**:
```elixir
def handle_message(_, message, _) do
  event = message.data
  
  if Idempotency.seen?(event.id, event.correlation_id) do
    # Drop duplicate, don't process
    Message.failed(message, :duplicate)
  else
    # Mark as seen, continue processing
    Idempotency.mark!(event.id, event.correlation_id)
    message
  end
end
```

---

## Dead Letter Queue Behavior

### DLQ Routing Conditions

Events are routed to the Dead Letter Queue (DLQ) when:

1. **Retry Budget Exhausted**: Max attempts exceeded per event type
2. **Invalid Event**: Schema validation fails persistently
3. **Handler Crash**: Batch handler crashes repeatedly
4. **Timeout**: Batch processing exceeds timeout threshold

### DLQ Implementation

```elixir
defp handle_batch_failures(messages, failed_events) do
  failed_event_ids = MapSet.new(failed_events, & &1.id)
  
  Enum.map(messages, fn message ->
    event = message.data
    
    if event.id in failed_event_ids do
      attempt = Message.get_metadata(message, :attempt, 1)
      {max_retries, _strategy} = retry_budget(event)
      
      if attempt >= max_retries do
        # Exhausted retries → DLQ
        :telemetry.execute([:thunderline, :event, :dlq], 
          %{event_id: event.id, reason: :max_retries_exceeded})
        
        route_to_dlq(message, :max_retries_exceeded)
        Message.failed(message, :max_retries_exceeded)
      else
        # Calculate backoff and retry
        delay = calculate_backoff(event, attempt)
        
        :telemetry.execute([:thunderline, :event, :retry], 
          %{event_id: event.id, attempt: attempt, delay_ms: delay})
        
        schedule_retry(message, delay, attempt + 1)
        Message.failed(message, {:retry_after, delay})
      end
    else
      # Event succeeded
      message
    end
  end)
end

defp route_to_dlq(message, reason) do
  event = message.data
  
  dlq_record = %{
    event_id: event.id,
    event: event,
    reason: reason,
    failed_at: DateTime.utc_now(),
    attempts: Message.get_metadata(message, :attempt, 1)
  }
  
  # Store in Mnesia DLQ table
  :mnesia.dirty_write({:event_dlq, event.id, dlq_record})
  
  # Publish DLQ event for alerting
  Phoenix.PubSub.broadcast(Thunderline.PubSub, 
    "thunderline:events:dlq", 
    {:event_dlq, dlq_record})
end
```

### DLQ Recovery

**Manual Recovery**:
```elixir
# Query DLQ
dlq_events = :mnesia.dirty_match_object({:event_dlq, :_, :_})

# Inspect failed event
[{:event_dlq, event_id, record}] = dlq_events
IO.inspect(record.reason)

# Reprocess event (after fixing root cause)
Thunderline.EventBus.publish_event(record.event)

# Remove from DLQ
:mnesia.dirty_delete({:event_dlq, event_id})
```

**Automated Recovery** (for transient failures):
```elixir
# Periodic DLQ reprocessing job (every 1 hour)
defmodule Thunderline.Jobs.DLQRetry do
  use Oban.Worker, queue: :maintenance
  
  @impl Oban.Worker
  def perform(_job) do
    # Retry events failed due to transient errors
    :mnesia.dirty_match_object({:event_dlq, :_, %{reason: :timeout}})
    |> Enum.each(fn {:event_dlq, event_id, record} ->
      Thunderline.EventBus.publish_event(record.event)
      :mnesia.dirty_delete({:event_dlq, event_id})
    end)
    
    :ok
  end
end
```

---

## Configuration Options

### Backoff Configuration

**Global Settings** (`Backoff.config/0`):
```elixir
%{
  min_ms: 1_000,        # Minimum delay: 1 second
  max_ms: 300_000,      # Maximum delay: 300 seconds (5 minutes)
  jitter_pct: 0.20      # Jitter: ±20% of base delay
}
```

**Tuning Guidelines**:

| Parameter | Default | Range | Impact |
|-----------|---------|-------|--------|
| `min_ms` | 1,000 | 100-5,000 | Lower = faster retries, higher CPU load |
| `max_ms` | 300,000 | 10,000-600,000 | Lower = faster failure detection, higher pressure on failing systems |
| `jitter_pct` | 0.20 | 0.0-0.5 | Lower = more synchronized retries, higher = better thundering herd prevention |

### Retry Budget Customization

**Per-Event-Type Configuration**:
```elixir
defmodule MyApp.CustomRetryPolicy do
  def retry_budget(%{name: "custom.event." <> _}), do: {10, :exponential}
  def retry_budget(%{name: "fast.fail." <> _}), do: {1, :none}
  def retry_budget(event), do: {3, :exponential}  # Default
end
```

**Linear Backoff Example**:
```elixir
def retry_budget(%{name: "rate.limited.api." <> _}), do: {5, {:linear, 10_000}}
# Attempts: 0ms, 10s, 20s, 30s, 40s
```

### Broadway Producer Tuning

**High-Throughput Configuration**:
```elixir
producer: [
  module: {MnesiaProducer, [
    table: :thunderline_events,
    poll_interval: 500,        # Poll more frequently (500ms)
    max_batch_size: 100        # Larger batches (100 events)
  ]},
  concurrency: 1
],
processors: [
  default: [
    concurrency: 20,             # More processors (20 concurrent)
    min_demand: 10,
    max_demand: 50               # Higher demand (50 events)
  ]
]
```

**Low-Latency Configuration**:
```elixir
batchers: [
  critical_events: [
    concurrency: 5,              # More handlers (5 concurrent)
    batch_size: 5,               # Smaller batches (5 events)
    batch_timeout: 100           # Shorter timeout (100ms)
  ]
]
```

---

## Best Practices

### Event Creation

**DO**:
- ✅ Use `name` field to categorize events for retry budgets
- ✅ Set `priority: :critical` for time-sensitive events
- ✅ Include `correlation_id` for transaction tracking across retries
- ✅ Use descriptive event names matching retry budget patterns

**DON'T**:
- ❌ Mix transient and permanent failures in same event type
- ❌ Use generic event names (e.g., `system.error`)
- ❌ Omit `correlation_id` (breaks retry chain tracking)
- ❌ Set all events to `:critical` priority (defeats fast-path optimization)

**Example**:
```elixir
# GOOD: Specific event name, priority, correlation
%Thunderline.Event{
  name: "ml.run.failed",
  source: :bolt,
  priority: :high,
  correlation_id: Thunderline.UUID.v7(),
  payload: %{
    run_id: "run_123",
    error: :gpu_oom,
    retryable: true
  }
}

# BAD: Generic name, no priority, no correlation
%Thunderline.Event{
  name: "error",
  source: :bolt,
  payload: %{reason: "something failed"}
}
```

### Retry Budget Design

**DO**:
- ✅ Set higher retry budgets for expensive operations (ML runs, API calls)
- ✅ Use exponential backoff for transient failures
- ✅ Use linear backoff for rate-limited APIs
- ✅ Set low retry budgets for UI commands (fast-fail)
- ✅ Monitor DLQ size to tune retry budgets

**DON'T**:
- ❌ Set unlimited retries (prevents DLQ routing)
- ❌ Use same retry budget for all event types
- ❌ Set retry budgets higher than batch timeout (causes timeout loops)
- ❌ Ignore DLQ growth (indicates systemic failures)

**Example**:
```elixir
# GOOD: Tailored retry budgets
def retry_budget(%{name: "ml.run." <> _}), do: {5, :exponential}     # Expensive
def retry_budget(%{name: "ui.command." <> _}), do: {2, :none}        # Fast-fail
def retry_budget(%{name: "api.call." <> _}), do: {4, {:linear, 5_000}}  # Rate-limited
def retry_budget(_), do: {3, :exponential}                           # Default

# BAD: One-size-fits-all
def retry_budget(_event), do: {10, :exponential}
```

### Pipeline Configuration

**DO**:
- ✅ Monitor batch timeout vs retry delay (ensure delay < timeout)
- ✅ Tune `batch_size` based on event throughput
- ✅ Set `critical_events` batcher concurrency lower than `domain_events`
- ✅ Use telemetry to measure batch processing time
- ✅ Test idempotency with duplicate event injection

**DON'T**:
- ❌ Set `batch_timeout` lower than max backoff delay
- ❌ Use identical batcher configuration for all event types
- ❌ Ignore batch processing time (causes timeout cascades)
- ❌ Disable idempotency checking (causes double-processing)

**Example**:
```elixir
# GOOD: Balanced configuration
batchers: [
  domain_events: [
    concurrency: 5,              # Standard throughput
    batch_size: 25,              # Reasonable batch
    batch_timeout: 2_000         # 2s timeout > max 300s delay
  ],
  critical_events: [
    concurrency: 2,              # Lower concurrency for urgent events
    batch_size: 10,              # Smaller batches for speed
    batch_timeout: 500           # 500ms fast-path
  ]
]

# BAD: Unbalanced configuration
batchers: [
  domain_events: [
    concurrency: 1,              # Too low, bottlenecks throughput
    batch_size: 1000,            # Too high, causes timeouts
    batch_timeout: 100           # Too low, shorter than retry delays
  ]
]
```

### Monitoring & Alerting

**Key Telemetry Events**:
```elixir
# Retry attempts
[:thunderline, :event, :retry]
%{event_id: id, attempt: 3, delay_ms: 4_000}

# DLQ routing
[:thunderline, :event, :dlq]
%{event_id: id, reason: :max_retries_exceeded}

# Batch processing
[:thunderline, :pipeline, :domain_events, :start]
[:thunderline, :pipeline, :domain_events, :stop]
[:thunderline, :pipeline, :domain_events, :error]

# Deduplication
[:thunderline, :event, :dedup]
%{event_id: id}
```

**Alert Thresholds**:
- **Retry Rate > 10%**: Investigate transient failures
- **DLQ Size > 100**: Check for systemic issues
- **Batch Timeout Rate > 5%**: Tune batch size or concurrency
- **Dedup Rate > 20%**: Check for producer duplication

---

## Summary

**Key Takeaways**:

1. **Event-Specific Budgets**: ML runs (5), ML trials (3), UI commands (2), default (3)
2. **Exponential Backoff**: Default strategy with ±20% jitter, capped at 300s
3. **Fast-Path**: Critical events use separate batcher with 500ms timeout
4. **Idempotency**: Composite key (event ID + correlation ID) prevents duplicates
5. **DLQ Routing**: Max retries exceeded → DLQ with alerting
6. **Tuning**: Monitor telemetry, adjust retry budgets and batcher config

**Related Documentation**:
- [EVENT_FLOWS.md](./EVENT_FLOWS.md) - Event architecture and pipeline
- [EVENT_TROUBLESHOOTING.md](./EVENT_TROUBLESHOOTING.md) - Debugging event issues
- [EVENT_TAXONOMY.md](./documentation/EVENT_TAXONOMY.md) - Event naming conventions
