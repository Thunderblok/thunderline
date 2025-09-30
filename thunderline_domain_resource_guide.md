# Thunderline Domain Resource Guide

> Version: 2025-09-25 | Maintainers: Thunderline Architecture Guild
> Scope: Unified reference for domain responsibilities, canonical resources, contracts, and operational guardrails.

## 0. Orientation

- **Purpose**: Provide a single annotated map of Thunderline domains, tying architectural doctrine, resource inventories, and operational controls into a living guide.
- **Audience**: Platform engineers, domain stewards, SRE/observability teams, governance reviewers, and AI orchestration partners.
- **Update cadence**: Reviewed each sprint by domain stewards. Changes require PR referencing this guide and related source docs.
- **Change control**: Updates demand cross-linking with source-of-truth files such as [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md) and [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md).

## 1. Domain Atlas

The Thunderline platform is organized into sovereign domains with explicit contracts. Containers align with the C4 views captured in [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md).

### 1.1 ThunderGate — Security, Ingest, Audit

- **Mission**: Enforce authentication, policy decisions, ingress normalization, and audit trails before events enter ThunderFlow.
- **Key services**: `gateAuth`, `ThunderBridge` ingest facade, Thunderwatch file monitor, audit/error resource emitters.
- **Primary resources**: `policy_rule`, `alert_rule`, `health_check`, `audit_log` (Ash resources under `Thunderline.Thundergate`).
- **Event responsibilities**: `ui.command.*` for ingress intents, `system.*` for policy results, `presence.*` for session state; see [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md).
- **Observability**: Emits `[:thunderline, :security, :]` telemetry and feeds audit logs into ThunderBlock vault.
- **Backlog highlights**: Implement bridged alias plan and encryption handshake per Honey Badger Phase A10/A6 in [`architecture/honey_badger_consolidation_plan.md`](Thunderline/documentation/architecture/honey_badger_consolidation_plan.md).

### 1.2 ThunderLink — Realtime UX, Voice, Federation

- **Mission**: Serve communities, channels, PAC homes, and emerging voice/WebRTC experiences.
- **Key services**: LiveView UI, WebSocket federation client, VoiceChannel signalling, Dashboard ThunderBridge.
- **Primary resources**: `channel`, `community`, `role`, `message`, `voice_room`, `voice_participant`, `voice_device`, `pac_home`.
- **Event responsibilities**: Emits `ui.command.*`, `system.voice.*`, and `voice.signal.*` families. Implement constructor enforcement tasks A7/A11 from Honey Badger plan.
- **Supervision**: Dynamic `RoomPipeline` supervisors transitioning to `Membrane.WebRTC` (see gap analysis in [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md)).
- **Feature flags**: Gated by `:voice_input`, `:ai_chat_panel`, `:presence_debug` per [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md).

### 1.3 ThunderFlow — Event Bus & Pipelines

- **Mission**: Normalize, route, and persist events via Broadway pipelines, enforcing taxonomy contracts and DLQ policy.
- **Key services**: `EventBus`, `EventPipeline`, `RealtimePipeline`, `CrossDomainPipeline`, DLQ handlers.
- **Primary resources**: `event_pipeline`, `realtime_pipeline`, `cross_domain_pipeline`, `dead_letter`, `lineage.edge`.
- **Event responsibilities**: Owns `flow.reactor.*`, ensures every domain obeys correlation/causation rules (Section 13 of [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md)).
- **Observability**: KPIs `[:flow, :market, :lag_ms]`, retry metrics, DLQ depth dashboards per [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md).
- **Backlog**: Implement taxonomy mix task (Section 14) and DLQ surfacing (Next Enhancements item in domain top-down architecture doc).

### 1.4 ThunderBolt — Compute, ML, Automata

