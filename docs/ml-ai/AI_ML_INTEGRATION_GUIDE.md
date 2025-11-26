# AI/ML Integration Guide

## Event Stream Architecture

### Canonical Event Sources

**Source of Truth for Stream Consumption: `Thunderflow.MnesiaProducer`**

All Broadway consumers that process events from the Thunderline event system MUST use `Thunderflow.MnesiaProducer` as their producer module. This ensures:

- **Back-pressure management**: MnesiaProducer implements proper demand/batching
- **Persistence**: Events are durably stored in Mnesia tables
- **Ordering guarantees**: FIFO within a single producer instance
- **Fault tolerance**: Events survive process crashes

```elixir
# CORRECT: Use MnesiaProducer for event consumption
producer: [
  module: {Thunderflow.MnesiaProducer,
    table: Thunderflow.MnesiaProducer,
    poll_interval: 1_000,
    max_batch_size: 10,
    broadway_name: __MODULE__}
]
```

```elixir
# WRONG: Do NOT consume from PubSub directly
# PubSub is for notifications only, not back-pressure queues
producer: [
  module: {SomePubSubProducer, topic: "events"}
]
```

### EventBus vs MnesiaProducer

- **`Thunderline.EventBus`**: Publish-only API wrapper
  - Use for: Publishing events to the system
  - Functions: `publish_event/1`, `publish_event!/1`
  - Does NOT support: `subscribe/3` (deliberately)

- **`Thunderflow.MnesiaProducer`**: Internal event queue
  - Use for: Broadway producer configuration
  - Provides: Durable storage, back-pressure, batching
  - Consumer pattern: Broadway pipelines

- **`Phoenix.PubSub`**: Notification layer
  - Use for: Real-time notifications, LiveView updates
  - NOT for: Event processing pipelines (no persistence)

## ML Pipeline Event Flow

```
┌─────────────┐
│   Ingest    │ publishes via EventBus.publish_event/1
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│  Thunderflow.EventBus   │ (wrapper)
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ MnesiaProducer (table)  │ (durable queue)
└──────────┬──────────────┘
           │
           ├─────────────────────────┐
           │                         │
           ▼                         ▼
┌───────────────────┐    ┌──────────────────┐
│   Classifier      │    │   Other          │
│   (Broadway)      │    │   Consumers      │
└───────────────────┘    └──────────────────┘
```

## Event Taxonomy Migration

### New Standard (enforced going forward)

Events MUST use the following structure:

```elixir
%Thunderline.Event{
  name: "ui.command.ingest.received",  # NEW: taxonomy field
  payload: %{                           # NEW: data field
    bytes: binary,
    filename: "file.pdf",
    correlation_id: "uuid"
  },
  source: :thunderflow,
  occurred_at: ~U[2024-01-01 00:00:00Z]
}
```

### Legacy Support (migration shim)

Consumers MAY still read legacy events during transition:

```elixir
%Thunderline.Event{
  type: "ui.command.ingest.received",  # LEGACY: old taxonomy
  data: %{                              # LEGACY: old payload
    bytes: binary,
    filename: "file.pdf"
  }
}
```

**Migration Policy**:
- New code MUST emit `name` + `payload`
- Consumers MUST handle both formats during transition
- Compile-time checks forbid new `type` emissions
- Full migration target: Q1 2025

## DLQ Invariants

All DLQ (Dead Letter Queue) messages MUST include:

```elixir
%{
  root_correlation_id: "uuid",
  voxel_candidate_id: "uuid",       # If applicable
  error_type: :classification_failed,
  error_reason: "...",
  magika_exit_code: 1,              # If applicable
  original_event: %Event{},
  failed_at: ~U[...],
  retry_count: 0
}
```

## References

- [Event Taxonomy](EVENT_TAXONOMY.md)
- [Magika Quick Start](MAGIKA_QUICK_START.md)
- [ML Pipeline Roadmap](ML_PIPELINE_EXECUTION_ROADMAP.md)
