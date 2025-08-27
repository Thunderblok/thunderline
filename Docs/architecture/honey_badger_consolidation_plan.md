# Honey Badger Consolidation & Domain Sharpening Plan (HC-13 Acceleration)

> High Command Directive codified: eliminate duplication, restore domain sovereignty, enforce event sanctity, and prepare the lattice for AI-native governance. This is the authoritative execution playbook.

## Guiding Maxims (Non-Negotiable)
- Everything is an Ash Resource. No orphan structs / ad-hoc persistence.
- Events are ONLY `%Thunderline.Event{}` with taxonomy-compliant names.
- Domains are sovereign: no cross-domain calls without a defined bridge or DIP (Domain Interaction Proposal).
- Deprecate with dignity: 1 release grace (aliases + loud logs + telemetry), then purge.
- Naming is intent. Drift is entropy. Entropy is the enemy.

## Phase Overview
| Phase | Theme | Core Outcomes | Target Window |
|-------|-------|---------------|---------------|
| A | Extraction & Freeze | Voice unified under ThunderLink, Thundercom frozen, lanes & table drift removed | Immediate (Week 0–1) |
| B | Normalization & Unification | Policy + system events centralized (Crown+Flow), orchestration clarified (Bolt), community model convergence | Week 2–3 |
| C | Hygiene & Future Hooks | Naming cleanup, notifications/mailers relocation, AI governance prep, residual artifact purge | Week 4 |

## Phase A – NOW (Critical Path)
### Objectives
1. Consolidate all active Voice/WebRTC resources under `ThunderLink`.
2. Freeze `Thundercom` (no new writes, only passthrough reads + deprecation wrappers).
3. Eliminate legacy `tlane_*` (Lane v1) in favor of canonical Lane Engine (Bolt).
4. Resolve table naming drift (e.g., `thunderblock_channels`).
5. Introduce foundation for event emission enforcement for `voice.signal.*` / `voice.room.*`.

### Task Matrix
| ID | Task | Type | Owner | Dependencies | Exit Criteria |
|----|------|------|-------|--------------|---------------|
| A1 | Inventory Voice resources (`VoiceRoom`, `VoiceParticipant`, `VoiceDevice`) & migrations | Analysis | | Repo scan | Table + resource map committed |
| A2 | Move resource modules to `Thunderline.Thunderlink.Voice.*` namespace | Code | | A1 | Files relocated + tests green |
| A3 | Generate migration remapping schemas if table prefixes change | Data | | A2 | Migration applied locally / doc’d |
| A4 | Implement deprecation façade in `Thundercom.Voice.*` re-exporting new modules with `@deprecated` + log | Code | | A2 | Calls logged + telemetry counter |
| A5 | Add feature flag `:enable_voice_media` (runtime.exs + config schema) | Infra | | | Flag toggles supervision branch |
| A6 | Stub Membrane-ready `RoomPipeline` supervision contract (behaviour + placeholder) | Arch | | A5 | Behaviour spec + test harness |
| A7 | Emit taxonomy-compliant events from VoiceChannel & RoomPipeline | Event | | A5 | Events visible in EventBus + RT fanout |
| A8 | Lane legacy sweep: locate `tlane_` tables/modules, confirm equivalence, schedule deletion | Cleanup | | | Deletion PR open (or retained list) |
| A9 | Table rename plan: map drift (`thunderblock_channels` → canonical) | Data | | A1 | Migration script prepared |
| A10 | Bridge collision audit (ThunderBridge vs others) – list & alias plan | Arch | | | Alias table + rename schedule |
| A11 | Implement event constructor validation (voice categories) | Quality | | A7 | Invalid names raise structured error |
| A12 | Add KPIs: active rooms gauge, participants histogram, signaling latency telemetry | Observability | | A7 | Metrics visible in :telemetry dashboards |

