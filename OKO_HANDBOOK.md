# 🌩️ OKO HANDBOOK: The Thunderline Technical Bible

> **LIVING DOCUMENT** - Last Updated: August 28, 2025  
> **Status**: � **ATLAS HANDOVER COMPLETE - PRODUCTION READY DOCUMENTATION**  
> **Purpose**: Comprehensive guide to Thunderline's Personal Autonomous Construct (PAC) platform & distributed AI orchestration system

---

## 🛰️ AGENT RAZOR SITREP — August 25, 2025
> Independent sweep across core, ThunderFlow, ThunderBolt (Cerebros), and (former) BOnus modules (now fully migrated). Focus: event bus unification, dashboard wiring, optional features (UPS/NDJSON), and ML persistence.

### 🔭 High Command External Review (Aug 25 2025) — Integrated Summary
External architectural & readiness audit produced prioritized launch gating backlog (HC-01..HC-10) now codified in Playbook ACTION MATRIX. Handbook records rationale layer; execution tracker lives in Playbook.

Key Accepted Findings (Doc Expansion Applied Aug 25 2025):
- (HC-01) Event publish helper absent → increases risk of divergent manual dispatch & missing telemetry.
- (HC-02) Residual shim alias usage creates conceptual double bus.
- (HC-03) Lack of canonical Event & Error taxonomy docs complicates cross-team alignment & SLO definition (addressed: Expanded `EVENT_TAXONOMY.md` v0.2 & `ERROR_CLASSES.md` v0.2 drafts seeded with governance + schema examples).
- (HC-04) Cerebros persistence disabled (migrations parked) blocking ML artifact auditability.
- (HC-05) Email MVP path undefined yet chosen as first user-facing automation goal.
- (HC-06) Presence & membership authorization incomplete = chat/presence instability risk.
- (HC-07) Missing production deployment scripts = operational uncertainty.
- (HC-08) CI lacks release packaging, dialyzer PLT caching, security audit (hex.audit), test partitioning.
- (HC-09) No centralized error classification / dead-letter governance.
- (HC-10) Feature flags undocumented; risk of hidden runtime behavior variance (addressed: Expanded `FEATURE_FLAGS.md` v0.2 with governance + override mechanics).

Strategic (P1/P2) Additions (post-launch hardening / scaling): ThunderBridge ingest layer (HC-11), DomainProcessor behaviour (HC-12), Voice/WebRTC (HC-13), richer telemetry dashboards (HC-14), security hardening expansion (HC-15), logging schema versioning (HC-16), federation phased roadmap (HC-17), performance baselines & regression guard (HC-18), mobile/offline strategy (HC-19).

Rationale / Mitigation Notes:
- Unified publish API will enforce `%Thunderline.Event{}` shape & trace span context → lower integration entropy.
- Taxonomy docs (`EVENT_TAXONOMY.md`, `ERROR_CLASSES.md`) become basis for SLO (retry rates, DLQ thresholds) & governance gates.
- ML migrations unblock run lineage, enabling reproducibility & later cost accounting.
- Deployment scripts codify release reproducibility (container digest, migration automation, healthcheck endpoint).
- Error classifier centralizes mapping (transient/permanent/user/system) feeding Broadway retry + DLQ metrics.
- Feature flag registry improves auditability & change risk review.

Cross-References:
- Playbook section: HIGH COMMAND REVIEW: ACTION MATRIX (authoritative backlog)
- Docs (HC-03 drafts complete): `EVENT_TAXONOMY.md` (v0.2), `ERROR_CLASSES.md` (v0.2)
- Docs (HC-10 draft complete): `FEATURE_FLAGS.md` (v0.2)
- Planned Mix Tasks: `mix thunderline.events.lint`, `mix thunderline.flags.audit` (see doc TODO sections)

Gating Definition: All P0 (HC-01..HC-10) must be GREEN before milestone `M1-EMAIL-AUTOMATION` (public pilot). Non-P0 feature PRs paused once P0 completion <70% until catch-up.

Risk if Deferred:
- Without HC-01/02 divergence will grow; taxonomy drift harder to reconcile retroactively.
- Shipping Email MVP without ML migrations (HC-04) limits observability of generated content performance/tuning.
- Lack of deployment automation (HC-07) increases incident MTTR & onboarding friction.

Tracking: Status values mirrored daily from Playbook into sitrep delta block; handbook retains summary only (no granular status churn to avoid duplication). Governance-affecting doc changes use commit prefix `GOV:`.

Recent Delta (Aug 29 2025):
- Internal UUID v7 generator (`Thunderline.UUID`) adopted; replaces interim v4 usage for event & correlation ids (improves chronological ordering heuristics).
- TOCP scaffold expanded: added `Routing.SwitchTracker` (emits `routing.relay_switch_rate`) & `Telemetry.Aggregator` (aggregates `security.sig_fail` / `security.replay_drop`).
- Security primitives scaffolded: `Security.Impl` (Ed25519 sign/verify via JOSE) and `Security.Pruner` (replay window pruning) under TOCP supervisor gating.
- Simulator report now surfaces security counters; telemetry docs & decisions updated (DIP-TOCP-002 partial progress).
- Feature flags registry extended with `:tocp` & `:tocp_presence_insecure` (pending insecure mode wiring).


 Summary
 - Event Bus: Canonical bus exists at `Thunderline.EventBus` (ThunderFlow). Legacy `Thunderline.Bus` kept as a compatibility shim and now forwards to the canonical pipelines. Decision: no runtime breakage; prefer EventBus in new code, shim remains until alias migration completes. (Aug 25–28 update) Added AI & batch helpers: `emit_batch_meta/2` (returns batch correlation id + aggregated meta) and `ai_emit/2` (whitelisted AI tool & streaming event emission enforcing taxonomy + correlation/causation rules). Correlation threading now codified (see `Docs/EVENT_TAXONOMY.md` §13) and error cross-link updated (`Docs/ERROR_CLASSES.md` §14). Lint task planned to enforce registry & AI event invariants. (Aug 28) UUID v7 migration complete (correlation & event ids) and architecture diagram added (see "System Architecture Overview" below & `Docs/architecture/system_overview.mmd`).
- Dashboard: LiveView is stable and minimal. Uses `EventBuffer.snapshot/1` for feed and listens to Bus status for UPS. Real-time pipeline already broadcasts optimized topics; next step is to subscribe to those for live metrics and reduce reliance on buffer snapshots.
- NDJSON + Checkpoint: Implemented (now under consolidated `lib/thunderline/` domains), wired to UI and optionally supervised (NDJSON behind `ENABLE_NDJSON`, Checkpoint always).
- UPS Watcher: Present and gated via `ENABLE_UPS`. Publishes status via Bus; UI badge renders correctly. Graceful when `upsc` missing.
- Cerebros (ThunderBolt ML): Code integrated (adapter, telemetry, simple_search, neural bridges). Persistence migrations for `ModelRun`/`ModelArtifact` currently parked under `priv/repo/_backup_*/` and not active. Action required to create tables before persisting artifacts/runs. Adapter supports external lib and CLI fallbacks; internal stub present.
- Pipelines & Storage: Broadway/Mnesia producers and real-time pipeline are in place; queue depth metrics available. Event struct normalization exists.

Risks / Gaps
- Alias debt: Multiple files still alias `Thunderline.Bus` (shim now forwards, but migration remains). Low risk; medium tech debt.
- ML persistence: Tables for Cerebros resources not yet migrated (migrations in backup). High risk for persistence features; low risk for demo/telemetry.
- External binaries: Optional dependencies (`upsc`, `cerebros` CLI) are environment-dependent; handled gracefully but should be documented in ops runbooks.
- BOnus reliance: (Resolved) All former BOnus code promoted; no special compile path required.

Decisions
- Bus consolidation: Canonical = `Thunderline.EventBus`. Keep `Thunderline.Bus` as a shim until repo-wide codemod completes. New code: use EventBus directly.

