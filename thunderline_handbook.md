# Thunderline Handbook

> Version: 2025-09-25  
> Maintainers: Thunderline Architecture Guild  
> Audience: Engineers, operators, AI orchestration staff, and partner teams onboarding to Thunderline.

---

## 0. Orientation & Principles

- **Mission**: Build and operate a sovereign, event-driven platform where every domain owns its contracts, telemetry, and enforcement.
- **Doctrine**: Honor the Honey Badger directives, keep events canonical, avoid cross-domain drift, and surface observability first.
- **Governance cadence**: Review this handbook each sprint. Changes require PR references to source documents such as [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md) and Honey Badger plan [`architecture/honey_badger_consolidation_plan.md`](Thunderline/documentation/architecture/honey_badger_consolidation_plan.md).
- **Contribution workflow**: Fork → update documentation → link supporting specs → request steward review → merge with changelog entry.

---

## 1. System Overview

- **Domains**: ThunderGate, ThunderLink, ThunderFlow, ThunderBolt, ThunderCrown, ThunderBlock, ThunderGrid, ThunderChief, and the legacy ThunderCom surface. Visual overview lives in [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md).
- **Voice/WebRTC path**: Current state, gaps, and roadmap are detailed in [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md). The path spans ThunderLink signaling, ThunderFlow normalization, and planned Membrane media processing.
- **Data vs control planes**: Data events route through ThunderFlow pipelines; control signals (policy, AI orchestration) traverse ThunderCrown and ThunderBolt. Cross-domain edges must follow the DIP process (Section 5).
- **External integrations**: Ingest via ThunderBridge (ThunderGate), publish via ThunderLink, ML feedback loops through ThunderBolt and Cerebros (see [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md)).

---

## 2. Getting Started

### 2.1 Environment Setup

1. Install Elixir/OTP and Erlang per project toolchain.
2. Bootstrap dependencies (`mix deps.get`), compile (`mix compile`), and run database migrations.
3. Configure `.env` with required secrets and feature flag defaults (see Section 4).
4. Start Phoenix endpoint and supporting supervisors via `iex -S mix phx.server`.

### 2.2 Repository Tour

- `lib/thunderline` – domain-specific apps (Link, Flow, Bolt, etc.).
- `documentation/` – canonical specs, including event taxonomy [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md), error handling [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md), and feature flags [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md).
- `documentation/docs/flower-power/` – federated learning project documentation.
- `documentation/tocp/` – Thunderline Open Circuit Protocol references.

### 2.3 Coding Standards

- **Events**: Instantiate via `Thunderline.Event.new/1` to ensure taxonomy compliance; see governance rules in [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md).
- **Errors**: Classify with structured `Thunderline.Thunderflow.ErrorClass`; mapping guidance in [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md).
- **Telemetry**: Emit metrics/trace events matching domain KPIs; consult Section 3 of this handbook.
- **Lints**: Run mix commands listed in Section 6 before opening PRs.

### 2.4 Local Quality Gates

- `mix test`
- `mix credo`
- `mix dialyzer`
- `mix format --check-formatted`
- Planned: `mix thunderline.events.lint` (see taxonomy TODOs).

---

## 3. Domain Deep Dives

### 3.1 ThunderGate (Security & Ingest)

- Auth, policy evaluation, normalized ingest via ThunderBridge, and audit logs.
- Emits `ui.command.*`, `system.*`, `presence.*` events.
- Honey Badger Phase A tasks cover bridge inventory and lightning of Thunderwatch integration.

### 3.2 ThunderLink (Realtime & Voice)

- LiveView dashboards, communities/channels, PAC homes, and voice signaling.
- Voice resource relocation plan and Membrane readiness detailed in Honey Badger Phase A and voice architecture doc [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md).
- Feature flags: `:voice_input`, `:ai_chat_panel`, `:presence_debug`.

### 3.3 ThunderFlow (Pipelines)

- EventBus normalization, Broadway ingestion, realtime fanout, DLQ.
- Event taxonomy ownership and linter scope captured in [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md).
- Backpressure ladders and feature window pipelines elaborated in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md).

