# Thunderline Market & EDGAR → MoE → NAS Architecture (Draft v0.1)

This document refines the pipeline you sketched (market/EDGAR → thunderline stack → MoE → Cerebros NAS) into concrete components, Ash resource plans, supervision, routing logic, and implementation phases. It is intentionally opinionated and optimized for: low-latency microstructure ingestion, adaptive compute allocation (hybrid Expert-Choice + Dynamic Top‑P routing), traceable lineage (ThunderDAG), and iterative model evolution via NAS.

---
## 1. High-Level Flow (Data Plane)

```
Adapters → Thunderblock (tenant ingress) → Thunderchief (assign/cadence) → Thunderflow (Broadway pipelines)
  → Feature Windows → Router (Thunderchief.Router) → Thunderbolt (Experts cluster)
  → Decisions (actions + scores) → Thundercell/Thunderbit (memory/trace) → Thunderlink (publish)
  → (Feedback) labels & outcomes → Feature Store + Model Registry → Thundergate (export) → PythonBridge → Cerebros NAS
```

Control plane (policies, configs, rollout) flows alongside via Ash resources + config registry.

---
## 2. Core Component Responsibilities

| Component | Responsibility | Key Tech | Notes |
|-----------|----------------|---------|-------|
| Thunderblock | Multi-tenant ingress, schema validation, raw persistence | Phoenix + Ash | Normalizes events; stamps tenant & auth claims |
| Thunderchief | Global scheduler/cadence, pipeline assignment, gating policy distribution | GenServer/Registry | Publishes routing config snapshots |
| Thunderflow | Deterministic windowing + feature extraction (Broadway pipelines) | Broadway + ETS + Ash | Separate pipelines: `:market_ingest`, `:edgar_ingest` |
| Thunderbolt | Expert processes (models) + lifecycle (load, hot swap, retire) | GenServer/Nx/Ports | Each expert isolated; latency budget enforced |
| Router (Hybrid) | Hybrid Expert-Choice + Dynamic Top‑P selection | Nx / pure Elixir | Exposes metrics (load balance, active experts/token) |
| Thundercell | Execution context & scratchpad | GenServer + ETS | Short-lived state & ephemeral caches |
| Thunderbit | Automata embedding & behavior vectorization | Nx/Erlang NIF | Compresses decision context |
| Thundervault | Data store (raw, features, lineage) | Postgres (AshPostgres) | Immutable raw tables + versioned feature windows |
| ThunderDAG | Lineage graph edges | Postgres / ETS / Graph layer | uuid→uuid edges with type + timestamps |
| Thundergate | Export orchestrator (training slices) | Ash actions + Oban jobs | Deals with versioned feature schemas |
| Thunderlink | Pub/Sub & external event publication | Phoenix.PubSub / Channels | Topics for dashboards, audits, downstream connectors |
| Thundereye | Telemetry dashboards (lag, drift, PnL) | LiveView + Telemetry | Real-time gating & backpressure visibility |
| Cerebros NAS | Arch search feedback loop | External (Python) | Returns candidate architectures + metrics |

---
## 3. Data Contracts (Canonical Schemas)

### MarketTick
```
%MarketTick{
  ts :: integer(), # monotonic microseconds
  venue :: String.t(),
  symbol :: String.t(),
  bid_px :: Decimal.t(), bid_qty :: integer(),
  ask_px :: Decimal.t(), ask_qty :: integer(),
  trade_px :: Decimal.t() | nil, trade_qty :: integer() | nil,
  condition :: String.t() | nil,
  seq :: non_neg_integer(),
  flags :: map() # microstructure annotations
}
```

### OrderBookSnapshot
Top N levels (configurable, default 10):
```
levels: [%{bid_px: d, bid_qty: i, ask_px: d, ask_qty: i}, ...]
imbalance, spread, realized_vol, microburst_flags
```

### EDGARDoc
```
%EDGARDoc{ cik, form, filing_time, period_end,
  sections: %{ "MDA" => text, "RISK" => text, ... },
  xbrl: [%{fact: atom(), value: decimal(), context: map()}],
  hash: binary()
}
```