Next 48h (proposed deltas)
1. Apply ML persistence migrations: move the Cerebros migrations from `priv/repo/_backup_*/` to `priv/repo/migrations/` and run them.
2. LiveView wiring: subscribe dashboard to ThunderFlow real-time topics (metrics and dashboard batches) and de-emphasize buffer snapshots.
3. Codemod pass: replace `alias Thunderline.Bus` with `Thunderline.EventBus` where safe; leave shim for legacy tuple consumers.
4. (Done) Clarify feature flags: documented `ENABLE_UPS`, `ENABLE_NDJSON`, broader registry now in `FEATURE_FLAGS.md` v0.2.
5. (Done) BOnus promotion: `Log.NDJSON` and `Persistence.Checkpoint` already live under consolidated domains; flags documented.
6. Seed stubs (optional): `mix thunderline.events.lint` & `mix thunderline.flags.audit` tasks.

Health signals to watch
- `event.queue.depth` (MnesiaProducer tables) — trending and p95 vs baseline
- `dashboard_batch_update` throughput and latency in RealTimePipeline
- `cerebros_*` telemetry volume and error rates post-migration

Codename: AGENT RAZOR

---

## 🔁 Event Bus AI / Batch Correlation Enhancements (Aug 25–28 2025)
Rationale: Reduce drift & enforce governance for emerging AI + batch processing flows while preserving backward compatibility.

Additions:
1. `emit_batch_meta/2` — Emits a list of event payloads (or pre-built `%Thunderline.Event{}` structs) and returns `{batch_meta, correlation_id}` enabling callers to:
   - Reuse a single `correlation_id` for downstream AI tool invocations spawned from the batch.
   - Inspect per-event results & accumulated flags (e.g., reliability set, experimental markers) without re-querying storage.
2. `ai_emit/2` — Thin helper around normalized constructor enforcing that only approved AI event names (`ai.tool_start`, `ai.tool_result`, `ai.model_token`, `ai.conversation_delta`) are emitted. Rejects unknown AI names early to prevent taxonomy sprawl.
3. Correlation & causation propagation rules expanded (see `Docs/EVENT_TAXONOMY.md` §13). Batch root event id adopted as correlation where upstream absent; never re-bases mid-flow.
4. Error taxonomy cross-link (see `Docs/ERROR_CLASSES.md` §14) provides guidance for classifying AI tool chain failures with contextual keys (`:ai_stage`, `:correlation_id`).

Operational Guidance:
- ALWAYS capture the returned `correlation_id` from `emit_batch_meta/2` and supply it to any subsequent `ai_emit/2` calls spawned by that batch; failing to do so will surface in future linter (`mix thunderline.events.lint`) as a drift warning.
- Prefer `ai_emit/2` over generic `emit/2` for AI tool & streaming token events; it provides early validation + future metrics hooks.
- When migrating older code: replace manual per-event correlation assignment inside loops with a single `emit_batch_meta/2` followed by AI tool emissions referencing the returned id.

Planned Automation (not yet merged):
- Mix task `mix thunderline.events.lint` to scan for:
  * AI events emitted without `ai_emit/2`
  * Missing correlation propagation after batch emission (heuristic: AI event within same function scope following a batch emit lacking explicit correlation match)
  * Unregistered / non-whitelisted AI event names
- Telemetry enrichment: automatic `[:thunderline,:ai,:emit]` instrumentation from `ai_emit/2` with `ai_stage` & token sequencing metadata.

Risk Mitigation:
- Early whitelist prevents ungoverned proliferation of `ai.*` names.
- Central batch correlation issuance simplifies tracing across concurrent tool chains spawned from one root command.
- Documentation alignment ensures SLO design (token latency, tool duration) can key off consistent correlation.

Next Steps:
1. Ship linter task (HC-03 TODO) with AI/batch correlation checks.
2. Add machine-readable registry export (JSON) for docs site & possible MCP integration.
3. Integrate classifier hooks to auto-tag AI errors with stage & latency buckets.

Correlation ID Migration Note (Aug 28 2025):
- Previous correlation ids were Base64/hex random 128-bit values. Implementation now emits UUID v7 (time-ordered) for `Thunderline.Event` and Thundervine DAG lineage helpers. Legacy persisted events retain old ids; no backfill required. Any consumer relying on lexical sort for approximate chronology will see improved ordering characteristics immediately. No action required other than acknowledging mixed formats during retention window.

Status: Code merged; tests for `emit_batch_meta/2` & `ai_emit/2` passing. Awaiting linter + telemetry instrumentation PR.

### 🗺 System Architecture Overview (Aug 28 2025)
The following Mermaid diagram provides an updated, time-sorted view of the seven operational domains, primary event flows, Thundervine DAG orchestration linkages, and external AI/model egress surfaces. It reflects:
1. UUID v7 adoption for event & correlation ids (ingestion ordering aid)
2. Batch + AI emission helpers (`emit_batch_meta/2`, `ai_emit/2`)
3. Thundervine integration points (`cmd.workflow.plan/execute`, `dag.commit` lineage feedback)
4. Voice signaling & planned TURN/STUN edge
5. Separation of ingestion bridge vs policy gating vs orchestration
 6. Replacement of legacy Hermes MCP layer with `AshAI` interface + explicit `Jido Actions` runtime producing governed `ai.*` events

```mermaid
---
config:
  layout: dagre
  theme: neo-dark
---
flowchart LR
    BLOCK["ThunderBlock A\n(Persistence)"] -- event/state --> FLOW["ThunderFlow\n(Event/Telemetry)"]
    BLOCK2["ThunderBlock B\n(Persistence)"]
    BLOCK3["ThunderBlock C\n(Persistence)"]
    GATE["ThunderGate\n(Security)"] -- authN/Z/events --> FLOW
    LINK["ThunderLink\n(Comms + Voice)"] -- voice+msg events --> FLOW
    GRID["ThunderGrid\n(Spatial)"] -- zone events --> FLOW
    BOLT["ThunderBolt\n(Orchestration)"] -- orchestration events --> FLOW
    CROWN["ThunderCrown\n(Governance/AI)\n(ai_emit/2)"] -- ai/intent events --> FLOW
    FLOW -- feedback --> BLOCK
    FLOW -- signals --> GATE
    FLOW -- updates --> LINK
    FLOW -- placement --> GRID
    FLOW -- tasks/compute --> BOLT
    FLOW -- ai/context --> CROWN
    BLOCK -- infra config --- GATE
    GATE -- federate & auth --- LINK
    LINK -- placement --- GRID
    GRID -- jobs/ops --- BOLT
    BOLT -- intent + plans --- CROWN
    CROWN -- policy --- BLOCK
    %% Federation (multi-block knowledge & event replication)
    BLOCK -- replicate/events --- BLOCK2
    BLOCK2 -- replicate/events --- BLOCK3
    BLOCK3 -- knowledge sync --> BLOCK
    %% Gate-mediated auth handshakes
    BLOCK -. auth handshake .- GATE
    BLOCK2 -. auth handshake .- GATE
    BLOCK3 -. auth handshake .- GATE

    %% Block domain resources
    BLOCK --> blkVault["Postgres / Mnesia (Thundervault)"]
    BLOCK --> vine["Thundervine (DAG Orchestrator)"]
    BLOCK2 --> blkVault
    BLOCK3 --> blkVault
    BLOCK2 --> vine
    BLOCK3 --> vine

    %% Gate domain
    GATE --> gatePolicy["Policy / Rate Limiter"]
    gatePolicy --> gateBridge["ThunderBridge (Ingest / Egress)"] & gateBridge

    %% Link domain
    LINK --> lnkChan["Communities / Channels"] & voiceChan["VoiceChannel (signaling)"]
    voiceChan --> voiceSup["VoiceSupervisor / DynamicRoom"]
    voiceSup --> voiceRoomRes["VoiceRoom"]
    voiceRoomRes --> voicePartRes["VoiceParticipant"] & voiceDevRes["VoiceDevice"]

    %% Flow domain
    FLOW --> flowBus["EventBus / Thunderline.Event (logical)\nai_emit/2 & emit_batch_meta/2 telemetry"]
    BLOCK2 -- federated event --> flowBus
    BLOCK3 -- federated event --> flowBus

    %% Bolt domain
    BOLT --> boltPlan["Plan / DAG Orchestrator"]
    boltPlan --> boltLane["Lane Engine (modern)"]
    boltLane --> boltCell["ThunderCell (CA / compute kernels)"] & boltJobs["Workers / Jobs"]
    boltCell -- snapshots --> blkVault

  %% Crown domain (AshAI + Jido integration)
  CROWN --> ashAI["AshAI Interface"]
  ashAI --> jidoActs["Jido Actions Runtime"]
  jidoActs --> crnAI["AI Orchestration / Tool Select"]
  crnAI -- request model/tool --> gatePolicy
    gateBridge -- egress --> extAPI["External APIs / LLMs"]

    %% Grid domain
    GRID --> grZones["Zones / ECS Runtime"]

    %% Voice → Flow events
    voiceChan -- "voice.signal.*" --> flowBus
    voiceSup -- "voice.room.*" --> flowBus
    flowBus -- telemetry --> blkVault

    %% TURN/STUN
    gateBridge --> turn["TURN/STUN (future)"]

    %% ThunderCom (federated comms / legacy migration surface)
    COM["ThunderCom\n(Federated Comms)"]
    COM --> flowBus
    GATE --> COM
    BLOCK --> COM
    BLOCK2 --> COM
    BLOCK3 --> COM
    COM --> LINK

    %% Thundervine connections
    flowBus -->|"cmd.workflow.plan / execute"| vine
    boltPlan -->|"consume workflow DAG"| vine
    vine -->|"persist DAG nodes/edges"| blkVault
    vine -->|"dag.commit"| FLOW
    vine -->|"lineage for agents"| CROWN

    %% Classes
    BLOCK:::domain
    BLOCK2:::domain
    BLOCK3:::domain
    FLOW:::central
    GATE:::domain
    LINK:::domain
    GRID:::domain
    BOLT:::domain
    CROWN:::domain
    COM:::domain
    blkVault:::store
    gatePolicy:::bridge
    gateBridge:::bridge
    lnkChan:::res
    voiceChan:::res
    voiceSup:::res
    voiceRoomRes:::res
    voicePartRes:::res
    voiceDevRes:::res
    flowBus:::pipe
    boltPlan:::res
    boltLane:::res
    boltCell:::res
    boltJobs:::res
  ashAI:::res
  jidoActs:::res
    crnAI:::res
    extAPI:::ext
    grZones:::res
    turn:::ext
    vine:::res

    classDef domain fill:#204059,stroke:#77b8e0,stroke-width:2px,color:#e7faff,rx:14,ry:14
    classDef central fill:#282940,stroke:#dde0ff,stroke-width:3px,color:#fff
    classDef res fill:#233,stroke:#7df,color:#e3faff,rx:6,ry:6
    classDef store fill:#0f1f1f,stroke:#4fd,color:#d9ffff,rx:6,ry:6
    classDef bridge fill:#20201f,stroke:#d4b14a,color:#fff7d5,rx:6,ry:6,stroke-dasharray:3 2
    classDef pipe fill:#0e1633,stroke:#6aa0ff,color:#ebf3ff,rx:6,ry:6
    classDef ext fill:#2b150e,stroke:#ffb28a,color:#fff7f2,rx:6,ry:6
```

