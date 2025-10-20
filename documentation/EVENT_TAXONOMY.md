# 📚 Event Taxonomy (Draft v0.2)

> Related High Command Item: HC-03 (P0)  
> Status: Expanded draft — adds governance rules, schema examples, correlation policy, domain matrix. Remaining automation tasks tracked in TODO section.

## 1. Purpose
Provide a canonical, versioned specification for all events exchanged within Thunderline so that:
- Producers emit normalized `%Thunderline.Event{}` shapes
- Consumers rely on stable categories & namespaces
- Telemetry, logging, and retry/DLQ semantics are consistent
- Backpressure & fanout analysis has a dependable semantic layer

## 2. Scope
Covers *domain-level* events (business + orchestration) and *system-level* events (infrastructure, telemetry worthy operational signals). Excludes low-level library telemetry (e.g. `:telemetry` spans) — those map into Observability dashboards but sit outside taxonomy governance.

## 3. Versioning
| Field | Meaning |
|-------|---------|
| `taxonomy_version` | Integer monotonically incremented for breaking semantic changes |
| `event_version` | Per-event schema version (payload shape change) |
| `deprecated_at` | Optional ISO8601 for sunset schedule |

Breaking changes require DIP referencing this file & migration notes.

## 4. Namespace Conventions
```
<layer>.<domain>.<category>.<action>[.<phase>]
```
Examples:
- `ui.command.email.requested`
- `system.email.sent`
- `system.presence.join`
- `ai.intent.email.compose`
- `flow.reactor.retry`

Guidelines:
- Use singular nouns (`email`, not `emails`).
- Prefer verbs for terminal actions (`sent`, `failed`, `completed`).
- Reserve `ui.command.*` for direct user-intent capture before orchestration expansion.

## 5. Event Envelope (Normalized)
```elixir
%Thunderline.Event{
  id: UUIDv7,
  at: DateTime.utc_now(),
  name: "<namespace>",
  source: :<atom_domain>,
  actor: %{id: <binary>|nil, type: :user|:system},
  correlation_id: <UUID or trace id>,
  causation_id: <parent event id>|nil,
  taxonomy_version: 1,
  event_version: <int>,
  payload: %{},
  meta: %{
    trace: <otel span ctx optional>,
    flags: [:experimental | :deprecated],
    reliability: :transient | :persistent
  }
}
```

Envelope Invariants:
- `id` MUST be UUID v7 (time sortable) — generated via internal `Thunderline.UUID.v7/0` (Week 0 scaffold).
- `correlation_id` stable across a logical transaction (e.g., full email send flow) — FIRST event's `id` becomes correlation id for subsequent derived events when no upstream correlation exists.
- `causation_id` ALWAYS points to the direct parent event that triggered the emission (acyclic chain).
- `taxonomy_version` bump ONLY on breaking semantic categorization shift, not on payload tweaks.
- `event_version` increments when payload contract (required/optional fields) changes — consumers must handle N and N-1 during rollout.
- `source` is the originating *domain atom* (see Section 12); NEVER a module name.

## 6. Lifecycle Categories
| Category | Description | Example Names |
|----------|-------------|---------------|
| `ui.command` | Raw user intent | `ui.command.email.requested`, `ui.command.voice.room.requested` |
| `ai.intent` | Interpreted AI intent or disambiguation | `ai.intent.email.compose`, `ai.intent.voice.transcription.segment` |
| `ai` | Generic AI runtime/tool events (batch/meta/tool streaming) | `ai.tool_start`, `ai.model_token` (via EventBus.ai_emit) |
| `system` | Internal system action results | `system.email.sent`, `system.voice.room.created` |
| `flow.reactor` | Reactor orchestration steps / retries | `flow.reactor.retry` |
| `presence` | User or agent presence transitions | `system.presence.join` |
| `ml.run` | ML lifecycle transitions | `ml.run.completed` |
| `voice.signal` | WebRTC signaling primitives (offers/answers/ICE) normalized | `voice.signal.offer`, `voice.signal.answer`, `voice.signal.ice` |
| `voice.room` | Room lifecycle, media pipeline + recording/transcription | `voice.room.closed`, `voice.room.recording.started` |
| `pac` | PAC (Policy-as-Code) lifecycle and execution | `pac.provisioned`, `pac.tick`, `pac.action.allow` |
| `device` | Edge device enrollment, telemetry, and firmware | `device.enrolled`, `device.heartbeat`, `device.offline` |
| `thundra` | Thundra VM zone orchestration and failover | `thundra.tick.{zone_id}`, `thundra.tock.{zone_id}`, `thundra.zone.failover` |