### FeatureWindow
```
%FeatureWindow{
  id, tenant_id, kind: :market | :edgar,
  key: symbol | cik,
  window_start, window_end,
  features: %{feature_name => numeric()},
  label_spec: %{horizon: integer(), type: :delta | :class},
  labels: %{label_name => value} | nil (filled async),
  provenance: %{raw_refs: [uuid()], recipe_version: integer()},
  feature_schema_version: integer()
}
```

### DecisionTrace
```
%DecisionTrace{
  id, feature_window_id, tenant_id,
  router_version, gate_scores: %{expert_id => float()},
  selected_experts: [expert_id],
  actions: [%{expert_id, action, confidence, latency_ms}],
  blended_action: map(),
  pnl_snapshot: map() | nil,
  risk_flags: [atom()],
  behavior_embedding: binary(),
  hash: binary()
}
```

---
## 4. Ash Resource Plan

Proposed new resources (namespace suggestions):

`Thunderline.Markets.RawTick` (table: raw_market_ticks)
`Thunderline.Filings.EDGARDoc` (raw_edgar_docs)
`Thunderline.Features.FeatureWindow` (feature_windows unified table; kind=:market|:edgar; status=:open|:filled|:superseded)
`Thunderline.MoE.Expert` (model_registry)
`Thunderline.MoE.DecisionTrace` (decision_traces)
`Thunderline.Lineage.Edge` (lineage_edges)
`Thunderline.Export.TrainingSlice` (export_jobs)

Aggregates & Calculations:
* FeatureWindow: `label_filled?` calculation; aggregate counts per key/time bucket.
* Expert: success rate, average latency (rolling window via materialized view or nightly refresh).
* DecisionTrace: blend quality metrics (PnL attribution & variance). 

Policies: Tenancy enforced per resource with `tenant_id` attribute + row-level policies. Feature export actions restricted to internal/system role.

---
## 5. Supervision & Processes

```
Thunderline.Application
  ├─ Thunderblock.Supervisor (Ingress Channels / HTTP controllers)
  ├─ Thunderchief.Supervisor
  │    ├─ Thunderchief.RouterConfig (ETS + PubSub for router snapshots)
  │    └─ Thunderchief.Cadence (periodic tick, load/backpressure monitor)
  ├─ Thunderflow.Supervisor
  │    ├─ Broadway :market_ingest
  │    └─ Broadway :edgar_ingest
  ├─ Thunderbolt.Supervisor
  │    └─ DynamicSupervisor (Expert workers)
  ├─ Thundercell.Supervisor (Registry + Dynamic cells)
  ├─ Thundergate.Supervisor (Oban queues / exporters)
  ├─ Thunderlink.PubSub (Phoenix.PubSub)
  └─ Thundereye.Telemetry (metrics & LiveView sources)
```

Failure Strategy: Isolate experts (let it crash, restart under latency health checks). RouterConfig broadcasts new config atomically (versioned). Backpressure escalates from Broadway (demand reduction) → Cadence reduces window frequency or coarsens features.

---
## 6. Broadway Pipelines

### market_ingest
Stages:
1. Source (WebSocket/Adapter GenServers → Producer) – pushes MarketTick.
2. Normalize (schema validation, decimal coercion).
3. WindowBuilder (per symbol partition key) – sliding windows (250ms, 50% overlap configurable).
4. FeatureCompute – enrich microstructure metrics.
5. Persist & Emit – write FeatureWindow (Ash create) + publish to `feature_windows:market` topic.

Partitioning: `:symbol`. Concurrency: N cores * 2 (empirically adjust).

Backpressure: WindowBuilder uses ETS ring buffer; if buffer length > threshold, signals Cadence to widen window (adaptive).

### edgar_ingest
Stages:
1. Source (Poll/Download queue) -> raw forms.
2. Parse/XBRL extraction.
3. SectionChunk (splits MDA/Risk/etc.).
4. Embedding & Sentiment (Nx or external microservice -> async Task.Supervisor with timeout fallback).
5. FeatureCompute (joins previous filing metrics; compute deltas & ratios).
6. Persist & Emit (FeatureWindow create + broadcast `feature_windows:edgar`).

Partitioning: `:cik`. Batch size tuned for memory; concurrency lower due to heavy tasks. 

---
## 7. Hybrid Routing (Expert-Choice + Dynamic Top‑P)

