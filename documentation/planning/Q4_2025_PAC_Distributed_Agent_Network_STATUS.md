# PAC Distributed Agent Network – Q4 2025 Execution Strategy Status & Gap Analysis

> Generated: (current snapshot)

## 1. Executive Snapshot

| Pillar | Goal (Strategy) | Current Maturity | Evidence | Immediate Gaps | Risk Level |
|--------|-----------------|------------------|----------|----------------|-----------|
| Memory / Vector Vault | Unified embeddings, similarity, lineage | ADVANCED CORE | `vault_embedding_vector.ex` (relationships, similarity search, validations) | Latency metrics + eviction strategy not instrumented | Medium |
| Orchestration & ThunderCell Automata | 3D CA visualization + process topology + cluster mgmt | PARTIAL / FUNCTIONAL SCAFFOLD | `thundercell/cluster.ex`, `ca_cell.ex`, UI `automata_panel.ex` | Lacks QA harness & emergent behavior scoring | High |
| Governance & Policy (ThunderCrown) | Policy-based execution, audit, guardrails | PARTIAL | `agent_runner.ex`, Credo guardrails, handbook guardrail table | Missing formal policy authoring DSL & verdict latency telemetry | Medium |
| Learning / Model Pipeline (Cerebros / ML) | Search + training lifecycle, artifact lineage | EMERGING (NEW CORE) | `model_run.ex`, `training_run.ex`, `run_worker.ex`, `model_artifact.ex`, adapter | Promotion workflows, drift-driven retraining triggers | Medium |
| Event Chain / On-chain Integrity | Cryptographic event lineage, version taxonomy | PARTIAL | Event validator, handbook guardrails, BRG referencing taxonomy | No hash chain persistence & integrity audit job | High |
| Federation & Gate (Thundergate / Thunderlink) | Cross-realm messaging & identity | PARTIAL | `federated_realm.ex`, `federated_message.ex`, `realm_identity.ex`, `federation_socket.ex` | Secure replay protection + QoS / rate adaptation | Medium |
| UI & Telemetry (Observability) | Real-time dashboards (queues, drift, automata) | PARTIAL | `drift_metrics_producer.ex`, BRG checker, Oban check, CA panel | Missing clustering telemetry & policy latency panels | Medium |
| BRG & Balance Readiness Gate | Composite readiness scoring pre-deploy | SCAFFOLD | `mix thunderline.brg.check` (placeholders) | Replace placeholders w/ live collectors + warning budget backend | Medium |

Legend: ADVANCED CORE (stable + feature-complete), PARTIAL (core path working, features missing), SCAFFOLD (structure only), EMERGING (recently added, converging), MISSING (no code yet).

### Immediate Sprint Target (September 2025)

**Outcome:** Demonstrate a complete PAC training cycle (data prep → Cerebros NAS trials → artifact promotion → capability vector update) ready for Thundergrid deployment.

**Prerequisites & Owners**

| Thread | Focus | Primary Owner | Support | Notes |
| --- | --- | --- | --- | --- |
| Data Readiness | Finalize `memory_nodes` IVFFlat index, retention/TTL doc, dataset manifest | Block (you) | AI Dev | Enables MOTPE sampling and replay safety |
| Cerebros Bridge | Land facade, telemetry, first invocation path | AI Dev | Bolt | Lives behind feature flag until end-to-end validated |
| Search & Trials | Rose-Tree shortlist + MOTPE config for target PAC | Bolt | Flow | Derives candidate slate for Cerebros |
| Promotion & VCV | Artifact scoring + VCV refresh + Thundergrid publish | Crown | Grid | Depends on training metrics availability |
| Observability | Training run telemetry + dashboard panels + BRG hook | Observability | Flow | Share instrumentation plan w/ BRG owners |
| Runbook & QA | Integration test + operator runbook + release checklist | Gate | All | Gated by telemetry + policy guardrails |

📌 Kanban board with granular tasks: `documentation/planning/PAC_training_cycle_kanban.md`.

## 2. Detailed Pillar Status

### 2.1 Memory / Vector Vault
Implemented: Ash resource with similarity search, relationships to memory/knowledge nodes, validations, indexing. Missing latency distribution telemetry, retention/TTL policy, vector cardinality audit, backpressure thresholds.