(Initial table; to be expanded.)

Phases (optional final segment) SHOULD be used when an action has distinguishable, observable internal stages that matter for SLOs (e.g., `system.email.dispatch.started`, `system.email.dispatch.completed`). Avoid over‑fragmentation; prefer a single terminal action plus reactor instrumentation unless external latency attribution benefits.

## 7. Canonical Event Registry (Seed Set)
| Name | Version | Payload Schema (Summary) | Reliability | Notes |
|------|---------|--------------------------|-------------|-------|
| `ui.command.email.requested` | 1 | `%{to: binary, subject: binary|nil, raw_text: binary}` | persistent | Entry point (HC-05) |
| `ai.intent.email.compose` | 1 | `%{to: list(binary), topic: binary, confidence: float}` | transient | Downstream of UI command |
| `system.email.sent` | 1 | `%{message_id: binary, to: list(binary), subject: binary}` | persistent | Terminal success |
| `system.email.failed` | 1 | `%{to: list(binary), reason: binary, code: integer|nil}` | persistent | Terminal failure - classify error |
| `system.presence.join` | 1 | `%{channel_id: binary, user_id: binary}` | transient | Presence bookkeeping |
| `system.presence.leave` | 1 | `%{channel_id: binary, user_id: binary}` | transient | Presence bookkeeping |
| `ml.run.started` | 1 | `%{run_id: binary, model: binary}` | persistent | After state transition -> running |
| `ml.run.completed` | 1 | `%{run_id: binary, model: binary, duration_ms: integer}` | persistent | State transition completed |
| `flow.reactor.retry` | 1 | `%{reactor: binary, step: binary, attempt: integer, reason: binary}` | transient | Observability & SLO |
| `ai.tool_start` | 1 | `%{tool: binary, ai_stage: :tool_start, correlation_id: binary}` | transient | Emitted at AI tool invocation begin |
| `ai.tool_result` | 1 | `%{tool: binary, ai_stage: :tool_result, duration_ms: integer|nil, status: atom, correlation_id: binary}` | transient | Terminal tool result (success/failure) |
| `ai.model_token` | 1 | `%{model: binary, token: binary, seq: integer, correlation_id: binary}` | transient | Streaming token emission |
| `ai.conversation_delta` | 1 | `%{delta: binary, role: atom, correlation_id: binary}` | transient | Conversation streaming delta |
| `ui.command.voice.room.requested` | 1 | `%{title: binary, requested_by: binary, scope: %{community_id: binary|nil, block_id: binary|nil}}` | persistent | Root of a voice session creation flow |
| `system.voice.room.created` | 1 | `%{room_id: binary, created_by: binary}` | persistent | Emitted after VoiceRoom persisted |
| `system.voice.room.closed` | 1 | `%{room_id: binary, closed_by: binary}` | persistent | Terminal state of room |
| `voice.signal.offer` | 1 | `%{room_id: binary, from: binary, sdp_type: "offer", size: integer}` | transient | Normalized inbound offer |
| `voice.signal.answer` | 1 | `%{room_id: binary, from: binary, sdp_type: "answer", size: integer}` | transient | Normalized inbound answer |
| `voice.signal.ice` | 1 | `%{room_id: binary, from: binary, candidate: map}` | transient | Individual ICE candidate |
| `voice.room.participant.joined` | 1 | `%{room_id: binary, participant_id: binary, role: atom}` | transient | High-churn presence-like voice join |
| `voice.room.participant.left` | 1 | `%{room_id: binary, participant_id: binary, reason: atom|nil}` | transient | Leave/kick/timeout |
| `voice.room.speaking.started` | 1 | `%{room_id: binary, participant_id: binary}` | transient | Start VAD-detected speech window |
| `voice.room.speaking.stopped` | 1 | `%{room_id: binary, participant_id: binary, duration_ms: integer}` | transient | End of speech window |
| `voice.room.recording.started` | 1 | `%{room_id: binary, recording_id: binary}` | persistent | Recording pipeline engaged |
| `voice.room.recording.completed` | 1 | `%{room_id: binary, recording_id: binary, duration_ms: integer, segments: integer}` | persistent | Recording artifact finalized |
| `ai.intent.voice.transcription.segment` | 1 | `%{room_id: binary, recording_id: binary|nil, participant_id: binary|nil, text: binary, start_ms: integer, end_ms: integer}` | transient | Streaming transcript segment |
| `evt.action.ca.rule_parsed` | 1 | `%{born: [int], survive: [int], rate_hz: int, seed: binary|nil, zone: binary|nil}` | transient | Parsed & accepted CA rule line (ingested) |
| `dag.commit` | 1 | `%{workflow_id: uuid, node_id: uuid, correlation_id: binary}` | persistent | DAG lineage mutation committed |
| `cmd.ca.rule.parse` | 1 | `%{line: binary, meta: map}` | transient | Command to parse & ingest a CA rule line |
| `cmd.workflow.spec.parse` | 1 | `%{spec: binary, meta: map}` | transient | Command to parse workflow textual spec |
| `pac.provisioned` | 1 | `%{pac_id: binary, owner_id: binary, policy_manifest_id: binary|nil}` | persistent | New PAC created in ThunderBlock |
| `pac.initialized` | 1 | `%{pac_id: binary, zone_id: integer, vm_id: binary, thunderbits: integer}` | persistent | Thundra VM zone allocated and started |
| `pac.tick` | 1 | `%{pac_id: binary, zone_id: integer, cycle_count: integer, state_hash: binary}` | transient | Execution tick cycle completed |
| `pac.action.allow` | 1 | `%{pac_id: binary, action: binary, policy_id: binary, reason: binary|nil}` | persistent | ThunderCrown policy allowed action |
| `pac.action.deny` | 1 | `%{pac_id: binary, action: binary, policy_id: binary, reason: binary}` | persistent | ThunderCrown policy denied action |
| `device.enrolled` | 1 | `%{device_id: binary, client_cert_fingerprint: binary, policy_manifest_id: binary}` | persistent | mTLS handshake success via ThunderGate |
| `device.heartbeat` | 1 | `%{device_id: binary, last_seen: datetime, telemetry_queue_depth: integer|nil}` | transient | Periodic device check-in via TOCP |
| `device.offline` | 1 | `%{device_id: binary, last_seen: datetime, timeout_threshold_ms: integer}` | persistent | Device timeout detected by ThunderGate |
| `device.firmware.updated` | 1 | `%{device_id: binary, firmware_version: binary, previous_version: binary|nil, duration_ms: integer}` | persistent | OTA update completed successfully |
| `thundra.tick.{zone_id}` | 1 | `%{zone_id: integer, cycle_count: integer, active_pacs: integer, state_mutations: integer}` | transient | Zone tick cycle (micro-update) |
| `thundra.tock.{zone_id}` | 1 | `%{zone_id: integer, cycle_count: integer, sync_duration_ms: integer, voxels_persisted: integer}` | persistent | Zone tock cycle (macro-sync every 7 ticks) |
| `thundra.zone.failover` | 1 | `%{from_zone_id: integer, to_zone_id: integer, pac_id: binary, reason: binary}` | persistent | Zone reassignment due to failure |

