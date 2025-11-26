# Thunderline Event Taxonomy

> **Status**: HC-03 Specification | **Version**: 1.0 | **Last Updated**: 2025-11-25

This document defines the canonical event naming taxonomy for Thunderline's event-driven architecture.

---

## 1. Event Structure

All events must be constructed via `Thunderline.Event.new/1` and conform to this structure:

```elixir
%Thunderline.Event{
  # Taxonomy Envelope (required)
  id: String.t(),                    # UUID v7 (sortable)
  at: DateTime.t(),                  # Event timestamp
  name: String.t(),                  # Canonical event name (see §2)
  source: atom(),                    # Source domain (:gate, :flow, :bolt, etc.)
  correlation_id: String.t(),        # UUID v7 for tracing
  taxonomy_version: pos_integer(),   # Schema version (default: 1)
  event_version: pos_integer(),      # Event-specific version (default: 1)
  payload: map(),                    # Event-specific data
  meta: map(),                       # Pipeline/routing metadata
  
  # Optional Fields
  actor: map() | nil,                # %{id: String.t(), type: atom()}
  causation_id: String.t() | nil,    # Parent event that caused this one
  priority: :low | :normal | :high | :critical
}
```

---

## 2. Event Naming Convention

### 2.1 Format

```
<prefix>.<domain|category>.<action>
```

Event names must have **at least 2 segments** separated by dots.

### 2.2 Reserved Prefixes

| Prefix | Purpose | Example |
|--------|---------|---------|
| `system.` | Infrastructure/lifecycle events | `system.email.sent` |
| `ui.` | User-initiated commands | `ui.command.email.requested` |
| `ai.` | AI/LLM operations | `ai.intent.email.compose` |
| `ml.` | Machine learning pipeline | `ml.run.metrics`, `ml.trial.started` |
| `flow.` | Event flow/reactor operations | `flow.reactor.retry` |
| `audit.` | Governance/compliance events | `audit.event_drop` |
| `grid.` | Cluster coordination | `grid.node.joined` |
| `cluster.` | Distributed system events | `cluster.link.established` |
| `reactor.` | Saga/workflow orchestration | `reactor.step.completed` |
| `evt.` | Experimental namespaces | `evt.action.ca` (Bolt-only) |
| `voice.` | WebRTC/voice signaling | `voice.signal.offer` |
| `stone.` | Cryptographic proofs | `stone.proof.emitted` |
| `foundry.` | Resource factory events | `foundry.blueprint.created` |

---

## 3. Domain → Category Mapping

Each source domain is restricted to specific event category prefixes:

| Domain | Allowed Categories |
|--------|-------------------|
| `:gate` | `ui.command`, `system`, `presence` |
| `:flow` | `flow.reactor`, `system`, `ai` |
| `:bolt` | `ml.run`, `ml.trial`, `ml.artifact`, `system`, `ai`, `evt.action.ca` |
| `:link` | `ui.command`, `system`, `voice.signal`, `voice.room`, `ai` |
| `:crown` | `ai.intent`, `ai.plan`, `system`, `ai` |
| `:block` | `system` (no direct AI emissions) |
| `:bridge` | `system`, `ui.command`, `ai` |
| `:stone` | `stone.proof`, `system` |
| `:foundry` | `foundry.*`, `system` |
| `:thunderlink` | `cluster.node`, `cluster.link`, `system` |
| `:unknown` | `system`, `ai` (fallback) |

**Enforcement**: `Thunderline.Event.new/1` validates source→category compatibility.

---

## 4. Registered Events (Seed Registry)

The following events are pre-registered in `Thunderline.Thunderflow.Events.Registry`:

### 4.1 Email Flow
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `ui.command.email.requested` | 1 | `:persistent` |
| `ai.intent.email.compose` | 1 | `:transient` |
| `system.email.sent` | 1 | `:persistent` |
| `system.email.failed` | 1 | `:persistent` |

### 4.2 Presence
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `system.presence.join` | 1 | `:transient` |
| `system.presence.leave` | 1 | `:transient` |

### 4.3 ML Pipeline
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `ml.trial.started` | 1 | `:persistent` |
| `ml.run.metrics` | 1 | `:transient` |
| `ml.run.completed` | 1 | `:persistent` |
| `ml.artifact.created` | 1 | `:persistent` |