Router steps per layer:
1. Compute token (feature embedding) → expert logits: `scores = softmax(embedding · W_g)`.
2. Expert-Choice: Transpose scores → for each expert take top-K tokens (K = capacity). Builds fixed buckets (balanced load).
3. For each token accumulate its assigned experts (from all expert buckets) sorted by descending score.
4. Dynamic Top‑P: keep adding experts until cumulative probability ≥ p_threshold (layer config). If already ≥ p with first expert, only one expert activated.
5. Emit routing assignment object with metadata (layer_id, version, token_expert_map, expert_token_map, capacity_factor, p_threshold).

Metrics:
* avg_experts_per_token
* load_balance_ratio (stddev token counts per expert)
* capacity_utilization (used/available slots)
* p_saturation histogram

Config (example):
```elixir
config :thunderline, Thunderchief.Router,
  layers: [
    %{layer: 0, experts: 16, capacity_factor: 2.0, p: 0.65},
    %{layer: 1, experts: 12, capacity_factor: 1.8, p: 0.6},
    %{layer: 2, experts: 8, capacity_factor: 1.6, p: 0.55}
  ]
```

Hot Reload: Publish new config version; experts update gating weights atomically (double buffer). Decisions carry `router_version` for traceability.

---
## 8. Storage & Indexing Strategy

Tables (proposed minimal columns):
* raw_market_ticks (id, tenant_id, symbol, ts, payload jsonb)
* raw_edgar_docs (id, tenant_id, cik, form, filing_time, period_end, sections jsonb, xbrl jsonb, hash)
* feature_windows (id, tenant_id, kind, key, window_start, window_end, status, features jsonb, label_spec jsonb, labels jsonb, feature_schema_version, provenance jsonb)
* decision_traces (id, tenant_id, feature_window_id, router_version, gate_scores jsonb, selected_experts jsonb, actions jsonb, blended_action jsonb, pnl_snapshot jsonb, risk_flags jsonb, behavior_embedding bytea, hash)
* experts (id, name, version, status, latency_budget_ms, metrics jsonb, model_artifact_ref, inserted_at)
* lineage_edges (id, from_id, to_id, edge_type, inserted_at)
* export_jobs (id, tenant_id, slice_spec jsonb, status, artifact_uri, created_at, completed_at)

Partitioning: feature_windows monthly on window_start.

Indexes:
* feature_windows: (tenant_id, kind, key, window_start DESC), (tenant_id, feature_schema_version, inserted_at)
* decision_traces: (feature_window_id), (tenant_id, inserted_at DESC)
* lineage_edges: (from_id), (to_id)

Retention Policy: Raw ticks & raw edgar optionally tiered to cold storage after X days; features & decisions kept longer (audits) with partitioning by month.

---
## 9. Telemetry & Guardrails

Events (prefix `:thunderline`):
* `[:flow, :market, :lag_ms]`
* `[:flow, :edgar, :throughput]`
* `[:router, :assignment, :experts_per_token]`
* `[:expert, :latency_ms]`
* `[:drift, :feature, :psi]`
* `[:risk, :breach]`
* `[:router, :entropy]`
* `[:router, :capacity_utilization]`
* `[:feature, :fill_latency_ms]`
* `[:label, :realization_latency_ms]`
* `[:router, :undercovered_token]`

Backpressure Policy Ladder:
1. If lag_p95 > 2 * target_window_ms → widen window +50% (market only).
2. If balancer_backlog > 5 * concurrency → set overlap=0%.
3. If avg_experts_per_token > planned + 0.3 → reduce p_threshold by 0.05 for next interval.
4. If still degraded next interval → switch to coarse feature recipe (reduced metrics set).
5. If still degraded → drop enrichment features (retain core price/volume) until lag normalizes.
6. If risk breach intervals ≥3 → force :abstain for high-latency experts.

Risk Hooks: Hard reject decision if risk flag set -> action replaced with `:abstain` + log.
Compliance:
* Deny map (tenant_id, symbol) → :halt kill switch.
* Decimal normalization of XBRL numerics.
* EDGAR retention flags: sections_redacted, xbrl_hash.

---
## 10. Implementation Phases (Executable Punch List)