Schema Detail (Selected):
```elixir
# ui.command.email.requested v1
%{
  to: binary(),                # Raw string as provided by user (pre-parsing)
  subject: binary() | nil,
  raw_text: binary()           # Unstructured user text
}

# ai.intent.email.compose v1
%{
  to: [binary()],              # Normalized list of resolved addresses
  topic: binary(),             # Canonicalized subject/topic extraction
  confidence: float()          # 0.0..1.0 classifier confidence
}

# system.email.failed v1
%{
  to: [binary()],
  reason: binary(),            # Human readable
  code: integer() | nil,       # Transport/provider code
  class: atom() | nil          # Error classifier result (when available)
}

# pac.provisioned v1
%{
  pac_id: binary(),            # UUID v7 PAC identifier
  owner_id: binary(),          # User/system owner
  policy_manifest_id: binary() | nil  # Crown policy manifest reference
}

# pac.initialized v1
%{
  pac_id: binary(),
  zone_id: integer(),          # 1-12 hexagonal zone assignment
  vm_id: binary(),             # Thundra VM instance identifier
  thunderbits: integer()       # Allocated Thunderbit count (~3M typical)
}

# pac.tick v1
%{
  pac_id: binary(),
  zone_id: integer(),
  cycle_count: integer(),      # Monotonic tick counter
  state_hash: binary()         # SHA256 of PAC voxel state
}

# pac.action.allow v1
%{
  pac_id: binary(),
  action: binary(),            # Action identifier (e.g., "email.send")
  policy_id: binary(),         # ThunderCrown policy rule ID
  reason: binary() | nil       # Optional explanation
}

# pac.action.deny v1
%{
  pac_id: binary(),
  action: binary(),
  policy_id: binary(),
  reason: binary()             # Required denial explanation
}

# device.enrolled v1
%{
  device_id: binary(),         # UUID v7 device identifier
  client_cert_fingerprint: binary(),  # SHA256 of client cert
  policy_manifest_id: binary() # Crown-issued edge policy manifest
}

# device.heartbeat v1
%{
  device_id: binary(),
  last_seen: datetime(),       # ISO8601 timestamp
  telemetry_queue_depth: integer() | nil  # Buffered telemetry count
}

# device.offline v1
%{
  device_id: binary(),
  last_seen: datetime(),
  timeout_threshold_ms: integer()  # Configured timeout value
}

# device.firmware.updated v1
%{
  device_id: binary(),
  firmware_version: binary(),  # Semantic version (e.g., "1.2.3")
  previous_version: binary() | nil,
  duration_ms: integer()       # OTA update duration
}

# thundra.tick.{zone_id} v1
%{
  zone_id: integer(),          # 1-12 (zone identifier in name also)
  cycle_count: integer(),      # Zone-specific tick counter
  active_pacs: integer(),      # PACs executing in this zone
  state_mutations: integer()   # Voxel changes this tick
}

# thundra.tock.{zone_id} v1
%{
  zone_id: integer(),
  cycle_count: integer(),      # Occurs every 7 ticks
  sync_duration_ms: integer(), # Time to persist state
  voxels_persisted: integer()  # Count of voxels written
}

# thundra.zone.failover v1
%{
  from_zone_id: integer(),     # Failed zone
  to_zone_id: integer(),       # Reassigned zone
  pac_id: binary(),            # PAC being migrated
  reason: binary()             # Failure reason (e.g., "zone_timeout")
}
```