Next Hardening Actions:
1. Add Telemetry span: `[:vault, :embedding_vector, :search]` with timings & result_count.
2. Add periodic job: orphan & low-utility vector pruning (configurable heuristic: age + low access frequency + low semantic centrality).
3. Metric: p95 vector search latency & eviction rate into BRG.

### 2.2 Orchestration & ThunderCell Automata
Existing cluster & cell modules; UI visualization available. Missing: deterministic QA harness, emergent metric extraction (stability, entropy, attractor detection), scenario replay, versioned CA parameter sets.

### 2.3 Governance & Policy
Guardrails via Credo custom checks and handbook; runtime runner scaffold. Missing: unified policy DSL versioning; signed verdict chain; policy execution latency instrumentation; simulation/audit replay.

### 2.4 Learning / Model Pipeline
ModelRun (state machine), TrainingRun worker, artifact creation, adapter bridging (hybrid stub). Missing: best artifact promotion workflow with multi-metric objective, retention/cleanup, dataset lineage linking to vector vault, drift-triggered retrain.

### 2.5 Event Chain Integrity
Validator exists; no persisted hash chain or periodic tamper audit. Need canonical event schema registry + `event_chain_blocks` table w/ previous_hash + digest.

### 2.6 Federation & Gate
Core identity + message resources present. Need: anti-replay nonce window, per-realm rate shaping, gossip health and liveness scoring, fallback routing.

### 2.7 UI & Telemetry
CA panel + drift metrics + BRG text output. Missing: clustering telemetry (transformer embedding cluster churn), policy latency panel, model training run timeline UI, vector search heatmap.

### 2.8 BRG
Current placeholders produce synthetic metrics. Need real collectors for: queue depth histograms, circuit breaker real state, vector latency, policy latency, event chain integrity score, retrain backlog pressure.

## 3. Phase Mapping & Gap Analysis

| Phase Deliverable (Strategy Inference) | Implemented | Gap Category | Priority | Notes |
|---------------------------------------|-------------|--------------|----------|-------|
| P1: Core vector similarity & memory linking | Yes | Hardening | High | Add latency + eviction metrics |
| P1: Basic CA cluster + visualization | Partial | Feature completion | High | QA harness absent |
| P1: Model run state machine + artifact lineage | Yes (initial) | Maturity | Medium | Promotion & drift triggers pending |
| P1: Federation identity + messaging scaffold | Yes (partial) | Security | High | Replay & QoS missing |
| P1: BRG skeleton | Yes | Instrumentation | High | Replace placeholder counts |
| P2: Event chain cryptographic integrity | No (validator only) | Net-new | Critical | Hash chain + audit job |
| P2: Policy DSL & verdict signatures | No | Net-new | High | Governance risk |
| P2: Clustering telemetry (transformer) | No | Net-new | High | Observability gap |
| P2: CA QA LifeGPT harness | No | Net-new | High | Quality gating missing |
| P2: Drift-triggered retraining | No | Automation | Medium | Depends on drift metrics completeness |
| P3: Multi-realm adaptive routing | No | Scaling | Medium | Depends on federation QoS layer |
| P3: Emergent behavior scoring (entropy/attractors) | No | Research/Analytics | Medium | Needs QA harness foundation |
| P3: Policy simulation replay & audit UI | No | Compliance | Medium | After DSL stabilization |

## 4. Prioritized Backlog (Top 15)

Priority basis: (Impact * Risk Mitigation * Strategic Alignment) – Effort heuristic.

1. Event Chain Hash Ledger (Block table + writer + audit job)  
2. CA QA Harness (spec below)  
3. Transformer Clustering Telemetry Collector + Panel  
4. Federation Anti-Replay & Rate Shaping (nonce cache + sliding window)  
5. Replace BRG placeholder metrics with live collectors (queues, circuits, vector latency)  
6. Policy Verdict Latency Telemetry + signed verdict_id hashing chain  
7. Vector Vault Eviction & Latency Metrics (p50/p95/p99)  
8. Drift → Retrain Trigger (threshold-based enqueue)  
9. Artifact Promotion Workflow (multi-metric + semantic diff)  
10. Model Artifact Retention Policy (age & promotion state)  
11. Federation Liveness & Gossip Health Score  
12. CA Parameter Pack Versioning + Replay Seeds  
13. Event Schema Registry & Version Gate in CI  
14. Policy DSL (AST + compiler) minimal viable version  
15. Emergent Behavior Analytics (entropy / attractor detection)  

## 5. PRD: CA QA LifeGPT Harness (Concise)

