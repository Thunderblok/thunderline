# Unified Persistent Model (UPM) Runbook (Draft)

> Status: Draft – HC-22 owner deliverable
> Scope: Cross-domain shared model trained online from ThunderFlow pipelines and consumed by ThunderBlock agents.

## 1. Purpose & Goals
- Maintain a single, sovereign model that reflects real-time state across Thunderline domains.
- Eliminate drift between per-agent heuristics by projecting consistent embeddings back into ThunderBlock agents.
- Provide auditable snapshots, rollback hooks, and telemetry to satisfy governance and safety requirements.

## 2. High-Level Architecture
```
ThunderFlow feature windows
        ↓
Thunderline.Thunderbolt.UPM.Trainer (online updates)
        ↓
Thunderline.Thunderbolt.UPM.Snapshot (stored in ThunderBlock vault)
        ↓
Thunderline.Thunderbolt.UPM.Adapter (push to ThunderBlock agents)
        ↓
Agent behavior / action surfaces (Link, Grid, Bolt orchestration lanes)
```

### Components
- **Trainer** (`upm_trainer.ex`): consumes feature windows, performs incremental SGD, logs update telemetry.
- **Replay Buffer** (`upm_replay_buffer.ex`): de-duplicates out-of-order events and enforces replay-safe training windows.
- **Drift Monitor** (`upm_drift_window.ex`): compares shadow predictions against ground truth, raises quarantine flags on divergence.
- **Snapshot Manager** (`upm_snapshot.ex`): persists versioned snapshots to ThunderBlock vault with metadata (`mode`, `version`, `tenant`, `checksum`).
- **Adapter** (`upm_adapter.ex`): syncs latest approved snapshot to ThunderBlock agents and records adoption metrics.
- **Policy Hooks** (`upm_policy.ex`): integrates with ThunderCrown verdicts to authorize rollout per tenant/actor.

## 3. Data Flow & Event Contracts
1. ThunderFlow emits `feature_window` resources and `system.feature_window.created` events.
2. Trainer ingests windows, emits telemetry `[:upm, :trainer, :update]` with loss and window id.
3. On snapshot boundary, `ai.upm.snapshot.created` event published, snapshot persisted via ThunderBlock vault action `store_snapshot/1`.
4. Activation pipeline checks drift + policy approval; upon success publishes `ai.upm.snapshot.activated`.
5. ThunderBlock adapters pull or receive push notifications (`[:upm, :adapter, :sync]`) and refresh agent embedding caches.
6. Shadow comparisons emit `ai.upm.shadow_delta` and feed drift window metrics.

## 4. Rollout Phases
| Phase | Description | Entry Criteria | Exit Criteria |
|-------|-------------|----------------|----------------|
| Shadow | Train continuously, do not influence production agents | Feature window ingestion stable, trainer telemetry healthy | Drift score p95 < 0.2 for 14 days |
| Canary | Activate for selected tenants/agents via feature flag `:unified_model` | Shadow success + governance approval | Canary tenants meet SLOs for 30 days; rollback count == 0 |
| Global | Promote as default for all agents | Canary success, governance sign-off | UPM adoption > 95%, legacy models retired |

Rollback procedure: deactivate `:unified_model`, publish `ai.upm.rollback`, revert adapters to last known-good snapshot, clear drift quarantine.

## 5. Telemetry & SLOs
| Metric | Source | Target |
|--------|--------|--------|
| `[:upm,:snapshot,:freshness]` (ms) | Snapshot manager | Shadow < 30s, Canary < 10s |
| `[:upm,:drift,:score]` (p95) | Drift monitor | < 0.2 |
| `[:upm,:adapter,:sync]` (success rate) | Adapter | ≥ 99.5% |
| `ai.upm.shadow_delta` volume | EventBus | Trending ↓ over time |
| Rollback count | Policy/Telemetry | 0 per rolling 30 days |

Dashboards: Grafana `UPM-001` (freshness, drift), LiveDashboard UPM pane (snapshot list, latest metrics), alerting on drift > threshold or freshness > SLO.

## 6. Operational Checklist
- [ ] Feature flag `:unified_model` disabled by default; enable per tenant using config overrides.
- [ ] Trainer cluster scaled via Bolt orchestrator; verify Oban job queues sized for replay buffer sweeps.
- [ ] Persistence: ThunderBlock retention policy `resource: :upm_snapshot` retains 7 days, archives beyond 30 days (TODO).
- [ ] Security: Snapshot payloads hashed (SHA-256) and signed; verify via ThunderGate audit hooks.
- [ ] Testing: `mix test upm` suite covers trainer math, adapter sync, drift quarantine.
- [ ] Backfill: `mix thunderline.upm.shadow --from TIMESTAMP` to warm trainer with historical data (planned task).

## 7. Integration Points
- **ThunderBolt**: Hosts trainer/adapters, supervises workers, exposes Ash actions for manual intervention.
- **ThunderBlock**: Stores snapshots, enforces retention, provides audit log of activation history.
- **ThunderFlow**: Supplies feature windows and drift feedback events.
- **ThunderCrown**: Applies policy decisions before activation, logs governance verdicts.
- **ThunderGate**: Ensures capability tokens for management endpoints.

## 8. Open Tasks (tracked in HC-22)
- [ ] Finalize Ash resource definitions for UPM entities and generate migrations.
- [ ] Implement drift monitor quarantine action and LiveDashboard widget.
- [ ] Seed observability dashboard (Grafana + LiveView) with freshness/drift/adoption metrics.
- [ ] Add CI smoke test `mix thunderline.upm.validate` to verify configuration before enabling flag.
- [ ] Document rollback drill and schedule recurring rehearsal.

---
For questions, ping Bolt steward (`@bolt-steward`) or Crown steward (`@crown-steward`). All updates must keep OKO Handbook and Playbook in sync.