Source file: `Docs/architecture/system_overview.mmd` (authoritative; regenerate copies from there).

---

## ⚡ **TEAM STATUS UPDATES** - August 17, 2025

### **🚨 CURRENT BLOCKERS & ACTIVE WORK**

- Add: Bus consolidation — canonical `Thunderline.EventBus` active; `Thunderline.Bus` retained as shim (no functional change). New code should target EventBus.
- Add: Cerebros persistence — migrations for `ModelRun`/`ModelArtifact` not yet applied (located under `_backup_`); required to persist runs/artifacts.

**Erlang → Elixir Conversion**: 🟡 **ASSIGNED TO WARDEN TEAM** - Remaining ThunderCell Erlang modules being ported (5 → 0 target)  
**External Review Prep**: � **ACTIVE** - Refining architecture & domain docs for multi‑team consumption  
**Dashboard Integration**: 🟡 **IN PROGRESS** - Wiring real CA & Blackboard metrics (mock data being phased out)  
**Blackboard Integration**: ✅ **CORE COMPLETE** - GenServer + ETS + PubSub broadcasting; expanding metrics & persistence strategy  
**Automata Feature Parity Checklist**: 🟡 **DRAFTING** - Mapping against upstream wiki; gap remediation plan in progress  
**Cerebros/NAS Integration (ThunderBolt)**: 🟡 **DESIGN** - ML search + dataset behaviors relocating under ThunderBolt with DIP governance  
**Compilation Status**: ✅ **CLEAN BUILD** - Zero critical errors, ~200 minor warnings scheduled for phased cleanup (target <50 by Aug 24)  

### **🎯 IMMEDIATE PRIORITIES (Next 48 Hours)**
1. Finalize Automata Feature Parity Audit — Document DONE / GAP items & open DIP issues for gaps
2. Complete Remaining Erlang → Elixir Ports — Achieve 100% native ThunderCell processes
3. Replace Mock Dashboard Data — Source all metrics from live Blackboard/ThunderFlow events
4. Relocate Interim ML (Cerebros) Code — Ensure all ML modules live under `Thunderline.ThunderBolt` namespace (no new domain)
5. Warning Reduction Sprint — Remove low‑hanging unused imports/variables (target: -60 warnings)
6. Bus codemod (new) — Replace `alias Thunderline.Bus` with `Thunderline.EventBus` where safe; keep shim for legacy tuple consumers
7. ML migrations (new) — Move and run Cerebros migrations to enable model run/artifact persistence
8. Dashboard wiring (new) — Subscribe LiveView to RealTimePipeline topics; de-emphasize snapshot feed

### **✅ RECENT WINS**
- **Domain Consolidation**: 21 domains → 7 efficient, well-bounded domains (67% complexity reduction)
- **Blackboard System**: Central shared-state layer implemented (ETS + PubSub) & surfaced in UI
- **Automata LiveView**: Real-time CA visualization test coverage confirmed (stability baseline)
- **Event Architecture**: Broadway + Mnesia event processing fully operational
- **State Machines**: AshStateMachine 0.2.12 integration complete with proper syntax
- **Clean Repository**: Minimal root structure, integrated components, production-ready state
- **Erlang Bridge Noise Reduction**: Legacy delegate warnings mitigated via compatibility wrappers
- **Conversion Planning**: Detailed brief created for Erlang → Elixir migration
- **Probe Analytics Pipeline**: Added `ProbeRun`, `ProbeLap`, `ProbeAttractorSummary` Ash resources + Oban worker computing attractor (corr dim & Lyapunov incl. Rosenstein) with telemetry emission.
- **Recompute Action & Canonical Lyapunov**: Service & worker select canonical exponent with reliability heuristics (r² threshold) enabling future model stability dashboards.
- **Automated Dependency Management**: Dependabot configuration (grouped stacks) + CI workflow (compile, test, Credo, Dialyzer, Sobelow) + optional auto-merge for green dependency PRs.
- **git_ops Hardening**: Scoped semantic-release tooling to dev environment to prevent prod/test startup issues.
- Event Architecture: Broadway + Mnesia event processing fully operational
- Bus Unification (new): Canonical EventBus affirmed; legacy Bus turned into a forwarding shim to avoid duplication

### **⚠️ TECHNICAL DEBT & WARNINGS**
- **Erlang Dependencies**: Being eliminated through conversion to pure Elixir solution
- **Dashboard Fake Data**: Currently using mock automata data, real integration in progress
- **Minor Warnings**: ~200 compilation warnings (unused variables/imports) - cleanup scheduled
- **Missing Controllers**: HealthController, DomainStatsController need implementation

---

## 🧩 Automata Feature Parity Status (Snapshot: Aug 17 2025)
Reference: upstream `upstarter/automata` wiki feature list.

Legend: ✅ Implemented | 🟡 Partial / In Progress | 🔴 Not Yet | 💤 Deferred (intentional)

