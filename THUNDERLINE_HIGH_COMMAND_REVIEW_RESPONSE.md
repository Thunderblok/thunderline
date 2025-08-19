# 🔩 Thunderline High Command Review – Action Response (Aug 2025)

This document captures the actionable response plan to the strategic review points you raised. It translates architectural critique into concrete, staged interventions while preserving delivery velocity.

---
## 1. Domain Structure & Ash Resources

### Findings
- `Thunderbolt` is an overloaded mega-domain (compute orchestration, lane consensus, Ising optimisation, model run lifecycle, *and* early model mgmt (ModelRun/ModelArtifact)).
- Cerebros/NAS lifecycle resources are logically distinct from execution orchestration.
- Policies currently permissive (`authorize_if always()`).

### Actions
| Phase | Action | Detail | Owner | ETA |
|-------|--------|--------|-------|-----|
| P0 | Freeze Thunderbolt scope | No new resource types added until split scaffolded | Arch Steward | Immediate |
| P1 | Introduce `ThunderCompute` domain | Extract cellular automata + orchestration primitives (ThunderCell engine, task nodes) | Arch Steward | +1 week |
| P1 | Introduce `ThunderModel` domain | Move `ModelRun` & `ModelArtifact`; add `ModelVersion` | ML Lead | +1 week |
| P2 | Introduce `ThunderOptimize` domain | Migrate Ising + optimisation resources | Arch Steward | +2 weeks |
| P2 | Introduce `ThunderLane` domain | Lane topology/consensus/coupling isolated | Arch Steward | +3 weeks |
| P3 | Tighten Policies | Replace `always()` with role/actor policy sets (Gate provided actor) | Security | Rolling |

### Target Outcome
`Thunderbolt` slimmed to only orchestration coordination shell; other concerns become peer domains with explicit Interaction Matrix edges (△ initially) enforced via events/actions.

---
## 2. ThunderCell & Bridging

### Findings
- Bridge pattern sound; metrics & heartbeat patterns present.
- Missing unified telemetry naming + incomplete ThunderBridge wiring + EventBus usage.

### Actions
1. Telemetry Namespace Standard: `[:thunderline, :compute, :cell, <event>]` (post-split) → shim current emissions.
2. Implement missing ThunderBridge module functions; add supervision spec verification test.
3. Replace any stray `PubSub.broadcast` with `EventBus.emit*` (migration helper already present).
4. Add CA metrics sampler `Compute.Cell.MetricsCollector` (interval configurable via runtime env).

---
## 3. NAS / Model Lifecycle (Thunderforge Initiative)

### Findings
- Model layer not yet implemented (`Thunderforge` / ThunderFormer missing).
- Adapter currently only internal stub (SimpleSearch) with no real delegation.

### Actions Completed (This Commit)
- Implemented hybrid Cerebros Adapter (`run_search/1`, `run_and_record/2`) with delegation cascade (Library → CLI → Stub) and real-time progress events via EventBus.
- Persistence pipeline: creates `ModelRun`, transitions state machine, writes `ModelArtifact` on completion.

### Next Steps
| Step | Action | Note |
|------|--------|------|
| 1 | Create `ThunderModel.Domain` & move runs/artifacts | Migration file rename tables if needed (keep data) |
| 2 | Add `ModelVersion`, `TrainingRun`, `PolicyConfig` resources | Governance & traceability |
| 3 | Implement `Thunderforge` base module | Inference + adapter binding |
| 4 | Adapter streaming telemetry → LiveView | Map progress events to UI table |
| 5 | CLI smoke test script | Ensures fallback path health |

---
## 4. Ash Best Practices Hardening

### Policy Roadmap
| Resource Class | Interim Policy | Future Policy |
|----------------|----------------|---------------|
| Model lifecycle | allow authenticated | actor must own or have :ml_admin role |
| Optimisation jobs | allow authenticated | gating on quota + org membership |
| Lane / consensus | allow authenticated | role:system or orchestrator token |
| Event log reads | allow authenticated | auditing roles only (export actions) |

### Additional
- Introduce `read_public` & `admin_only` action level policies.
- Add `:redact` calculation fields for sensitive metadata (Ash attribute calculations).

---
## 5. Runtime Stabilisation (Critical Path)

| Area | Gap | Action |
|------|-----|--------|
| EventBus | Already implemented publish variants | Add property tests for format validation |
| MnesiaProducer | Stability uncertain | Add supervised restart intensity metrics + soak test ExUnit case |
| ThunderMemory | Helper gaps | Implement missing API for memory fetch & event emission |
| Dashboard (AutomataLive) | Missing | Scaffold LiveView fed by progress events |

---
## 6. Telemetry & Observability
Actions:
1. Register unified Telemetry handlers writing to Logger + ETS ring buffer.
2. Add OpenTelemetry span wrappers for adapter delegation path.
3. Emit `:cerebros_search_progress` (already) → map to `Phoenix.PubSub` channel for UI.

---
## 7. Deployment Strategy (MVP)
Single release (Elixir release) containing: Phoenix + Broadway + Oban + internal stub + optional Cerebros library.
Sidecar option: `cerebros` CLI binary baked into image; adapter auto-detects.
Mnesia ephemeral (non-persistent); Postgres authoritative store.

---
## 8. Risk Register
| Risk | Impact | Mitigation |
|------|--------|------------|
| Overloaded Thunderbolt persists | Architectural drag | Enforce freeze + migration schedule |
| Telemetry namespace drift | Observability fragmentation | Central module test asserting prefix list |
| CLI fallback divergence | Inconsistent metrics | Unified contract & JSON schema validation |
| Policy hardening deferred | Security exposure | Sprint gate requires upgraded policies before external API |
| Mnesia instability | Lost realtime events | Dual path (EventBus fallback to PubSub) + soak tests |

---
## 9. Immediate Execution Queue (Next 5 PRs)
1. PR: Domain split scaffolding (create empty domains + move ModelRun/Artifact) – includes migration + doc update.
2. PR: Presence & Channel Membership resources (auth UX hardening) + policies.
3. PR: Thunderforge skeleton + BitFit adapter stub.
4. PR: Telemetry unification + progress LiveView.
5. PR: Policy tightening phase 1 (replace always() on model resources).

---
## 10. Summary
Hybrid adapter implemented now. Strategic decomposition & governance hardening scheduled. Runtime stabilization, presence, and AI activation follow immediately to convert architectural readiness into user-visible capability.

> We move from monolith-mega-domain to *purposeful domain mesh*, while lighting up genuine ML lifecycle and keeping runtime stable.

---
Owner: Architecture Stewardship Circle  
Status: ACTIVE  
Last Updated: Aug 19 2025