- **Mission**: Execute computational workloads including ThunderCell CA engine, Lane orchestrators, Model of Experts, and Cerebros bridges.
- **Key services**: `ThunderCell`, `Lane` orchestrators, expert registries, `ErlangBridge` for neuro handoff, `CerebrosBridge` helpers (`RunOptions`, `Summary`).
- **Primary resources**: `lane_*`, `workflow_dag`, `thundercell_cluster`, `model_run`, `model_artifact`, `ising_*`; helper coverage enforced by `test/thunderline/thunderbolt/cerebros_bridge/run_options_test.exs` and `cerebros/summary_test.exs`.
- **Event responsibilities**: `ml.run.*`, `ai.tool_*`, `dag.commit`, `cmd.workflow.*`; cross-domain dispatch to Flow pipelines.
- **Roadmap**: Phase B policy/ orchestration unification; NAS integration phases (Section 10 in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md)). Flower federation now runs exclusively through the Keras backend wiring (`python/cerebros/keras/flower_app.py`) so PyTorch dependencies can be dropped from NAS control plane images.
- **Feature flags**: `:ml_nas`, `:signal_stack`, `:vim`, `:vim_active` gating advanced features.

### 1.5 ThunderCrown — Governance & AI Orchestration

- **Mission**: Provide policy enforcement, AI intent derivation, and tool selection via Daisy and Hermes MCP bus.
- **Key services**: MCP bus, workflow orchestrator, Daisy cognitive modules, future AI governance hooks.
- **Primary resources**: `workflow_orchestrator`, `ai_policy`, `daisy_module`, future `AIGovernanceHook` (Honey Badger Phase C3).
- **Event responsibilities**: `ai.intent.*`, `ai.tool_*`, and governance `system.*` events; ensures correlation propagation with Flow.
- **Compliance**: Policy centralization plan (Phase B1) and taxonomy governance from [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md) Section 9.

### 1.6 ThunderBlock — Persistence & Provision

- **Mission**: Own persistent state (Postgres, Mnesia), provisioning, vault memories, and cluster nodes.
- **Key services**: Vault storage, provisioning orchestrators, checkpointing.
- **Primary resources**: `vault_*`, `execution_container`, `workflow_tracker`, `vault_agent`, `checkpoint`.
- **Migration governance**: Track namespace moves via [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md); enforce CI gating for deprecated modules.
- **Resilience**: Provide DR notes, retention tiers, and event emission `system.persistence.*`.

### 1.7 ThunderGrid — Spatial Runtime & ECS

- **Mission**: Coordinate zones, spatial coordinates, ECS placement for PAC agents and automata.
- **Primary resources**: `grid_zone`, `spatial_coordinate`, `zone_boundary`, `chunk_state`, `zone_event`.
- **Event responsibilities**: Publish spatial updates to Flow (`grid`→EventBus). Feed placement metadata to ThunderBolt orchestrations.
- **Future work**: Voice agents targeting zones, advanced placement heuristics (Section 2 in [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md)).

### 1.8 ThunderChief — Batch & Domain Processors

- **Mission**: Execute scheduled jobs, domain processors, and large batch exports through Oban and custom schedulers.
- **Primary resources**: `domain_processor`, `scheduled_workflow_processor`, `export_jobs` (`Thunderline.Export.TrainingSlice`).
- **Event responsibilities**: `system.batch.*`, `dag.commit` fanout, integration with NAS export loops.
- **Operational KPIs**: Job success rate, cadence lag, queue depth; align with Honey Badger telemetry (Section Telemetry/KPIs).

### 1.9 ThunderCom — Legacy Chat & Merge Surface

- **Mission**: Provide backward compatibility for chat constructs while migration to ThunderLink completes.
- **Status**: Frozen per Honey Badger Phase A; new writes funneled through ThunderLink voice resources.
- **Risks**: Residual dependencies on `Thundercom.Voice.*`; monitor deprecation telemetry and plan removal after grace period.

## 2. Resource Reference Tables