JSON Schema (excerpt) for `system.email.sent`:
```json
{
  "$id": "https://schema.thunderline.dev/event/system.email.sent.v1.json",
  "type": "object",
  "required": ["message_id", "to", "subject"],
  "properties": {
    "message_id": {"type": "string"},
    "to": {"type": "array", "items": {"type": "string", "format": "email"}},
    "subject": {"type": ["string", "null"], "maxLength": 512}
  },
  "additionalProperties": false
}
```

## 8. Reliability Semantics
| Reliability | Storage Expectation | Retry on Failure | Notes |
|-------------|---------------------|------------------|-------|
| `persistent` | Stored/durable (DB or append log) | At-least-once | Business state mutation or audit |
| `transient` | May be in-memory only | Best-effort | High volume / ephemeral signals |

## 9. Taxonomy Governance Workflow
1. Propose new event: DIP referencing this file.
2. Include: purpose, consumers, reliability classification, sample payload.
3. Assign `event_version = 1` (or increment if existing).
4. Update table + add tests for shape validation.
5. PR must receive steward + observability sign-off.

## 10. Deprecation Policy
- Mark with meta flag `:deprecated` and add `deprecated_at`.
- Provide replacement event name.
- Maintain for ≥2 release cycles or 30 days (whichever longer) before removal.