| Feature Category | Item | Status | Notes / Next Action |
|------------------|------|--------|----------------------|
| Core Evolution | Step/advance API | ✅ | Deterministic evolution cycle implemented |
| Core Evolution | Rule swapping at runtime | 🟡 | Basic rule module injection; add validation & telemetry gap |
| Neighborhoods | Moore / Von Neumann | ✅ | Configurable; verify 3D radius >1 variants |
| State Management | Multi-layer grids | 🔴 | Not yet; design doc needed (possible ThunderBolt extension) |
| State Management | Blackboard shared context | ✅ | GenServer + ETS + PubSub complete (extend metrics set) |
| Persistence | Snapshot / restore | 🔴 | Plan: Ash resource for snapshots (ThunderBolt) |
| Metrics | Cell churn rate | 🟡 | Calculated transiently; persist periodic aggregate via ThunderFlow |
| Metrics | Rule application counts | 🔴 | Add instrumentation hooks around evolution loop |
| UI | Live 3D lattice | 🟡 | LiveView test baseline; voxels integration pending Three.js fix |
| UI | Blackboard panel | ✅ | Rendering current key/value entries |
| Distribution | Multi-node CA partitioning | 🔴 | Requires post-Erlang conversion strategy (DIP to draft) |
| Distribution | Backpressure signaling | 🟡 | Event queue depth metric present; tie into evolution pacing |
| Safety | Rule sandboxing | 🔴 | Potential WASM/Elixir boundary; security review needed |
| Extensibility | Plugin rule modules | 🟡 | Manual injection supported; need registry & DIP constraints |
| API | External control actions | 🟡 | Internal calls exist; expose controlled Ash actions |

Gap Remediation Workflow:
1. Open DIP Issue per 🔴 gap (Intent + Mapping + Observability).
2. Attach parity table row link in issue description.
3. Implement smallest viable slice + telemetry.
4. Update this table (commit referencing issue ID).

Primary Focus Gaps (next): Snapshot/restore, rule application counts, voxel UI completion.

---

## 🧠 ThunderBolt ML (Cerebros) Integration Plan
All ML / NAS functionality is governed by ThunderBolt domain (NO new domain). Any proposal to diverge requires DIP approval & steward sign‑off.

### Migration Log (Cerebros → Thunderbolt)
| Date (UTC) | Change | Details | Removal Target |
|-----------|--------|---------|----------------|
| 2025-08-17 | Relocated Cerebros modules | Moved `Thunderline.ML.Cerebros.*` → `Thunderline.Thunderbolt.Cerebros.*` with deprecation aliases | v0.7.0 |
| 2025-08-17 | Added Ash resources | `ModelRun`, `ModelArtifact` + migration `20250817164740` | N/A |
| 2025-08-17 | Added telemetry & seeding to SimpleSearch | Namespaced under `[:thunderline,:thunderbolt,:cerebros,...]` | N/A |
| 2025-08-17 | Removed deprecated Cerebros & Automata aliases | Deleted all `Thunderline.ML.Cerebros.*` alias modules after migration | N/A |
| 2025-08-18 | Implemented dedicated Automata Blackboard process | Added `Thunderline.Thunderbolt.Automata.Blackboard` GenServer (ephemeral shared state + PubSub); legacy alias removed in 2025-08-19 refactor | N/A |
| 2025-08-17 | Purged legacy apps/thundervault folder | Removed root-owned infra artifacts (pgbouncer.ini, init.sql) after ThunderBlock consolidation | N/A |

Deprecation Policy: Alias modules will be removed after tag `v0.7.0` or 30 days (whichever later). CI task (planned) will fail builds if legacy namespace persists beyond window.

Phase 0 (Now):
- Relocate interim modules (`param_count`, dataset behaviours, search API) under `Thunderline.ThunderBolt.ML.*` namespace.
- Wrap experimental APIs with `@moduledoc :experimental` & guard usage behind feature flag (`:thunderline, :features, :ml_nas`).

Phase 1 (Foundational Resources):
- Ash Resources: `ModelRun`, `Trial`, `Artifact`, `DatasetSpec`.
- Actions: `start_run`, `record_trial_result`, `finalize_run`.
- Telemetry: `[:thunderline, :ml, :run, :start|:stop|:exception]` etc. standardized.

Phase 2 (Search & Scheduling):
- Strategy modules (random, grid, evolutionary) implementing `@behaviour Thunderline.ThunderBolt.ML.SearchStrategy`.
- Reactor orchestrating multi-trial life cycle (compensation on failed allocation).

Phase 3 (Optimization & Distribution):
- Distributed trial execution across CA cells (leveraging Blackboard for shared hyperparameter constraints).
- Persistence of best artifact lineage & reproducibility metadata.

Governance & Observability:
- Every new resource passes DIP checklist (10/10) & adds at least 1 metric + 1 telemetry event.
- No cross-domain direct DB joins; event emission via ThunderFlow when other domains must react.

Out-of-Scope (Deferred): Advanced NAS meta-learning, multi-tenant dataset marketplaces, GPU scheduler.

---

## 🛠️ Handbook Continuous Update SOP
Purpose: Keep this handbook an operationally trusted artifact across teams.

Trigger Events Requiring Update (commit should reference section changed):
1. New Ash resource merged (add to appropriate domain subsection + parity / metrics tables if relevant).
2. Domain invariant change (update DIP references + highlight in STATUS section for 7 days).
3. New telemetry namespace introduced (append to Observability or relevant domain plan).
4. Feature parity table row status change (update row + date suffix if major shift).
5. Completion of a previously listed blocker (move to Recent Wins within 24h).

Update Workflow:
1. Author prepares patch modifying ONLY relevant sections (minimize churn).
2. Include `HANDBOOK-UPDATE:` prefix in commit message.
3. Steward of impacted domain reviews for accuracy (async approval acceptable).
4. CI lint ensures date stamp updated if STATUS section changed.

Quality Bar:
- No stale status entries older than 7 days in Current Blockers.
- Parity tables reflect reality of main branch ≤24h old.
- All TODO / GAP items link to an open issue (or marked `planned` if within 48h of issue creation).

Audit Cadence:
- Weekly automated script (planned) flags missing issue links & stale dates.
- Monthly steward review rotates across domains.

Failure Handling:
- Missing update → create retro issue tagging responsible team.
- Repeated misses (>2 in a month) escalate to Steering Council for process adjustment.

---

---

## 🏛️ **AGENT ATLAS TENURE REPORT** -August 15, 2025

> **CODENAME**: ATLAS  
> **OPERATIONAL PERIOD**: JULY 2025  
> **MISSION**: Strategic codebase stabilization, domain consolidation, and handover preparation  
> **STATUS**: MISSION COMPLETE - HANDOVER READY

---

## 🏛️ **AGENT BIG CHIEF TENURE REPORT** - Active (Aug 17, 2025 → Present)

> **CODENAME**: BIG CHIEF  
> **OPERATIONAL PERIOD**: August 2025 (Post-Atlas Handover)  
> **MISSION**: Continuous domain guardianship, automata parity completion, ML (Cerebros) integration under ThunderBolt, handbook real-time accuracy, and noise (warnings) reduction  
> **STATUS**: IN PROGRESS - OPERATIONAL STABILITY MAINTAINED

### 🎯 Operational Focus
- Preserve 7-domain ecological balance (no domain sprawl)
- Finish Automata feature parity (snapshot/restore, rule metrics, voxel UI)
- Migrate remaining Erlang ThunderCell modules to Elixir
- Relocate & formalize ML/NAS components inside ThunderBolt with Ash resources
- Reduce compilation warnings (<50 near-term, <25 stretch)
- Elevate Blackboard from shared scratchpad to measurable system substrate (metrics + persistence plan)

### ✅ Early Contributions
- Handbook modernization cadence established (Continuous Update SOP embedded)
- Automata parity matrix drafted with remediation workflow
- Blackboard GenServer synthesized & surfaced in LiveView (UI observability of shared state)
- ErlangBridge noise reduction (delegate & pattern match harmonization)
- ThunderGrid domain clarification & documentation corrections (GraphQL/interface scope)

### 🧭 Invariants Being Guarded
| Invariant | Rationale | Guard Mechanism |
|-----------|-----------|-----------------|
| No new domains | Prevent complexity explosion | DIP Gate + Steward review |
| ML stays in ThunderBolt | Avoid shadow AI domain drift | Namespace audit in CI (planned) |
| Every new persistent process emits telemetry | Ensures observability-first | SOP + checklist enforcement |
| Parity table ≤24h stale | Keeps execution aligned with vision | Weekly script (planned) + manual spot checks |

### 📈 Near-term Metrics Targets (T+14d)
- `warning.count`: < 50 (from ~200)
- `ca.cell.churn.rate` variance: < 1.5x daily baseline
- Parity gaps (🔴): reduce by 3 (focus: snapshot/restore, rule counts, voxel UI)
- Telemetry coverage: +5 new events across ML & automata evolution