### 3.4 ThunderBolt (Compute)

- ThunderCell CA engine, Lane orchestrators, expert clusters, Cerebros bridges.
- Phased rollout for market → MoE → NAS pipeline documented in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md).
- Active feature flags: `:ml_nas`, `:signal_stack`, `:vim`, `:vim_active`.

### 3.5 ThunderCrown (Governance)

- Daisy cognitive modules, MCP bus, policy enforcement.
- Consolidation plan with single policy engine (Honey Badger Phase B1) and AI governance hooks (Phase C3).
- Emits `ai.intent.*`, `ai.tool_*` events with strict correlation rules.

### 3.6 ThunderBlock (Persistence)

- Vault storage, provisioning, checkpoints, retention policy.
- Migration matrix maintained in [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md); follow removal plan to eliminate deprecated delegates.

### 3.7 ThunderGrid (Spatial Runtime)

- Zone and ECS placement for agents; integrally linked with grid events in ThunderFlow.
- Future integration of voice agents targeting zones per [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md).

### 3.8 ThunderChief (Batch)

- Scheduled processors, export orchestrations, Oban-based jobs.
- Export jobs feed NAS loop (Phase 5) in market pipeline plan.

### 3.9 ThunderCom (Legacy)

- Frozen merge surface; maintainer responsibility is deprecation telemetry and alias wrappers until removal (Honey Badger Phase C4).

---

## 4. Operational Excellence

### 4.1 Observability Stack

- Metrics: Telemetry events under `[:thunderline, ...]` namespaces. Voice KPIs (active rooms, speaking bursts) TODO in Honey Badger A12; pipeline metrics in market MoE plan.
- Traces: Use Otel instrumentation across pipeline and AI tool spans.
- Dashboards: Thundereye surfaces aggregated metrics (Flow lag, expert load, DLQ depth).

### 4.2 Incident Response

1. Detect via alerts (SLO breaches, DLQ thresholds, policy latency spikes).
2. Declare incident, appoint commander, document timeline.
3. Mitigate using runbooks (Section 6).
4. Post-incident review within 48 hours (template in Section 8).

### 4.3 Deprecation & Migration Hygiene

- Monitor `[:thunderline, :deprecated_module, :used]` telemetry for legacy code usage.
- Replace modules per [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md) migration matrix.
- Honor 1-release grace rule before removal (Honey Badger directive).

### 4.4 Feature Flags

- Registry maintained in [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md).
- Implementation pending for helper module and overrides (see open TODO).
- For tests, use override helpers once implementation lands; document toggles in PRs.

---

## 5. Governance & Compliance

### 5.1 DIP Process

- Required for any new cross-domain interaction.
- Proposal must cover purpose, latency tolerance, event vs call justification, telemetry spec, security hooks.
- Template and expectations outlined in Honey Badger plan (Section DIP Outline).

### 5.2 Event Taxonomy Stewardship

- New events must update registry tables, JSON schemas, and tests in [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md).
- Pending tasks: event linter mix task, docs site generation, fanout guard metrics.

### 5.3 Error Classification Governance

- Classifier rules live in [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md).
- Governance workflow: open issue → propose mapping → add tests → observe telemetry.
- DLQ policy requires `system.dlq.message` events and alerting; security-classified errors bypass standard DLQ to audit streams.

### 5.4 Security & Compliance

- ThunderGate enforces auth/policy; audit logs stored in ThunderBlock vault.
- TOCP insecure presence flag requires explicit approval; documented in [`TOCP_SECURITY.md`](Thunderline/documentation/TOCP_SECURITY.md).
- Maintain audit trail for feature toggles and DIP approvals.

---

## 6. Playbooks & Runbooks