| Domain | Representative Resources | Status | Notes |
|--------|--------------------------|--------|-------|
| ThunderGate | `policy_rule`, `alert_rule`, `health_check`, `audit_log` | Active | Normalize ingress, feed audit events |
| ThunderLink | `channel`, `community`, `role`, `message`, `voice_room`, `voice_participant`, `voice_device`, `pac_home` | Active | Voice resources relocating from ThunderCom (Honey Badger A1–A4) |
| ThunderFlow | `event_pipeline`, `realtime_pipeline`, `cross_domain_pipeline`, `dead_letter`, `lineage.edge` | Active | DLQ surfacing pending |
| ThunderBolt | `lane_*`, `workflow_dag`, `model_run`, `model_artifact`, `ising_*`, `thundercell_cluster` | Active | NAS integration staged Phases 0–5 |
| ThunderCrown | `workflow_orchestrator`, `ai_policy`, `daisy_module`, planned `ai_governance_hook` | In flight | Policy consolidation B1–B3 |
| ThunderBlock | `vault_*`, `execution_container`, `workflow_tracker`, `vault_agent`, `checkpoint` | Active | Migration matrix ensures namespace hygiene |
| ThunderGrid | `grid_zone`, `spatial_coordinate`, `chunk_state`, `zone_event` | Active | Provide placement metadata to Link/Bolt |
| ThunderChief | `domain_processor`, `scheduled_workflow_processor`, `export_job` | Active | Export jobs feed Cerebros NAS loop |
| ThunderCom | `channel`, `community`, `message` (legacy) | Deprecated | Monitor telemetry and plan removal |

**Feature flag crosswalk** (see [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md)):

| Flag | Controls | Default | Lifecycle |
|------|----------|---------|-----------|
| `:voice_input` | Membrane-ready voice pipeline enablement | false | Planned |
| `:ml_nas` | NAS export + expert auto-tuning | false | Experimental |
| `:signal_stack` | Signal/phase processing stack | false | Experimental |
| `:tocp` | Thunderline Open Circuit Protocol runtime | false | Scaffold |
| `:tocp_presence_insecure` | Controlled insecure mode for TOCP perf tests | false | Debug |
| `:ai_chat_panel` | Dashboard AI assistant experience | false | Experimental |

## 3. Event and Telemetry Contracts

- **Envelope**: All events instantiate `%Thunderline.Event{}` via constructor enforcing UUIDv7 `id`, `correlation_id`, allowed category mapping (Section 5 & 12 in [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md)).
- **Taxonomy governance**: New events require DIP, payload schema, and tests; `mix thunderline.events.lint` target pending (Section 14).
- **Reliability tiers**: `persistent` events recorded durably (e.g., `system.email.sent`), `transient` events best-effort (e.g., `voice.signal.*`).
- **Correlation rules**: Root commands set `correlation_id` to their `id`; derived intents and tool invocations maintain causation chains per Section 13 matrix.
- **Telemetry catalogue**: Key metrics include `[:flow, :market, :lag_ms]`, `[:router, :assignment, :experts_per_token]`, `[:thunderline, :error, :classified]`, and voice KPIs (active rooms, speaking bursts).
- **Alerting**: Establish thresholds for pipeline lag, DLQ depth, router load imbalance, and policy evaluation latency; align dashboards with `Thundereye` instrumentation.

## 4. Error and Recovery Surfaces

- **Classifier contract**: `%Thunderline.Thunderflow.ErrorClass{origin, class, severity, visibility, code, reason}` as defined in [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md).
- **Retry matrix**: Transient (5 attempts, exponential backoff), timeout (3 attempts), dependency (7 attempts) before DLQ transfer.
- **DLQ event**: `system.dlq.message` payload captures queue, attempts, reason; escalate security classified events to audit channel.
- **Telemetry**: Emit `[:thunderline, :error, :classified]` and `[:thunderline, :dlq, :enqueue]` with class/origin metadata; correlate with event categories.
- **Governance workflow**: New error patterns require issue tagged `error-taxonomy`, classifier update, tests, observability steward approval.
- **AI tool hooks**: Reserve codes `AI-TOOL-*`, `AI-STREAM-*` to align with `ai_emit/2` path, ensuring `correlation_id` propagation.