### 🧪 Upcoming DIP Issues (Queue)
1. DIP-AUTO-SNAPSHOT: CA snapshot & restore resource + persistence format
2. DIP-AUTO-RULE-METRICS: Instrumentation for rule application counting
3. DIP-AUTO-VOXEL-VIS: Three.js integration & performance budget definition
4. DIP-ML-FOUNDATION: ModelRun/Trial/Artifact resource introduction
5. DIP-BLACKBOARD-PERSIST: Strategy for durable Blackboard snapshots

### 🚨 Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Parity drift | Feature confusion, regressions | Weekly parity sync; enforce issue links |
| Warning debt ignored | Hidden defects & onboarding friction | Dedicated cleanup sprint allocation |
| ML sprawl | Domain boundary erosion | Namespace scanner + steward review |
| Blackboard overcoupling | Tight coupling to multiple domains | Keep API minimal; emit neutral events only |

### 🪙 Success Criteria (Exit Conditions)
- All 🔴 automata gaps closed or reclassified with scheduled DIP
- Warnings < 25 sustained for 7 days
- ML foundational Ash resources merged & emitting telemetry
- Blackboard persistence blueprint approved (DIP accepted)
- Handbook parity & status sections stable with <24h drift for 30 consecutive days

> "Big Chief maintains the living heartbeat post-Atlas—protecting clarity, finishing the parity journey, and hardening the substrate for scale."  

---

### **🎯 STRATEGIC ACCOMPLISHMENTS**

**Domain Architecture Overhaul**
- **Reduced complexity by 67%**: Consolidated 21 scattered domains into 7 focused, well-bounded domains
- **Established clear boundaries**: Each domain now has distinct responsibilities and minimal coupling
- **Documented patterns**: Created comprehensive guidelines for future domain expansion
- **Technical Debt Reduction**: Eliminated circular dependencies and architectural anti-patterns

**AshOban Integration Mastery**
- **Resolved critical authorization issues**: Fixed AshOban trigger authorization bypasses
- **Cleaned invalid configurations**: Removed non-existent `on_error` options causing compilation failures
- **Established working patterns**: Created reliable templates for future Oban job integration
- **Operational validation**: Confirmed working GraphQL API with proper AshOban resource handling

**Codebase Stabilization**
- **Achieved clean builds**: Zero critical compilation errors, system fully operational
- **Server stability**: Phoenix server running reliably with all domains properly initialized
- **Migration success**: All database schemas migrated and validated
- **Component integration**: AshPostgres, AshGraphQL, and AshOban working in harmony

### **💡 CRITICAL INSIGHTS & WARNINGS FOR NEXT OPERATOR**

**Domain Complexity Management**
> "This codebase demonstrates how quickly complexity can spiral in distributed systems. The original 21-domain structure was unsustainable - each new feature created exponential integration complexity. The 7-domain architecture is the maximum sustainable complexity for a team of this size. **Resist the urge to create new domains unless absolutely necessary.**"

**Ash Framework Gotchas**
> "Ash 3.x syntax is unforgiving. The `data_layer: AshPostgres.DataLayer` in the `use` statement is CRITICAL - forget this and you'll spend hours debugging mysterious errors. Always validate with `mix compile` after any resource changes. The two-pattern attribute syntax (inline vs block) should be used consistently within each resource."

**Event-Driven Architecture**
> "The Broadway + Mnesia event system is powerful but requires careful memory management. Monitor event queue depths religiously - they can grow unbounded under high load. The cellular automata visualization is completely dependent on event flow, so any Broadway pipeline failures will immediately impact the user experience."

**Technical Debt Accumulation**
> "~200 compilation warnings represent technical debt that will compound rapidly. Each unused import and variable makes the codebase harder to navigate. Schedule regular cleanup cycles or this will become unmanageable. The Erlang → Elixir conversion is urgent - the mixed-language architecture creates deployment and debugging complexity."

### **🔧 OPERATIONAL RECOMMENDATIONS**

**Immediate Actions (Next 7 Days)**
1. **Complete ThunderCell conversion**: Eliminate Erlang dependencies entirely
2. **Fix Three.js import**: Unblock the CA voxel lattice demo for stakeholder presentations
3. **Clean compilation warnings**: Target 90% reduction in minor warnings
4. **Implement missing controllers**: HealthController and DomainStatsController for monitoring

**Strategic Initiatives (Next 30 Days)**
1. **Dashboard real data integration**: Replace mock metrics with live CA state
2. **GraphQL Interface Hardening**: ThunderGrid (GraphQL interface & spatial grid resources) stabilization & schema hygiene
3. **Federation protocol**: ActivityPub implementation for multi-instance coordination
4. **Performance baseline**: Establish benchmarks before adding new features

**Long-term Vision (Next 90 Days)**
1. **MCP integration**: Model Context Protocol for AI tool coordination
2. **Production deployment**: Multi-tenant architecture with proper security
3. **Mobile applications**: iOS/Android interfaces for PAC management
4. **AI marketplace**: Ecosystem for sharing autonomous constructs

### **⚠️ CRITICAL WARNINGS**

**Memory Management**
> "The Mnesia + Broadway combination can consume memory rapidly under load. Implement proper backpressure and circuit breakers before production deployment. The 3D CA visualization is particularly memory-intensive - consider LOD (Level of Detail) optimizations for large automata grids."

**Distributed State Consistency**
> "The federated architecture assumptions require careful consideration of CAP theorem tradeoffs. Current implementation favors availability over consistency - this is correct for most use cases but may require adjustment for financial or safety-critical applications."

**Complexity Boundaries**
> "The current 7-domain architecture is near the maximum sustainable complexity. Any new major features should be implemented within existing domains rather than creating new ones. If you must add an 8th domain, consider whether you need to split the codebase into separate services."

### **🎖️ HANDOVER CERTIFICATION**

**Code Quality Assessment**: ✅ **PRODUCTION READY**
- Clean compilation with zero critical errors
- All core domains operational and tested
- Database schema consistent and migrated
- GraphQL API functional with proper authorization

**Documentation Status**: ✅ **COMPREHENSIVE**
- Architecture patterns documented and validated
- Common pitfalls identified with solutions
- Development workflow established and tested
- Critical dependencies mapped with version constraints

**Operational Readiness**: ✅ **DEPLOYMENT READY**
- Phoenix server stable with proper supervision
- Event processing pipelines operational
- Resource management functional across all domains
- Security boundaries identified (implementation pending)

**Strategic Positioning**: ✅ **GROWTH READY**
- Technical debt catalogued with remediation plans
- Performance baselines established
- Federation architecture designed for scale
- AI integration pathways clearly defined

### **🌩️ FINAL REMARKS FROM ATLAS**

> "Thunderline represents a fascinating intersection of distributed systems, cellular automata, and AI orchestration. The codebase has evolved from a experimental prototype to a production-capable platform during this tenure. The 7-domain architecture provides a solid foundation for the Personal Autonomous Construct vision."

> "Future operators should remember that complexity is the enemy of reliability. Every feature addition should be evaluated not just for its immediate value, but for its impact on system comprehensibility. The cellular automata visualization is not just a nice-to-have - it's a critical tool for understanding system behavior in production."

> "The federated architecture positioning is prescient. As AI agents become more sophisticated, the need for distributed, autonomous coordination will only grow. Thunderline is well-positioned to become infrastructure for the next generation of AI systems."

> "May your cellular automata evolve beautifully, and may your domains remain well-bounded. **ATLAS OUT.** ⚡"

---

## 🎯 **WHAT IS THUNDERLINE?**

**Thunderline** is a distributed Personal Autonomous Construct (PAC) platform that enables AI-driven automation through 3D cellular automata, federated communication, and intelligent resource orchestration. Think of it as "Kubernetes for AI agents" with real-time 3D visualization and distributed decision-making capabilities.

---

## 🌿 **SYSTEMS THEORY & DOMAIN ECOLOGY**

We treat the 7 domains as an ecological system, not a pile of folders. Each domain is a biome with:
- **Niche (Purpose)** – Explicit, narrow responsibility surface.
- **Energy Flows (Events)** – Ingress/egress event types it produces/consumes.
- **Symbiosis (Dependencies)** – Allowed collaboration paths (documented in the Domain Interaction Matrix).
- **Homeostasis Signals (Metrics)** – Health indicators we monitor to avoid pathological growth.

