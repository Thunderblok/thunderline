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

## 11. Open TODOs (for completion of HC-03)
- [x] Add full domain → event matrix (Section 12 seed)
- [x] Add JSON Schema examples per event (selected examples added)
- [x] Document correlation/causation threading rules (Section 5 invariants & Section 13)
- [ ] Add additional JSON Schema for remaining seed events _(DocsOps owner; reference refresh plan in [`documentation/README.md`](documentation/README.md))_
- [ ] Ship automated linter mix task (`mix thunderline.events.lint`) — see Section 14 _(Observability squad; CI enablement tracked under HC-02)_
- [ ] Generate docs site variant (mdbook or LiveDashboard page) from registry _(Platform Engineering; align with catalog restructure)_
- [ ] Add fanout guard metrics spec _(ThunderFlow; include Grafana panel export)_

## 12. Domain → Event Category Matrix (Seed)
| Domain (source) | Allowed Top-Level Categories | Notes |
|-----------------|------------------------------|-------|
| `:gate` (Auth/Gateway) | `ui.command`, `system`, `presence` | Auth flows, presence join/leave |
| `:flow` (Pipelines/Reactor) | `flow.reactor`, `system` | Reactor orchestration + internal pipeline completions |
| `:bolt` (ML / ThunderBolt) | `ml.run`, `system` | ML lifecycle & internal orchestration |
| `:link` (Comms / Chat / Voice) | `ui.command`, `system`, `voice.signal`, `voice.room` | Adds voice session + signaling categories |
| `:crown` (AI Governance) | `ai.intent`, `system` | AI interpretation & governance decisions |
| `:block` (Provisioning/Tenancy) | `system` | Provisioning, server lifecycle events |
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

Batch Emission Policy:
* `emit_batch_meta/2` returns a batch-level `correlation_id` — **callers MUST propagate** this id to any follow-on AI tool or reactor emissions spawned from the batch.
* When a provided payload already includes `:correlation_id`, the constructor preserves it (no overwrite) ensuring upstream trace continuity (e.g., external MCP client session id).

Never re-base a correlation mid-flow. If a *new* logical transaction emerges (e.g., follow-up automation triggered by email success), start a NEW correlation with that event's id.

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
6. Emits summary metrics for gating CI.

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