## 11. Open TODOs (for completion of HC-03 & HC-23)
- [x] Add full domain → event matrix (Section 12 seed)
- [x] Add JSON Schema examples per event (selected examples added)
- [x] Document correlation/causation threading rules (Section 5 invariants & Section 13)
- [x] Add Thundra/Nerves event prefixes (pac.*, device.*, thundra.*) — HC-23.7
- [x] Add event DAG lineage examples for PAC lifecycle and device operations
- [x] Document metadata requirements for Thundra/Nerves events (Section 13A)
- [ ] Add JSON Schema for Thundra/Nerves events (`pac.provisioned`, `device.enrolled`, etc.) _(DocsOps owner)_
- [ ] Add additional JSON Schema for remaining seed events _(DocsOps owner; reference refresh plan in [`documentation/README.md`](documentation/README.md))_
- [ ] Ship automated linter mix task (`mix thunderline.events.lint`) — see Section 14 _(Observability squad; CI enablement tracked under HC-02 & HC-23.7)_
- [ ] Add zone_id consistency validation to linter (thundra.tick.N name must match payload zone_id) _(Observability squad)_
- [ ] Generate docs site variant (mdbook or LiveDashboard page) from registry _(Platform Engineering; align with catalog restructure)_
- [ ] Add fanout guard metrics spec _(ThunderFlow; include Grafana panel export)_

## 12. Domain → Event Category Matrix (Seed)
| Domain (source) | Allowed Top-Level Categories | Notes |
|-----------------|------------------------------|-------|
| `:gate` (Auth/Gateway) | `ui.command`, `system`, `presence`, `device` | Auth flows, presence join/leave, device enrollment/offline |
| `:flow` (Pipelines/Reactor) | `flow.reactor`, `system` | Reactor orchestration + internal pipeline completions |
| `:bolt` (ML / ThunderBolt) | `ml.run`, `system`, `pac`, `thundra` | ML lifecycle, PAC orchestration, VM zone management |
| `:link` (Comms / Chat / Voice) | `ui.command`, `system`, `voice.signal`, `voice.room`, `device` | Voice/chat + TOCP transport, device heartbeat |
| `:crown` (AI Governance) | `ai.intent`, `system`, `pac` | AI interpretation, governance decisions, PAC action allow/deny |
| `:block` (Provisioning/Tenancy) | `system`, `pac` | Provisioning, server lifecycle, PAC state storage |
| `:bridge` (Future Ingest Layer) | `system`, `ui.command` | External ingest normalization |

Violations (emitting a category not in the domain row) MUST be justified in PR description & typically indicate domain boundary confusion.

## 13. Correlation & Causation Threading Rules (Expanded for AI & Batches)
| Scenario | Correlation Rule | Causation Rule | Example |
|----------|------------------|----------------|---------|
| First user command | `correlation_id = id` | `causation_id = nil` | `ui.command.email.requested` |
| AI intent derived | Inherit from parent | `causation_id = parent.id` | `ai.intent.email.compose` |
| Reactor step retry | Inherit from original root | `causation_id = previous attempt id` | `flow.reactor.retry` |
| Terminal success/failure | Inherit | `causation_id = immediate predecessor (intent or reactor)` | `system.email.sent` |
| Fanout (parallel steps) | Inherit | `causation_id = originating split event` | Multiple parallel reactor steps |
| AI tool start | Inherit (from triggering command/intent) | `causation_id = parent intent/command` | `ai.tool_start` |
| AI tool result | Inherit | `causation_id = ai.tool_start event id` | `ai.tool_result` |
| AI streaming token | Inherit | `causation_id = ai.tool_start event id` | `ai.model_token` |
| AI conversation delta | Inherit | `causation_id = parent (token or tool)` | `ai.conversation_delta` |
| PAC provisioned | `correlation_id = id` | `causation_id = nil` (or provisioning command if present) | `pac.provisioned` |
| PAC initialized | Inherit from provisioned | `causation_id = pac.provisioned event id` | `pac.initialized` |
| PAC tick | Inherit | `causation_id = previous pac.tick or pac.initialized` | `pac.tick` |
| PAC action allow/deny | Inherit | `causation_id = pac.tick that triggered evaluation` | `pac.action.allow` |
| Device enrolled | `correlation_id = id` | `causation_id = nil` (root mTLS handshake) | `device.enrolled` |
| Device heartbeat | Inherit from enrollment | `causation_id = device.enrolled or previous heartbeat` | `device.heartbeat` |
| Device offline | Inherit | `causation_id = last device.heartbeat` | `device.offline` |
| Thundra zone tick | `correlation_id = zone session id` | `causation_id = previous tick or zone initialization` | `thundra.tick.{zone_id}` |
| Thundra zone tock | Inherit | `causation_id = 7th tick event id` | `thundra.tock.{zone_id}` |
| Zone failover | Inherit from PAC correlation | `causation_id = failure detection event` | `thundra.zone.failover` |