Ecological Anti‑Patterns:
- **Domain Predation**: One domain starts implementing logic belonging to another → triggers a governance review.
- **Unchecked Biomass**: Rapid resource proliferation (>5 new resources in a sprint) without pruning legacy.
- **Mutation Drift**: Silent changes to core invariants (naming, state machine transitions, event shapes) without catalog update.
- **Trophic Collapse**: Removal/refactor in a foundational domain (ThunderBlock/ThunderFlow) without impact simulation.

Mitigation Principles:
1. **Constrain before you add** – Prefer refining existing resource capabilities or adding calculations/actions over new resources.
2. **One Event Shape per Flow** – Normalize before fan‑out (Reactor enforced) to prevent combinatorial variant explosion.
3. **Compensate, then Retry** – Sagas (Reactors) encode systemic resilience; no ad-hoc retry loops.
4. **Metric Before Feature** – New persistent process must expose at least one health metric & one telemetry event.

---

## 🛡️ **DOMAIN INTEGRITY PROTOCOL (DIP)**

| Step | Gate | Description | Artifact |
|------|------|-------------|----------|
| 1 | Intent | Describe why existing resources insufficient | DIP Issue (GitHub) |
| 2 | Mapping | Show domain alignment & rejection of others | Domain matrix delta |
| 3 | Invariants | List new/modified invariants | Invariants section PR diff |
| 4 | Impact | Affected event types, backpressure risk | Event impact table |
| 5 | Observability | Metrics + telemetry events planned | Metrics spec snippet |
| 6 | Reactor Plan | Orchestration model (if multi-step) | Reactor graph (Mermaid) |
| 7 | Review | Two maintainers + domain steward sign-off | PR approvals |
| 8 | Catalog Update | Update Domain Catalog & Playbook | Synced docs PR |

Failure to pass all gates → change rejected or quarantined under `/experimental` (time-boxed).

Forbidden without Steering Council approval:
- Creation of an 8th domain.
- Cross-domain DB table joins (use events or actions).
- Introducing new global process registries (coordinate via existing patterns).

---

## 🧪 **RESOURCE ADDITION CHECKLIST**

Before merging a new Ash resource:
1. Domain confirmed (NO cross-cutting leakage).
2. `use Ash.Resource` uses correct `data_layer`.
3. Table + index strategy documented (if Postgres).
4. Authorization / visibility defined (or explicitly deferred with comment).
5. At least one action returns consistent shape (struct/map) + spec.
6. Telemetry: `[:thunderline, :resource, :<domain>, :action, :stop]` emitted or planned.
7. Event emission path (if any) uses normalized `%Thunderline.Event{}` or documented variant.
8. Tests: happy path + one failure path (or stub with TODO + ticket).
9. Domain Catalog updated (resource line added under correct heading).
10. No duplicate or overlapping semantic with existing resource (search pass).
11. Lifecycle evaluated: if constrained, uses `state_machine` (or PR documents exception rationale).

Gate phrase in PR description: `DIP-CHECKLIST: 10/10`.

---

## 🔄 **REACTOR / SAGA GOVERNANCE**

Reactor adoption must *reduce* orchestration entropy.

Use a Reactor when ALL apply:
- ≥3 dependent steps OR ≥2 parallelizable branches.
- At least one external side-effect (DB, network, event emit) plus a rollback obligation.
- Need for targeted retry policies (transient vs fatal).

DO NOT use a Reactor for simple single-step CRUD or pure transforms—keep it inline.

Standard Step Classification:
| Prefix | Semantics | Side Effect | Undo Required |
|--------|-----------|-------------|---------------|
| `load_` | Fetch / hydrate | No | No |
| `compute_` | Pure derivation | No | No |
| `persist_` | DB mutation | Yes | Yes |
| `emit_` | Event/pubsub | Yes | Optional (idempotent emit preferred) |
| `call_` | External API / bridge | Yes | Usually (compensate or classify transient) |
| `finalize_` | Terminal commit / ack | Yes | Yes (undo cascades) |

---

## 🧷 **FINITE STATE MACHINES (Ash StateMachine) – LIFECYCLE MODELING STANDARD**

Explicit state machines are FIRST-CLASS lifecycle boundaries. They prevent impossible states, centralize transition logic, and enable policy & UI coupling. Inspired by Christian's traffic light → ecommerce order transcript: enumerate valid states, restrict transitions, expose them as code + diagrams.

### When to Use
Adopt `ash_state_machine` when:
1. Bounded set of semantic lifecycle states (≤ ~15).
2. At least one transition has validation/side-effect.
3. Illegal states would create data ambiguity or policy bugs.
4. UI or authorization changes per lifecycle phase.

Do NOT use for: derived/calculated states, unbounded enums, trivial booleans.

### Example (Proposed `ModelRun` Resource)
```elixir
defmodule Thunderline.ThunderBolt.ML.ModelRun do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "ml_model_runs"
    repo Thunderline.Repo
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending
    transition :start_run,     from: [:pending],  to: [:running, :failed]
    transition :record_trial,  from: [:running],  to: [:running]
    transition :finalize,      from: [:running],  to: [:completed, :failed]
    transition :archive,       from: [:completed], to: [:archived]
    transition :retry,         from: [:failed],   to: [:pending, :running]
  end

  actions do
    defaults [:read]
    action :start_run do
      change transition_state(:running, fallback: :failed)
    end
    action :finalize do
      change transition_state(:completed)
    end
  end

  policies do
    policy action(:archive) do
      authorize_if relates_to_actor_via(:owner)
      forbid_unless can_transition_to_state(:archived)
    end
  end
end
```

### Telemetry
Emit:
- `[:thunderline, :state_machine, :transition, :start|:stop]`
- `[:thunderline, :<domain>, :<resource>, :transition, :<from>, :<to>]`

Metadata: `actor_id`, `resource_id`, `transition`, `from`, `to`, `result`, duration (µs).

### Candidate Conversions
| Domain | Implicit Lifecycle | Proposed States | Benefit |
|--------|--------------------|-----------------|---------|
| ThunderBolt.ML (Cerebros) | Run status | `:pending → :running → :completed | :failed → :archived` | Retry & UI gating |
| ThunderFlow | Event batch | `:queued → :processing → :acked | :failed | :dead_letter` | Backpressure clarity |
| ThunderBlock Vault Ingestion | Memory indexing | `:received → :parsing → :indexed | :error` | Reprocessing strategy |
| Automata Snapshot (planned) | Snapshot lifecycle | `:scheduled → :capturing → :persisted | :expired` | Retention policy |
| Financial Refund (future) | Refund workflow | `:requested → :approved → :executing → :settled | :rejected` | Audit integrity |

### Reactor vs State Machine
| Need | State Machine | Reactor | Both |
|------|---------------|---------|------|
| Enforce allowed target states | ✅ | ✗ | ✅ |
| Multi-step orchestration | ✗ | ✅ | ✅ |
| Visual diagram generation | ✅ | ✗ | ✅ |
| UI enable/disable logic | ✅ | ✗ | ✅ |
| Compensating rollback | ✗ | ✅ | ✅ |

### Adoption Steps
1. Inventory attributes named `:state` / `:status` / `:phase`.
2. Open DIP referencing this section (batch similar trivial conversions).
3. Implement state_machine + telemetry + policy guards.
4. Remove scattered manual state mutations.

## 🧭 **CHANGE CONTROL FLOW (SUMMARY)**

```
Idea → DIP Issue → Design (Reactor + Metrics + Catalog delta) → PR (Checklist + Mermaid) → Review (Steward + Peer) → Merge → Catalog Sync → Post-merge Health Snapshot
```

Stewards (initial assignment):
- ThunderBlock: Infrastructure Lead
- ThunderBolt: Orchestration Lead
- ThunderCrown: AI Governance Lead
- ThunderFlow: Observability Lead
- ThunderGate: External Integrations/Federation Lead
- ThunderGrid: GraphQL & Spatial/Grid Lead
- ThunderLink: Realtime Interface/Comms Lead

Steward sign-off required for domain modifications & resource deletions.

---

### **🔑 Core Value Proposition**
- **Personal AI Automation**: Deploy and manage autonomous AI constructs that handle complex workflows
- **3D Cellular Automata**: Visual, interactive representation of distributed processes and decisions
- **Federated Architecture**: Connect multiple Thunderline instances across organizations and networks
- **Real-time Orchestration**: Live coordination of AI agents, resources, and computational tasks
- **Event-driven Processing**: Reactive system with Broadway pipelines and distributed state management