| Scenario | Reference | Notes |
|----------|-----------|-------|
| Voice/WebRTC rollout | Honey Badger Phase A, [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md) | Relocate resources, enable feature flag, instrument events |
| Market → MoE → NAS pipeline | [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md) | Follow phased plan (0–5) for ingestion, routing, NAS integration |
| Flower Power federation | [`docs/flower-power/runbooks`](Thunderline/documentation/docs/flower-power/runbooks) | Round orchestration, deployment, dashboards |
| TOCP protocol operations | [`tocp/TOCP_TELEMETRY.md`](Thunderline/documentation/tocp/TOCP_TELEMETRY.md), [`TOCP_SECURITY.md`](Thunderline/documentation/TOCP_SECURITY.md) | Security posture, telemetry expectations |
| Deprecation sweep | [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md) | Telemetry monitoring, CI enforcement, removal steps |

**Launch checklist template**:
1. Identify feature flag coverage.
2. Update event taxonomy or error classifiers if emitting new signals.
3. Add telemetry instrumentation and dashboards.
4. Update runbooks and rollback plan.
5. Conduct dry run or shadow release.
6. Record approvals (DIP, security, governance).

---

## 7. Growth & Roadmap

### 7.1 Upcoming Milestones

| Milestone | Domain | Source | Target |
|-----------|--------|--------|--------|
| Voice Membrane integration | ThunderLink | Honey Badger A6/A7 | Sprint +2 |
| Policy centralization | ThunderCrown | Honey Badger B1 | Sprint +4 |
| Event lint mix task | ThunderFlow | `EVENT_TAXONOMY.md` Section 14 | Sprint +1 |
| Feature helper implementation | Platform | `FEATURE_FLAGS.md` Section 10 | Sprint +1 |
| DLQ dashboard surfacing | ThunderFlow | Domain top-down enhancements | Sprint +2 |
| NAS loop Phase 5 | ThunderBolt/Chief | Market MoE plan Section 10 | Sprint +5 |

### 7.2 Risks & Mitigations

- **Migration drift**: Use alias telemetry, CI enforcement, and manual audits per [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md).
- **Event taxonomy churn**: Version events, stage schema changes with consumer readiness, and publish upgrade guides.
- **Policy refactor regression**: Add contract tests and golden fixtures when moving to unified policy engine.
- **Orchestration backlog**: Feature flag gating to decouple Bolt refactors from Link deliverables.
- **Deprecated wrappers lingering**: Monitor telemetry thresholds and enforce removal in Phase C (Honey Badger plan).

### 7.3 Skills & Mentorship

- Encourage cross-domain pairings, quarterly architecture reviews, and knowledge sessions using this handbook as the anchor.
- Maintain resource matrix showing domain owners and backup operators (kept in internal directory).

---

## 8. Reference & Appendices

### 8.1 Glossary

- **PAC**: Personal Autonomous Companion.
- **Lane**: Workflow engine orchestrating tasks in ThunderBolt.
- **ThunderBridge**: Ingest/offload adapter bridging external systems to EventBus.
- **DIP**: Domain Interaction Proposal.

### 8.2 Naming Conventions

- Event names: `<layer>.<domain>.<category>.<action>[.<phase>]` with singular nouns.
- Ash resources: Namespace by domain (`Thunderline.Thunderlink.Voice.*` after Honey Badger migrations).
- Feature flags: `:thunderline, :features, <snake_case_flag>`.

### 8.3 Post-Incident Review Template

```markdown
## Summary
- Incident ID / Title:
- Date / Duration:
- Domains Impacted:

## Timeline
- Detection:
- Mitigation:
- Resolution:

## Root Cause
- Trigger:
- Contributing Factors:

## Remediation Actions
- Immediate:
- Follow-up:

## Lessons & Preventive Measures
```

### 8.4 Change Log Template

```markdown
## YYYY-MM-DD – Title
- Domains touched:
- Linked PRs:
- Feature flags toggled:
- Event or error taxonomy updates:
- Follow-up tasks:
```

### 8.5 Legacy References

- Voice/WebRTC architecture [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md)
- Honey Badger consolidation plan [`architecture/honey_badger_consolidation_plan.md`](Thunderline/documentation/architecture/honey_badger_consolidation_plan.md)
- Event taxonomy [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md)
- Error classes [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md)
- Feature flags [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md)
- Migration matrix [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md)

---

_This handbook is living documentation. Keep it current, reference it during onboarding, and use it to drive consistent, sovereign domain operations._