Batch Emission Policy:
* `emit_batch_meta/2` returns a batch-level `correlation_id` — **callers MUST propagate** this id to any follow-on AI tool or reactor emissions spawned from the batch.
* When a provided payload already includes `:correlation_id`, the constructor preserves it (no overwrite) ensuring upstream trace continuity (e.g., external MCP client session id).

Never re-base a correlation mid-flow. If a *new* logical transaction emerges (e.g., follow-up automation triggered by email success), start a NEW correlation with that event's id.

**Thundra/Nerves Event DAG Examples:**

PAC Lifecycle (Cloud Execution):
```
pac.provisioned (correlation_id=C1, causation_id=nil)
  → pac.initialized (correlation_id=C1, causation_id=E1)
    → pac.tick #1 (correlation_id=C1, causation_id=E2)
      → pac.action.allow (correlation_id=C1, causation_id=E3)
    → pac.tick #2 (correlation_id=C1, causation_id=E3)
```

Device Enrollment & Operation (Edge Execution):
```
device.enrolled (correlation_id=D1, causation_id=nil)
  → device.heartbeat #1 (correlation_id=D1, causation_id=D1)
  → device.heartbeat #2 (correlation_id=D1, causation_id=D2)
  → device.offline (correlation_id=D1, causation_id=D3)
```

Thundra Zone Orchestration:
```
thundra.tick.1 #1 (correlation_id=Z1, causation_id=nil)
  → thundra.tick.1 #2 (correlation_id=Z1, causation_id=T1)
  → ... (ticks 3-7)
  → thundra.tock.1 (correlation_id=Z1, causation_id=T7)
```

Cross-Domain PAC Execution (Cloud + Edge):
```
device.enrolled (correlation_id=D1, causation_id=nil)
  → pac.provisioned (correlation_id=C1, causation_id=D1) [triggered by enrollment]
    → pac.initialized (correlation_id=C1, causation_id=C1)
      → pac.tick (correlation_id=C1, causation_id=C2)
        → pac.action.allow (correlation_id=C1, causation_id=C3)
          → device.heartbeat (correlation_id=D1, causation_id=C4) [action executed telemetry]
```

## 13A. Event Metadata Requirements

Certain event categories require specific metadata fields for proper routing, lineage tracking, and observability:

| Event Category | Required Metadata Fields | Purpose | Example |
|----------------|-------------------------|---------|---------|
| `pac.*` | `pac_id` in payload | PAC instance identification | `%{pac_id: "01234567-89ab-cdef..."}` |
| `pac.tick`, `pac.action.*` | `zone_id` in payload | Zone assignment tracking | `%{zone_id: 3}` |
| `device.*` | `device_id` in payload | Device instance identification | `%{device_id: "89abcdef-0123-4567..."}` |
| `thundra.tick.*`, `thundra.tock.*` | `zone_id` in event name AND payload | Zone-specific events | `thundra.tick.3 → %{zone_id: 3}` |
| `thundra.zone.failover` | `from_zone_id`, `to_zone_id`, `pac_id` in payload | Failover tracking | `%{from_zone_id: 2, to_zone_id: 5, pac_id: "..."}` |
| All Thundra/Nerves events | `correlation_id`, `causation_id` | Event DAG lineage | Standard envelope fields |

Additional Requirements:
- **Thundra zone events**: Zone ID MUST match event name suffix (e.g., `thundra.tick.7` payload must have `zone_id: 7`)
- **Device offline**: MUST include `last_seen` timestamp for timeout calculation
- **PAC action events**: MUST include `policy_id` for audit trail
- **Firmware updates**: MUST include both `firmware_version` and `previous_version` for rollback capability