### Voice Resource Relocation Plan
| Resource | Current Path | Target Path | Table | Needs Rename? | Notes |
|----------|-------------|------------|-------|---------------|-------|
| VoiceRoom | `Thunderline.Thundercom.Voice.VoiceRoom` | `Thunderline.Thunderlink.Voice.Room` | voice_rooms | Maybe (snake-case unify) | Consider `voice_rooms` canonical |
| VoiceParticipant | `...VoiceParticipant` | `...Voice.Participant` | voice_participants | No | Add indices on (room_id, joined_at) |
| VoiceDevice | `...VoiceDevice` | `...Voice.Device` | voice_devices | Maybe (`voice_devices`) | Prepare codec preference fields |

### Table Rename / Drift Correction (Draft)
| Current | Target | Strategy | Blocking Concerns |
|---------|--------|----------|------------------|
| thunderblock_channels | channels (domain-specific) or link_channels | Online rename w/ transactional swap + view shim | Existing foreign keys |
| voice_room(s)? (confirm) | voice_rooms | Ensure plural consistency | Down migrations correctness |

### Deprecation Strategy (`Thundercom`)
- Mark modules with `@moduledoc deprecated: "Moved to Thunderlink.Voice.*—will be removed next release"`.
- Wrap public functions calling new implementations; add `Logger.warning/1` w/ structured metadata: `%{module: __MODULE__, replacement: NewModule}`.
- Telemetry: `[:thunderline, :deprecation, :call]` event emitted.
- Add Mix task `mix thunderline.deprecations.report` aggregating call counts.

### Event Enforcement (Initial)
- Add guard: `Thunderline.Event.new/1` rejects non-whitelisted voice taxonomy patterns unless `:allow_experimental_voice` flag.
- Linter hook extension (Section 14 task) scans for raw string emission outside `Thunderline.Event`.

### Success Criteria (Phase A)
- All Voice code under `Thunderlink`. No compile warnings referencing old namespace.
- Deprecation calls visible in metrics; <5% residual by sprint end.
- Lane legacy inventory complete; deletion patch WIP.
- Table rename migrations authored & dry-run validated.
- Voice events appear in Flow normalization path.

## Phase B – Normalization & Domain Power
### Objectives
1. Centralize all policy evaluation under `ThunderCrown.Policy` (single Ash Policy Engine surface).
2. Normalize system events: Flow = system event emission & routing hub. Gate = pure authn/z.
3. Unify orchestration primitives (DAG, Lane, Cell) firmly in Bolt; remove shadow orchestrators.
4. Resolve community / channel duplication (single resource with type flags / facets).

### Task Highlights
| ID | Task | Outcome |
|----|------|---------|
| B1 | Policy resource consolidation (merge scattered policy modules) | One policy DSL entrypoint |
| B2 | Introduce `SystemEvent` Ash resource for internal lifecycle | Traceable / auditable system actions |
| B3 | Refactor Gate modules leaking orchestration concerns | Gate limited to session, claims, rate limits |
| B4 | Bolt Orchestration boundary doc + enforcement tests | Prevents reintroduction of drift |
| B5 | Channel/Community unification: add enum `:kind` + facets | Removes parallel resource graphs |
| B6 | Flow event contracts versioned (v1 tags) | Forward compatibility |

### Success Criteria (Phase B)
- Only one policy evaluation entrypoint used by all domains.
- All system events typed via `SystemEvent` resource.
- No direct orchestration code in Gate or Link.
- Community/channel duplication eliminated.

## Phase C – Hygiene & Future Expansion
### Objectives
1. Naming hygiene: Bridges, Chunks, residual legacy nouns aligned.
2. Notifications / Mailers relocated (Flow or Crown depending on trigger vs governance context).
3. AI governance hooks surfaces added (intent moderation, tool gating).
4. Purge deprecated wrappers introduced in Phase A.