## 5. Cross-Domain Bridges and DIP Governance

- **Sanctioned bridges**: ThunderBridge (external ingest), Dashboard ThunderBridge (observability), ErlangBridge (Cerebros handoff).
- **Pending proposals**: Honey Badger tasks A10 (bridge collision audit) and C1 (rename execution) require registry updates.
- **DIP requirements**: Purpose, latency tolerance, event vs direct call rationale, telemetry spec, security hooks (Honey Badger Section DIP Outline).
- **Compliance**: PRs introducing cross-domain calls must reference DIP ID and update this guide; lint rule forbids unauthorized aliases (Honey Badger Quality Gates).

## 6. Operational Playbooks

- **Voice HC-13 rollout**: Follow Phase A tasks (resource relocation, feature flag gating, Membrane stub, event enforcement). Monitor KPIs listed in Honey Badger telemetry table.
- **Market → MoE → NAS pipeline**: Execute Phase 0–5 sequence in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md) for ingestion scaffolding, routing, drift detection, and NAS integration.
- **TOCP operations**: Reference security & telemetry expectations in [`TOCP_SECURITY.md`](Thunderline/documentation/TOCP_SECURITY.md) and `tocp` documentation set.
- **Flower Power federated training**: Use runbooks in [`docs/flower-power/runbooks/*`](Thunderline/documentation/docs/flower-power/runbooks) and architecture overview in [`docs/flower-power/architecture.md`](Thunderline/documentation/docs/flower-power/architecture.md).
- **Deprecation monitoring**: Attach to `[:thunderline, :deprecated_module, :used]` telemetry to enforce migration matrix (Phase 3–4 tasks in [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md)).

## 7. Roadmap and Open Actions

| Item | Domain | Source | Owner | Status |
|------|--------|--------|-------|--------|
| Voice resource relocation & Membrane scaffolding | ThunderLink | Honey Badger A1–A7 | Link steward | In progress |
| Event taxonomy lint task | ThunderFlow | `EVENT_TAXONOMY.md` Section 14 | Observability guild | TODO |
| Feature helper implementation | Global | `FEATURE_FLAGS.md` Section 10 | Core platform | TODO |
| Policy engine consolidation | ThunderCrown | Honey Badger B1 | Crown steward | Planned |
| DLQ dashboard surfacing | ThunderFlow | Domain top-down Next Enhancements | Flow steward | TODO |
| Bridge alias audit | ThunderGate/Link | Honey Badger A10 | Arch guild | TODO |
| AI governance hooks | ThunderCrown | Honey Badger C3 | Crown steward | Planned |
| NAS export loop Phase 5 | ThunderChief/Bolt | Market MoE plan Section 10 | Bolt steward | Planned |

- **Risk register**: Table rename migrations risk (Honey Badger mitigation plan), event taxonomy churn risk (versioning strategy), policy centralization regression risk (contract tests), orchestration refactor stall (feature flags), lingering deprecation wrappers (telemetry thresholds).

## 8. Appendices

- **Glossary**: Maintain shared definitions for domains, resources, and telemetry tags; align with runbook nomenclature.
- **Naming conventions**: Enforce singular nouns in event names, Ash resource naming consistent with domain (see domain top-down Section 4 resource coverage note).
- **Change log template**:

```markdown
## YYYY-MM-DD – Summary
- Domains touched:
- Source references:
- Flags toggled:
- Event/Telemetry changes:
- Follow-up actions:
```

- **Legacy references**: Retain access to prior deep dives (e.g., `architecture/system_architecture_webrtc.md`, `docs/flower-power/README.md`, `TOCP_TELEMETRY.md`) for historical context; this guide supersedes their scattered status sections.

---

_This guide is living documentation. Submit PRs with updated resource tables, bridge inventories, and roadmap actions as domains evolve._