# Event Flows - Thunderline Event System

> **Status**: Production Reference  
> **Last Updated**: Sprint 3 Documentation Phase  
> **Related**: [EVENT_TAXONOMY.md](documentation/EVENT_TAXONOMY.md), [CEREBROS_SETUP.md](CEREBROS_SETUP.md)

## Overview

This document describes the event flow architecture in Thunderline, from event creation through validation, routing, and consumption. It serves as an operational guide for understanding how events move through the system and how different components interact with the event pipeline.

## Table of Contents

1. [Event Architecture](#event-architecture)
2. [Event Taxonomy](#event-taxonomy)
3. [Event Creation & Validation](#event-creation--validation)
4. [Pipeline Architecture](#pipeline-architecture)
5. [Routing & Batching](#routing--batching)
6. [Cross-Domain Event Flows](#cross-domain-event-flows)
7. [Example Event Flows](#example-event-flows)
8. [Idempotency & Deduplication](#idempotency--deduplication)
9. [Best Practices](#best-practices)

---

## Event Architecture

Thunderline uses a Broadway-based event pipeline with three main stages:

```
Event Creation → Validation → EventBus Enqueue → Pipeline Processing → Batcher Routing → Consumption
     ↓              ↓              ↓                    ↓                    ↓                ↓
  new/1         Validator      Mnesia Table      Idempotency Check    domain_events    Handlers
                                                                       critical_events
```

### Key Components

**Event Struct** (`Thunderline.Event`)
- Canonical event representation
- Dual envelope: taxonomy (new) + legacy (transition)
- Smart constructor with validation
- UUID v7 identifiers for time-ordered correlation

**Event Validator** (`Thunderline.Thunderflow.EventValidator`)
- Pre-publication validation
- Reserved prefix enforcement
- Correlation ID validation (UUID v7)
- Mode-based failure handling (warn/raise/drop)

**Event Bus** (`Thunderline.Thunderflow.EventBus`)
- Publication interface
- Mnesia table persistence
- Telemetry instrumentation
- Shim for legacy `Thunderline.Bus` references

**Event Pipeline** (`Thunderline.Thunderflow.Pipelines.EventPipeline`)
- Broadway pipeline with MnesiaProducer
- Idempotency checking
- Dual batcher routing
- Transform & enrichment

---

## Event Taxonomy

### Reserved Prefix Families

Thunderline enforces a strict taxonomy with 9 reserved prefix families:

| Prefix | Domain | Purpose | Examples |
|--------|--------|---------|----------|
| `system.*` | All | Internal system actions, infrastructure events | `system.email.sent`, `system.presence.join` |
| `reactor.*` | Flow | Reactor orchestration, step execution | `reactor.step.started`, `reactor.saga.completed` |
| `ui.*` | Gate, Link | User interface commands, raw user intent | `ui.command.email.requested`, `ui.command.voice.room.requested` |
| `audit.*` | All | Audit trail events, compliance logging | `audit.event_drop`, `audit.policy.changed` |
| `evt.*` | Bolt | Experimental namespace (tight allowlist) | `evt.action.ca.rule_parsed` |
| `ml.*` | Bolt | Machine learning lifecycle | `ml.run.completed`, `ml.trial.started` |
| `ai.*` | Crown, Flow | AI orchestration, intent interpretation | `ai.intent.email.compose`, `ai.tool_start` |
| `flow.*` | Flow | Flow control, pipeline events | `flow.reactor.retry` |
| `grid.*` | Grid | Spatial grid operations | `grid.zone.updated`, `grid.voxel.mutated` |

### Naming Conventions

Events follow a hierarchical naming structure:

```
<layer>.<domain>.<category>.<action>[.<phase>]
```

**Requirements:**
- Minimum 2 segments (e.g., `system.heartbeat`)
- Use singular nouns (`email`, not `emails`)
- Prefer verbs for terminal actions (`sent`, `failed`, `completed`)
- Phases are optional (`system.email.dispatch.started` vs `system.email.sent`)

**Examples:**
```elixir
✅ VALID
"ui.command.email.requested"      # User interface command
"system.email.sent"                # System action result
"ai.intent.email.compose"          # AI interpretation
"ml.run.completed"                 # ML lifecycle
"flow.reactor.retry"               # Reactor orchestration

❌ INVALID
"sent"                             # < 2 segments
"user_created"                     # No namespace
"emails.sent"                      # Plural noun
"UI.Command.Email"                 # Wrong case
```

### Domain → Event Category Matrix

Each domain has allowed event categories it can emit:

| Source Domain | Allowed Categories | Purpose |
|---------------|-------------------|---------|
| `:gate` | `ui.command`, `system`, `presence`, `device` | Auth flows, presence, device enrollment |
| `:flow` | `flow.reactor`, `system`, `ai` | Reactor orchestration, pipelines |
| `:bolt` | `ml.run`, `ml.trial`, `system`, `ai`, `pac`, `thundra` | ML lifecycle, PAC orchestration |
| `:link` | `ui.command`, `system`, `voice.signal`, `voice.room`, `device` | Comms, voice, TOCP transport |
| `:crown` | `ai.intent`, `system`, `ai`, `pac` | AI governance, intent interpretation |
| `:block` | `system`, `pac` | Provisioning, tenancy, PAC storage |
| `:bridge` | `system`, `ui.command`, `ai` | External ingest normalization |
| `:unknown` | `system`, `ai` | Fallback for unclassified events |

**Enforcement:** EventValidator rejects events with forbidden domain/category combinations.

---

## Event Creation & Validation

### Creating Events

Events are created using the smart constructor `Thunderline.Event.new/1`:

```elixir
# Minimal event (correlation_id auto-generated)
{:ok, event} = Thunderline.Event.new(
  name: "system.email.sent",
  source: :link,
  payload: %{message_id: "msg_123", to: ["user@example.com"], subject: "Hello"}
)

# Full event with correlation tracking
{:ok, event} = Thunderline.Event.new(
  name: "system.email.sent",
  source: :link,
  payload: %{message_id: "msg_123", to: ["user@example.com"]},
  correlation_id: "01234567-89ab-cdef-0123-456789abcdef",  # Explicit tracking
  causation_id: "parent_event_id",                          # Parent event reference
  actor: %{id: "user_123", type: :user},                    # Actor context
  event_version: 2,                                         # Schema version
  meta: %{reliability: :persistent}                         # Metadata
)

# Raising version for tight error handling
event = Thunderline.Event.new!(
  name: "ml.run.completed",
  source: :bolt,
  payload: %{run_id: "run_456", duration_ms: 1234}
)
```

### Constructor Validation

The constructor validates:
- **Name format**: Minimum 2 segments, valid string
- **Category allowance**: Domain/category matrix enforcement
- **Payload**: Must be a map
- **Source**: Must be an atom

```elixir
# Validation failure examples
{:error, [{:missing, :name}]} = Thunderline.Event.new(
  source: :gate,
  payload: %{}
  # Missing name
)

{:error, [{:forbidden_category, {:block, "ai.intent.test"}}]} = Thunderline.Event.new(
  name: "ai.intent.test",  # Block domain cannot emit ai.intent.*
  source: :block,
  payload: %{}
)

{:error, [{:invalid_format, "sent"}]} = Thunderline.Event.new(
  name: "sent",  # < 2 segments
  source: :link,
  payload: %{}
)
```

### Pre-Publication Validation

Before events reach the pipeline, `EventValidator` applies additional checks:

```elixir
defmodule Thunderline.Thunderflow.EventValidator do
  @reserved_prefixes ~w(system. reactor. ui. audit. evt. ml. ai. flow. grid.)
  @uuid_v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  # Validation checks:
  # 1. Name has >= 2 segments
  # 2. Reserved prefix is in allowed list
  # 3. correlation_id is UUID v7 format
  # 4. taxonomy_version >= 1
  # 5. event_version >= 1
  # 6. meta is a map
end
```

**Validation Modes:**

| Mode | Environment | Behavior | Use Case |
|------|-------------|----------|----------|
| `:warn` | Development | Log warning + telemetry, allow event | Iterative development |
| `:raise` | Test | Raise `ArgumentError`, fail fast | Test suite validation |
| `:drop` | Production | Drop event + emit audit event | Graceful degradation |

```elixir
# Development: warnings logged
config :thunderline, :event_validator_mode, :warn

# Test: strict validation
config :thunderline, :event_validator_mode, :raise

# Production: drop silently with audit
config :thunderline, :event_validator_mode, :drop
```

**Telemetry Events:**
- `[:thunderline, :event, :validated]` - Validation result (`:ok` or `:error`)
- `[:thunderline, :event, :dropped]` - Event dropped in `:drop` mode

**Audit Trail:**
When an event is dropped (mode: `:drop`), an audit event is emitted:

```elixir
# Audit event structure
%{
  name: "audit.event_drop",
  source: :flow,
  payload: %{
    original_name: "invalid.event",
    reason: "reserved_prefix_violation",
    dropped_at: ~U[2024-01-15 10:30:00Z]
  }
}
```

---

## Pipeline Architecture

### Broadway Configuration

The Event Pipeline uses Broadway with MnesiaProducer for reliable event processing:

```elixir
defmodule Thunderline.Thunderflow.Pipelines.EventPipeline do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Thunderflow.MnesiaProducer, poll_interval: 1000, max_batch_size: 50},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10, min_demand: 5, max_demand: 20]
      ],
      batchers: [
        domain_events: [concurrency: 5, batch_size: 25, batch_timeout: 2000],
        critical_events: [concurrency: 2, batch_size: 10, batch_timeout: 500]
      ]
    )
  end
end
```

**Producer Settings:**
- **poll_interval**: 1000ms - How often to check Mnesia for new events
- **max_batch_size**: 50 - Maximum events per producer batch
- **concurrency**: 1 - Single producer (Mnesia table read serialization)

**Processor Settings:**
- **concurrency**: 10 - Parallel message processing
- **min_demand**: 5 - Minimum events to request
- **max_demand**: 20 - Maximum events to request

**Batcher Settings:**

| Batcher | Concurrency | Batch Size | Timeout | Purpose |
|---------|-------------|------------|---------|---------|
| `domain_events` | 5 | 25 | 2000ms | Standard domain events, moderate throughput |
| `critical_events` | 2 | 10 | 500ms | High-priority events, fast processing |

### Pipeline Stages

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│  Mnesia     │    │  Processor   │    │  Batcher    │    │  Handler    │
│  Producer   │───→│  Idempotency │───→│  Routing    │───→│  Execution  │
│  Poll 1s    │    │  Transform   │    │  Batching   │    │  Telemetry  │
└─────────────┘    └──────────────┘    └─────────────┘    └─────────────┘
      ↓                    ↓                    ↓                   ↓
  Fetch 50         Check seen?          domain_events        Process batch
  events           Transform            critical_events      Emit telemetry
                   Enrich                                    Broadcast
```

**Stage 1: Producer**
- Polls Mnesia table every 1 second
- Fetches up to 50 events per poll
- Maintains event ordering within table

**Stage 2: Processor**
1. **Idempotency Check**: `Idempotency.seen?/1`
   - Check if event already processed
   - Generate idempotency key from event ID + correlation ID
   - Emit telemetry on duplicate: `[:thunderline, :event, :dedup]`

2. **Transform**: `transform_event/1`
   - Normalize event shape (taxonomy envelope + legacy)
   - Enrich with metadata (processing node, trace ID, timestamp)
   - Validate schema

3. **Routing**: `determine_batcher/1`
   - Route to `domain_events` or `critical_events`
   - Based on priority field (`:high`, `:critical`)

**Stage 3: Batcher**
- Accumulate events based on batcher configuration
- Emit telemetry: `[:thunderline, :pipeline, :domain_events, :start]`
- Batch processing with error handling
- Emit completion telemetry: `[:thunderline, :pipeline, :domain_events, :stop]`

**Stage 4: Handler**
- Process batch of events
- Emit domain-specific events
- Broadcast to PubSub: `thunderflow:batch_completed`
- Handle failures with DLQ routing

---

## Routing & Batching

### Batcher Selection

Events are routed to batchers based on priority:

```elixir
defp determine_batcher(%{"severity" => severity}) when severity in ["critical", "error"],
  do: :critical_events

defp determine_batcher(%{"priority" => priority}) when priority in [:high, :critical],
  do: :critical_events

defp determine_batcher(_event), do: :domain_events
```

**Routing Logic:**
- **Critical Events** → `:critical_events` batcher
  - `priority: :critical` or `priority: :high`
  - `severity: "critical"` or `severity: "error"`
  - Faster processing (500ms timeout vs 2000ms)
  - Smaller batches (10 vs 25)
  - Lower concurrency (2 vs 5)

- **Domain Events** → `:domain_events` batcher
  - All other events
  - Standard throughput processing
  - Larger batches for efficiency
  - Higher concurrency for parallelism

### Batch Processing

**Domain Events Batch:**
```elixir
def handle_batch(:domain_events, messages, _batch_info, _context) do
  Logger.debug("Processing batch of #{length(messages)} domain events")
  events = Enum.map(messages, & &1.data)

  # Emit telemetry
  :telemetry.execute(
    [:thunderline, :pipeline, :domain_events, :start],
    %{count: length(messages)},
    %{}
  )

  # Process batch
  case process_domain_events_batch(events) do
    :ok ->
      :telemetry.execute(
        [:thunderline, :pipeline, :domain_events, :stop],
        %{count: length(messages)},
        %{}
      )

      # Broadcast completion
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderflow:batch_completed",
        {:domain_events_processed, length(events)}
      )

      messages

    {:error, failed_events} ->
      handle_batch_failures(messages, failed_events)
  end
end
```

**Critical Events Batch:**
```elixir
def handle_batch(:critical_events, messages, _batch_info, _context) do
  Logger.warning("Processing batch of #{length(messages)} critical events")
  events = Enum.map(messages, & &1.data)

  # Higher priority telemetry
  :telemetry.execute(
    [:thunderline, :pipeline, :critical_events, :start],
    %{count: length(messages)},
    %{}
  )

  case process_critical_events_batch(events) do
    :ok ->
      # Immediate notification
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderflow:critical_processed",
        {:critical_events_processed, length(events), DateTime.utc_now()}
      )

      messages

    {:error, reason} ->
      # Send alerts
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderline:alerts:critical",
        {:critical_event_processing_failed, reason}
      )

      Enum.map(messages, &Message.failed(&1, reason))
  end
end
```

---

## Cross-Domain Event Flows

### Correlation & Causation Threading

Events maintain lineage through correlation and causation IDs:

```elixir
# Event envelope fields for lineage
%Thunderline.Event{
  id: "event_001",              # This event's unique ID (UUID v7)
  correlation_id: "corr_123",   # Transaction/flow identifier
  causation_id: "event_000"     # Parent event that triggered this one
}
```

**Correlation Rules:**

| Scenario | Correlation ID | Causation ID | Example |
|----------|---------------|--------------|---------|
| First user command | `correlation_id = id` | `causation_id = nil` | `ui.command.email.requested` |
| AI intent derived | Inherit from parent | `causation_id = parent.id` | `ai.intent.email.compose` |
| Reactor step | Inherit | `causation_id = previous_step.id` | `flow.reactor.retry` |
| Terminal event | Inherit | `causation_id = immediate_predecessor` | `system.email.sent` |
| Fanout (parallel) | Inherit | `causation_id = split_event.id` | Multiple parallel steps |

**Example Flow:**

```elixir
# 1. User requests email send
{:ok, cmd_event} = Event.new(
  name: "ui.command.email.requested",
  source: :gate,
  payload: %{to: "user@example.com", raw_text: "Hello"},
  correlation_id: Event.gen_uuid(),  # New correlation (root)
  causation_id: nil                  # Root event, no parent
)

# 2. AI interprets intent
{:ok, intent_event} = Event.new(
  name: "ai.intent.email.compose",
  source: :crown,
  payload: %{to: ["user@example.com"], topic: "greeting", confidence: 0.95},
  correlation_id: cmd_event.correlation_id,  # Inherit correlation
  causation_id: cmd_event.id                 # This event caused intent
)

# 3. System sends email
{:ok, sent_event} = Event.new(
  name: "system.email.sent",
  source: :link,
  payload: %{message_id: "msg_789", to: ["user@example.com"]},
  correlation_id: cmd_event.correlation_id,  # Same flow
  causation_id: intent_event.id              # Intent caused send
)
```

**Trace Visualization:**

```
ui.command.email.requested (id=cmd_001, corr=cmd_001, cause=nil)
  │
  └─→ ai.intent.email.compose (id=int_001, corr=cmd_001, cause=cmd_001)
       │
       └─→ system.email.sent (id=sent_001, corr=cmd_001, cause=int_001)
```

### Domain Boundary Crossing

Events cross domain boundaries with preserved context:

```elixir
# Gate domain receives UI command
{:ok, cmd} = Event.new(
  name: "ui.command.voice.room.requested",
  source: :gate,                           # Gate domain
  payload: %{title: "Team Standup"},
  actor: %{id: "user_123", type: :user}    # Actor preserved
)

# Crown domain interprets intent
{:ok, intent} = Event.new(
  name: "ai.intent.voice.room.create",
  source: :crown,                          # Crown domain
  correlation_id: cmd.correlation_id,      # Preserved
  causation_id: cmd.id,
  actor: cmd.actor                         # Actor propagated
)

# Link domain creates room
{:ok, created} = Event.new(
  name: "system.voice.room.created",
  source: :link,                           # Link domain
  payload: %{room_id: "room_456"},
  correlation_id: cmd.correlation_id,      # Preserved
  causation_id: intent.id,
  actor: cmd.actor                         # Actor propagated
)
```

**Best Practices:**
- ✅ Preserve `correlation_id` across all events in a flow
- ✅ Set `causation_id` to immediate parent event
- ✅ Propagate `actor` context for authorization
- ✅ Use explicit correlation IDs (not auto-generated) for traceability
- ❌ Never re-base correlation mid-flow
- ❌ Don't create circular causation chains

---

## Example Event Flows

### Email Send Flow

```
User Input → UI Command → AI Intent → Email Service → Success Event

Step 1: User requests email
────────────────────────────
ui.command.email.requested
  source: :gate
  actor: {id: "user_123", type: :user}
  correlation_id: "corr_email_001" (NEW)
  causation_id: nil

Step 2: AI interprets intent
─────────────────────────────
ai.intent.email.compose
  source: :crown
  correlation_id: "corr_email_001" (INHERITED)
  causation_id: "ui.command.email.requested.id"

Step 3: Email sent successfully
────────────────────────────────
system.email.sent
  source: :link
  payload: {message_id: "msg_789"}
  correlation_id: "corr_email_001" (INHERITED)
  causation_id: "ai.intent.email.compose.id"
```

### Voice Room Creation Flow

```
UI Command → Room Creation → Participant Join → Recording Start

Step 1: User requests voice room
─────────────────────────────────
ui.command.voice.room.requested
  source: :gate
  payload: {title: "Team Standup"}
  correlation_id: "corr_voice_001" (NEW)

Step 2: Room created
────────────────────
system.voice.room.created
  source: :link
  payload: {room_id: "room_456"}
  correlation_id: "corr_voice_001"

Step 3: Participant joins
──────────────────────────
voice.room.participant.joined
  source: :link
  payload: {room_id: "room_456", participant_id: "user_123"}
  correlation_id: "corr_voice_001"

Step 4: Recording starts
─────────────────────────
voice.room.recording.started
  source: :link
  payload: {room_id: "room_456", recording_id: "rec_789"}
  correlation_id: "corr_voice_001"
```

### ML Run Flow with Retry

```
ML Run Start → Failure → Retry → Success

Step 1: ML run starts
─────────────────────
ml.run.started
  source: :bolt
  payload: {run_id: "run_123", model: "gpt-4"}
  correlation_id: "corr_ml_001" (NEW)

Step 2: Run fails (transient error)
────────────────────────────────────
ml.run.failed
  source: :bolt
  payload: {run_id: "run_123", reason: "timeout"}
  correlation_id: "corr_ml_001"

Step 3: Retry triggered
────────────────────────
flow.reactor.retry
  source: :flow
  payload: {reactor: "MLRunner", step: "inference", attempt: 2}
  correlation_id: "corr_ml_001"

Step 4: Run completes
──────────────────────
ml.run.completed
  source: :bolt
  payload: {run_id: "run_123", duration_ms: 5432}
  correlation_id: "corr_ml_001"
```

---

## Idempotency & Deduplication

### Idempotency Strategy

The pipeline uses idempotency checking to prevent duplicate event processing:

```elixir
defp handle_message(_processor, message, _context) do
  event = message.data

  # Generate idempotency key
  key = idempotency_key(event)

  # Check if already processed
  case Idempotency.seen?(key) do
    true ->
      # Emit deduplication telemetry
      :telemetry.execute(
        [:thunderline, :event, :dedup],
        %{count: 1},
        %{event_name: event["name"]}
      )

      # Cancel processing (ack but skip)
      Message.put_broadway_cancelled(message)

    false ->
      # Mark as seen and process
      Idempotency.mark!(key)
      transformed = transform_event(event)
      batcher = determine_batcher(transformed)
      Message.put_batcher(message, batcher)
  end
end
```

**Idempotency Key Generation:**

```elixir
defp idempotency_key(%{"id" => id, "correlation_id" => corr}) do
  "event:#{id}:#{corr}"
end

defp idempotency_key(%{id: id, correlation_id: corr}) do
  "event:#{id}:#{corr}"
end
```

**Deduplication Scenarios:**

| Scenario | Key Components | Behavior |
|----------|---------------|----------|
| Same event re-published | `id` + `correlation_id` | Deduplicated, telemetry emitted |
| Retry after failure | Different `id`, same `correlation_id` | Processed (different key) |
| Parallel processing | Same `id`, different nodes | One succeeds, others deduplicated |

### Telemetry Events

```elixir
# Deduplication detected
:telemetry.execute(
  [:thunderline, :event, :dedup],
  %{count: 1},
  %{event_name: "system.email.sent"}
)

# Query in observer
:telemetry.attach(
  "dedup-logger",
  [:thunderline, :event, :dedup],
  fn _name, measurements, metadata, _config ->
    Logger.info("Deduplicated event: #{metadata.event_name}")
  end,
  nil
)
```

---

## Best Practices

### Event Creation

✅ **DO:**
- Use `Event.new/1` for all event creation
- Provide explicit `correlation_id` for traceability
- Set `causation_id` to parent event ID
- Propagate `actor` context across domains
- Use semantic event names from taxonomy
- Include version numbers for schema evolution
- Add metadata for observability

```elixir
# Good: Explicit correlation and context
{:ok, event} = Event.new(
  name: "system.email.sent",
  source: :link,
  payload: %{message_id: "msg_123"},
  correlation_id: parent_event.correlation_id,
  causation_id: parent_event.id,
  actor: %{id: "user_123", type: :user}
)
```

❌ **DON'T:**
- Create raw event maps without constructor
- Auto-generate correlation IDs for non-root events
- Rebase correlation mid-flow
- Emit events with forbidden domain/category combinations
- Use unstructured event names
- Skip actor context for authorization

```elixir
# Bad: Raw map, missing context
event = %{
  type: :email_sent,  # Wrong shape
  payload: %{message_id: "msg_123"}
  # Missing correlation, causation, actor
}
```

### Event Validation

✅ **DO:**
- Use `:raise` mode in test environment
- Use `:drop` mode in production
- Monitor validation telemetry
- Review audit events for dropped events
- Update event registry for new events

❌ **DON'T:**
- Use `:warn` mode in production
- Ignore validation failures
- Create events without payload validation
- Skip correlation ID validation

### Pipeline Configuration

✅ **DO:**
- Use `critical_events` batcher for high-priority events
- Monitor batch processing telemetry
- Configure appropriate batch sizes for throughput
- Set reasonable timeouts for batch processing
- Monitor idempotency deduplication rates

❌ **DON'T:**
- Route all events to `critical_events`
- Set batch timeouts too low (< 500ms)
- Ignore batch processing failures
- Skip idempotency checking

### Correlation Tracking

✅ **DO:**
- Start new correlation for root events (UI commands, external webhooks)
- Inherit correlation for derived events
- Set causation to immediate parent
- Use UUID v7 for time-ordered correlation
- Document correlation flows in event documentation

❌ **DON'T:**
- Create circular causation chains
- Mix correlation IDs from different flows
- Skip causation for non-root events
- Use random UUIDs (prefer UUID v7)

### Observability

✅ **DO:**
- Attach telemetry handlers for key events
- Monitor validation, deduplication, and batch processing
- Track correlation IDs across distributed traces
- Set up alerts for critical event failures
- Review audit events regularly

```elixir
# Good: Comprehensive telemetry monitoring
:telemetry.attach_many(
  "event-metrics",
  [
    [:thunderline, :event, :validated],
    [:thunderline, :event, :dropped],
    [:thunderline, :event, :dedup],
    [:thunderline, :pipeline, :domain_events, :start],
    [:thunderline, :pipeline, :critical_events, :error]
  ],
  &handle_event/4,
  nil
)
```

❌ **DON'T:**
- Ignore telemetry events
- Skip error monitoring
- Overlook deduplication spikes
- Miss validation failures

---

## Related Documentation

- [EVENT_TAXONOMY.md](documentation/EVENT_TAXONOMY.md) - Comprehensive event taxonomy specification
- [EVENT_RETRY_STRATEGIES.md](EVENT_RETRY_STRATEGIES.md) - Retry policies and backoff strategies
- [EVENT_TROUBLESHOOTING.md](EVENT_TROUBLESHOOTING.md) - Debugging and troubleshooting guide
- [CEREBROS_SETUP.md](CEREBROS_SETUP.md) - Event system setup and configuration

---

**Document Version**: 1.0  
**Maintained By**: Platform Engineering  
**Review Cycle**: Quarterly or on major event system changes