### 4.4 Flow/Reactor
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `flow.reactor.retry` | 1 | `:transient` |

### 4.5 AI Runtime
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `ai.tool_start` | 1 | `:transient` |
| `ai.tool_result` | 1 | `:transient` |
| `ai.model_token` | 1 | `:transient` |
| `ai.conversation_delta` | 1 | `:transient` |

### 4.6 Voice/Signaling
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `voice.signal.offer` | 1 | `:transient` |
| `voice.signal.answer` | 1 | `:transient` |
| `voice.signal.ice` | 1 | `:transient` |

### 4.7 Governance
| Event Name | Version | Reliability |
|------------|---------|-------------|
| `stone.proof.emitted` | 1 | `:persistent` |

---

## 5. Reliability Classification

Events are classified by their delivery guarantee:

| Reliability | Description | Storage | Retry Behavior |
|-------------|-------------|---------|----------------|
| `:persistent` | Must survive restarts, replayed on failure | Mnesia + WAL | Full retry budget |
| `:transient` | Best-effort, acceptable to drop on overload | Memory only | Limited retries |

**Inference Rules** (from `Thunderline.Event`):
- `system.*` → `:persistent`
- `ml.run.*` → `:persistent`
- All others → `:transient` (default)

---

## 6. Validation

### 6.1 EventValidator Modes

Configured via `:thunderline, :event_validator_mode`:

| Mode | Environment | Behavior on Invalid |
|------|-------------|---------------------|
| `:warn` | Development | Log warning, emit telemetry, allow |
| `:raise` | Test | Raise `ArgumentError` (fail fast) |
| `:drop` | Production | Drop event, emit audit event, telemetry |

### 6.2 Validation Rules

1. **Name Format**: ≥2 dot-separated segments
2. **Reserved Prefix**: Must match one of the reserved prefixes (§2.2)
3. **Correlation ID**: Must be present and UUID v7 format
4. **Version Fields**: `taxonomy_version` and `event_version` must be positive integers
5. **Meta**: Must be a map

### 6.3 Linting

Run `mix thunderline.events.lint` to validate event literals in code:

```bash
# Text output
mix thunderline.events.lint

# JSON output (for CI)
mix thunderline.events.lint --format=json
```

**CI Integration**: Stage 4 in `.github/workflows/ci.yml` runs this as a hard gate.

---

## 7. Telemetry Events

The EventBus emits the following telemetry:

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:thunderline, :event, :enqueue]` | `%{count: 1}` | `%{pipeline, name, priority}` |
| `[:thunderline, :event, :publish]` | `%{duration: integer}` | `%{status, name, pipeline}` |
| `[:thunderline, :event, :dropped]` | `%{count: 1}` | `%{reason, name}` |
| `[:thunderline, :event, :validated]` | `%{duration: integer}` | `%{status, name, reason?}` |

---

## 8. Pipeline Routing

Events are routed to pipelines based on:

| Pipeline | Criteria |
|----------|----------|
| `:realtime` | `ai.*`, `grid.*`, `meta.pipeline = :realtime`, `priority = :high` |
| `:cross_domain` | `target_domain` specified (not "broadcast") |
| `:general` | Default fallback |

---

## 9. Adding New Events

1. Add to `Thunderline.Thunderflow.Events.Registry` with version and reliability
2. Ensure source domain is allowed for the category prefix
3. Update this document
4. Run `mix thunderline.events.lint` to verify

---

## 10. Migration Notes

### Legacy Fields (Deprecated but Supported)
- `type` → Inferred from `name` (last segment as atom)
- `source_domain` → String version of `source`
- `target_domain` → Defaults to `"broadcast"`
- `timestamp` → Use `at` instead

### Breaking Changes (Future)
- `taxonomy_version: 2` will require explicit `actor` for all events
- `evt.*` namespace will be promoted from experimental once Bolt adoption matures

---

## References

- `lib/thunderline/thunderflow/event.ex` - Event struct and constructor
- `lib/thunderline/thunderflow/event_validator.ex` - Validation logic
- `lib/thunderline/thunderflow/events/registry.ex` - Seed registry
- `lib/mix/tasks/thunderline.events.lint.ex` - Linter task
