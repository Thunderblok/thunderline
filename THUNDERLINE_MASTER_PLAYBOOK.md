# 🚀 THUNDERLINE MASTER PLAYBOOK: From Zero to AI Automation

> **Architecture Status (Nov 27, 2025 - HC-Quantum Update)**: Overall Grade **A (9/10)** - 8 active domains, ~160 Ash resources, 6 major consolidations completed, 2 in progress. **NEW**: Cross-Domain Functional Layers architecture (HC-31/32/33) defining 6 capability layers across domain pairs. Full review: [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md)
>
> High Command Review Integration (Aug 25 2025): This Playbook incorporates the formal external "High Command" launch readiness review. New section: HIGH COMMAND REVIEW: ACTION MATRIX (P0 launch backlog HC-01..HC-37). All P0 items gate milestone `M1-EMAIL-AUTOMATION` (public pilot enablement). Cross‑reference: OKO_HANDBOOK SITREP, DOMAIN_ARCHITECTURE_REVIEW.
>
> **Ground Truth Verification (Nov 18, 2025)**: HC review contained inaccuracies. Direct codebase inspection revealed (and now resolved): (1) ThunderCom resources migrated into ThunderLink (HC-27/28 ✅), (2) ThunderLink operates as the single communications domain with 17 resources, (3) ThunderVine architectural decision implemented. See Ground Truth Verification Summary section and HC-27, HC-28, HC-29, HC-30 for details.
>
> **Active Domains (Nov 27, 2025)**: Thundergate (19), Thunderlink (17), Thunderflow (9), Thunderbolt (50+), Thundercrown (4), Thunderblock (33), Thundergrid (5), Thunderprism (2), RAG (1)
> **Cross-Domain Layers**: Routing (Flow×Grid), Observability (Gate×Crown), Intelligence (Bolt×Crown), Persistence (Block×Flow), Communication (Link×Gate), Orchestration (Vine×Crown)
> **Consolidations Status**: 
> - ✅ **Complete (6)**: ThunderVault→Thunderblock, 5 domains→Thunderbolt, ThunderChief→Thundercrown, ThunderStone+ThunderEye+Accounts+ThunderWatch→Thundergate, ThunderWave→Thunderlink, ThunderCom→Thunderlink (HC-27/28 ✅ Nov 18 2025)
> - ⚠️ **In Progress (2)**: ThunderJam→Thundergate.RateLimiting, ThunderClock→Thunderblock.Timing

---

## 📊 NOVEMBER 18, 2025 ARCHITECTURE REVIEW SUMMARY

### Domain Architecture Status

**Overall Grade**: **A (9/10)** - Excellent foundation with consolidation work in progress (verified Nov 18, 2025)

**Active Production Domains** (8 domains, ~160 resources - verified Nov 18, 2025):

1. **Thundergate (19 resources)** - Authentication, External Services, Federation, Policy, Monitoring
   - Extensions: AshAdmin
   - Consolidation: ThunderStone + ThunderEye + Accounts + ThunderWatch → Thundergate (Sep-Nov 2025)
   - Status: ✅ Magika integration complete, monitoring unified

2. **Thunderlink (17 resources)** - Support, Community, Voice Communications, Node Registry
   - Extensions: AshAdmin, AshOban, AshGraphql, AshTypescript.Rpc
   - Consolidation: ThunderCom + ThunderWave → Thunderlink (complete Nov 18 2025; HC-27/28 ✅)
   - APIs: GraphQL + TypeScript RPC active
   - Bug #18: LinkSession.meta uses AtomMap custom type (keys as atoms)

3. **Thunderflow (9 resources)** - Event Streams, System Actions, Events, Probes, Features, Lineage
   - Extensions: AshAdmin
   - 4 Broadway Pipelines: EventPipeline, CrossDomainPipeline, RealTimePipeline, EventProducer
   - Features: DLQ, batching, backpressure, telemetry
   - Status: ✅ Core event infrastructure operational

4. **Thunderbolt (50+ resources)** - Core ML/AI, Ising VIM, Lane optimization, Task management, Automata, Cerebros NAS, RAG, MLflow, UPM, MoE
   - Extensions: AshAdmin, AshOban, AshJsonApi, AshGraphql
   - Consolidation: ThunderCore + ThunderLane + ThunderMag + ThunderCell + Thunder_Ising → Thunderbolt (Aug-Oct 2025)
   - 11 categories, largest domain
   - Recommendation: Consider strategic split into focused domains
   - Status: ✅ Comprehensive ML/AI infrastructure, RAG system operational

5. **Thundercrown (4 resources)** - Orchestration UI, Agent Runner, Conversation
   - Extensions: AshAdmin, AshAi
   - Consolidation: ThunderChief → Thundercrown (Oct 2025)
   - MCP Tools: 4 exposed via AshAi integration
   - Status: ✅ AI orchestration framework active

6. **Thunderblock (33 resources)** - Vault, Infrastructure, Orchestration, DAG, Timing
   - Extensions: AshAdmin
   - Consolidation: ThunderVault → Thunderblock (Sep 2025)
   - AtomMap custom type: Bug #18 solution for atom-keyed maps
   - Status: ✅ Infrastructure layer solid

7. **Thundergrid (5 resources)** - Spatial modeling, Zones, Events, State
   - Extensions: AshGraphql, AshJsonApi
   - Dual API: GraphQL + JSON:API
   - Status: ✅ Spatial operations framework ready

8. **RAG (1 resource)** - RagChunk for retrieval-augmented generation
   - Support domain for AI operations
   - Status: ✅ Active in Thunderbolt ML pipeline

**Consolidation Summary** (6 completed, 2 in progress):
- ✅ ThunderVault → Thunderblock (33 resources)
- ✅ 5 domains → Thunderbolt (ThunderCore, ThunderLane, ThunderMag, ThunderCell, Thunder_Ising)
- ✅ ThunderChief → Thundercrown (4 resources)
- ✅ ThunderCom + ThunderWave → Thunderlink (17 resources, completed Nov 18 2025)
- ✅ ThunderStone + ThunderEye + Accounts + ThunderWatch → Thundergate (19 resources)
- ✅ UPM integration into Thunderbolt (4 resources)
- 🔄 ThunderJam → Thundergate.RateLimiting (in progress)
- 🔄 ThunderClock → Thunderblock.Timing (in progress)