## 14. Automated Lint / Validation (Planned)
Proposed Mix Task: `mix thunderline.events.lint`
Checks:
1. All event names used in code exist in registry (this file parsed as data section) — includes dynamic AI names enforced via `ai_emit/2` whitelist.
2. No forbidden domain→category pairings (Section 12).
3. Payload validation: selected events have JSON Schema file present.
4. Deprecations older than grace window raise warning.
5. Ensures correlation/causation presence according to category transitions (heuristic ruleset):
   - `ui.command.*` must have `causation_id == nil`.
   - Non-root events must have non-nil `causation_id` unless explicitly flagged `:root`.
   - AI tool & streaming events (`ai.tool_*`, `ai.model_token`, `ai.conversation_delta`) MUST have non-nil `correlation_id` AND `ai_stage` (except conversation delta which may omit `ai_stage`).
   - `pac.*` events MUST have `pac_id` in payload (Section 13A).
   - `device.*` events MUST have `device_id` in payload (Section 13A).
   - `thundra.tick.*` and `thundra.tock.*` events MUST have `zone_id` in both name and payload, with values matching (Section 13A).
   - `thundra.zone.failover` events MUST have `from_zone_id`, `to_zone_id`, and `pac_id` in payload (Section 13A).
6. Validates metadata requirements per Section 13A (zone_id consistency, required fields).
7. Emits summary metrics for gating CI.

Implementation Sketch (excerpt additions for AI & batch correlation auditing):
```elixir
defmodule Mix.Tasks.Thunderline.Events.Lint do
  use Mix.Task
  @shortdoc "Validate event taxonomy adherence"
  def run(_argv) do
    {:ok, registry} = Thunderline.Events.Registry.load()
  issues = Thunderline.Events.Linter.run(registry)
    Thunderline.Events.Linter.print(issues)
    if Enum.any?(issues, & &1.severity == :error) do
      Mix.raise("Event taxonomy lint failed")
    end
  end
end
```

## 15. Future Extensions
- CloudEvents mapping (add explicit attributes section for external boundary translation).
- AI lineage enrichment: attach `tool_chain_id` and aggregate latency spans.
- Batch correlation leak detector: warn if events derived from `emit_batch_meta/2` omit returned correlation id.
- Dynamic registry generation to publish machine-readable artifact (JSON) for tooling.
- Event replay guidelines & immutability guarantees.
- Governance metrics: `taxonomy.drift.detected` telemetry when unknown events observed.

---
Expanded draft complete. Populate remaining schema files & linter code in subsequent PRs.

## 16. Creating & Validating Events (Operational How-To)

All new events MUST be instantiated via the smart constructor `Thunderline.Event.new/1` (or bang `new!/1`). Raw maps (`%{type: ..., payload: ...}`) are deprecated and will be rejected at emission points as the migration hardens.

Minimal example:
```elixir
{:ok, ev} = Thunderline.Event.new(name: "system.email.sent", source: :link, payload: %{message_id: mid, to: recipients, subject: subj})
Thunderline.EventBus.emit(:email_sent, %{message_id: mid, to: recipients, subject: subj, domain: "thunderlink"})
```

Constructor Responsibilities:
- Validates name format & allowed category for `source` (Section 12 matrix)
- Supplies `id` (UUID v7), `at`, `correlation_id` (UUID v7), default `taxonomy_version`
- Infers `type` from name if omitted (last segment)
- Applies reliability heuristic to `meta.reliability`

Rejection Examples (returning `{:error, errs}`):
- Missing name & type
- Non-map payload
- Category not permitted for the emitting domain (`{:forbidden_category, {source, name}}`)

Linter Enforcement (CI):
The Mix task `mix thunderline.events.lint --format=json` scans source for event literals and validates against:
1. Registry presence (seed set; expanding)
2. Domain/category matrix
3. Deprecation flags

CI Step (excerpt) added to `.github/workflows/ci.yml`:
```yaml
  - name: Event Taxonomy Lint
    run: mix thunderline.events.lint --format=json
```
Failing conditions raise `Mix.raise/1` (strict mode default). Use `--no-strict` only for local exploratory runs.

Migration Path:
1. Replace ad-hoc event maps with constructor usage.
2. Remove legacy `Thunderline.Bus` references (keeping shim temporarily).
3. Enable `--warnings-as-errors` to forbid drift reintroduction.

Any future event additions MUST update Sections 6–7 and include tests asserting constructor acceptance and linter pass.