### Problem
No deterministic quality gate for automata emergent behaviors; regressions or chaotic parameter shifts unbounded.

### Objectives / Success Criteria
| Metric | Target |
|--------|--------|
| Deterministic replay fidelity | ≥ 99% identical observable state over 100 steps |
| Run variance band (entropy) | Stable ±5% across baseline suite |
| CI runtime | < 90s for core scenario pack |

### Scope (MVP)
1. Scenario spec format (YAML/JSON) – grid size, seed, parameter vector, duration, probe points.
2. Harness runner (Mix task + internal module) executes scenarios in isolation (no global side-effects).
3. Metrics extracted: state entropy, alive cell ratio, cluster count, convergence time, oscillation period.
4. Baseline snapshot store (ETS or file) committed for comparison.
5. Diff report (JSON + colored text) fail gate on threshold breach.

### Non-Goals (MVP)
GPU acceleration, multi-node CA, visual diff rendering.

### Data Flow
Scenario -> Runner -> Step Loop -> Metric Extractors -> Aggregator -> Assertion -> Report.

### Interfaces
`mix thunderline.ca.qa --suite core`  
`Thunderline.Thundercell.QA.run_suite(:core)` -> `%{passed: true, metrics: ...}`

### Telemetry
`[:ca, :qa, :scenario, :completed]` measurements: duration_ms, entropy_mean, convergence_steps.

### Risks
Non-determinism (solution: seed control, isolate RNG); performance overhead (opt: streaming collectors).

### Acceptance Tests
1. Deterministic replay under same seed identical.  
2. Entropy drift > threshold triggers failure exit code.  
3. Suite runtime under budget.  
4. Telemetry events observed in test harness.  

## 6. PRD: Transformer Clustering Telemetry

### Problem
Lack of visibility into semantic cluster dynamics (collapse, fragmentation) for transformer embeddings – impairs drift detection & retrieval tuning.

### Objectives
| Metric | Purpose |
|--------|---------|
| Cluster Count (k_eff) | Detect collapse or explosion |
| Silhouette Score p50/p95 | Cohesion vs separation |
| Largest Cluster % | Dominance / imbalance |
| Churn Rate (Δ membership / min) | Stability measure |
| Novelty Rate (% new vectors forming singleton cluster) | Outlier surfacing |

### Scope (MVP)
1. Periodic sampler: fetch N recent vectors (time-decay sample).  
2. Mini-batch clustering (HDBSCAN or k-means adaptive) in-process w/ fallback to approximate method.  
3. Metrics emitted via Telemetry: `[:embed, :cluster, :update]`  
4. Persistence: Rolling window metrics table (`embedding_cluster_metrics`).  
5. LiveView panel (sparkline + alert badges).  

### Out of Scope
Distributed clustering, GPU acceleration, canonical labeling across shards.

### Algorithm Notes
Start with k-means (k heuristic = sqrt(n/2)). Flag TODO for swapping w/ HDBSCAN when N > threshold.

### Alerting Threshold Examples
* Largest cluster > 55% -> warning.  
* Silhouette p50 < 0.15 -> warning, < 0.05 critical.  
* Churn > 25% sustained 3 intervals -> warning.  

### Acceptance Tests
1. Synthetic dataset with 3 clusters yields k_eff within ±1.  
2. Collapsed dataset triggers largest cluster alert.  
3. High noise dataset lowers silhouette -> warning path.  

## 7. Metrics & Governance Instrumentation Plan

| Metric | Source Module | Telemetry Event | BRG Integration | Notes |
|--------|---------------|-----------------|-----------------|-------|
| Vector Search Latency p50/p95/p99 | Vault search wrapper | `[:vault,:vector,:search]` | Metrics section | Wrap repo call + measure duration |
| Vector Eviction Count | Pruner job | `[:vault,:vector,:evict]` | Metrics | Include reason tag |
| CA Entropy Mean/Std | QA harness & live sampler | `[:ca,:entropy,:sample]` | New automata panel + BRG extension | Requires deterministic seed control |
| CA Convergence Steps | QA harness | `[:ca,:qa,:scenario,:completed]` | BRG (quality) | Bound performance drift |
| Policy Verdict Latency | Policy executor wrapper | `[:policy,:verdict,:complete]` | Governance subsection | Add hash of verdict payload |
| Policy Hash Chain Integrity | Periodic auditor | `[:policy,:chain,:audit]` | BRG (governance) | % verified vs expected |
| Event Hash Continuity Failures | Event ledger auditor | `[:event_chain,:audit,:failure]` | BRG (critical gate) | Halt deploy on >0 |
| Clustering Churn Rate | Cluster updater | `[:embed,:cluster,:update]` | Metrics panel | Derived delta calculation |
| Silhouette Scores | Cluster updater | same event (tags) | Metrics | Compute distribution |
| Training Run Duration | RunWorker | `[:ml,:run,:completed]` | ML health | Already partly emitted |
| Drift Trigger Count | Drift metrics producer | `[:drift,:trigger]` | BRG (model freshness) | Map to retrain backlog |