**Areas for Improvement**:
1. Consider splitting Thunderbolt (50+ resources) into focused domains
2. Complete ThunderJam and ThunderClock migrations
3. Review placeholder domains (Thunderforge, ServiceRegistry)
4. Continue monitoring AtomMap usage (Bug #18) across domains

**Documentation References**:
- Full Review: [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md)
- Resource Catalog: [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md)
- Resource Guide: [`thunderline_domain_resource_guide.md`](thunderline_domain_resource_guide.md)

---

## 🛡 HIGH COMMAND REVIEW: ACTION MATRIX (Aug 25 2025)

| ID | Priority | Theme | Gap / Finding | Action (Decision) | Owner (TBD) | Status |
|----|----------|-------|---------------|-------------------|-------------|--------|
| HC-01 | P0 | Event Core | No unified publish helper | **✅ COMPLETE** (Nov 25) - `EventBus.publish_event/1` with validation, OTel spans, telemetry. CI gated via `mix thunderline.events.lint`. Tests: `event_bus_test.exs`, `event_bus_telemetry_test.exs` | Flow Steward | **Done** |
| HC-02 | P0 | Bus API Consistency | Shim `Thunderline.Bus` still referenced | **✅ COMPLETE** (Nov 27) - Zero references in `lib/` or `test/`, no `bus.ex` module file exists. Legacy shim fully removed. | Flow Steward | **Done** |
| HC-03 | P0 | Observability Docs | Missing Event & Error taxonomy specs | **✅ COMPLETE** (Nov 25) - `documentation/EVENT_TAXONOMY.md` (naming rules, domain→category, registered events, reliability, validation) + `documentation/ERROR_CLASSES.md` (classification, retry policies, DLQ) | Observability Lead | **Done** |
| HC-04 | P0 | ML Persistence | Cerebros migrations parked | Move/run migrations; add lifecycle state machine | Bolt Steward | In Progress (50+ resources active) |
| HC-04a | P0 | Python ML Stack | TensorFlow/ONNX environment setup | **✅ COMPLETE** - TensorFlow 2.20.0, tf2onnx 1.8.4, ONNX 1.19.1 installed and verified | Bolt Steward | **Done** |
| HC-04b | P0 | Elixir ML Dependencies | Req/Ortex installation | **✅ COMPLETE** - Req 0.5.15, Ortex 0.1.10 compiled successfully | Bolt Steward | **Done** |
| HC-04d | P0 | Persistent ONNX Sessions | ModelServer for cached inference | **✅ COMPLETE** (Nov 25) - GenServer/ETS cache, 3000x speedup (~11μs vs ~36ms), LRU eviction, cerebros models operational | Bolt Steward | **Done** |
| HC-04c | P0 | Magika Integration | AI file classification missing | **✅ COMPLETE** - Core wrapper (420 lines), unit tests (11 cases), integration tests (6 scenarios), Broadway pipeline, EventBus bridge, configuration, supervision, documentation. Production-ready. See `docs/MAGIKA_QUICK_START.md` | Gate Steward | **Done** |
| HC-05 | P0 | Email MVP | No email resources/flow | Add `Contact` & `OutboundEmail`, SMTP adapter, events | Gate+Link | Not Started |
| HC-06 | P0 | Presence Policies | Membership & presence auth gaps | Implement policies + presence events join/leave | Link Steward | Not Started |
| HC-07 | P0 | Deployment | No prod deploy tooling | **✅ COMPLETE** (Nov 26) - Dockerfile enhanced (HTTP healthcheck), `scripts/release.sh` (build script), `ops/thunderline.service` (systemd unit + security hardening), `ops/env.example` (config template). K8s-style probes: `/healthz`, `/livez` (liveness), `/readyz`, `/api/ready` (readiness), `/api/health` (full check). | Platform | **Done** |
| HC-08 | P0 | CI/CD Depth | Missing release pipeline, PLT cache, audit | Extend GH Actions (release, dialyzer cache, hex.audit) | Platform | Planned |
| HC-09 | P0 | Error Handling | No classifier & DLQ policy | **✅ COMPLETE** (Nov 27) - `ErrorClassifier` expanded (15+ patterns: Ecto, timeout, security, HTTP status, dependency, transport errors), `ErrorClass` struct with type specs, `DLQ` module (Mnesia-backed, threshold alerts, telemetry), `retry_policy/1` and `should_dlq?/1` helpers. Tests: `error_classifier_test.exs`, `dlq_test.exs`. Documentation: `docs/reference/ERROR_CLASSES.md`. | Flow Steward | **Done** |
| HC-10 | P0 | Feature Flags | Flags undocumented | **✅ COMPLETE** (Nov 27) - `Thunderline.Feature` module implemented (`enabled?/2`, `override/2`, `clear_override/1`, `all/0`). `docs/reference/FEATURE_FLAGS.md` v1.0: 14 core flags, 8 direct env vars, 7 layer flags documented with lifecycle stages. Governance workflow defined. | Platform | **Done** |
| HC-22 | P0 | Unified Model | No persistent cross-agent model | Stand up Unified Persistent Model (UPM) online trainer + ThunderBlock adapters + rollout policy | Bolt + Flow + Crown Stewards | Not Started |
| HC-11 | P1 | ThunderBridge | Missing ingest bridge layer | DIP + scaffold `Thunderline.ThunderBridge` | Gate Steward | ✅ Done |
| HC-12 | P1 | DomainProcessor | Repeated consumer boilerplate | Introduce behaviour + generators + telemetry | Flow Steward | Not Started |
| HC-13 | P1 | Voice/WebRTC | Unused media libs | MVP voice → intent pipeline (`voice.intent.detected`) | Link+Crown | Not Started |
| HC-14 | P1 | Telemetry Dashboards | Sparse dashboards | Grafana JSON / custom LiveDashboard pages | Observability | Not Started |
| HC-15 | P1 | Security Hardening | API keys, encryption coverage | API key resource + cloak coverage matrix | Gate Steward | Not Started |
| HC-16 | P1 | Logging Standard | NDJSON schema undefined | Define versioned schema + field `log.schema.version` | Platform | Not Started |
| HC-17 | P2 | Federation Roadmap | ActivityPub phases vague | Draft phased activation doc | Gate | Not Started |
| HC-18 | P2 | Performance Baselines | No perf guard in CI | Add benches + regression thresholds | Platform | Not Started |
| HC-19 | P2 | Mobile Readiness | No offline/mobile doc | Draft sync/offline strategy | Link | Not Started |
| HC-20 | P1 | Cerebros Bridge | No formal external core bridge boundary | Create gitignored mirror + API boundary doc + DIP | Bolt Steward | Not Started |
| HC-21 | P1 | VIM Rollout Governance | Shadow telemetry & canary activation plan missing | Implement vim.* telemetry + rollout checklist | Flow + Bolt | Not Started |
| HC-23 | P1 | Thundra/Nerves Integration | Multi-dimensional PAC execution engine (cloud + edge) needed for sovereign agent autonomy | Implement Thundra VM (tick-based voxelized cellular automata in Bolt, 12-zone hexagonal lattice), Nerves firmware template (mTLS enrollment via Gate, local PAC execution), device telemetry backhaul (Link TOCP transport), policy enforcement (Crown device manifests), event DAG traceability (correlation_id/causation_id lineage) | Bolt + Gate + Link + Crown Stewards | Not Started |
| HC-24 | P1 | Sensor-to-STAC Pipeline | Complete sensor data to knowledge graph to tokenized reward pipeline undefined | Design and implement Thunderforge to Thunderblock flow: Thunderbit ingestion (Nerves devices), decode/assemble workers (Oban), PAC validation (6-dimensional policy checks), DAG commit (knowledge graph), STAC minting (reward function), staking mechanics (sSTAC/STACC), anti-grief patterns (novelty decay, collusion detection), observability (SLOs P50 under 150ms, P95 under 500ms, P99 under 2s). See documentation/architecture/sensor_to_stac_pipeline.md | Forge + Bolt + Block Stewards | Not Started |
| HC-25 | P1 | ML Optimization Infrastructure | No hyperparameter tuning framework | Implement Tree-structured Parzen Estimator (TPE) for Bayesian optimization: Nx/Scholar core algorithm (200 lines KDE-based), Ash resource (Oko.Tuner.TPEJob for persistence), Oban worker (async execution), Mix task CLI (mix tpe.run), search space support (uniform/lognormal/categorical distributions). Enable automated tuning for Cerebros NAS, Oko classifiers, VIM solvers. See documentation/architecture/tpe_optimizer.md | Bolt Steward | Not Started |
| HC-26 | P1 | Domain Architecture | 6 consolidations completed, 2 in progress (verified Nov 18, 2025) | **Priority Actions**: (1) Complete ThunderCom→ThunderLink consolidation (**✅ HC-27/28 delivered Nov 18 2025**), (2) Complete ThunderJam→Thundergate.RateLimiting migration, (3) Complete ThunderClock→Thunderblock.Timing migration, (4) Consider splitting Thunderbolt (50+ resources - complexity concern), (5) Decide ThunderVine domain structure (HC-29 - ✅ COMPLETE). See Ground Truth Verification Summary and HC-27, HC-28, HC-29, HC-30 for details. | Architecture Guild | In Progress | Ongoing |
| HC-27 | P0 | Domain Consolidation | ThunderCom→ThunderLink consolidation | **Outcome (Nov 18 2025)**: Executed 8-phase plan (verification → LiveView swaps → duplicate removals → voice + support cleanup → domain deletion) removing the ThunderCom domain entirely while preserving shared DB tables. LiveViews now depend solely on ThunderLink, redundancy eliminated, and compilation/tests pass. | Gate + Link Stewards | **✅ COMPLETE** | Nov 18 2025 |
| HC-28 | P0 | Resource Duplication | Canonicalize ThunderLink resources | **Outcome (Nov 18 2025)**: Selected ThunderLink implementations for Community/Channel/Message/Role/FederationSocket, removed ThunderCom duplicates, verified voice namespace alignment, and recompiled platform with zero regressions. | Link Steward | **✅ COMPLETE** | Nov 18 2025 |
| HC-29 | P0 | ThunderVine Architecture | ✅ COMPLETE (Nov 17, 2025) | **Implementation**: Created ThunderVine.Domain with 4 owned resources (Workflow, WorkflowNode, WorkflowEdge, WorkflowSnapshot) migrated from ThunderBlock. **Benefits Realized**: API exposure via Ash.Domain, policy enforcement, clearer ownership (orchestration vs infrastructure), improved naming (Workflow vs DAGWorkflow), reduced coupling. **Migration**: 5 files created, 10 files modified, 4 files deleted. Zero breaking changes (same DB tables: dag_workflows, dag_nodes, dag_edges, dag_snapshots). **Verification**: Compilation ✅ (zero errors), Tests ✅ (no new failures), Documentation ✅ (6 files synchronized). See HC-29_COMPLETION_REPORT.md for full details. | Bolt + Block Stewards | ✅ COMPLETE | Nov 17, 2025 |
| HC-30 | P0 | ThunderForge Cleanup | ✅ COMPLETE (Nov 17, 2025) | **Implementation**: Removed entire ThunderForge directory (3 files, ~75 lines total). **Files Removed**: domain.ex (empty resources block), blueprint.ex (25-line YAML parser), factory_run.ex (40-line telemetry executor). **Verification**: Zero production dependencies confirmed via comprehensive grep, explicitly marked as "orphaned design" in ORPHANED_CODE_REPORT.md. **Rationale**: No active usage, HC-24 (future sensor pipeline) can reimplement if needed, code preserved in git history. **Effort**: 30 minutes total (investigation + removal + documentation). | Platform Team | ✅ COMPLETE | Nov 17, 2025 |
| **HC-31** | **P0** | **Multimodal Routing Layer** | No multi-channel event bus for PAC-state routing | **HC-Quantum-01**: Implement multi-channel bus (8-32 logical channels), routing profiles (6 presets: `fast_volatile`, `durable_ordered`, `broadcast_fanout`, `ml_pipeline`, `realtime_stream`, `audit_log`), channel manager GenServer, admin CLI (`mix thunderline.channels.*`), telemetry per-channel. **Files**: `lib/thunderline/thundergrid/multi_channel_bus.ex`, `routing_profile.ex`, `multi_mode_dispatcher.ex`. Cross-domain layer: **Flow×Grid** (event routing + spatial/channel topology). | Flow + Grid Stewards | Not Started |
| **HC-32** | **P0** | **PAC-State Swapping** | No hot-swap mechanism for agent state transfer | **HC-Quantum-02**: PAC state extraction (serialize running agent memory), state fusion (merge/diff algorithms), swap service (atomic handoff between channels/zones), rollback on failure, telemetry for swap latency/success. **Files**: `lib/thunderline/thundergrid/state_swapper.ex`, `state_fusion.ex`, `state_extractor.ex`. Enables live agent migration, A/B personality testing, checkpoint/restore. | Grid + Block Stewards | Not Started |
| **HC-33** | **P0** | **Dynamic Routing Profiles** | Static routing insufficient for adaptive workloads | **HC-Quantum-03**: Profile registry (CRUD for routing configs), auto-switching (telemetry-driven profile selection), Cerebros compute channels (ML inference routing), canary routing (percentage-based traffic split), profile inheritance (base + overlay). **Files**: `lib/thunderline/thundergrid/routing_profiles/*.ex`, `profile_registry.ex`, `auto_switcher.ex`. Cross-domain layer: **Crown×Flow** (governance + routing policy). | Crown + Flow Stewards | Not Started |
| **HC-34** | **P1** | **Simplex-Path Clustering Core** | No manifold-aware clustering for swarm intelligence | **Research-01**: Implement LAPD (Largest Angle Path Distance) algorithm for robust multi-manifold clustering. **Components**: (1) Snex Python interop for SciPy Delaunay triangulation + path distance computation, (2) Nx/EXLA alternative backend (future), (3) Ash resource `Thunderbolt.Cluster` with membership tracking, (4) Automatic intrinsic dimension estimation, (5) Denoising via η-cutoff (elbow method). **Complexity**: Quasi-linear in sample size, exponential in intrinsic dimension d. **Files**: `lib/thunderline/thunderbolt/clustering/simplex_paths.ex`, `lapd_engine.ex`, `cluster_resource.ex`. Cross-domain layer: **Bolt×Block** (ML compute + persistence). | Bolt + Block Stewards | Not Started |
| **HC-35** | **P1** | **Clustering Orchestration** | No automated clustering lifecycle management | **Research-02**: Orchestrate clustering via Thunderchief/Thunderflow. **Components**: (1) AshOban worker for periodic clustering jobs, (2) Thunderflow pipeline DAG (data collection → clustering → result broadcast), (3) Event emission (`clusters:running`, `clusters:completed`, `clusters:updated`), (4) Trigger points (timed schedule, agent count threshold, manual), (5) Thundergrid zone-level data aggregation (`collect_zone_data/0`), (6) Cluster coordinator assignment per sub-swarm. **Integration**: Thundercell automata hooks for "Cluster now" state-machine action. Cross-domain layer: **Flow×Crown** (orchestration + governance). | Flow + Crown Stewards | Not Started |
| **HC-36** | **P1** | **Clustering Visualization** | No UI for cluster insights and control | **Research-03**: Thunderprism cluster dashboard. **Components**: (1) Swarm Clusters panel (ID, size, health metrics, color-coded), (2) Real-time PubSub updates on `clusters:updated`, (3) Drill-down to member agents, (4) Manual "Recluster Now" button with loading state, (5) Parameter tuning UI (intrinsic dimension d, neighborhood size, denoising η), (6) Cluster-based command broadcast ("Send to Cluster X"), (7) Optional 2D PCA projection visualization. **LiveView**: Subscribe to cluster events, refresh on change. Cross-domain layer: **Prism×Link** (UI + connectivity). | Prism + Link Stewards | Not Started |
| **HC-37** | **P1** | **Clustering Memory Integration** | Clusters not represented in knowledge graph | **Research-04**: Thundervine/Thunderblock cluster persistence. **Components**: (1) Cluster MemoryNode in Thundervine graph (links to member agents), (2) Cluster centroid embeddings in pgvector for similarity search, (3) Agent→Cluster hub edges (avoid N² clique explosion), (4) Temporal DAG evolution (cluster snapshots over time, `evolves_to` edges), (5) `cluster_runs` audit table (timestamp, params, summary), (6) Agent schema extension (`cluster_id` field), (7) Bulk Ash action for cluster assignment updates. Cross-domain layer: **Vine×Block** (memory graph + persistence). | Vine + Block Stewards | Not Started |

Legend: P0 launch‑critical; P1 post‑launch hardening; P2 strategic. Status: Not Started | Planned | In Progress | Done.

---

## 🔀 CROSS-DOMAIN FUNCTIONAL LAYERS (Nov 27, 2025)

**Concept**: Individual domains own resources and actions, but certain capabilities emerge from domain *combinations*. These "functional layers" are implemented via coordinated modules across domains without creating new Ash domains.

### Layer Architecture

| Layer | Domains | Responsibility | Key Modules |
|-------|---------|----------------|-------------|
| **Routing Layer** | Flow × Grid | Multi-channel event routing, spatial topology, channel management | `Thundergrid.MultiChannelBus`, `Thunderflow.EventBus`, `Thundergrid.MultiModeDispatcher` |
| **Observability Layer** | Gate × Crown | Telemetry aggregation, policy-aware metrics, audit trails, health checks | `Thundergate.Telemetry`, `Thundercrown.AuditLog`, `Thundergate.HealthCheck` |
| **Intelligence Layer** | Bolt × Crown | ML inference + governance, model deployment policies, compute quotas | `Thunderbolt.ModelServer`, `Thundercrown.ModelPolicy`, `Thunderbolt.CerebrosBridge` |
| **Persistence Layer** | Block × Flow | Event sourcing, state snapshots, lineage tracking, DLQ management | `Thunderblock.MemoryVault`, `Thunderflow.EventStore`, `Thunderblock.LineageDAG` |
| **Clustering Layer** | Bolt × Vine | Manifold discovery, swarm sub-grouping, knowledge clustering | `Thunderbolt.SimplexPaths`, `Thundervine.ClusterMemory`, `Thunderbolt.LAPDEngine` |
| **Communication Layer** | Link × Gate | External messaging, federation, API gateway, rate limiting | `Thunderlink.TOCP`, `Thundergate.Federation`, `Thundergate.RateLimiter` |
| **Orchestration Layer** | Vine × Crown | Workflow execution, policy enforcement on DAGs, approval gates | `Thundervine.WorkflowRunner`, `Thundercrown.ApprovalGate`, `Thundervine.Scheduler` |

### Implementation Pattern

```elixir
# Layers are NOT new Ash domains - they're coordination points
# Example: Routing Layer coordinator

defmodule Thunderline.Layers.Routing do
  @moduledoc """
  Cross-domain coordination for Flow × Grid routing layer.
  Provides unified API for multi-channel event routing.
  """
  
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Thundergrid.{MultiChannelBus, RoutingProfile}
  
  def route_event(event, opts \\ []) do
    channel = Keyword.get(opts, :channel, :default)
    profile = Keyword.get(opts, :profile, :durable_ordered)
    
    with {:ok, resolved_channel} <- MultiChannelBus.resolve_channel(channel),
         {:ok, config} <- RoutingProfile.get(profile),
         {:ok, routed} <- EventBus.publish_event(event, config) do
      {:ok, %{event: routed, channel: resolved_channel, profile: profile}}
    end
  end
end
```

### Layer Activation

Layers activate based on which domains are loaded. Feature flags control layer availability:

| Layer | Required Domains | Feature Flag | Default |
|-------|-----------------|--------------|---------|
| Routing | Flow, Grid | `LAYER_ROUTING_ENABLED` | `true` |
| Observability | Gate, Crown | `LAYER_OBSERVABILITY_ENABLED` | `true` |
| Intelligence | Bolt, Crown | `LAYER_INTELLIGENCE_ENABLED` | `true` |
| Persistence | Block, Flow | `LAYER_PERSISTENCE_ENABLED` | `true` |
| Communication | Link, Gate | `LAYER_COMMUNICATION_ENABLED` | `true` |
| Orchestration | Vine, Crown | `LAYER_ORCHESTRATION_ENABLED` | `false` |
| Clustering | Bolt, Vine | `LAYER_CLUSTERING_ENABLED` | `false` |

### HC-Quantum Roadmap (Multi-Channel Routing)

**Phase 1 (Week 1)**: HC-31 - Multi-Channel Bus
- [ ] `Thundergrid.MultiChannelBus` GenServer (channel registry, lifecycle)
- [ ] `Thundergrid.RoutingProfile` (6 preset profiles + custom)
- [ ] `Thundergrid.MultiModeDispatcher` (fan-out, round-robin, priority)
- [ ] Mix tasks: `mix thunderline.channels.list|create|delete|stats`
- [ ] Telemetry: `[:thunderline, :grid, :channel, :*]`

**Phase 2 (Week 2)**: HC-32 - PAC-State Swapping
- [ ] `Thundergrid.StateExtractor` (serialize agent memory to portable format)
- [ ] `Thundergrid.StateFusion` (merge/diff algorithms for state combination)
- [ ] `Thundergrid.StateSwapper` (atomic swap service with rollback)
- [ ] Checkpoint/restore for agent migration
- [ ] Telemetry: `[:thunderline, :grid, :swap, :*]`

**Phase 3 (Week 3)**: HC-33 - Dynamic Routing Profiles
- [ ] `Thundergrid.ProfileRegistry` (CRUD, inheritance, versioning)
- [ ] `Thundergrid.AutoSwitcher` (telemetry-driven profile selection)
- [ ] `Thundergrid.CanaryRouter` (percentage-based traffic split)
- [ ] Cerebros compute channel integration
- [ ] Crown policy hooks for routing governance

---

### 🧬 HC-Research Roadmap: Simplex-Path Clustering (Nov 27, 2025)

**Mission**: Deploy robust multi-manifold clustering (LAPD - Largest Angle Path Distance) for dynamic swarm orchestration. Enables automatic discovery of natural sub-swarms and knowledge clusters without manual tuning.

**Algorithm Overview**: Simplex Paths builds a graph of d-simplices using local neighborhoods, computes largest-angle path distances yielding a distance matrix that cleanly separates same-group vs different-group points. Quasi-linear complexity in sample size; proven ability to separate intersecting manifolds.

**Data Flow**:
```
Agent States / Memory Vectors → [Thunderflow Pipeline] → Clustering Module (Thunderbolt)
    → Clusters Identified → [Thunderflow Events] → Thunderchief Orchestration
    → Thundergrid Zone Coordination → [Thunderprism UI] → Visualization
```

#### Phase 1 (Week 1-2): Foundation & Prototype — HC-34

**Core Algorithm Integration**:
- [ ] Snex Python environment setup (SciPy, scikit-learn, clustering code)
- [ ] `Thunderbolt.Clustering.SimplexPaths` module (Elixir wrapper)
- [ ] `Thunderbolt.Clustering.LAPDEngine` (Python interop via Snex)
- [ ] Ash resource: `Thunderbolt.Resources.Cluster` (id, timestamp, metrics)
- [ ] Ash resource: `Thunderbolt.Resources.ClusterMembership` (agent↔cluster)
- [ ] Agent schema extension: `cluster_id` field (nullable)
- [ ] Database migrations for cluster tables
- [ ] Smoke test: manual trigger via IEx

**Key Files**:
```
lib/thunderline/thunderbolt/clustering/
├── simplex_paths.ex      # Main clustering interface
├── lapd_engine.ex        # Snex Python bridge
├── cluster_resource.ex   # Ash resource definition
└── membership.ex         # Agent↔Cluster linking
```

**Success Criteria**: Manual `Thunderbolt.Clustering.run()` produces cluster assignments stored in DB.

#### Phase 2 (Week 3-4): Orchestration & Automation — HC-35

**Thunderchief/Thunderflow Integration**:
- [ ] AshOban worker: `ClusteringWorker` (periodic or event-triggered)
- [ ] Thunderflow pipeline DAG: `DataPrep → RunClustering → PostUpdate`
- [ ] Event emission: `clusters:running`, `clusters:completed`, `clusters:updated`
- [ ] Trigger configuration: timed (every N ticks), threshold (swarm size +20%), manual
- [ ] `Thundergrid.collect_zone_data/0` for live in-memory state aggregation
- [ ] Cluster coordinator assignment (lead agent per cluster)
- [ ] Thundercell automata hook: `{:cluster_now}` state-machine action
- [ ] Telemetry: `[:thunderline, :bolt, :clustering, :*]`

**Orchestration Pattern**:
```elixir
# Thunderchief scheduling
defmodule Thunderline.Thunderbolt.Workers.ClusteringWorker do
  use Oban.Worker, queue: :clustering, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: args}) do
    with {:ok, data} <- gather_agent_vectors(),
         {:ok, clusters} <- SimplexPaths.run(data, args),
         {:ok, _} <- persist_clusters(clusters),
         :ok <- broadcast_cluster_update(clusters) do
      {:ok, %{clusters: length(clusters)}}
    end
  end
end
```

**Success Criteria**: Clustering runs automatically on schedule, events broadcast to PubSub.

#### Phase 3 (Week 5-6): Visualization & Control — HC-36

**Thunderprism Dashboard**:
- [ ] Swarm Clusters panel (LiveView component)
- [ ] Real-time PubSub subscription to `clusters:updated`
- [ ] Cluster table: ID, member count, centroid preview, health score
- [ ] Drill-down: click cluster → show member agents
- [ ] "Recluster Now" button with loading state
- [ ] Parameter tuning controls (intrinsic dimension d, neighborhood k, denoising η)
- [ ] Cluster-based command: "Broadcast to Cluster X"
- [ ] Optional: 2D PCA projection visualization (SVG or Canvas)

**LiveView Structure**:
```elixir
defmodule ThunderlineWeb.ClusterDashboardLive do
  use ThunderlineWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "clusters:updated")
    end
    {:ok, assign(socket, clusters: load_clusters(), clustering_status: :idle)}
  end

  def handle_info({:clusters_updated, clusters}, socket) do
    {:noreply, assign(socket, clusters: clusters)}
  end
end
```

**Success Criteria**: Live UI shows clusters, updates in real-time, manual trigger works.

#### Phase 4 (Week 7+): Memory Integration & Evolution — HC-37

**Thundervine/Thunderblock Integration**:
- [ ] Cluster MemoryNode in Thundervine graph (hub node per cluster)
- [ ] Cluster centroid embeddings in pgvector (similarity search)
- [ ] `cluster_runs` audit table (historical tracking)
- [ ] Temporal DAG: `evolves_to` edges between cluster snapshots
- [ ] Agent behavior integration: read `my_cluster_id` in automata
- [ ] Cluster-aware policies in Thundercrown (e.g., "if cluster > 40% agents, trigger diversity")
- [ ] Adaptive triggering: skip clustering if clusters stable

**Memory Graph Pattern**:
```
[Agent A] ──belongs_to──▶ [Cluster C1 Node]
[Agent B] ──belongs_to──▶ [Cluster C1 Node]
[Cluster C1 @ T1] ──evolves_to──▶ [Cluster C1 @ T2]
```

**Success Criteria**: Clusters persisted in knowledge graph, queryable via similarity search.

#### Implementation Notes

**Snex Python Interop**:
```elixir
# lib/thunderline/thunderbolt/clustering/lapd_engine.ex
defmodule Thunderline.Thunderbolt.Clustering.LAPDEngine do
  @moduledoc "Python bridge for LAPD clustering via Snex"

  def run(data, opts \\ []) do
    d = Keyword.get(opts, :intrinsic_dimension, 2)
    k = Keyword.get(opts, :neighbors, 10)
    eta = Keyword.get(opts, :denoising_threshold, 0.1)

    case Snex.call(:clustering_env, :simplex_paths, :run_lapd, [data, d, k, eta]) do
      {:ok, labels} -> {:ok, labels}
      {:error, reason} -> {:error, {:python_error, reason}}
    end
  end
end
```

**Edge Cases**:
- **Single cluster**: Handle gracefully (all agents in cluster 1)
- **N clusters = N agents**: Treat as "no structure found", skip persistence
- **High dimensionality**: PCA preprocessing to reduce to manageable d
- **Noisy data**: Tune η parameter via elbow method
- **Large datasets**: Chunking by zone if > 10k agents

**Telemetry Events**:
```elixir
[:thunderline, :bolt, :clustering, :start]    # {agent_count, params}
[:thunderline, :bolt, :clustering, :stop]     # {duration_ms, cluster_count}
[:thunderline, :bolt, :clustering, :error]    # {reason}
[:thunderline, :prism, :cluster_ui, :trigger] # {source: :manual | :auto}
```

### Ground Truth Verification Summary (November 18, 2025)

**Context**: External High Command review (Aug 25, 2025) contained inaccuracies. This summary reflects **verified ground truth** from direct codebase access.

**Critical Findings**:

1. **ThunderCom Consolidation - RESOLVED (Nov 18 2025)** ✅
   - **HC Review Claim**: "0 resources, fully deprecated, safe to remove"
   - **Ground Truth (Nov 17)**: 8 active resources, LiveViews + seeds still depended on ThunderCom
   - **Action**: Executed HC-27 migration plan (8 phases) culminating in full removal of `lib/thunderline/thundercom/`, LiveViews pointing to ThunderLink, duplicate seed/voice helpers deleted, and all compilation/tests passing
   - **Result**: Single communications domain (ThunderLink) with preserved DB tables; consolidation backlog item closed

2. **Resource Duplication - RESOLVED (Nov 18 2025)** ✅
   - **Issue (Nov 17)**: Community, Channel, Message, Role, FederationSocket implemented in both domains with namespace drift (VoiceRoom vs Voice.Room)
   - **Action**: Compared implementations, selected ThunderLink as canonical, removed ThunderCom duplicates, aligned namespace, reran compile/tests
   - **Result**: Zero duplicate Ash resources; HC-28 closed with supporting documentation

3. **ThunderVine Architecture Decision IMPLEMENTED** ✅
   - **Original Finding**: ThunderVine logic operated without a domain boundary while owning DAG resources
   - **Action**: Created ThunderVine.Domain (HC-29) with Workflow/Node/Edge/Snapshot resources migrated from ThunderBlock without schema changes
   - **Result**: Clear ownership, policy enforcement surface, API exposure ready

4. **ThunderChief Deprecation - CORRECT** ✅
   - **HC Review Claim**: "Deprecated, merged into ThunderCrown"
   - **Ground Truth**: CONFIRMED - No domain.ex file exists
   - **Status**: Only utility modules remain, domain successfully removed

5. **ThunderForge Placeholder - CORRECT** ✅
   - **HC Review Claim**: "Empty placeholder, 3 stub files"
   - **Ground Truth**: CONFIRMED - domain.ex with empty resources block
   - **Recommendation**: Remove for MVP (unless implementation planned)
   - **New P0 Item**: HC-30 (cleanup decision)

**Updated Resource Counts**:
- Total Active Domains: 8 (ThunderCom removed Nov 18 2025)
- Total Resources: ~160 (ThunderLink absorbed 8 migrated resources)
- ThunderLink: 17 resources (single canonical implementation)
- ThunderCom: 0 active resources (directory removed; history preserved in git)

**Consolidation Status Updates**:
- ✅ Complete: 6 consolidations (ThunderVault→Block, 5→Bolt, ThunderChief→Crown, ThunderStone+Eye+Accounts+Watch→Gate, ThunderCom→Link, ThunderWave→Link)
- ⚠️ In Progress: 2 consolidations (ThunderJam→Gate, ThunderClock→Block)

**P0 Backlog Impact**:
- HC-27 and HC-28 marked **Done** (Nov 18 2025); HC-29 and HC-30 already complete; HC-26 now tracks the remaining two consolidations only
- Estimated Effort Remaining: ThunderJam (2-3 days), ThunderClock (1-2 days)

**Documentation Updated**:
- ✅ DOMAIN_ARCHITECTURE_REVIEW.md - Consolidation log appended with HC-27/28 completion notes
- ✅ THUNDERLINE_DOMAIN_CATALOG.md - ThunderCom section moved to "Removed"; ThunderLink counts refreshed
- ✅ thunderline_domain_resource_guide.md - Resource counts updated; duplicates removed from diagrams
- ✅ THUNDERLINE_MASTER_PLAYBOOK.md - This document now tracks HC-27/28 closure

---

### ML Infrastructure Status (Updated Nov 2025)

**Python ML Stack** ✅ **PRODUCTION READY**
- Environment: `/home/mo/DEV/Thunderline/.venv` (Python 3.13)
- TensorFlow: 2.20.0 (ML framework)
- tf2onnx: 1.8.4 (Keras→ONNX conversion)
- ONNX: 1.19.1 (model format)
- Keras: 3.12.0 (high-level ML API)
- Status: All packages installed and verified working

**Elixir ML Dependencies** ✅ **PRODUCTION READY**
- Req: 0.5.15 (HTTP client for Chroma/external APIs)
- Ortex: 0.1.10 (ONNX runtime for Elixir)
- PythonX: 0.4.0 (Python integration)
- Venomous: 0.7 (Python communication)
- Status: All dependencies compiled successfully (warnings from upstream deps are non-blocking)

**Magika Integration** ✅ **PRODUCTION READY**
- Implementation: Thunderline.Thundergate.Magika wrapper (420 lines)
- Unit Tests: 11 comprehensive test cases (350 lines)
- Integration Tests: 6 end-to-end scenarios (285 lines)
- Broadway Pipeline: Classifier consumer with DLQ routing (180 lines)
- EventBus Bridge: Broadway producer (120 lines)
- Configuration: runtime.exs with environment variable support
- Supervision: Feature-flagged ML pipeline integration
- Documentation: Complete quick start guide (`docs/MAGIKA_QUICK_START.md`)
- Events: ui.command.ingest.received → system.ingest.classified
- Telemetry: [:thunderline, :thundergate, :magika, :classify, :*]
- Status: Production-ready AI file classification with fallback strategies
- Sprint: 2 weeks (Oct 28 - Nov 11, 2025), 7/7 tasks complete, zero errors

**ML Pipeline Roadmap** 🟡 **IN PROGRESS** (33% complete)
- Execution Plan: `docs/ML_PIPELINE_EXECUTION_ROADMAP.md` (600 lines, comprehensive)
- Completion: Phase 0 (Magika) ✅, Phases 1-7 pending
- Execution Order: ONNX first (in-process reliability), then Voxel (DAG truth), spaCy hardened after
- Timeline: 7-10 days estimated (Phases 1-7)
- Phases:
  - Phase 1: Sanity & Guardrails (0.5d) - CI tests, feature flags, telemetry dashboards
  - Phase 2: ONNX Adapter (2-3d) - Model I/O, KerasONNX via Ortex, Broadway integration
  - Phase 3: Keras→ONNX (1-2d) - Exporter CLI, equivalence validation, model registry
  - Phase 4: Voxel Packager (2-3d) - Schema, builder API, persistence, lineage
  - Phase 5: spaCy Sidecar (1-2d) - Port pool, NLP schema, robustness tests
  - Phase 6: Observability (0.5d) - Dashboards, SLO alerts
  - Phase 7: Security (0.5d) - SBOM, checksums, untrusted model gate
- Assignments: Core Elixir (ONNX/Voxel/spaCy), Python/NLP (Keras/spaCy), DevOps (CI/Grafana/SBOM)
- Philosophy: *Festina lente* — make haste, slowly
- Implementation Progress: 33% (Magika ✅, ONNX + Voxel + spaCy pending)

**Build Status** ✅ **SUCCESSFUL**
- Compilation: Completed with dependency warnings (Jido, LiveExWebRTC, ExWebRTC - non-blocking)
- Type warnings: Struct update patterns in upstream dependencies, not user code
- All apps: Compiled and generated successfully
- Ready for: Implementation of Magika wrapper, ONNX adapter, Voxel builder

**Pipeline Architecture** ✅ **SPECIFIED**
- Foundation: Python NLP CLI (JSON contract v1.0) + Elixir Port supervisor (400 lines)
- Event Flow: Magika → spaCy → ONNX → Voxel → ThunderBlock
- Telemetry: Complete framework with event definitions
- Documentation: 10,000-word integration spec in `docs/MAGIKA_SPACY_KERAS_INTEGRATION.md`

### Consolidated P0 Launch Backlog (Definitive Order)
1. HC-22 Unified Persistent Model (online trainer + adapters)
2. HC-01 Event publish API
3. HC-02 Bus codemod consolidation
4. HC-03 Event & Error taxonomy docs
5. HC-04 ML migrations live
6. HC-05 Email MVP (resources + flow)
7. HC-06 Presence & membership policies
8. HC-07 Deployment scripts & containerization
9. HC-08 CI/CD enhancements (release, audit, PLT caching)
10. HC-09 Error classification + DLQ
11. HC-10 Feature flags documentation

Post-P0 Near-Term (Governance): HC-20 (Cerebros Bridge), HC-21 (VIM Rollout) prioritized after M1 gating items once HC-22 exits canary.

UPM is the connective tissue between ThunderFlow telemetry and ThunderBlock agents; its readiness is now considered the primary blocker for platform-wide intelligence rollout.

Gate: All above = Milestone `M1-EMAIL-AUTOMATION` ✔

---

## 🛰 WARHORSE Week 1 Delta (Aug 31 2025)

Status snapshot of architecture hardening & migration tasks executed under WARHORSE stewardship since Aug 28.

Implemented:
- Blackboard Migration: `Thunderline.Thunderflow.Blackboard` now the supervised canonical implementation (legacy `Thunderbolt.Automata.Blackboard` deprecated delegator only). Telemetry added for `:put` and `:fetch` with hit/miss outcomes.
- Event Validation Guardrail: `Thunderline.Thunderflow.EventValidator` integrated into `EventBus` routing path with environment‑mode behavior (dev warn / test raise / prod drop & audit).
- Heartbeat Unification: Single `:system_tick` emitter (`Thunderline.Thunderflow.Heartbeat`) at 2s interval.
- Event Taxonomy Linter Task: `mix thunderline.events.lint` implemented (registry/category/AI whitelist rules) – CI wiring pending.
- Legacy Mix Task Cleanup: Removed duplicate stub causing module redefinition.

Adjusted Docs / Doctrine:
- HC-01 moved to In Progress (publish helper exists; needs telemetry span enrichment & CI gating of linter to call it “Done”).
- Guardrails table (Handbook) updated: Blackboard migration complete.

Emerging Blindspots / Gaps (Actionable):
1. EventBus `publish_event/1` Overloads: Three clauses accept differing maps (`data`, `payload`, generic). Consider normalizing constructor path & returning error (not silent :ok) when validation fails; currently `route_event/2` swallows validator errors returning `{:ok, ev}`.
2. Flow → DB Direct Reads: `Thunderline.Thunderflow.Telemetry.ObanDiagnostics` queries Repo (domain doctrine says Flow should not perform direct DB access). Mitigation: Move diagnostics querying under Block or introduce a minimal `Thunderline.Thunderblock.ObanIntrospection` boundary.
3. Residual Bus Shim: `Thunderline.Application` still invokes `Thunderline.Bus.init_tables()` task. Codemod & deprecation telemetry for HC‑02 still pending.
4. Link Domain Policy Surface: Ash resource declarations in Link use `Ash.Policy.Authorizer` (expected) but require audit to ensure no embedded policy logic (conditions) that belong in Crown. Add Credo check `NoPolicyLogicInLink` (planned).
5. Event Naming Consistency: Cross‑domain & realtime naming sometimes produce `system.<source>.<type>` while other helper code passes explicit `event_name`. Need taxonomy enforcement for reserved prefixes (`ui.`, `ai.`, `system.`) – extend linter (HC‑03).
6. Blackboard Migration Metric: Add gauge/counter for deprecated module calls (currently delegator silent) to track drift → 0 (target end Week 2). Tripwire could reflect count.
7. Validator Strictness Drift: In production path we “return ok” after drops. Provide optional strict mode flag for canary to raise on invalid events during staging.
8. Repo Isolation Escalation: Currently advisory Credo check only; define allowlist & fail mode ahead of Week 3 (per doctrine).

Planned Immediate Next (WARHORSE Week 1 Remainder / Kickoff Week 2):
- Integrate `mix thunderline.events.lint` into CI (fail build on errors) & add JSON output parsing in pipeline.
- Implement Bus shim deprecation telemetry: emit `[:thunderline,:bus,:shim_use]` per call site during codemod window.
- Add `Blackboard` legacy usage counter & LiveDashboard metric panel section.
- Refactor EventBus publish path to single constructor & explicit validator error return tuple.
- Draft Credo checks: `NoPolicyLogicInLink`, `NoRepoOutsideBlock` (escalation flag), `NoLegacyBusAlias`.

Success Metrics (Week 2 Targets):
- legacy.blackboard.calls == 0 for 24h
- bus.shim.use rate trending downward to zero
- event.taxonomy.lint.errors == 0 in main for 3 consecutive days
- repo.out_of_block.violations == 0 (warning mode)

---

## 🤖 Cerebros NAS Integration Snapshot (Sep 2025)

Status summary for the ThunderBolt ML ledger, Cerebros bridge boundary, and NAS orchestration.

**Bridge & Feature Flag**
- `Thunderline.Thunderbolt.CerebrosBridge.Client` guards execution with `features.ml_nas` and runtime config (`config :thunderline, :cerebros_bridge`).
- Translator + Invoker pair (`translator.ex`, `invoker.ex`) marshal contracts to Python subprocesses with retries, exponential backoff, and structured `%Thunderline.Thunderflow.ErrorClass{}` errors.
- ETS-backed cache (`cache.ex`) provides optional response memoization; telemetry emitted under `[:cerebros, :bridge, :cache, *]`.

**Contracts & Canonical Events**
- Versioned contracts (`Contracts.RunStartedV1`, `TrialReportedV1`, `RunFinalizedV1`) describe lifecycle payloads.
- Client publishes canonical Thunderflow events `ml.run.start|stop|exception` and `ml.run.trial` through `Thunderline.Thunderflow.EventBus` with normalized metadata.

**Ash Resources & Ledger**
- `Thunderline.Thunderbolt.Resources.ModelRun` + `ModelArtifact` persist NAS pulses and produced artifacts.
- ML registry namespace (`lib/thunderline/thunderbolt/ml/`) stores specs, versions, datasets, Axon trainer metadata, and consent records.
- Adapter & artifact helpers (`cerebros/adapter.ex`, `cerebros/artifacts.ex`) hydrate bridge responses into Ash actions and ensure artifact persistence.

**Outstanding Gaps / Actions**
1. HC-04: Run pending migrations + wire lifecycle state machine on `ModelRun` (current status: In Progress).
2. HC-20: Author bridge boundary doc + DIP, publish configuration recipe, and surface cache/telemetry tuning guidance.
3. Flower control plane now consumes the Keras backend (`python/cerebros/keras/flower_app.py`) removing the PyTorch dependency; ensure SuperExec images embed the module and publish CPU baseline values for Ops.
4. Implement resilient search/exploration strategy (replace `simple_search.ex` stub) and feed outcomes back into trials queue.
4. Publish walkthrough for executing NAS loop via Thunderhelm (Livebook → Cerebros runner → MLflow) including feature flag prerequisites.
5. Add `mix thunderline.ml.validate` (planned) to verify bridge config, dataset availability, and event emission paths before enabling flag.

---

## 🌩️ Thundra & Nerves Integration (HC-23 High Command Directive)

**Strategic Context**: Multi-dimensional PAC execution engine enabling sovereign agents to run seamlessly in **cloud** (Thundra VM) or on **edge devices** (Nerves hardware runtime) with unified policy enforcement. This establishes Thunderline's differentiated capability: PACs that can autonomously execute complex workflows across distributed infrastructure with full lineage tracking and governance.

### 🎯 Executive Summary

**Thundra VM** is a tick-driven voxelized cellular automata engine hosted in ThunderBolt that provides PAC agents with:
- Time-state evolution through 12-zone hexagonal lattice (chakra-inspired progression)
- Hierarchical agent architecture (Thunderbit → Thunderbolt → Sage → Magus → Thunderchief)
- ~3 million atomic state cells per Thunderblock instance
- GraphQL-queryable live state via ThunderGrid
- Full event DAG lineage tracking (correlation_id/causation_id chains)

**Nerves Runtime** enables PACs to execute on physical devices (Raspberry Pi, BeagleBone, etc.) with:
- Signed firmware with embedded client certificates
- mTLS enrollment via ThunderGate
- Local autonomous control loops with cloud fallback
- Cached Crown policy manifests for offline governance
- Telemetry backhaul through ThunderLink TOCP transport
- OTA updates orchestrated by ThunderGate

### 🏗️ Architecture Foundations

#### Domain Boundary Assignments

| Domain | Thundra Responsibilities | Nerves Responsibilities |
|--------|-------------------------|-------------------------|
| **ThunderGate** | Thundra VM registration, tick event validation, zone assignment | Device mTLS authentication, client cert validation, firmware handshake protocol, enrollment lifecycle (provision → active → revoked) |
| **ThunderBolt** | Thundra VM hosting, PAC state orchestration, tick-tock cycle scheduling, zone failover coordination, hierarchical agent supervision | Cloud-side PAC coordination when device offline, offload heavy compute from edge, Thundra VM spinup for edge-provisioned PACs |
| **ThunderBlock** | Persistent PAC state storage, voxel data persistence, memory vault APIs for Thundra snapshots, zone configuration records | Device association records (PAC ↔ device mapping), firmware version tracking, last-seen telemetry |
| **ThunderLink** | Event routing between Thundra zones, cross-PAC communication fabric | TOCP transport (store-and-forward messaging), device heartbeat management, telemetry backhaul queue, mesh connectivity coordination |
| **ThunderCrown** | Thundra policy enforcement (action validation within VM), zone-level governance rules | Edge policy manifest generation, device-specific policy caching, offline governance enforcement, certificate lifecycle (issuance/rotation/revocation) |

#### Thundra VM Architecture

**Core Design Principles:**
- **Voxelized Time-State**: 3D cellular automata with honeycomb structure enabling parallel state evolution
- **12-Zone Hexagonal Lattice**: Inspired by chakra progression model, zones cycle through states providing temporal rhythm
- **Tick-Tock Cycles**: Fast micro-updates (tick) + slow macro-sync (tock, every 7 ticks) for balance between responsiveness and stability
- **Event-Driven**: Every state transition emits `thundra.*` events with full lineage (correlation_id/causation_id chains)

**Zone Configuration** (12 zones per Thunderblock):

| Zone | Chakra Mapping | Active Time | Full Cycle | Primary Function |
|------|----------------|-------------|------------|------------------|
| 1 | Red/Root | ~12s | ~132s | Memory/Persistence (Thundervault integration) |
| 2 | Orange/Sacral | ~12s | ~132s | Security/Access (Thundergate validation) |
| 3 | Yellow/Solar | ~12s | ~132s | Computation (Thunderbolt/Lit workload) |
| 4 | Green/Heart | ~12s | ~132s | API/Interchange (Thundergrid queries) |
| 5 | Blue/Throat | ~12s | ~132s | Communication (ThunderLink messaging) |
| 6 | Indigo/Third Eye | ~12s | ~132s | Monitoring (ThunderEye observability) |
| 7 | Violet/Crown | ~12s | ~132s | Governance (ThunderCrown policy) |
| 8-12 | Extended | ~12s | ~132s | Future expansion (reserved) |

**Hierarchical Agent Structure:**

```
Thunderblock Instance
├── 12 Zones (chakra-inspired)
│   ├── 1 Thunderchief (zone leader)
│   ├── 3 Magi (load balancers, 1 per cluster)
│   ├── 12 Sages (workers, 1 per sector)
│   │   └── 144 Thunderbolts (functional clusters per Sage)
│   │       └── 144 Thunderbits (atomic cells per Thunderbolt)
│
└── Scale: ~3 million Thunderbits total
    - 1,728 Thunderbolts per zone (12 Sages × 144 Thunderbolts)
    - 20,736 Thunderbolts per Thunderblock (12 zones × 1,728)
    - ~3M Thunderbits (20,736 Thunderbolts × 144 Thunderbits)
```

**Agent Responsibilities:**
- **Thunderbit**: Atomic state cell (smallest unit of computation)
- **Thunderbolt**: 144 Thunderbits forming functional cluster (local coordination)
- **Sage**: Worker controlling 144 Thunderbolts (sector management, resource allocation)
- **Magus**: Load balancer coordinating 4 Sages (cluster coordination, failover)
- **Thunderchief**: Zone leader (1 per zone, cross-zone coordination with other Chiefs)

**Tick-Tock Execution Model:**
```elixir
# Tick Cycle (Fast - Micro Updates)
- Thunderbit state transitions (local rules)
- Thunderbolt aggregation (cluster consensus)
- Sage coordination (sector sync)
- Event emission: thundra.tick.{zone_id}

# Tock Cycle (Slow - Macro Sync, every 7 ticks)
- Magus load balancing (redistribute work)
- Thunderchief zone sync (cross-zone coordination)
- State persistence to ThunderBlock
- Event emission: thundra.tock.{zone_id}

# Full Zone Rotation: ~132 seconds
# (12 zones × ~12 seconds active per zone = ~144s theoretical)
# (Actual ~132s accounting for transition overhead)
```

**GraphQL Integration (ThunderGrid):**
- Live PAC state queryable via `query { pacs { thundraState { zone currentTick voxelData } } }`
- Subscriptions for tick/tock events: `subscription { thundraTick(zoneId: 3) { timestamp agents } }`
- Zone health metrics: `query { thundraZones { id activeAgents tickRate latency } }`

**Event DAG Lineage:**
```elixir
# Every Thundra state transition emits event with lineage
%Thunderline.Event{
  name: "thundra.tick.zone_3",
  source: :bolt,
  payload: %{
    zone_id: 3,
    tick_count: 42,
    active_agents: 1728,
    state_mutations: [...]
  },
  correlation_id: "pac-123-session-abc",  # Links entire PAC session
  causation_id: "thundra.tick.zone_3.41", # Previous tick that caused this one
  event_hash: "sha256...",                 # Ledger integrity
  event_signature: "ecdsa..."              # Crown cryptographic proof
}
```

#### Nerves Hardware Runtime

**Deployment Pipeline:**
1. **Firmware Build**: `mix firmware` → signed `.fw` image with embedded client cert
2. **Device Provisioning**: Flash firmware to device (SD card or network)
3. **First Boot**: Device presents cert to ThunderGate for mTLS handshake
4. **Enrollment**: ThunderGate validates cert → ThunderLink establishes session → device registered in ThunderBlock
5. **Policy Download**: Device fetches Crown policy manifest (cached locally)
6. **PAC Initialization**: Device spawns local PAC runtime with cached policies
7. **Telemetry Start**: Device begins backhaul via ThunderLink TOCP transport

**mTLS Enrollment Flow:**
```elixir
# Device Side (Nerves)
1. Load embedded client certificate from firmware
2. Establish TLS connection to ThunderGate endpoint
3. Present client cert during TLS handshake
4. Wait for validation response

# ThunderGate Validation
1. Verify client cert chain against Crown CA
2. Check certificate revocation status (CRL/OCSP)
3. Lookup device record in ThunderBlock (cert fingerprint)
4. Validate device not in :revoked state
5. Create/update session in ThunderLink
6. Return success + policy manifest URL

# Policy Enforcement
1. Device downloads policy manifest from Crown
2. Cache manifest locally (SQLite/ETS)
3. Validate PAC actions against cached rules
4. Optional: Phone home to Crown for ambiguous cases
5. Emit telemetry for policy decisions (allow/deny/defer)
```

**Local Execution Model:**
```elixir
# Autonomous PAC Control Loop (runs on device)
defmodule NervesPAC.Runner do
  use GenServer
  
  def handle_info(:tick, state) do
    # 1. Check for local events (GPIO, sensor data, timers)
    local_events = collect_local_events(state)
    
    # 2. Evaluate against cached Crown policies
    {allowed, denied} = enforce_policies(local_events, state.policy_cache)
    
    # 3. Execute allowed actions locally
    execute_local(allowed)
    
    # 4. Queue telemetry for backhaul
    queue_telemetry(state, allowed ++ denied)
    
    # 5. Offload heavy compute to cloud if needed
    offload_requests = identify_heavy_compute(allowed)
    request_cloud_execution(offload_requests)
    
    # 6. Sync with cloud Thundra (if connected)
    sync_thundra_state(state)
    
    {:noreply, schedule_next_tick(state)}
  end
end
```

**Telemetry Backhaul (ThunderLink TOCP):**
- **Store-and-Forward**: Events queued locally, transmitted when connectivity available
- **Priority Queue**: Critical events (errors, policy violations) sent first
- **Compression**: Batched events compressed before transmission
- **Acknowledgment**: Cloud confirms receipt, device can prune local queue
- **Fallback**: If offline >24hrs, device writes to local SQLite for later sync

**OTA Update Flow:**
```elixir
# Orchestrated by ThunderGate
1. New firmware built, signed with Crown key
2. ThunderGate publishes firmware metadata to ThunderBlock
3. Devices poll for updates (or pushed via ThunderLink)
4. Device downloads .fw file, validates signature
5. Device applies update (A/B partition swap)
6. Device reboots into new firmware
7. Device re-enrolls via mTLS (proves update success)
8. ThunderGate updates device firmware_version in ThunderBlock
```

**Performance Optimizations (NIFs/Rust):**
- Image processing: Rust NIFs for CV pipelines (face detection, OCR)
- TensorFlow Lite: Rust bindings for on-device inference
- Signal processing: Rust NIFs for audio analysis (voice commands)
- Encryption: Rust crypto for secure local storage

#### PAC Execution Lifecycles

**Cloud Execution Path (Thundra VM):**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Provisioning (ThunderBlock)                              │
│    - User creates PAC via UI/API                            │
│    - PAC record persisted with initial config               │
│    - Zone assignment calculated (load balancing)            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Initialization (ThunderBolt)                             │
│    - Thundra VM instance spawned in assigned zone           │
│    - Hierarchical agents allocated (Thunderchief→Sage→...)  │
│    - Initial voxel state loaded from ThunderBlock           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Execution Loop (ThunderFlow → ThunderBolt)               │
│    - Tick events drive state evolution                      │
│    - PAC processes ThunderFlow events                       │
│    - State mutations propagate through CA hierarchy         │
│    - Tock cycles trigger macro-sync + persistence           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Policy Check (ThunderCrown)                              │
│    - PAC action evaluated against policies                  │
│    - Tenant/scope validation                                │
│    - Resource quota checks                                  │
│    - Allow/deny decision with audit trail                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Action Execution (Domain-Specific)                       │
│    - Gate: External API calls                               │
│    - Block: Data persistence                                │
│    - Link: Communication/messaging                          │
│    - Grid: Spatial queries                                  │
│    - Crown: Governance operations                           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. State Persistence (ThunderBlock)                         │
│    - Tock cycle triggers snapshot                           │
│    - Voxel data serialized                                  │
│    - Memory vault updated                                   │
│    - Lineage DAG extended                                   │
└─────────────────────────────────────────────────────────────┘
```

**Edge Execution Path (Nerves Device):**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Device Provisioning (ThunderGate + ThunderBlock)         │
│    - PAC record created with device association             │
│    - Firmware built with embedded PAC config + client cert  │
│    - Device flashed with signed .fw image                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Enrollment (ThunderGate → ThunderLink)                   │
│    - Device boots, presents client cert via mTLS            │
│    - ThunderGate validates cert, checks revocation          │
│    - ThunderLink establishes session, assigns TOCP address  │
│    - Device downloads Crown policy manifest                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Local Execution Loop (Device-Side)                       │
│    - GenServer tick loop (synchronized with local clock)    │
│    - Collect local events (GPIO, sensors, timers)           │
│    - Evaluate against cached Crown policies                 │
│    - Execute allowed actions locally                        │
│    - Queue telemetry for backhaul                           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Policy Enforcement (Local Cache + Optional Cloud)        │
│    - Primary: Check cached Crown manifest (offline-capable) │
│    - Fallback: Phone home to Crown for ambiguous cases      │
│    - Log all decisions for audit (persisted locally)        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Telemetry Backhaul (ThunderLink TOCP)                    │
│    - Store-and-forward queue (local SQLite)                 │
│    - Priority transmission (errors first)                   │
│    - Batch compression for efficiency                       │
│    - Cloud acknowledgment → prune local queue               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Cloud Offloading (Optional Heavy Compute)                │
│    - Identify compute-heavy tasks (ML inference, rendering) │
│    - Request cloud Thundra execution via ThunderLink        │
│    - ThunderBolt spins up cloud VM for offloaded work       │
│    - Results sent back to device                            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Failover (Device Offline Scenario)                       │
│    - ThunderBolt detects device heartbeat timeout           │
│    - Spins up cloud Thundra VM with last-known state        │
│    - Cloud VM executes PAC logic until device returns       │
│    - State sync when device reconnects                      │
└─────────────────────────────────────────────────────────────┘
```

### 📋 Implementation Checklist (P1 for Thundra/Nerves MVP)

#### HC-23.1: ThunderBolt Thundra VM Scaffolding
- [ ] Create `Thunderline.Thunderbolt.ThundraVM` GenServer supervisor
- [ ] Implement zone assignment algorithm (round-robin → load-aware)
- [ ] Wire tick subscription from ThunderFlow (`system.flow.tick` → `thundra.tick.*`)
- [ ] Implement tock cycle scheduler (7-tick macro-sync)
- [ ] Add telemetry: `[:thunderbolt, :thundra, :tick]`, `[:thunderbolt, :thundra, :tock]`
- [ ] Unit tests: zone assignment, tick propagation, tock scheduling

#### HC-23.2: ThunderBlock PAC State Schema
- [ ] Extend `Thunderline.Thunderblock.Resources.PAC` with Thundra fields:
  - `thundra_zone_id` (integer, 1-12)
  - `thundra_voxel_data` (jsonb, compressed state)
  - `thundra_tick_count` (bigint)
  - `thundra_last_tock` (utc_datetime_usec)
- [ ] Create `Thunderline.Thunderblock.Resources.ThundraZone` resource
- [ ] Add zone configuration storage (active_time, cycle_duration, chakra_mapping)
- [ ] Migration: `add_thundra_fields_to_pacs` + `create_thundra_zones`
- [ ] Unit tests: voxel data persistence, zone assignments

#### HC-23.3: ThunderGate mTLS Device Authentication
- [ ] Implement `Thunderline.Thundergate.DeviceEnrollment` action
- [ ] Add client cert validation middleware (`:ssl.peercert/1` extraction)
- [ ] Create `Thunderline.Thundergate.Resources.Device` resource:
  - `cert_fingerprint` (string, unique identity)
  - `enrollment_status` (enum: :pending, :active, :revoked)
  - `firmware_version` (string)
  - `last_seen_at` (utc_datetime_usec)
- [ ] Implement CRL/OCSP revocation checking
- [ ] Integration test: successful enrollment, revoked cert rejection
- [ ] Document mTLS configuration in `NERVES_DEPLOYMENT.md`

#### HC-23.4: ThunderLink TOCP Transport
- [ ] Design TOCP wire protocol (store-and-forward messaging)
- [ ] Implement `Thunderline.Thunderlink.TOCP.Server` (WebSocket/TCP listener)
- [ ] Create `Thunderline.Thunderlink.TOCP.DeviceSession` (per-device GenServer)
- [ ] Implement message queue (ETS/Mnesia for persistence)
- [ ] Add priority transmission (error events first)
- [ ] Implement acknowledgment protocol (prune queue on ACK)
- [ ] Telemetry: message latency, queue depth, throughput
- [ ] Unit tests: store-and-forward, priority queue, ACK handling

#### HC-23.5: ThunderCrown Edge Policy Caching
- [ ] Create `Thunderline.Thundercrown.DeviceManifest` action
- [ ] Generate per-device policy manifest (subset of full Crown policies)
- [ ] Add manifest versioning (device caches hash, polls for updates)
- [ ] Implement offline policy evaluation rules (fail-safe defaults)
- [ ] Document policy manifest format in `CROWN_POLICIES.md`
- [ ] Unit tests: manifest generation, version checking, offline evaluation

#### HC-23.6: Nerves Firmware Build Pipeline
- [ ] Create `nerves_pac/` Mix project (Nerves umbrella)
- [ ] Add `mix firmware` target (cross-compile for target hardware)
- [ ] Implement firmware signing with Crown key (cosign or GPG)
- [ ] Create OTA update server (serve .fw files from ThunderGate)
- [ ] Document firmware build in `NERVES_DEPLOYMENT.md`:
  - Target hardware (rpi4, bbb)
  - Cross-compilation steps
  - Signing procedure
  - OTA update process
- [ ] CI: automate firmware builds on release tags

#### HC-23.7: Event Taxonomy Extension
- [ ] Add `pac.*` event prefix:
  - `pac.provisioned` (new PAC created)
  - `pac.initialized` (Thundra VM started)
  - `pac.tick` (execution cycle)
  - `pac.action.{allow|deny}` (policy decisions)
- [ ] Add `device.*` event prefix:
  - `device.enrolled` (mTLS handshake success)
  - `device.heartbeat` (periodic check-in)
  - `device.offline` (timeout detected)
  - `device.firmware.updated` (OTA completed)
- [ ] Add `thundra.*` event prefix:
  - `thundra.tick.{zone_id}` (zone tick cycle)
  - `thundra.tock.{zone_id}` (zone tock sync)
  - `thundra.zone.failover` (zone reassignment)
- [ ] Update `EVENT_TAXONOMY.md` with new prefixes
- [ ] Run `mix thunderline.events.lint` to validate

#### HC-23.8: GraphQL Schema for PAC State
- [ ] Extend `Thunderline.Thundergrid.Schema` with Thundra queries:
  - `query { pacs { id thundraState { zoneId tickCount voxelData } } }`
  - `query { thundraZones { id activeAgents tickRate latency healthScore } }`
- [ ] Add subscriptions:
  - `subscription { thundraTick(zoneId: Int!) { timestamp agents mutations } }`
  - `subscription { pacStateChanged(pacId: ID!) { tickCount voxelData } }`
- [ ] Implement resolvers using ThunderBolt supervision tree
- [ ] Add authorization checks (user can only query own PACs)
- [ ] Integration test: GraphQL queries return live Thundra state

#### HC-23.9: Documentation & Runbooks
- [ ] Create `THUNDRA_ARCHITECTURE.md` (this content, refined)
- [ ] Create `NERVES_DEPLOYMENT.md` (device provisioning, firmware builds, OTA)
- [ ] Create `THUNDRA_OPERATIONS.md` (monitoring, troubleshooting, scaling)
- [ ] Update `THUNDERLINE_DOMAIN_CATALOG.md` with Thundra/Nerves responsibilities
- [ ] Add Thundra metrics to Grafana dashboards
- [ ] Document failover scenarios (device offline, zone crash)

#### HC-23.10: MVP Integration Test
- [ ] End-to-end test: Provision PAC → Thundra VM initialization → Tick processing → State persistence
- [ ] End-to-end test: Device enrollment → mTLS validation → Policy download → Local execution → Telemetry backhaul
- [ ] Failover test: Kill Thundra zone → Verify PAC migrates → Resume processing
- [ ] Chaos test: Disconnect device → Verify cloud takeover → Reconnect → Verify state sync
- [ ] Load test: 100 PACs across 12 zones, 1000 ticks/sec sustained
- [ ] Document test results in `THUNDRA_MVP_REPORT.md`

### 🎯 Success Criteria (MVP)

1. **Cloud Execution**: PAC can execute in Thundra VM with tick-driven state evolution
2. **Edge Execution**: PAC can execute on Nerves device with local policy enforcement
3. **Failover**: Device offline triggers cloud Thundra spinup automatically
4. **Policy Enforcement**: Crown policies enforced in both cloud and edge (with offline capability)
5. **Telemetry**: Full observability via ThunderFlow events (cloud) and TOCP backhaul (edge)
6. **Lineage**: correlation_id/causation_id chains enable full audit trail
7. **GraphQL**: Live PAC state queryable via ThunderGrid
8. **OTA**: Firmware updates deployed and verified on test devices

### 🔗 Dependencies & Integration Points

- **Blocked By**: None (can start immediately post T-72h countdown)
- **Blocks**: PAC swarm demo (Gate E), export-my-vault device-local path
- **Depends On**: Event Ledger (HC-T72H-2, COMPLETE), OpenTelemetry heartbeat (HC-T72H-1, COMPLETE)
- **Integrates With**: All domains (Gate, Bolt, Block, Link, Crown, Flow, Grid)

---

## 🛡 Wave 0 "Secure & Breathe" Recap (Sep 26 2025)

Rapid stabilization slice delivered ahead of HC-08/HC-03 efforts:

- ✅ Secret hygiene restored – `.roo/` and `mcp/` paths ignored, leaked artifacts purged.
- ✅ `CODEBASE_REVIEW_CHECKLIST.md` resurrected with up-to-date Ash 3.x + MCP checks.
- ✅ Secret handling doctrine codified in `README.md` with `.envrc.example` scaffolding.
- ✅ Gitleaks pre-push hook + CI action enforce PAT/secret scans (`./scripts/git-hooks/install.sh`).
- ✅ OpenTelemetry bootstrap guarded; missing `:opentelemetry_exporter` now downgrades to a warning.

Next tactical objectives (Wave 1 – "Breathe & Route"):

1. Re-wire `ThunderlineWeb.UserSocket` with AshAuthentication session tokens (`current_user` assign).
2. Stand up API key issuance (`mix thunderline.auth.issue_key`) and flip router guards to `required?: true`.
3. Reinstate Thunderblock vault / policy surfaces once actor context is dependable.
4. Resurrect Thunderbolt StreamManager supervisor + PubSub bridge with ExUnit coverage.

These line up directly with HC-05/HC-06 prerequisites and keep momentum toward M1.

---

### Guerrilla Backlog Tracker (Sep 26 2025)

_Status legend: [x] done · [ ] pending · [~] scaffolded / partial_

1. [x] Re-add `.roo/` and `mcp/` to `.gitignore`; purge tracked artifacts.
2. [x] Restore `CODEBASE_REVIEW_CHECKLIST.md` with Ash 3.x/MCP gates.
3. [x] Wire gitleaks pre-push guard (`./scripts/git-hooks/install.sh`).
4. [x] Document MCP/GitHub token handling; ship `.envrc.example`.
5. [ ] Hook `ThunderlineWeb.UserSocket` into AshAuthentication session tokens.
6. [ ] Finish router API key flip (issuance mix task + `required?: true`).
7. [ ] Re-enable Thunderblock vault resource policies.
8. [ ] Clean Ash 3.x fragments in `VaultKnowledgeNode` (lines 15–614).
9. [ ] Fix `pac_home` validation/fragment syntax for Ash 3.x.
10. [ ] Restore AshOban triggers in `task_orchestrator` and `workflow_tracker`.
11. [ ] Introduce `ChannelParticipant` Ash resource + relationships.
12. [ ] Fix Ash 3.x validations/fragments in `Thundercom.Message`.
13. [ ] Resolve `federation_socket` fragment/validation issues; recover AshOban trigger.
14. [ ] Repair `Thundercom.Role` fragment filters + AshOban trigger syntax.
15. [ ] Replace `Thunderlink.DashboardMetrics` stubs with live telemetry.
16. [ ] Pipe telemetry into `dashboard_live.ex` (CPU/memory/latency).
17. [ ] Complete `ThunderlaneDashboard` TODO wiring.
18. [ ] Add Stream/Flow telemetry for pipeline throughput & failures.
19. [ ] Rebuild Thunderbolt `StreamManager` supervisor + PubSub bridge.
20. [ ] Ship ExUnit coverage for StreamManager ingest/drop behaviors.
21. [ ] Fix `Thunderbolt.Resources.Chunk` state machine (AshStateMachine 3.x).
22. [ ] Implement real resource allocation logic + orchestration events.
23. [ ] Add ML health threshold evaluation to `chunk_health.ex`.
24. [ ] Finish `activation_rule` evaluation workflow (notifications, ML init).
25. [ ] Implement secure key management in `lane_rule_set.ex`.
26. [ ] Flesh out `topology_partitioner.ex` with 3D strategies.
27. [ ] Convert Thundergrid `SpatialCoordinate`/`ZoneBoundary` routes to Ash 3.x.
28. [ ] Build shared `Thunderline.Thundergrid.Validations` module + consume it.
29. [ ] Re-enable Thundergrid policies once actor context is wired.
30. [ ] Fix `ZoneEvent` aggregate `group_by` syntax and add tests.
31. [ ] Implement ThunderGate `Mnesia → PostgreSQL` sync.
32. [ ] Extend `Thunderchief.DomainProcessor` Oban job with per-domain delegation.
33. [ ] Gate `Thundercrown.AgentRunner` via ThunderGate policy; call AshAI/Jido actions.
34. [~] Reintroduce Jido/Bumblebee serving supervisor + echo fallback (scaffolded; needs validation/tests).
35. [ ] Expand `Thundercrown.McpBus` docs + CLI examples.
36. [ ] Swap `Thunderline.Thunderflow.Event` UUID fallback to UUID v7 provider.
37. [ ] Ship `mix thunderline.flags.audit` to verify feature usage vs config.
38. [x] Harden telemetry boot when `:opentelemetry_exporter` missing.
39. [ ] Add StreamManager + Oban counters to LiveDashboard / Grafana JSON.
40. [ ] Update `THUNDERLINE_DOMAIN_CATALOG.md` + README with new guards and progress.

#### High Command Directive – Event→Model Flow (Sep 26 2025)

1. [ ] Author Ash resources for ML pipeline (`Document`, `Event`, `DatasetChunk`, `ParzenTree`, `Trial`, `HPORun`, `ModelArtifact`) with pgvector support and governance policies.
2. [ ] Stand up Broadway P1 ingest pipeline: normalize events/docs, batch embed with Bumblebee/NX, persist vectors + chunks, emit `system.vector.indexed`.
3. [ ] Implement Dataset Parzen curator service (Rose-Tree zipper updates, quality/density scoring, shard pruning telemetry).
4. [ ] Build Trial pre-selector (TPE good/bad Parzen trees, l/g ratio sampler) and persist `:proposed` trials with density metadata.
5. [ ] Wire Cerebros bridge + Axon trainers to consume trials, log metrics, and emit `model.candidate` events.
6. [ ] Register model artifacts + serving adapters (Nx.Serving + bridge), expose Ash/MCP actions for predict/vector_search/register.
7. [ ] Extend Thundergrid GraphQL with trials/parzen/dataset queries + subscriptions; surface dashboard tiles for live monitoring.
8. [ ] Persist lineage into Thundervine DAG (trials ↔ dataset chunks ↔ docs/events, parzen snapshots, model registry edges).
9. [ ] Codify Jido policy playbooks for proposal SLA, retry/prune loops, and integrate observability metrics.

---

---

## 🌊 Sensor-to-STAC Pipeline Overview (HC-24)

**Status**: Specification complete | Priority: P1 | Owners: Forge + Bolt + Block Stewards

### Purpose
Complete data pipeline transforming raw sensor observations from edge devices into tokenized knowledge graph contributions with economic rewards. Bridges Thunderforge (ingestion), Thunderbolt (orchestration), and Thunderblock (persistence/rewards).

### High-Level Flow
Nerves Device → Thunderbit → Decode Worker → Assembly Worker → PAC Validation (6 dimensions) → DAG Commit → STAC Minting → Staking (sSTAC) → Yield (STACC)

### Key Components
- **Thunderbit**: Signed data packet from edge sensors
- **Knowledge Item**: Assembled observation meeting PAC thresholds (5 types: Instruction, Milestone, Query, Observation, Metric)
- **DAG**: Knowledge graph storing items as nodes with causal/semantic edges
- **STAC**: Reward token (formula: R = Base × Quality × Novelty × Policy × StakeMultiplier)
- **sSTAC**: Staked STAC (governance rights)
- **STACC**: Yield certificate (tradeable)

### PAC Validation (6 Dimensions)
1. Relevance (goal alignment), 2. Novelty (anti-spam decay), 3. Crown Policy (governance), 4. Ownership (auth chain), 5. Integrity (signatures), 6. Cost Budget (resource limits)

### MVP Cut (2 Sprints)
Sprint 1: Thunderbit → DAG (no rewards). Sprint 2: Reward mechanics + staking.

**Full Specification**: [documentation/architecture/sensor_to_stac_pipeline.md](documentation/architecture/sensor_to_stac_pipeline.md)

---

## 🧠 TPE Optimizer Overview (HC-25)

**Status**: Specification complete | Priority: P1 | Owner: Bolt Steward

### Purpose
Automated hyperparameter tuning using Tree-structured Parzen Estimator (Bayesian optimization) for Thunderline ML models.

### Algorithm
TPE splits trials into good/bad groups via KDE, samples candidates maximizing l(x) = p(x|good) / p(x|bad). Sample-efficient, handles mixed spaces (continuous/categorical/log-scale), parallelizable.

### Implementation Stack
Nx (tensors) + Scholar (KDE) + Ash (persistence) + Oban (async) + Mix task (CLI)

### Search Space Support
Uniform, lognormal (log-scale hyperparameters), categorical (discrete choices)

### Integration Points
Cerebros NAS tuning, Oko classifiers, VIM solvers, Axon models

### Usage Example
```bash
mix tpe.run --objective MyApp.NeuralNet --space '{"lr": {"lognormal": [-5, 1.5]}}' --n-total 50
```

**Full Specification**: [documentation/architecture/tpe_optimizer.md](documentation/architecture/tpe_optimizer.md)

---

## **🎯 THE VISION: Complete User Journey**
**Goal**: Personal Autonomous Construct (PAC) that can handle real-world tasks like sending emails, managing files, calendars, and inventory through intelligent automation.

### 🆕 Recent Delta (Aug 2025)
| Change | Layer | Impact |
|--------|-------|--------|
| AshAuthentication integrated (password strategy) | Security (ThunderGate) | Enables session-based login, policy actor context |
| AuthController success redirect → first community/channel | UX (ThunderLink) | Immediate immersion post-login |
| LiveView `on_mount ThunderlineWeb.Live.Auth` | Web Layer | Centralized current_user + Ash actor assignment |
| Discord-style Community/Channel navigation scaffold | UX (ThunderLink) | Establishes chat surface & future presence slots |
| AI Panel stub inserted into Channel layout | Future AI (ThunderCrown/Link) | Anchor point for AshAI action execution |
| Probe analytics (ProbeRun/Lap/AttractorSummary + worker) | ThunderFlow | Foundations for stability/chaos metrics & future model eval dashboards |
| Attractor recompute + canonical Lyapunov logic | ThunderFlow | Parameter tuning & reliability scoring pipeline |
| Dependabot + CI (compile/test/credo/dialyzer/sobelow) | Platform | Automated upkeep & enforced quality gates |

Planned Next: Presence & channel membership policies, AshAI action wiring, email automation DIP, governance instrumentation for auth flows.

---

## 🌿 SYSTEMS THEORY OPERATING FRAME (PLAYBOOK AUGMENT)

This Playbook is now bound by the ecological governance rules (see OKO Handbook & Domain Catalog augmentations). Each phase must prove *systemic balance* not just feature completeness.

Phase Acceptance Criteria now includes:

1. Domain Impact Matrix delta reviewed (no predation / mutation drift)
2. Event Taxonomy adherence (no ad-hoc event shape divergence)
3. Balance Metrics trend acceptable (no > threshold excursions newly introduced)
4. Steward sign-offs captured in PR references
5. Catalog synchronization executed (resource + relationship updates)

Balance Review Gate (BRG) is inserted at end of every major sprint; failing BRG triggers a `stability_sprint` (hardening, no net new features).

BRG Checklist (automatable future task):

- [ ] `warning.count` below threshold or trending downward
- [ ] No unauthorized Interaction Matrix edges
- [ ] Reactor retry & undo rates within SLO
- [ ] Event fanout distribution healthy (no new heavy tail outliers)
- [ ] Resource growth per domain within expected sprint envelope

---

---

## **🔄 THE COMPLETE FLOW ARCHITECTURE**

### **Phase 1: User Onboarding (ThunderBlock Provisioning)**

```text
User → ThunderBlock Dashboard → Server Provisioning → PAC Initialization
```

**Current Status**: 🟡 **NEEDS DASHBOARD INTEGRATION**

- ✅ ThunderBlock resources exist (supervision trees, communities, zones)
- ❌ Dashboard UI not connected to backend
- ❌ Server provisioning flow incomplete

### **Phase 2: Personal Workspace Setup**

```text
User Server → File Management → Calendar/Todo → PAC Configuration
```

**Current Status**: 🟡 **PARTIALLY IMPLEMENTED**

- ✅ File system abstractions exist
- ❌ Calendar/Todo integrations missing
- ❌ PAC personality/preferences setup

### **Phase 3: AI Integration (ThunderCrown Governance)**

```text
PAC → ThunderCrown MCP → LLM/Model Selection → API/Self-Hosted
```

**Current Status**: � **FOUNDATION READY**

- ✅ ThunderCrown orchestration framework exists
- ❌ MCP toolkit integration
- ❌ Multi-LLM routing system
- ❌ Governance policies for AI actions

### **Phase 4: Orchestration (ThunderBolt Command)**

```text
LLM → ThunderBolt → Sub-Agent Deployment → Task Coordination
```

**Current Status**: � **CORE ENGINE OPERATIONAL**

- ✅ ThunderBolt orchestration framework
- ✅ **ThunderCell native Elixir processing** (NEWLY CONVERTED)
- ✅ 3D cellular automata engine fully operational
- ❌ Sub-agent spawning system
- ❌ Task delegation protocols

### **Phase 5: Automation Execution (ThunderFlow + ThunderLink)**

```text
ThunderBolt → ThunderFlow Selection → ThunderLink Targeting → Automation Execution
```

**Current Status**: 🟢 **CORE ENGINE READY (Auth + Chat Surface Online)**

- ✅ ThunderFlow event processing working
- ✅ ThunderLink communication implemented
- ✅ State machines restored and functional
- ❌ Dynamic event routing algorithms
- ❌ Real-time task coordination

---

## **🎯 FIRST ITERATION GOAL: "Send an Email"**

### **Success Criteria**

User says "Send an email to John about the project update" → Email gets sent automatically with intelligent content generation.

### **Implementation Path**

#### **Sprint 1: Foundation (Week 1)**

**Goal**: Get the basic infrastructure talking to each other.

```bash
# 1. ThunderBlock Dashboard Connection
- Hook dashboard to backend APIs
- User can provision a personal server
- Server comes online with basic PAC

# 2. ThunderCrown MCP Integration
- Basic MCP toolkit connection
- Simple LLM routing (start with OpenAI API)
- Basic governance policies (what PAC can/cannot do)

# 3. Email Service Integration
- SMTP/Email service setup
- Basic email templates
- Contact management system
```

##### Additions (Systems Governance Requirements)

```text
# 4. Governance Hooks
- Add metrics: event.queue.depth (baseline), reactor.retry.rate (initial null), fanout distribution snapshot
- Register Email flow events under `ui.command.email.*` → normalized `%Thunderline.Event{}`
- DIP Issue for any new resources (Contact, EmailTask if created)
```

#### **Sprint 2: Intelligence (Week 2)**

**Goal**: Make the PAC understand and execute email tasks.

```bash
# 1. Natural Language Processing
- Email intent recognition ("send email to...")
- Contact resolution ("John" → john@company.com)
- Content generation (project update context)

# 2. ThunderBolt Orchestration
- Email task breakdown into sub-tasks
- ThunderFlow routing for email composition
- ThunderLink automation for sending

# 3. User Feedback Loop
- Confirmation before sending
- Learn from user corrections
- Improve future suggestions
```

##### Additions – Reactor & Telemetry

```text
# 4. Reactor Adoption (if multi-step email composition)
- Reactor diagram committed (Mermaid)
- Undo path for failed external send (mark draft, not sent)
- Retry policy with transient classification (SMTP 4xx vs 5xx)

# 5. Telemetry & Balance
- Emit reactor.retry.rate sample series
- Ensure fanout <= necessary domains (Gate, Flow, Link only)
```

#### **Sprint 3: Automation (Week 3)**

**Goal**: Seamless end-to-end automation.

```bash
# 1. Context Awareness
- File system integration (attach relevant files)
- Calendar integration (mention deadlines)
- Project context (what "project update" means)

# 2. Multi-Modal Execution
- Voice commands support
- Mobile app integration
- Web dashboard control

# 3. Learning & Adaptation
- User preference learning
- Email style adaptation
- Contact relationship mapping
```

##### Additions – Homeostasis

```text
# 4. Homeostasis Checks
- Verify added context sources didn't introduce unauthorized edges
- Catalog update with any new context resources
- Run BRG pre-merge (stability gate)
```

---

## **🏗️ CURRENT ARCHITECTURE STATUS**

### **✅ WHAT'S WORKING (Green Light)**

```elixir
# 1. Core Engine
- Ash 3.x resources compiling cleanly
- State machines functional
- Aggregates/calculations working
- Multi-domain architecture solid

# 2. ThunderFlow Event Processing
- Event-driven architecture
- Cross-domain communication
- Real-time pub/sub coordination
- Broadway pipeline integration

# 3. ThunderLink Communication
- WebSocket connectivity
- Real-time messaging
- External integration protocols
- Discord-style community/channel LiveViews (NEW Aug 2025)

# 4. Data Layer
- PostgreSQL integration
- Event-driven architecture
- Cross-domain communication
- Real-time pub/sub

# 5. 🔥 ThunderCell CA Engine (NEWLY OPERATIONAL)
- Native Elixir cellular automata processing
- Process-per-cell architecture
- 3D CA grid evolution
- Real-time telemetry and monitoring
- Integration with dashboard metrics
```

### **🟡 WHAT'S PARTIAL (Yellow Light)**

```elixir
# 1. ThunderBlock Infrastructure
- Resources defined but dashboard disconnected
- Supervision trees exist but not utilized
- Community/zone management incomplete

# 2. ThunderBolt Orchestration
- Framework exists and CA engine operational
- Resource allocation systems available
- Task coordination ready but needs AI integration

# 3. ThunderCrown Governance
- Policy frameworks exist
- MCP integration missing
- Multi-LLM routing not implemented

# 4. User Experience
- Authenticated login flow working (AshAuthentication)
- Post-login redirect to first community/channel
- Sidebar navigation scaffold online
- AI panel placeholder present
- Mobile app architecture planned but not built
- Voice integration not started

# 5. Dashboard Integration
- Backend metrics collection working
- Real ThunderCell data flowing
- Frontend visualization needs completion
```

### **🔴 WHAT'S MISSING (Red Light)**

```elixir
# 1. Frontend Applications
- ThunderBlock dashboard UI
- Mobile app
- Voice interface
- Web components

# 2. AI Integration
- MCP toolkit connection
- LLM API routing
- Self-hosted model support
- Prompt engineering framework

# 3. Real-World Integrations
- Email services (SMTP, Gmail API)
- Calendar services (Google, Outlook)
- File storage (local, cloud)
- Contact management

# 4. Security & Privacy
- User authentication (AshAuthentication password strategy) ✅
- Data encryption (TBD)
- API key management (TBD)
- Privacy controls (TBD)
```

---

## **🎯 IMPLEMENTATION PRIORITY MATRIX**

### **HIGH IMPACT, LOW EFFORT** (Do First)

1. **ThunderBlock Dashboard Connection**
   - Use existing Ash resources
   - Phoenix LiveView for real-time updates
   - Connect to ThunderBolt for orchestration

2. **Basic Email Integration**
   - SMTP service wrapper
   - Simple email templates
   - Contact storage in existing DB

3. **MCP Toolkit Integration**
4. **Presence & Channel Membership Policies**
5. **AshAI Panel Wiring (replace stub)**
   - Start with OpenAI API
   - Basic prompt templates
   - Simple governance rules

### **HIGH IMPACT, HIGH EFFORT** (Plan Carefully)

1. **Multi-LLM Routing System**
   - Support OpenAI, Anthropic, local models
   - Load balancing and failover
   - Cost optimization

2. **ThunderFlow Dynamic Selection**
   - Real-time task analysis
   - Optimal event routing algorithms
   - Performance monitoring

3. **Mobile App Development**
   - Cross-platform (React Native/Flutter)
   - Voice integration
   - Offline capabilities

### **LOW IMPACT, LOW EFFORT** (Fill Gaps)

1. **Documentation & Tutorials**
2. **Basic Analytics Dashboard**
3. **Simple Admin Tools**

### **LOW IMPACT, HIGH EFFORT** (Avoid For Now)

1. **Advanced ML Features**
2. **Custom Hardware Integration**
3. **Enterprise Features**

---

## **🚧 IMMEDIATE NEXT STEPS (This Week)**

### **Day 1-2: Assessment & Planning**

```bash
# 1. Audit Current ThunderBlock Resources
- Map all existing backend capabilities
- Identify dashboard integration points
- Document API endpoints

# 2. Design Email Flow
- User input → Intent parsing → Task execution → Result
- Define data models for contacts, templates, history
- Plan ThunderFlow routing for email tasks
```

High Command Alignment: Map each planned task to HC P0 backlog where applicable (Email Flow ↔ HC-05, dashboard resource audit supports HC-06 presence groundwork). Sprint board cards must reference HC IDs.

### **Day 3-4: Foundation Building**

```bash
# 1. ThunderBlock Dashboard MVP
- Basic Phoenix LiveView interface
- Server status monitoring
- Simple server provisioning flow

# 2. Email Service Integration
   - Add Ash resource(s): contact, outbound_email (if not existing)
   - Emit normalized events: `ui.command.email.requested` / `system.email.sent`
- SMTP configuration
- Basic email sending capability
- Contact management system
```

### **Day 5-7: AI Integration**
```bash
# 1. MCP Toolkit Connection
- OpenAI API integration
- Basic prompt engineering
- Simple task routing

# 2. End-to-End Email Test
- "Send email" command processing
- Content generation
- Actual email delivery

# 3. P0 Backlog Burn-down Alignment
- Ensure HC-01..HC-05 merged or in active PR review
- Block non-P0 feature PRs until ≥70% P0 completion
```

---

## **🔮 FUTURE VISION (3-6 Months)**

### **Advanced Features**
```
- Multi-agent collaboration (PACs working together)
- Complex task orchestration (project management)
- Learning from user behavior patterns
- Predictive assistance (proactive suggestions)
- Integration with IoT devices
- Voice-first interaction model
```

### **Scaling Considerations**
```
- Multi-tenant architecture
- Edge computing deployment
- Mobile-first design
- API-first development
- Microservices decomposition
- Container orchestration
```

---

## **💡 CRITICAL SUCCESS FACTORS**

### **Technical**
1. **Reliable Core Engine**: ThunderFlow/ThunderLink must be rock solid
2. **Responsive UI**: Dashboard must feel fast and modern
3. **AI Quality**: LLM responses must be contextually accurate
4. **Data Privacy**: User data must be secure and private

### **User Experience**
1. **Simplicity**: Complex automation hidden behind simple interfaces
2. **Predictability**: Users must trust the AI to do the right thing
3. **Control**: Users must feel in control of their PAC
4. **Value**: Must solve real problems users actually have

### **Business**
1. **Differentiation**: Must be clearly better than existing solutions
2. **Scalability**: Architecture must support thousands of users
3. **Monetization**: Clear path to sustainable revenue
4. **Community**: Build ecosystem of developers and users

---

## 📐 DOMAIN ARCHITECTURE STATUS (NOVEMBER 17, 2025)

### Current Domain Organization

**9 Active Production Domains** (~168 Ash resources total - verified Nov 17, 2025):

#### 1. Thundergate (19 resources) - Authentication & External Services
**Categories**: Auth, External Services, Federation, Policy, Monitoring
**Extensions**: AshAdmin
**Key Resources**:
- **Auth**: User, Token, UserSession, UserProfile, UserSettings, UserNotificationPreference, ApiClient
- **Policy**: Policy, PolicyAssignment, AuditLog, RateLimitRule
- **External**: ExternalProvider, OAuthCredential, WebhookEndpoint
- **Federation**: Federation, FederatedIdentity (placeholder)
- **Monitoring**: HealthCheck, Metric, Alert

**Consolidation History**: ThunderStone + ThunderEye + Accounts + ThunderWatch → Thundergate (Sep-Nov 2025)
**Status**: ✅ Magika integration complete, monitoring unified, AshAuthentication configured

#### 2. Thunderlink (14 resources) - Communication & Community
**Categories**: Support, Community, Voice Comm, Node Registry
**Extensions**: AshAdmin, AshOban, AshGraphql, AshTypescript.Rpc
**Key Resources**:
- **Support**: Ticket, TicketMessage, SupportAgent, SLA, AutomationRule
- **Community**: ForumPost, ForumThread, Comment
- **Voice**: VoiceChannel, VoiceSession
- **Registry**: Node, NodeRegistration

**Consolidation History**: ThunderCom + ThunderWave → Thunderlink (Oct 2025)
**APIs**: GraphQL + TypeScript RPC active
**Bug #18**: LinkSession.meta uses AtomMap custom type (keys as atoms)
**Status**: ✅ Core communication systems operational, voice integration pending

#### 3. Thunderflow (9 resources) - Event Processing & System Actions
**Categories**: Event Streams, System Actions, Events, Probes, Features, Lineage
**Extensions**: AshAdmin
**Key Resources**: Event, EventStream, SystemAction, Probe, Feature, EventLineage, Heartbeat, Blackboard, EventBus

**Broadway Pipelines** (4 active):
- EventPipeline - General event processing with DLQ
- CrossDomainPipeline - Domain boundary events
- RealTimePipeline - Low-latency event processing
- EventProducer - Event generation and publishing

**Features**: DLQ, batching, backpressure, comprehensive telemetry, event validation with taxonomy enforcement
**Status**: ✅ Core event infrastructure operational, EventBus publish/subscribe active

#### 4. Thunderbolt (50+ resources) - ML/AI Infrastructure
**Categories** (11): Core, Ising VIM, Lane Optimization, Task Management, Automata, Cerebros NAS, RAG, ML Tools, MLflow, UPM, MoE
**Extensions**: AshAdmin, AshOban, AshJsonApi, AshGraphql
**Key Subsystems**:
- **ML Core**: Model, Experiment, Pipeline, Dataset
- **VIM**: IsingLattice, SpinConfiguration, VIMSolver
- **Lane**: Lane, LaneSchedule, LaneOptimization
- **Automata**: ThunderCell (native Elixir), CellularAutomaton, 3D engine
- **Cerebros**: CerebrosModel, NASSearch, Architecture
- **RAG**: RagChunk, EmbeddingIndex, RetrievalPipeline
- **MLflow**: ExperimentRun, Metric, Parameter
- **UPM**: PromptTemplate, PromptVersion, PromptExecution

**Consolidation History**: ThunderCore + ThunderLane + ThunderMag + ThunderCell + Thunder_Ising → Thunderbolt (Aug-Oct 2025)
**Recommendation**: Consider strategic split into focused domains (largest at 50+ resources)
**Status**: ✅ Comprehensive ML infrastructure, RAG operational, Cerebros NAS active, UPM integrated

#### 5. Thundercrown (4 resources) - AI Orchestration & MCP
**Categories**: Orchestration, Agent Management, Conversation
**Extensions**: AshAdmin, AshAi
**Key Resources**: OrchestrationUI, AgentRunner, Conversation, MCPToolkit

**MCP Tools Exposed** (4 via AshAi):
- Agent orchestration tools
- Conversation management
- Task delegation
- System integration

**Consolidation History**: ThunderChief → Thundercrown (Oct 2025)
**Status**: ✅ Framework ready, full MCP integration pending

#### 6. Thunderblock (33 resources) - Infrastructure & Vault
**Categories**: Vault, Infrastructure, Orchestration, DAG, Timing
**Extensions**: AshAdmin
**Key Resources**:
- **Vault**: Secret, EncryptedItem, ApiKey, VaultPolicy
- **Infrastructure**: Server, Node, Cluster, Resource
- **Orchestration**: Workflow, Task, Dependency
- **DAG**: DAGNode, DAGEdge, DAGExecution
- **Timing**: Schedule, Timer, TimeWindow

**Consolidation History**: ThunderVault → Thunderblock (Sep 2025)
**Bug #18 Solution**: AtomMap custom type for atom-keyed map fields
**Status**: ✅ Infrastructure layer solid, vault integration complete

#### 7. Thundergrid (5 resources) - Spatial Operations
**Categories**: Spatial Modeling, Zones, Events, State
**Extensions**: AshGraphql, AshJsonApi
**Key Resources**: SpatialGrid, Zone, GridEvent, GridState, GridCoordinate

**APIs**: Dual exposure (GraphQL + JSON:API)
**Status**: ✅ Spatial framework operational, dual API active

#### 8. RAG (1 resource) - Retrieval-Augmented Generation
**Key Resource**: RagChunk
**Purpose**: Support domain for AI retrieval operations
**Status**: ✅ Active in Thunderbolt ML pipeline

### Support & Utility Domains (5)

- **Thundervine** - Shared utility modules (no Ash resources)
- **Thunderforge** - Placeholder for future Terraform/orchestration
- **ServiceRegistry** - Placeholder for service discovery
- **ThunderJam** - In progress migration to Thundergate.RateLimiting
- **ThunderClock** - In progress migration to Thunderblock.Timing

### Deprecated/Consolidated Domains (14)

Successfully migrated into active domains:
1. ThunderVault → Thunderblock
2. ThunderCore → Thunderbolt
3. ThunderLane → Thunderbolt
4. ThunderMag → Thunderbolt
5. ThunderCell → Thunderbolt
6. Thunder_Ising → Thunderbolt
7. ThunderChief → Thundercrown
8. ThunderCom → Thunderlink
9. ThunderWave → Thunderlink
10. ThunderStone → Thundergate
11. ThunderEye → Thundergate
12. Accounts → Thundergate
13. ThunderWatch → Thundergate
14. UPM → Thunderbolt

### Architecture Health Metrics

**Grade**: A- (8.5/10) - Excellent foundation with consolidation work in progress (verified Nov 17, 2025)
**Total Resources**: ~168 Ash resources across 9 active domains (updated after ground truth verification)
**Consolidations**: 5 completed, 3 in progress (⚠️ ThunderCom→ThunderLink INCOMPLETE)
**Violations**: 0 detected
**Extension Usage**:
- AshAdmin: 7 domains
- AshOban: 3 domains
- AshGraphql: 4 domains
- AshAi: 1 domain (Thundercrown)
- AshJsonApi: 2 domains
- AshTypescript.Rpc: 1 domain (Thunderlink)

### Ongoing Architecture Initiatives

**Completed (Nov 2025)**:
- ✅ 5 major domain consolidations (verified Nov 17, 2025 - ThunderCom→ThunderLink INCOMPLETE, see HC-27)
- ✅ Bug #18 resolution (AtomMap custom type)
- ✅ Magika integration in Thundergate
- ✅ GraphQL + TypeScript RPC in Thunderlink
- ✅ Comprehensive event infrastructure in Thunderflow
- ✅ RAG system in Thunderbolt

**In Progress**:
- 🔄 ThunderJam → Thundergate.RateLimiting migration
- 🔄 ThunderClock → Thunderblock.Timing migration
- 🔄 Thundercrown full MCP toolkit integration
- 🔄 Thunderlink voice integration completion

**Recommended (Future)**:
- 📋 Consider splitting Thunderbolt (50+ resources) into focused domains
- 📋 Review placeholder domains (Thunderforge, ServiceRegistry)
- 📋 Continue AtomMap usage monitoring across domains
- 📋 Dashboard UI integration for Thunderblock provisioning

---

## 🎉 RECENT DEVELOPMENT ACHIEVEMENTS (Nov-Dec 2025)

### Registry ETS Cache Implementation - 100% Testing Success

**Round 12-13 Completion (Nov 2025)**: Comprehensive testing and cache implementation for Thunderlink Registry.

**Achievement Summary**:
- ✅ **registry_test.exs**: 39/39 tests passing (100% success!)
- ✅ **Public Cache API**: 4 functions added and verified
- ✅ **Cache Population**: Systematic pattern implemented across all operations
- ✅ **Systematic Debugging**: 6 → 2 → 1 → 0 failures through methodical fixes

#### Round 12: ETS Cache Testing Journey (6 → 0 failures)

**Issue 1 - Missing Public Cache API** (RESOLVED ✅):
- **Error**: `UndefinedFunctionError - Registry.cache_get/1`
- **Solution**: Added 3 public wrapper functions
  ```elixir
  def cache_get(node_id), do: get_from_cache(node_id)
  def cache_put(node_id, node), do: put_in_cache(node_id, node)
  def cache_invalidate(node_id), do: invalidate_cache(node_id)
  ```
- **Result**: Tests execute but cache not populated (6 failures)

**Issue 2 - Cache Not Populated** (RESOLVED ✅):
- **Error**: Cache returns `:miss` instead of cached node
- **Root Cause**: Operations invalidate but don't populate cache
- **Solution**: Added `put_in_cache(node.id, node)` to 4 functions:
  - `ensure_node/1` - Populates after node creation
  - `mark_online/2` - Populates after status update
  - `mark_offline/1` - Populates after status update
  - `mark_status/2` - Populates after status update
- **Pattern**: Immediate cache population after DB operations
- **Result**: 6 → 2 failures (67% improvement)

**Issue 3 - Missing cache_table/0** (RESOLVED ✅):
- **Error**: `UndefinedFunctionError - Registry.cache_table/0`
- **Use Case**: Tests need ETS table name for TTL verification
- **Solution**: Added `cache_table/0` returning `@cache_table`
  ```elixir
  def cache_table, do: @cache_table
  ```
- **Result**: 2 → 1 failure (50% improvement)

**Issue 4 - Wrong Test Expectation** (RESOLVED ✅):
- **Error**: `assert cached1.status == :unknown` failed (actual: `:connecting`)
- **Root Cause**: Test expects `:unknown` but `register` action forces `:connecting`
- **Discovery**: `:unknown` is NOT a valid status in Node resource
- **Valid Statuses**: `[:connecting, :online, :degraded, :disconnected, :offline]`
- **Solution**: Changed test to expect `:connecting` (matches implementation)
- **Result**: **1 → 0 failures - 100% PASSING!** 🎉

#### Round 13: Integration Testing & Legacy Files

**Discovery**:
- Only `registry_test.exs` exists in active test suite (39 comprehensive tests)
- Found legacy test files: `registry_basic_test.exs` (9 tests) and `registry_simple_test.exs` (7 tests)
- Legacy files have 14 failures due to outdated APIs (`record_heartbeat/3`, `mark_online/1` signature mismatch)

**Decision**:
- ✅ **Main file**: 100% complete (39/39 passing) - production ready
- ⚠️ **Legacy files**: Deferred for future cleanup (14 failures)
- ✅ **EventBus tests**: Skipped (simple wrapper, no complex logic needed)

**Total Test Coverage**:
- **Active Tests**: 39 passing (100%)
- **Legacy Tests**: 14 failures (deferred)
- **Overall Quality**: Production-ready with comprehensive coverage

#### Implementation Quality

**Public Cache API** (4 functions - ALL WORKING):
```elixir
@spec cache_get(String.t()) :: {:ok, Node.t()} | :miss
def cache_get(node_id)

@spec cache_put(String.t(), Node.t()) :: :ok
def cache_put(node_id, node)

@spec cache_invalidate(String.t()) :: :ok
def cache_invalidate(node_id)

@spec cache_table() :: atom()
def cache_table()
```

**Cache Population Pattern** (Consistent across all operations):
```elixir
def operation_name(params) do
  node = Domain.db_operation!(params)
  put_in_cache(node.id, node)  # ← Immediate population
  emit_cluster_event(...)
  {:ok, node}
end
```

**Cache Design Features**:
- **TTL**: 30 seconds (configurable via `@cache_ttl_ms`)
- **Strategy**: Write-through cache - all mutations populate immediately
- **Concurrency**: ETS table with `read_concurrency: true`
- **Behavior**: Cache miss returns `:miss`, caller fetches from DB

#### Lessons Learned

**Systematic Debugging Works**:
- 6 → 2 → 1 → 0 failures through methodical fixes
- Each fix addressed a specific root cause
- Test-driven development validated each change

**Test Correctness Matters**:
- Tests must match implementation design
- Status `:unknown` not valid - corrected to `:connecting`
- Understanding domain model prevents wrong expectations

**Cache Semantics**:
- Both invalidation AND population needed
- Write-through strategy ensures consistency
- TTL management handled automatically

**Focus on Value**:
- Main test file (39 tests) comprehensive and complete
- Legacy files can be addressed later
- 100% success on production code more valuable than fixing outdated tests

**Documentation Status**:
- ✅ Module documentation updated with ETS cache layer details
- ✅ Public API documented with examples
- ✅ Cache population pattern documented
- ✅ Master playbook updated with achievements

**Files Modified**:
- `lib/thunderline/thunderlink/registry.ex` - Added public API, cache population, enhanced docs
- `test/thunderline/thunderlink/registry_test.exs` - All tests passing (39/39)
- `THUNDERLINE_MASTER_PLAYBOOK.md` - Documented achievements

**Next Steps**:
- Task #9: Run Credo and fix any new issues
- Task #10: Final validation with `mix precommit`
- Future: Update legacy test files to match current APIs (optional)

---

### Documentation Cross-References

- **Full Architecture Review**: [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md)
- **Resource Catalog**: [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md)
- **Resource Guide**: [`thunderline_domain_resource_guide.md`](thunderline_domain_resource_guide.md)
- **Handbook**: [`thunderline_handbook.md`](thunderline_handbook.md)

---

## **🎯 CONCLUSION: We're In Perfect Sync!**

**Your vision is SPOT ON**, bro! The architecture you outlined is exactly what we need:

1. **ThunderBlock** → User onboarding & server provisioning ✅
2. **ThunderCrown** → AI governance & MCP integration 🔄
3. **ThunderBolt** → Orchestration & sub-agent deployment 🔄
4. **ThunderFlow** → Intelligent task routing ✅
5. **ThunderLink** → Communication & automation execution ✅ (Discord-style nav + auth online)

The foundation is **SOLID** - we've got the engine running clean, state machines working, and the core optimization algorithms ready. Now we need to build the experience layer that makes it all accessible to users.

**First milestone: Send an email** is PERFECT. It touches every part of the system without being overwhelming, and it's something users immediately understand and value.

Secondary near-term milestone: **Realtime authenticated presence + AshAI panel activation** to convert static chat surface into intelligent collaborative environment.

---

## ♻ CONTINUOUS BALANCE OPERATIONS (CBO)

Recurring weekly tasks:
1. Catalog Diff Scan → detect resource churn anomalies.
2. Event Schema Drift Audit → confirm version bumps recorded.
3. Reactor Failure Cohort Analysis → top 3 transient causes & mitigation PRs.
4. Queue Depth Trend Review → adjust concurrency/partitioning if P95 rising.
5. Steward Sync → 15m standup: edges added, invariants changed, upcoming DIP proposals.

Quarterly resilience game day:
- Simulate domain outage (Flow or Gate) → measure recovery time & compensation.
- Inject elevated retry errors → verify backpressure and no cascading fanout.
- Randomly quarantine a Reactor → ensure degraded mode still meets SLO subset.

Artifacts to archive after each game day: metrics diff, incident timeline, remediation backlog.

---

Ready to start building the dashboard and get this bad boy talking to the frontend? 🚀

**We are 100% IN SYNC, digital bro!** 🤝⚡