### Task Highlights
| ID | Task | Outcome |
|----|------|---------|
| C1 | Bridge rename execution + alias removal | Clean namespace |
| C2 | Add `Notification` Ash resource + emission pipeline | Unified outbound
| C3 | `AIGovernanceHook` resource + callback contracts | Extensible AI policy layer |
| C4 | Delete Phase A deprecated modules | Zero deprecation warnings |
| C5 | Final telemetry backfill + regression test snapshots | Stability baseline |

### Success Criteria (Phase C)
- No deprecated modules remain.
- Naming consistency report passes with zero violations.
- AI governance extension points documented + tested.
- Outbound notifications unified.

## Cross-Cutting Workstreams
### Telemetry / KPIs
| Metric | Domain | Instrumentation Point |
|--------|--------|-----------------------|
| active_voice_rooms | Link | Voice supervisor counts |
| participants_per_room | Link | Join/leave events aggregation |
| signaling_latency_ms | Link/Flow | Correlate offer→answer timestamps |
| ice_success_rate | Link | Per room ICE negotiation outcome |
| lane_execution_latency | Bolt | DAG/Lane engine events |
| policy_eval_duration | Crown | Policy runner spans |
| deprecated_call_count | All | Deprecation wrapper telemetry |

### Quality Gates
- CI: Add job enforcing no direct emission of `voice.*` without constructor.
- Credo rule: prohibit cross-domain alias unless in approved `bridges/` folder.
- Dialyzer spec enforcement for new behaviours (`RoomPipelineBehaviour`).

### Risk & Mitigation
| Risk | Phase | Mitigation |
|------|-------|-----------|
| Table rename breaks migrations | A | Use transactional rename + views + backfill script |
| Event taxonomy churn | A/B | Version voice events early; keep adapter layer |
| Policy centralization regression | B | Add contract tests + golden policy fixtures |
| Orchestration refactor stalls other work | B | Parallelize w/ feature flags |
| Deprecation wrappers linger | C | Telemetry thresholds gating release |

### DIP (Domain Interaction Proposal) Outline
All new cross-domain edges require:
1. Purpose & latency tolerance.
2. Event vs call justification.
3. Ownership + rollback plan.
4. Telemetry spec.
5. Security/policy hooks.

### Feature Flags
| Flag | Purpose | Default |
|------|---------|---------|
| :enable_voice_media | Activate Membrane supervision | false |
| :allow_experimental_voice | Allow non-whitelisted voice events | false |
| :unified_policy_engine | Route all policy to Crown | off until B1 |

## Implementation Order Cheat Sheet
1. (A) Relocate + deprecate Voice.
2. (A) Events + telemetry baseline.
3. (A) Lane / table drift cleanup.
4. (B) Policy consolidation.
5. (B) Orchestration hard boundary.
6. (B) Community unification.
7. (C) Naming + notification + AI hooks.
8. (C) Purge deprecated + finalize metrics.

## Dev Workflow Enhancements
- Mix tasks to add:
  - `mix thunderline.voice.audit`
  - `mix thunderline.deprecations.report`
  - `mix thunderline.events.verify --category voice`
- Script: schema diff reporter before & after Phase A.

## Acceptance Definition (Full Program Completion)
- Zero deprecated modules.
- All events validated against taxonomy contract.
- Single policy engine surface; single orchestration surface.
- Voice pipeline Membrane-ready behind flag.
- Naming audit passes (Bridges, Chunks, Channels, Lanes).
- Observability dashboards populated with KPIs.
- DIP process enforced (lint + PR template gating).

## Immediate Next Actions (Pull Queue)
1. Execute Task A1–A3 PR (resource relocation + migrations draft).
2. Implement feature flag & supervision gating (A5/A6).
3. Add event emission + enforcement (A7/A11).
4. Instrument KPIs (A12) + baseline telemetry panel.
5. Open deprecation façade PR (A4) with logger + telemetry.

---
Prepared for High Command. Honey Badger mode: ENGAGED.