Implementation Order: 1) Vector + Policy latency, 2) Clustering metrics, 3) Event chain + policy hash chain, 4) CA QA metrics, 5) Drift triggers.

## 8. Data Model Additions (Proposed)

```text
event_chain_blocks(id uuid, seq bigint, prev_hash text, payload_hash text, aggregate_hash text, inserted_at)
embedding_cluster_metrics(id uuid, window_start, window_end, sample_size, cluster_count, silhouette_p50, silhouette_p95, largest_cluster_pct, churn_rate, novelty_rate, inserted_at)
policy_verdict_chain(id uuid, prev_hash text, verdict_hash text, policy_module text, latency_ms integer, inserted_at)
```

## 9. CI / Guardrail Enhancements

| Guardrail | Enhancement | Failure Condition |
|-----------|-------------|-------------------|
| BRG Gate | Use live collectors | overall_status != healthy |
| Event Schema Registry | Add spec file + validator | undocumented event emits |
| CA QA Harness | Run in test workflow | entropy drift > threshold |
| Clustering Telemetry | Smoke sample run | no metrics row inserted |
| Policy Chain Audit | Auditor verifies chain continuity | gap or hash mismatch |

## 10. Incremental Delivery Plan (Weeks)

Week 1: Event chain ledger, vector latency instrumentation, BRG real metrics.  
Week 2: CA QA harness MVP + policy latency telemetry.  
Week 3: Clustering telemetry collection + panel, eviction job.  
Week 4: Policy verdict hash chain + drift → retrain trigger.  
Week 5: Federation anti-replay + rate shaping + artifact promotion workflow.  
Week 6: Emergent behavior analytics initial (entropy trend + attractor detection prototype).  

## 11. Risk Register (Top) & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|-----------|
| Undetected event tampering | Governance failure | Medium | Hash ledger + auditor (Week 1) |
| Automata regressions | Hidden instability | High | QA harness deterministic scenarios |
| Embedding cluster collapse | Retrieval degradation | Medium | Clustering telemetry + alerts |
| Policy latency spikes | SLA breach | Medium | Telemetry + BRG gating |
| Drift unacted | Model staleness | Medium | Trigger pipeline + backlog metrics |

## 12. Immediate Actionable Tasks (Ticket Seeds)

1. feat(event-chain): Add `event_chain_blocks` table + writer API.  
2. chore(telemetry): Instrument vector search path with timings + tags.  
3. feat(brg): Replace placeholder resource counts with Ash Domain queries.  
4. feat(ca-qa): Scaffold scenario spec + runner + 2 baseline scenarios.  
5. feat(policy): Wrap verdict emitter with telemetry + hash chain append.  
6. feat(cluster-metrics): Add sampler + k-means step + metrics table.  
7. feat(vector): Implement eviction job (age+LFU heuristic).  
8. feat(drift): Emit drift trigger event -> enqueue training run.  
9. feat(federation): Nonce cache + sliding window middleware.  
10. feat(ml): Artifact promotion action w/ multi-metric decision.  

## 13. Acceptance Gate Revisions (BRG Additions)

Deploy blocks if: (a) event chain audit failures > 0, (b) policy chain continuity failures > 0, (c) vector p95 latency > configured threshold, (d) clustering churn sustained high 3 intervals, (e) CA QA suite fail.

## 14. Open Questions
* Which hash algorithm final for chain (SHA-256 vs BLAKE2)?
* Acceptable entropy variance band for CA across releases? (Need baseline capture)
* k-means vs HDBSCAN threshold pivot point (sample size-based)?
* Multi-metric artifact promotion (weighted composite vs Pareto frontier)?

---
Prepared for engineering alignment; file will be iteratively updated as implementations land.