### Phase 0 (Scaffold – 1 day)
* Create Ash resources: RawTick, EDGARDoc, FeatureWindow (single table with :kind), Expert, DecisionTrace.
* Migrations for core tables + indexes.
* Supervision skeleton & empty Broadway pipelines.
* Telemetry events stubs.

### Phase 1 (Market Path – 1–2 days)
* Market adapter (mock generator initially) → market_ingest pipeline.
* WindowBuilder (ETS ring buffer) & FeatureCompute (basic features: mid_return, spread, imbalance).
* Persist FeatureWindow v0; LiveView dashboard of lag & throughput.
* Simple static router (single expert) + DecisionTrace skeleton.

### Phase 2 (EDGAR Path – 2–3 days)
* EDGAR polling stub + parser for sample filings.
* Section splitting & embedding placeholder (random vectors) → later real embeddings.
* Feature recipe merging fundamentals & text sentiment placeholder.

### Phase 3 (Hybrid Router & Experts – 2 days)
* Implement ExpertChoice bucket assignment.
* Implement Dynamic Top‑P pruning.
* Expose config reload + metrics.
* Add ≥3 experts (mock model function returning action + latency simulate) & weighted vote.

### Phase 4 (Lineage, Drift, Risk – 2 days)
* Lineage edge writes (window→trace→expert, etc.).
* Feature drift computation (PSI vs baseline) nightly job.
* Risk policy module & PnL placeholder ingest (paper trading mode).

### Phase 5 (NAS Loop Integration – 2 days)
* Thundergate export job -> Arrow/Parquet builder (mock slice).
* Python bridge handshake (gRPC/Port) returning candidate metadata.
* Blue/green expert rollout state machine.

---
## 11. Testing Strategy

* Unit: WindowBuilder (overlap correctness), Router (capacity, p-threshold invariants), Expert registry (hot swap atomicity).
* Property: Routing load balance (stddev ≤ bound), no token assigned > max_experts.
* Integration: End-to-end mock tick burst → DecisionTrace produced within SLA < 500ms.
* Performance: Synthetic spikes (10× tick rate) – verify backpressure ladder triggers.
* Regression: Snapshot feature schema versioning; ensure forward migration path.
* Deterministic Replay: Reprocess 1-min captured slab → identical hashes for FeatureWindow & DecisionTrace.
* Partial→Fill: Delayed EDGAR section produces status transition (:open→:filled) & lineage edges.
* Router Invariants: No capacity violations; undercovered_token rate ≈ 0 normal load.
* NAS Stub: Export 3 task packs; shadow dummy expert decisions logged, no influence.

---
## 12. Open Design Questions / TODO

* Behavior embedding shape & compression algorithm (PCA vs autoencoder?).
* Multi-tenant gating isolation (per-tenant gating weights vs shared?).
* Storage of gate score matrices (dense vs top-n sparse) for large scale.
* Real embeddings infra (on-device Nx vs external microservice) – latency trade study needed.
* Live labeling horizons (Δp, volatility) – asynchronous scheduler design.

---
## 13. Immediate Next Actions (Recommend Doing Next)

1. Approve resource list & table naming.
2. Generate migrations & empty resources (Phase 0).
3. Implement MarketTick mock adapter + market_ingest skeleton.
4. Add telemetry events + initial LiveView panel.
5. Draft Router config struct + validation.

Once confirmed, we can scaffold code directly.

---
## 14. Appendix: Example Router Assignment Struct
```elixir
defmodule Thunderchief.Router.Assignment do
  @enforce_keys [:router_version, :layer, :token_experts, :expert_tokens, :stats]
  defstruct [:router_version, :layer, :token_experts, :expert_tokens, :stats, :config]
  # token_experts: %{token_id => [%{expert: id, p: float()}]}
  # expert_tokens: %{expert_id => [token_id]}
  # stats: %{avg_experts_per_token: float(), capacity_utilization: float(), p_distribution: map()}
end
```

---
## 15. References

* Expert Choice MoE (NeurIPS 2022)
* Dynamic Top‑P MoE Routing (2024)
* Broadway + Nx official docs (for integration patterns)

---
Feedback welcome – after sign-off, we convert this into concrete modules & migrations (Phase 0).