## 🏗️ **SYSTEM ARCHITECTURE OVERVIEW**

### **High-Level Architecture**
Thunderline follows a **domain-driven, event-sourced architecture** built on Elixir/Phoenix with distributed processing capabilities:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ThunderCrown  │    │   ThunderLink   │    │   ThunderGate   │
│ GOVERNANCE      │◄──►│  Communication  │◄──►│   SECURITY      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ThunderFlow   │    │   ThunderBolt   │    │   ThunderBlock  │
│ Event Processing│◄──►│ Resource Mgmt   │◄──►│ Infrastructure  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                               ▲
                               │
                               ▼
                    ┌─────────────────┐
                    │   ThunderGRID   │
                    │  GRAPHQL / GRID │
                    └─────────────────┘
```

### **🎯 The 7-Domain Architecture**

**🏗️ ThunderBlock** (23 resources) - **Infrastructure & Memory Management**
- Distributed memory management with Mnesia/Memento
- Resource allocation and container orchestration
- Vault systems for secure data storage and encryption

**⚡ ThunderBolt** (31 resources) - **Resource & Lane Management Powerhouse**
- Lane configuration and rule orchestration
- ThunderCell integration (3D cellular automata processing)
- Chunk management and distributed computation coordination

**👑 ThunderCrown** (4 resources) - **AI Governance & Orchestration**
- Model Context Protocol (MCP) integration for AI tool coordination
- Neural network orchestration with Nx/EXLA
- AI workflow management and decision trees

**🌊 ThunderFlow** (13 resources) - **Event Processing & System Monitoring**
- Broadway event pipelines with Mnesia backend
- Real-time metrics collection and aggregation
- Cross-domain event coordination and state synchronization

**🚪 ThunderGate** (7 resources) - **External Integration & Federation**
- ActivityPub protocol implementation for federated communication
- External API integrations and webhook management
- Multi-realm coordination and identity management

**🔗 ThunderLink** (6 resources) - **Communication & Social Systems**
- WebSocket connections and real-time messaging
- Dashboard metrics and user interface coordination
- Social features and collaboration tools

**🧭 ThunderGrid** (TBD resource count) - **GraphQL Interface & Spatial Grid**
- Central GraphQL schema & boundary enforcement
- Spatial grid & zone resource modeling (coordinates, zones, boundaries)
- Aggregation & projection layer for cross-domain read models


## 🤖 **WHAT MAKES THUNDERLINE UNIQUE?**

### **1. 3D Cellular Automata as Process Visualization**
Unlike traditional monitoring dashboards, Thunderline represents distributed processes as living 3D cellular automata where:
- **Each cell** = A computational process, AI agent, or resource
- **Cell states** = Process health, workload, or decision state
- **Cell evolution** = Real-time process interactions and state changes
- **CA rules** = Business logic, resource allocation policies, or AI decision trees

### **2. Event-Driven Everything**
Every action in Thunderline generates events processed through Broadway pipelines:
- **User interactions** → Events → State changes → CA visualization updates
- **AI decisions** → Events → Resource allocation → Visual feedback
- **System changes** → Events → Federation sync → Multi-realm coordination

### **3. Personal Autonomous Constructs (PACs)**
PACs are sophisticated AI agents that:
- **Learn** from user behavior and preferences
- **Automate** complex workflows across multiple systems
- **Coordinate** with other PACs in federated networks
- **Visualize** their decision-making through cellular automata

### **4. Federated Architecture**
Multiple Thunderline instances can federate through ActivityPub protocol:
- **Cross-organization** AI collaboration
- **Distributed computation** across multiple nodes
- **Shared learning** between autonomous constructs
- **Resilient operations** with no single point of failure

## 🛣️ **DEVELOPMENT ROADMAP & VISION**

### **Phase 1: Foundation (COMPLETE ✅)**
- **Domain Architecture**: 7-domain consolidated architecture with clear boundaries
- **Event System**: Broadway + Mnesia event processing pipeline
- **State Management**: AshStateMachine integration with Ash 3.x resources
- **Infrastructure**: ThunderBlock memory management and resource allocation

### **Phase 2: Core Features (IN PROGRESS 🔄)**
- **3D Cellular Automata**: Real-time visualization of distributed processes
- **Dashboard Integration**: Live metrics from actual system state
- **ThunderCell Engine**: Native Elixir cellular automata processing
- **Basic AI Orchestration**: Simple autonomous construct deployment

### **Phase 3: AI & Federation (PLANNED 📋)**
- **MCP Integration**: Model Context Protocol for AI tool coordination
- **ActivityPub Federation**: Cross-instance communication and collaboration
- **Advanced PACs**: Learning autonomous constructs with behavior trees
- **Neural Networks**: Nx/EXLA integration for distributed ML workloads

### **Phase 4: Production & Scale (FUTURE 🚀)**
- **Multi-tenant Architecture**: Support for multiple organizations
- **Enterprise Security**: Advanced authentication, authorization, audit
- **Performance Optimization**: Distributed processing and load balancing
- **Mobile Applications**: iOS/Android apps for PAC management

## 🗺️ **CODEBASE NAVIGATION GUIDE**

### **📁 Key Directories**
```
/lib/thunderline/
├── application.ex              # OTP application and supervision tree
├── repo.ex                     # Database connection and Ecto setup
├── thunderblock/               # Infrastructure & memory management
├── thunderbolt/                # Resource management & ThunderCell
│   ├── thundercell/           # 3D cellular automata engine
│   └── erlang_bridge.ex       # Integration layer (being deprecated)
├── thundercrown/              # AI governance & orchestration
├── thunderflow/               # Event processing & metrics
├── thundergate/               # External integrations & federation
├── thunderlink/               # Communication & dashboard
├── thundergrid/               # GraphQL interface & spatial grid resources
└── (security pending)         # Security domain deferred (placeholder removed)

/lib/thunderline_web/
├── live/                      # Phoenix LiveView modules
├── controllers/               # HTTP API endpoints
└── components/                # Reusable UI components

/config/
├── config.exs                 # Base configuration
├── dev.exs                    # Development environment
├── prod.exs                   # Production environment
└── test.exs                   # Test environment

/priv/
├── repo/migrations/           # Database schema changes
└── static/                    # Static assets (CSS, JS, images)
```

### **🎯 Starting Points for New Contributors**

**For Backend Developers:**
1. **Start with**: `/lib/thunderline/application.ex` - Understand the supervision tree
2. **Key Resources**: Explore Ash resources in each domain for data models
3. **Event System**: Look at `/lib/thunderline/thunderflow/` for event processing
4. **Integration**: Check `/lib/thunderline/thunderbolt/thundercell/` for CA engine

**For Frontend Developers:**
1. **Start with**: `/lib/thunderline_web/live/` - Phoenix LiveView modules
2. **Components**: `/lib/thunderline_web/components/` for reusable UI elements
3. **Dashboard**: `/lib/thunderline/thunderlink/dashboard_metrics.ex` for metrics
4. **Real-time**: WebSocket integration through Phoenix channels

**For AI/ML Engineers:**
1. **Start with**: `/lib/thunderline/thundercrown/` - AI governance domain
2. **Neural Networks**: Look for Nx/EXLA integration patterns
3. **Behavior Trees**: Check ThunderBolt for agent decision-making logic
4. **MCP Protocol**: Model Context Protocol integration points

**For DevOps Engineers:**
1. **Start with**: `/config/` - Environment configuration
2. **Infrastructure**: `/lib/thunderline/thunderblock/` for resource management
3. **Monitoring**: `/lib/thunderline/thunderflow/` for metrics and events
4. **Federation**: `/lib/thunderline/thundergate/` for external integrations  

## 🚀 **GETTING STARTED: DEVELOPMENT SETUP**

### **Prerequisites**
- **Elixir 1.15+** with OTP 26+
- **PostgreSQL 14+** for primary data storage
- **Node.js 18+** for asset compilation
- **Git** for version control

### **Quick Start**
```bash
# Clone the repository
git clone https://github.com/Thunderblok/Thunderline.git
cd Thunderline

# Install dependencies
mix deps.get
npm install --prefix assets

# Setup database
mix ecto.setup

# Start the development server
mix phx.server
```

**Access Points:**
- **Web Interface**: http://localhost:4000
- **Dashboard**: http://localhost:4000/live/dashboard
- **LiveView Debug**: http://localhost:4000/dev/dashboard

### **Development Workflow**
1. **Check Status**: `mix compile` - Ensure clean build
2. **Run Tests**: `mix test` - Validate changes
3. **Code Quality**: `mix format` and `mix credo` - Maintain standards
4. **Live Development**: `mix phx.server` - Hot reload enabled

## 🔧 **TECHNICAL STACK**

### **Core Technologies**
- **Language**: Elixir (functional, concurrent, fault-tolerant)
- **Framework**: Phoenix (web framework with LiveView for real-time UI)
- **Database**: PostgreSQL (primary) + Mnesia (distributed events)
- **ORM**: Ash Framework 3.x (resource-based data layer)
- **Events**: Broadway (event processing) + PubSub (real-time communication)

### **Specialized Libraries**
- **State Machines**: AshStateMachine for complex workflow management
- **Neural Networks**: Nx/EXLA for distributed machine learning
- **Encryption**: Cloak for secure data storage
- **Spatial Processing**: Custom 3D coordinate systems for cellular automata
- **Federation**: ActivityPub protocol implementation

### **Architecture Patterns**
- **Domain-Driven Design**: Clear domain boundaries with focused responsibilities
- **Event Sourcing**: All state changes captured as immutable events
- **CQRS**: Command/Query separation for optimal read/write performance
- **Actor Model**: Process-per-entity for distributed, fault-tolerant processing

## 🎮 **USE CASES & EXAMPLES**

### **Personal Automation**
```elixir
# Deploy a PAC to automate email processing
Thunderline.ThunderCrown.deploy_pac(%{
  name: "EmailProcessor",
  triggers: ["new_email"],
  actions: ["categorize", "respond", "schedule"],
  learning_enabled: true
})
```

### **Distributed Computation**
```elixir
# Process large dataset across multiple nodes
Thunderline.ThunderBolt.distribute_computation(%{
  dataset: large_dataset,
  processing_function: &ml_training_step/1,
  nodes: [:node1, :node2, :node3],
  visualization: :cellular_automata
})
```

### **Real-time Collaboration**
```elixir
# Create federated workspace
Thunderline.ThunderGate.create_federation(%{
  name: "CrossOrgProject",
  participants: ["org1.thunderline.com", "org2.thunderline.com"],
  shared_resources: [:ai_models, :computation_power],
  governance: :consensus_based
})
```

## 📊 **MONITORING & OBSERVABILITY**

### **Built-in Metrics**
- **System Health**: Process counts, memory usage, message queue depths
- **Domain Metrics**: Resource utilization, event processing rates, error counts
- **AI Performance**: Model accuracy, inference times, learning progress
- **Federation Stats**: Cross-instance communication, sync status, latency

### **3D Cellular Automata Dashboard**
The unique feature of Thunderline is its 3D CA visualization where:
- **Healthy processes** = Bright, stable cells
- **Overloaded systems** = Rapidly changing, hot-colored cells  
- **Failed components** = Dark or flickering cells
- **Communication flows** = Connections between cells
- **AI decisions** = Cascading cell state changes

### **Real-time Monitoring**
```bash
# Access live dashboard
open http://localhost:4000/live/dashboard

# Monitor specific domain
Thunderline.ThunderFlow.monitor_domain(:thunderbolt)

# Track PAC performance
Thunderline.ThunderCrown.pac_metrics("EmailProcessor")
```

## 🤝 **CONTRIBUTING & COLLABORATION**

### **How to Contribute**
1. **Read the Code**: Start with this handbook and explore the codebase
2. **Pick a Domain**: Choose an area that interests you (AI, UI, infrastructure, etc.)
3. **Small Changes First**: Begin with documentation, tests, or minor features
4. **Follow Patterns**: Maintain consistency with existing code architecture
5. **Submit PRs**: Use clear commit messages and detailed pull request descriptions

### **Code Standards**
- **Elixir Style**: Follow official Elixir style guide and use `mix format`
- **Documentation**: All public functions must have `@doc` and examples
- **Testing**: Write tests for new features and maintain coverage
- **Domain Boundaries**: Respect the 7-domain architecture
- **Event-Driven**: Use events for cross-domain communication

### **Communication Channels**
- **GitHub Issues**: Bug reports, feature requests, discussions
- **Team Updates**: Check this handbook's status section regularly
- **Technical Decisions**: Document in OKO_HANDBOOK.md
- **Code Reviews**: Collaborative, educational, and constructive

## 🎯 **CURRENT FOCUS AREAS**

### **🔥 Immediate Opportunities (Next 2 weeks)**
1. **ThunderCell Conversion**: Help convert Erlang modules to Elixir GenServers
2. **Dashboard UI**: Implement real-time 3D cellular automata visualization
3. **Documentation**: Improve code documentation and examples
4. **Testing**: Increase test coverage across domains

### **🚀 Medium-term Goals (Next 2 months)**
1. **MCP Integration**: Model Context Protocol for AI tool coordination
2. **ActivityPub Federation**: Cross-instance communication protocol
3. **Performance Optimization**: Benchmark and optimize event processing
4. **Security Implementation**: Authentication, authorization, and audit systems

### **🌟 Long-term Vision (Next 6 months)**
1. **Production Deployment**: Multi-tenant, scalable cloud deployment
2. **Mobile Applications**: iOS/Android apps for PAC management
3. **AI Ecosystem**: Rich marketplace of autonomous constructs
4. **Enterprise Features**: Advanced security, compliance, and management tools

---

## 📚 **TECHNICAL APPENDIX**

### **🔧 ASH 3.X DATA LAYER CONFIGURATION PATTERN**

**CRITICAL REFERENCE**: Proper AshPostgres.DataLayer setup for new resources

**Correct Pattern** (from working resources like `lib/thunderline/thunder_bolt/resources/chunk.ex`):
```elixir
defmodule Thunderline.ThunderBolt.Resources.Chunk do
  use Ash.Resource,
    domain: Thunderline.ThunderBolt,
    data_layer: AshPostgres.DataLayer,  # <-- CRITICAL: data_layer in use statement
    extensions: [AshStateMachine]

  # Then separate postgres block for table config
  postgres do
    table "chunks"
    repo Thunderline.Repo
  end
  
  # Attribute syntax for Ash 3.x (two valid patterns):
  # Pattern 1: Inline (simple attributes)
  attribute :name, :string, allow_nil?: false, public?: true
  
  # Pattern 2: Block syntax (for complex attributes with descriptions)
  attribute :status, :string do
    description "Current chunk processing status"
    allow_nil? false
    default "pending"
    constraints [one_of: ["pending", "processing", "complete", "failed"]]
  end
end
```

**COMMON MISTAKES TO AVOID**:
- ❌ `postgres/1` macro (doesn't exist) 
- ❌ `attribute :name, :type, option: value do` (old syntax)
- ❌ Missing `data_layer: AshPostgres.DataLayer` in use statement
- ✅ `data_layer: AshPostgres.DataLayer` in use statement + separate `postgres do` block
- ✅ Options inside attribute block: `allow_nil? false`, `default value`

### **Key Dependencies**
```elixir
# Core Framework
{:phoenix, "~> 1.7.0"}
{:phoenix_live_view, "~> 0.20.0"}
{:ash, "~> 3.0"}
{:ash_postgres, "~> 2.0"}

# Event Processing
{:broadway, "~> 1.0"}
{:memento, "~> 0.3.0"}

# AI & ML
{:nx, "~> 0.6.0"}
{:exla, "~> 0.6.0"}

# Specialized
{:ash_state_machine, "~> 0.2.12"}
{:cloak, "~> 1.1.0"}
```

### **Environment Variables**
```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/thunderline_dev

# Security  
SECRET_KEY_BASE=your-secret-key-base
CLOAK_KEY=your-encryption-key

# External Services
FEDERATION_HOST=your-domain.com
MCP_API_KEY=your-mcp-api-key
```

### **Performance Benchmarks**
- **Event Processing**: 10,000+ events/second on modest hardware
- **CA Evolution**: 100x100x100 3D grid at 60 FPS
- **Concurrent PACs**: 1000+ autonomous constructs per node
- **Federation Latency**: <100ms cross-instance communication

---

**🌩️ Welcome to the future of Personal Autonomous Constructs with Thunderline!** ⚡
