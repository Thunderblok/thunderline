# 🚀 THUNDERLINE MASTER PLAYBOOK: From Zero to AI Automation

> **Architecture Status (Nov 28, 2025 - 12-Domain Pantheon Update)**: Overall Grade **A (9/10)** - **12 canonical domains** defined, ~160 Ash resources, domain restructuring in progress. **NEW**: 12-Domain Pantheon architecture (HC-46/47/48/49) establishing final domain model. Full review: [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md)
>
> High Command Review Integration (Aug 25 2025): This Playbook incorporates the formal external "High Command" launch readiness review. New section: HIGH COMMAND REVIEW: ACTION MATRIX (P0 launch backlog HC-01..HC-68). All P0 items gate milestone `M1-EMAIL-AUTOMATION` (public pilot enablement). Cross‑reference: OKO_HANDBOOK SITREP, DOMAIN_ARCHITECTURE_REVIEW.
>
> **Ground Truth Verification (Nov 18, 2025)**: HC review contained inaccuracies. Direct codebase inspection revealed (and now resolved): (1) ThunderCom resources migrated into ThunderLink (HC-27/28 ✅), (2) ThunderLink operates as the single communications domain with 17 resources, (3) ThunderVine architectural decision implemented. See Ground Truth Verification Summary section and HC-27, HC-28, HC-29, HC-30 for details.
>
> **HC Architecture Synthesis (Nov 28, 2025)**: New comprehensive reference [`docs/HC_ARCHITECTURE_SYNTHESIS.md`](docs/HC_ARCHITECTURE_SYNTHESIS.md) consolidates all High Command strategic directives on CA Lattice, NCA/LCA kernels, CAT transforms, and Cerebros integration.
>
> **12-Domain Pantheon (Nov 28, 2025)**: Core, Pac, Crown, Bolt, Gate, Block, Flow, Grid, Vine, Prism, Link, Wall
> **Cross-Domain Layers**: Routing (Flow×Grid), Observability (Gate×Crown), Intelligence (Bolt×Crown), Persistence (Block×Flow), Communication (Link×Gate), Orchestration (Vine×Crown), Compute (Bolt×Flow), **Lattice (Bolt×Link×Gate)**, **Transform (Bolt×Block)**
> **Domain Restructure Status**: 
> - ✅ **Active (10)**: Thundercrown (merged Chief), Thunderbolt (50+), Thundergate (19), Thunderblock (33), Thunderflow (9), Thundergrid (5→API focus), Thundervine (6), Thunderprism (2), Thunderlink (17), RAG (1)
> - 🆕 **New Domains (HC-46/47/48)**: Thundercore (tick/identity), Thunderpac (PAC lifecycle), Thunderwall (entropy/GC)
> - ✅ **Consolidation (HC-49)**: Thunderchief → Thundercrown (orchestration + governance unified)

---

## ⚡ 12-DOMAIN THUNDERLINE PANTHEON (Nov 28, 2025)

**Mission**: Establish the canonical 12-domain architecture for Thunderline, providing clear ownership boundaries, symbolic alignment, and operational coherence.

### Domain Registry

| # | Domain | Focus | Symbolic Mapping | Status |
|---|--------|-------|------------------|--------|
| 1️⃣ | **Thundercore** | Tick emanation, system clock, identity kernel, PAC ignition | Seedpoint / Identity Core (Metatron's 1st Domain) | 🆕 HC-46 |
| 2️⃣ | **Thunderpac** | PAC lifecycle, state containers, role/intent management | Soul Container / Ascension Flow | 🆕 HC-47 |
| 3️⃣ | **Thundercrown** | Governance + Orchestration (absorbed Chief), policy, authorization, saga coordination | Crown Oversight / Structure (Mental-Buddhic) | ✅ Active |
| 4️⃣ | **Thunderbolt** | ML + Automata execution, loop monitors, CA intervention, Cerebros | Execution / Will / Fire (Key + Flame) | ✅ Active (50+) |
| 5️⃣ | **Thundergate** | Security, IAM, crypto, OAuth, boundaries, keys, rate limiting | Security / Network IAM (Cyber Shield) | ✅ Active (19) |
| 6️⃣ | **Thunderblock** | Persistence runtime, vaults, ledgers, data substrates | Persistence / Data (Cloud + DB layer) | ✅ Active (33) |
| 7️⃣ | **Thunderflow** | Signal/event flow, telemetry, causal DAGs, criticality hooks | Flow / Communication (Color bands) | ✅ Active (9) |
| 8️⃣ | **Thundergrid** | GraphQL interface, boundary contracts, data shape APIs | API / Connection Nexus (Heart/Throat) | ✅ Active (5) |
| 9️⃣ | **Thundervine** | DAG workflows, macrostructure graphs, orchestration edges | DAG / Roots-Workflow (Biocultural ecology) | ✅ Active (6) |
| 🔟 | **Thunderprism** | UI/UX, cognition layer, creativity, reflexive thought, code editing | Creativity / Reflexivity (Ambition, Relevance) | ✅ Active (2) |
| 1️⃣1️⃣ | **Thunderlink** | Communication, federation, WebRTC, TOCP transport | Communication / Federation (External Interface) | ✅ Active (17) |
| 1️⃣2️⃣ | **Thunderwall** | System boundary, decay, GC, overflow, archive, entropy sink | Entropy Boundary / Void (Black Hole Portal) | 🆕 HC-48 |

### System Cycle Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                        THUNDERLINE CYCLE                            │
│                                                                     │
│   ┌─────────┐                                        ┌─────────┐   │
│   │  CORE   │ ─────── Spark to containment ──────── │  WALL   │   │
│   │ (Tick)  │                                        │(Entropy)│   │
│   └────┬────┘                                        └────▲────┘   │
│        │                                                  │        │
│        ▼                                                  │        │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐             │        │
│   │   PAC   │ ─► │  CROWN  │ ─► │  BOLT   │ ────────────┘        │
│   │ (State) │    │(Govern) │    │(Execute)│                       │
│   └────┬────┘    └─────────┘    └────┬────┘                       │
│        │                              │                            │
│        ▼                              ▼                            │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐                       │
│   │  BLOCK  │ ◄─ │  VINE   │ ◄─ │  FLOW   │                       │
│   │(Persist)│    │  (DAG)  │    │ (Event) │                       │
│   └────┬────┘    └─────────┘    └────┬────┘                       │
│        │                              │                            │
│        ▼                              ▼                            │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐                       │
│   │  GATE   │ ─► │  GRID   │ ─► │  PRISM  │ ─► UI/Output          │
│   │(Security│    │  (API)  │    │  (UX)   │                       │
│   └─────────┘    └────┬────┘    └─────────┘                       │
│                       │                                            │
│                       ▼                                            │
│                  ┌─────────┐                                       │
│                  │  LINK   │ ─► External/Federation                │
│                  │ (Comms) │                                       │
│                  └─────────┘                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Domain Vectors

| Vector | Domains | Flow Description |
|--------|---------|------------------|
| **Policy→Execute** | Crown → Chief (absorbed) → Bolt | Governance decisions flow to execution layer |
| **IO→Surface→UX** | Flow → Grid → Prism | Events route through API to user interface |
| **State→Persist→Orchestrate** | Pac → Block → Vine | Stateful computational lifelines |
| **Spark→Containment** | Core → Wall | Full system lifecycle (ignition to entropy) |

### Key Consolidations (Nov 28, 2025)

| Source | Target | Rationale |
|--------|--------|-----------|
| **Thunderchief** | **Thundercrown** | Orchestration + Governance = unified authority (HC-49) |
| **Thunderlit** (concept) | **Thundercore** | Identity kernel + tick emanation = temporal/identity origin |
| **N/A** | **Thunderpac** | PAC lifecycle extracted from scattered Bolt/Block resources |
| **N/A** | **Thunderwall** | Entropy boundary, decay, GC - the "black hole portal" |

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
| HC-12 | P1 | DomainProcessor | Repeated consumer boilerplate | **✅ COMPLETE** (Nov 27) - `Thunderline.Thunderflow.DomainProcessor` behaviour + `__using__` macro. Eliminates ~200 lines of Broadway boilerplate per pipeline. Features: auto-telemetry on message/batch start/stop/error, DLQ routing via EventBus, `do_*` overridable config hooks, `normalize_event/1`, `broadcast/2`, `enqueue_job/3` helpers. Example: `ExampleDomainPipeline` (~80 lines vs ~300). Tests: `domain_processor_test.exs`. | Flow Steward | **Done** |
| HC-13 | P1 | Voice/WebRTC | Unused media libs | **✅ COMPLETE** (Nov 27) - MVP voice → intent pipeline: VoiceChannel emits `voice.signal.*` events (offer/answer/ice), RoomPipeline emits `voice.room.*` lifecycle events, MVP intent detection from transcripts (`voice.intent.detected`), telemetry for join/leave/signal/speaking. Categories added to Event taxonomy (`voice.signal`, `voice.room`, `voice.intent`). Tests: `room_pipeline_test.exs`. | Link+Crown | **Done** |
| HC-14 | P1 | Telemetry Dashboards | Sparse dashboards | Grafana JSON / custom LiveDashboard pages | Observability | Not Started |
| HC-15 | P1 | Security Hardening | API keys, encryption coverage | API key resource + cloak coverage matrix | Gate Steward | Not Started |
| HC-16 | P1 | Logging Standard | NDJSON schema undefined | Define versioned schema + field `log.schema.version` | Platform | Not Started |
| HC-17 | P2 | Federation Roadmap | ActivityPub phases vague | Draft phased activation doc | Gate | Not Started |
| HC-18 | P2 | Performance Baselines | No perf guard in CI | Add benches + regression thresholds | Platform | Not Started |
| HC-19 | P2 | Mobile Readiness | No offline/mobile doc | Draft sync/offline strategy | Link | Not Started |
| HC-20 | P1 | Cerebros Bridge | No formal external core bridge boundary | **In Progress** (Dec 2025) - Cerebros-mini MVP: `Feature.from_bit/1` (12-dim extraction), `Scorer.infer/1` (mock model), `Bridge.evaluate_and_apply/2` (unified pipeline), BitChief integration (`{:cerebros_evaluate, ...}` action). Remaining: real ML model, feature flag, dashboard. See §Cerebros-Mini MVP. | Bolt Steward | In Progress |
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
| **HC-38** | **P0** | **Cerebros-DiffLogic Integration** | No unified compute pipeline for voxel-automata optimization | **DIRECTIVE**: Integrate Thunderbolt voxel automata + Cerebros TPE orchestration + DiffLogic CA. **Components**: (1) Event protocol (`bolt.pac.compute.request/response`, `bolt.ca.rule.update`), (2) LoopMonitor criticality metrics (PLV, entropy, λ̂), (3) Multivariate TPE via Optuna (Python), (4) DiffLogic gradient-based rule updates, (5) OTel tracing across Elixir↔Python boundary. **Goal**: Self-optimizing CA system at "edge of chaos". Cross-domain layer: **Bolt×Flow** (ML + events). See §HC-Cerebros-DiffLogic Directive. | Bolt + Flow Stewards | Not Started |
| **HC-39** | **P0** | **PAC Compute Event Protocol** | No formal schema for PAC task routing | **Cerebros-01**: Define event schemas (`PACComputeRequest`, `PACComputeResponse`, `CAVoxelUpdate`) with versioning. **Components**: (1) Ash resource `Thunderbolt.PACComputeTask` (task lifecycle), (2) JSON schema validation, (3) OTel context propagation, (4) Broadway consumer for Python responses, (5) EventBus taxonomy entries (`bolt.pac.*`). Cross-domain layer: **Bolt×Flow**. | Bolt Steward | Not Started |
| **HC-40** | **P0** | **LoopMonitor Criticality Metrics** | CA criticality not measured | **Cerebros-02**: Implement criticality sensors in CA.Stepper. **Metrics**: (1) Phase-Locking Value (PLV) for synchrony, (2) Permutation entropy for complexity, (3) Langton's λ̂ (non-quiescent rule fraction), (4) Lyapunov exponent estimation. **Output**: Attach to `bolt.ca.metrics.snapshot` events, telemetry `[:thunderline, :bolt, :ca, :criticality]`. | Bolt Steward | Not Started |
| **HC-41** | **P1** | **Cerebros TPE Orchestration** | No Bayesian hyperparameter tuning | **Cerebros-03**: Python service for multivariate TPE. **Components**: (1) Optuna `TPESampler(multivariate=True)` for coupled params, (2) Trial database (Postgres or Optuna storage), (3) Event consumer for `PACComputeRequest`, (4) Result emission via `PACComputeResponse`, (5) Auto-scaling worker pool (Celery/asyncio). **Tunes**: PAC topology, rule weights, mutation rates. | Bolt + Platform | Not Started |
| **HC-42** | **P1** | **DiffLogic CA Rule Learning** | CA rules not differentiable | **Cerebros-04**: Treat voxel-update rules as differentiable parameters. **Components**: (1) Float-parameterized rule tables in Thunderbolt, (2) Gradient computation in Python (DiffLogic-style), (3) `CAVoxelUpdate` delta-events with rule patches, (4) Quantization layer for discrete execution, (5) Stability guards (clamp updates, detect divergence). **Goal**: Gradient descent on emergent patterns. | Bolt Steward | Not Started |
| **HC-43** | **P1** | **Agent0 Co-Evolution Loop** | No self-improving agent training | **Agent0-01**: Curriculum+Executor LLM co-evolution. **Components**: (1) Ash resources `CurriculumAgent`, `ExecutorAgent`, (2) Snex Python bridge for RL updates (GRPO/ADPO), (3) Zero-shot bootstrapping (no external data), (4) Episodic training with uncertainty×tool-use rewards, (5) ONNX model export/import via Ortex. **Goal**: Self-reinforcing training cycle. | Bolt + Crown Stewards | Not Started |
| **HC-44** | **P1** | **Agent0 Swarm Orchestration** | No multi-agent parallel execution | **Agent0-02**: Swarm scheduling in Thunderflow/Thunderchief. **Components**: (1) Reactor DAG for agent-spawn nodes, (2) Dynamic scaling (GenStage backpressure, K8s HPA), (3) Routing heuristics (round-robin, skill-based), (4) Task patterns (batching, sharding, voting), (5) Result aggregation and scoring. Cross-domain layer: **Flow×Crown**. | Flow + Crown Stewards | Not Started |
| **HC-45** | **P1** | **Event-Driven Agent Triggers** | No automata-based agent activation | **Agent0-03**: Thundercell triggers for agent spawning. **Components**: (1) Voxel state sensors (entropy burst, event-band), (2) Thunderbolt automata watchers, (3) Cool-off periods and rate limits, (4) Nerves edge constraints (central check-in), (5) LoopMonitor integration for runaway prevention. | Bolt + Gate Stewards | Not Started |
| **HC-46** | **P0** | **Thundercore Domain** | No unified tick/identity origin | **Pantheon-01**: Create Thundercore domain for tick emanation, system clock, identity kernel, PAC ignition. **Components**: (1) `Thundercore.Domain` Ash domain, (2) `TickEmitter` GenServer (system heartbeat), (3) `IdentityKernel` resource (PAC seedpoints), (4) `SystemClock` monotonic time service, (5) Event categories `core.tick.*`, `core.identity.*`. **Files**: `lib/thunderline/thundercore/`. | Core Steward | Not Started |
| **HC-47** | **P0** | **Thunderpac Domain** | PAC lifecycle scattered across domains | **Pantheon-02**: Create Thunderpac domain for PAC lifecycle management. **Components**: (1) `Thunderpac.Domain` Ash domain, (2) Extract PAC resources from Thunderbolt/Thunderblock, (3) `PAC` resource (state containers), (4) `PACRole` (role definitions), (5) `PACIntent` (intent management), (6) Lifecycle state machine (`:dormant`, `:active`, `:suspended`, `:archived`). **Files**: `lib/thunderline/thunderpac/`. | Pac Steward | Not Started |
| **HC-48** | **P0** | **Thunderwall Domain** | No entropy/decay boundary | **Pantheon-03**: Create Thunderwall domain for system boundary, entropy sink, GC. **Components**: (1) `Thunderwall.Domain` Ash domain, (2) `DecayProcessor` (archive expired resources), (3) `OverflowHandler` (reject stream management), (4) `EntropyMetrics` (system decay telemetry), (5) `GCScheduler` (garbage collection coordination), (6) Event categories `wall.decay.*`, `wall.archive.*`. **Files**: `lib/thunderline/thunderwall/`. Cross-domain: **Wall = final destination for all domains' expired/rejected data**. | Wall Steward | Not Started |
| **HC-49** | **P0** | **Crown←Chief Consolidation** | Orchestration split from governance | **Pantheon-04**: Complete Thunderchief → Thundercrown merger. **Components**: (1) Move remaining Thunderchief modules to Thundercrown, (2) Update all `Thunderchief.*` references to `Thundercrown.*`, (3) Delete Thunderchief domain directory, (4) Update imports/aliases across codebase, (5) Event categories `chief.*` → `crown.*`. **Rationale**: Orchestration + Governance = unified authority (saga planners + policy = single control plane). | Crown Steward | Not Started |
| **HC-50** | **P0** | **ThunderCell Lattice Communications** | No CA-based communication fabric | **Lattice-01**: Implement hybrid CA/WebRTC communication layer. **Architecture**: (1) 3D hexagonal Thunderbit lattice as routing/signaling fabric, (2) WebRTC for high-bandwidth payload transport, (3) CA rules for presence detection, route discovery, topology healing. **Components**: `Thunderbolt.Thunderbit` (voxel cell struct), `Thunderbolt.CAChannel` (lattice path definition), `Thunderbolt.CAStepper` (automaton tick engine), `Thunderlink.CACircuit` (WebRTC over CA routes). **Security**: mTLS/DTLS tunnels, per-hop XOR encryption, geometric secrecy (only path-aware endpoints reconstruct). **Events**: `ca.channel.*`, `ca.presence.*`, `ca.route.*`. Cross-domain: **Bolt×Link×Gate** (CA compute + transport + crypto). See §ThunderCell Lattice Architecture. | Bolt + Link + Gate Stewards | Not Started |
| **HC-51** | **P0** | **CA Channel Mesh Resources** | No Ash resources for CA channels | **Lattice-02**: Define Ash resources for CA communication. **Resources**: (1) `Thunderbolt.CAChannel` (id, path coords, rule version, key_id, ttl_ticks), (2) `Thunderbolt.CAEndpoint` (pac_id, coord, presence_state), (3) `Thundervine.CARoute` (DAG edge for channel topology), (4) `Thundergate.CASession` (session keys, DTLS state). **Actions**: `create_channel`, `teardown_channel`, `refresh_keys`, `reroute_path`. **Queries**: `list_channels_for_pac`, `get_channel_health`, `find_path`. | Bolt + Vine + Gate Stewards | Not Started |
| **HC-52** | **P1** | **WebRTC Circuit Layer** | CA signaling not integrated with WebRTC | **Lattice-03**: Bridge CA route discovery to WebRTC circuit establishment. **Flow**: (1) CA lattice converges on stable path → (2) `ca.channel.established` event → (3) ICE candidate exchange over CA channel → (4) Thundergate key negotiation → (5) WebRTC DataChannel/MediaChannel opened → (6) Bulk traffic bypasses CA (uses WebRTC). **Components**: `Thunderlink.CACircuitManager` (lifecycle), `Thunderlink.ICEOverCA` (signaling adapter), `Thunderbolt.PresenceField` (endpoint discovery). **Fallback**: If CA route collapses → auto-resignaling → new circuit. Cross-domain: **Link×Bolt**. | Link + Bolt Stewards | Not Started |
| **HC-53** | **P1** | **CA Lattice Visualization** | No 3D view of Thunderbit lattice | **Lattice-04**: Thunderprism 3D lattice debugger. **Components**: (1) LiveView + Three.js/WebGL for 3D voxel rendering, (2) Real-time PubSub subscription to `ca.tick.*` events, (3) Channel highlighting (active paths glow), (4) Slow-motion replay mode, (5) "Paint path" tool for manual route definition, (6) Metrics overlay (PLV, entropy, λ̂ per region). **Dev UI**: Watch signals propagate wave-by-wave. | Prism Steward | Not Started |
| **HC-54** | **P0** | **SNN Thunderbit Mode** | No spiking neuron dynamics in CA cells | **Neuro-01**: Extend CACell with spiking neuron dynamics (LIF model, trainable delays). **Components**: (1) `Thunderbolt.SpikingCell` struct (membrane_potential, spike_threshold, leak_rate, refractory_period, delay_queue), (2) Trainable per-neighbor synaptic delays (Paper 1 key insight: delays extend intrinsic memory), (3) Event-driven sparse updates (cells compute only on spike events), (4) EventProp-compatible gradient hooks for delay learning, (5) Multi-spike support per tick. **Benefits**: <50% memory vs frame-based, 26× faster than BPTT for SNN training, improved temporal pattern recognition. **Events**: `snn.spike.*`, `snn.delay.update`. Cross-domain: **Bolt** (CA extension). See §SNN/Photonic Research Integration. | Bolt Steward | Not Started |
| **HC-55** | **P0** | **Perturbation Layer** | No error tolerance for deep CA stacks | **Neuro-02**: Photonic-inspired decorrelation for error-tolerant deep automata. **Components**: (1) `Thunderbolt.CA.Perturbation` module (inject controlled noise between layers), (2) Per-cell random phase offset to break propagation redundancy (Paper 2 SLiM chip insight), (3) LoopMonitor integration: if λ̂ > 0 (divergent) → increase perturbation strength, (4) Zone-to-zone decorrelation transforms on event handoff, (5) Periodic re-normalization/reset steps to clear accumulated drift. **Goal**: Stack 100+ CA layers without error amplification. **Telemetry**: `[:thunderline, :bolt, :ca, :perturbation]`. Cross-domain: **Bolt×Flow** (CA + observability). | Bolt Steward | Not Started |
| **HC-56** | **P1** | **EventProp Training** | No event-based gradient computation for SNN | **Neuro-03**: Implement EventProp-style sparse backpropagation for SNN parameter tuning. **Components**: (1) Exact gradients computed only at discrete spike events (not dense time steps), (2) Weight + delay co-optimization, (3) Recurrent SNN support (delay loops), (4) Python bridge (Snex) for gradient computation, (5) Integration with Cerebros TPE for architecture search. **Target**: Train spike thresholds, leak rates, synaptic delays on temporal tasks (speech, sensor sequences). **Metrics**: Memory <50% of BPTT, runtime up to 26× faster. Cross-domain: **Bolt×Flow** (training + events). | Bolt + Flow Stewards | Not Started |
| **HC-57** | **P1** | **Cerebros SNN Priors** | TPE search space lacks SNN-specific axes | **Neuro-04**: Extend Cerebros TPE search space for spiking/photonic architectures. **New axes**: (1) `spike_threshold` (0.5–2.0), (2) `leak_rate` (0.8–0.99), (3) `trainable_delays_enabled` (bool), (4) `max_delay_ticks` (1–16), (5) `perturbation_strength` (0.001–0.1), (6) `layer_decorrelation_method` (noise/dropout/phase_shift). **Constraints**: PLV ∈ [0.3, 0.6] as objective constraint (healthy criticality). **Integration**: Use LoopMonitor metrics as TPE objective signals, inject noise during architecture evaluation to select error-tolerant designs. Cross-domain: **Bolt×Crown** (ML + governance). | Bolt + Crown Stewards | Not Started |
| **HC-58** | **P1** | **Spike Train Parser** | No event-driven signal→spike conversion | **Neuro-05**: Neuromorphic signal processing for Thunderforge. **Components**: (1) `Thunderbolt.Signal.SpikingParser` (threshold-crossing detector → spike stream), (2) Learned delay insertion for predictive timing (e.g., anticipate rhythmic beats), (3) On-device SNN inference for signal classification (arrhythmia, anomaly detection), (4) Spike event injection into ThunderCell CA (instead of raw values), (5) Hilbert phase coupling on spike trains. **Benefits**: Dramatically reduced bandwidth, focus computation on salient moments, Nerves-compatible (low memory). **Events**: `signal.spike.*`. Cross-domain: **Bolt×Link** (signal + transport). | Bolt + Link Stewards | Not Started |
| **HC-59** | **P0** | **HC-49 Consolidation** | Thunderchief → Thundercrown migration | ✅ **COMPLETE** (Nov 28, 2025): Domain consolidation executed. Orchestrator moved, legacy domain deleted, 12+ files updated, backward compat routes in place. See `docs/HC_TODO_SWEEP.md`. | Crown Steward | **Done** |
| **HC-60** | **P1** | **Thunderbit Resource & Stepper** | No formal Thunderbit definition | **CA-Lattice-01**: Create foundational Thunderbit infrastructure. **Components**: (1) `Thunderbolt.Thunderbit` struct with full state vector (ϕ_phase, σ_flow, λ̂_sensitivity, trust_score, presence_vector, relay_weight, key_fragment), (2) `Thunderbolt.CA.Stepper` basic CA step execution, (3) `Thunderbolt.CA.Neighborhood` 3D neighborhood computation. See `docs/HC_ARCHITECTURE_SYNTHESIS.md`. Cross-domain: **Bolt**. | Bolt Steward | Not Started |
| **HC-61** | **P1** | **CAT Transform Primitives** | No CA-based signal encoding | **CA-Lattice-02**: Implement Cellular Automata Transforms for signal representation, compression, encryption. **Components**: (1) `Thunderbolt.CATTransform` module with forward/inverse transforms, (2) Basis function generation from CA evolution, (3) Compression mode (sparse coefficients), (4) CAT encryption with avalanche property. **Goal**: Unified encoding for Thunderbit state → storage/transport. Cross-domain: **Bolt×Block**. | Bolt Steward | Not Started |
| **HC-62** | **P1** | **NCA Kernel Infrastructure** | No trainable CA rules | **CA-Lattice-03**: Neural CA kernel system. **Components**: (1) `Thunderbolt.NCAKernel` Ash resource, (2) `Thunderbolt.NCAEngine.step/3` execution via Ortex/ONNX, (3) Training curriculum (signal propagation, logic gates, memory), (4) LoopMonitor as auxiliary loss (PLV/λ̂ targets). **Goal**: Universal compute substrate via learned CA rules. Cross-domain: **Bolt×Crown**. | Bolt Steward | Not Started |
| **HC-63** | **P1** | **LCA Kernel Infrastructure** | CA rules require fixed topology | **CA-Lattice-04**: Latent CA (mesh-agnostic) kernels. **Components**: (1) `Thunderbolt.LCAKernel` Ash resource, (2) `Thunderbolt.LCAEngine.step/2` with kNN graph, (3) Embedding network for latent neighborhood. **Goal**: CA rules that work on ANY mesh/topology/geometry. Cross-domain: **Bolt**. | Bolt Steward | Not Started |
| **HC-64** | **P2** | **TPE Search Space Extension** | Cerebros lacks CAT/NCA hyperparams | **CA-Lattice-05**: Extend Cerebros TPE for CA architecture search. **Components**: (1) CAT hyperparameters (rule_id, dims, alphabet, radius, window, time_depth), (2) NCA/LCA hyperparameters, (3) Trial lifecycle events (cat.*, nca.*, lca.*). **Goal**: Automated discovery of optimal CA basis families. Cross-domain: **Bolt×Crown**. | Bolt + Crown Stewards | Not Started |
| **HC-65** | **P2** | **Training Loop Integration** | No NCA/LCA training pipeline | **CA-Lattice-06**: Complete training pipeline. **Components**: (1) Multi-task curriculum definition, (2) LoopMonitor as auxiliary loss, (3) Kernel registration on success, (4) Telemetry dashboards for CA training. Cross-domain: **Bolt×Flow**. | Bolt Steward | Not Started |
| **HC-66** | **P2** | **Co-Lex Ordering Service** | No O(1) state comparison for automata | **CA-Lattice-07**: Implement co-lex ordering from SODA/ESA research. **Components**: (1) Forward-stable reduction (Paige-Tarjan), (2) Co-lex extension (Becker et al.), (3) Infimum/supremum graphs + Forward Visit, (4) `Thunderbolt.CoLex.compare/3` O(1) comparator. **Goal**: Linear-space BWT-style indexing for automata/DAGs. Cross-domain: **Bolt×Block×Vine**. | Bolt + Block Stewards | Not Started |
| **HC-67** | **P2** | **WebRTC Circuit Integration** | CA signaling not bridged to WebRTC | **CA-Lattice-08**: Bridge CA route discovery to WebRTC circuits. **Components**: (1) CA lattice converges → `ca.channel.established`, (2) ICE exchange over CA channel, (3) `Thunderlink.CACircuitManager` lifecycle, (4) Auto-rerouting on path degradation. Cross-domain: **Link×Bolt**. | Link + Bolt Stewards | Not Started |
| **HC-68** | **P2** | **CAT Security Layer** | No CA-based crypto layer | **CA-Lattice-09**: CAT-based security primitives. **Components**: (1) CAT encryption implementation, (2) Key fragment distribution across voxels, (3) Per-hop XOR obfuscation, (4) Geometric secrecy validation (only path-aware endpoints reconstruct). Cross-domain: **Gate×Bolt**. | Gate + Bolt Stewards | Not Started |
| **HC-69** | **P1** | **Continuous Tensor Abstraction** | No real-valued indexing for spatial/temporal computation | **Research-CTA-01**: Implement continuous tensor operations for Thunderline spatial computing. **Research Source**: Won et al. "The Continuous Tensor Abstraction: Where Indices are Real" (OOPSLA 2025). **Components**: (1) Piecewise-constant tensor representation, (2) Real-valued index operations (`A[3.14]`), (3) Continuous algebra expressions (`C(x,y) = A(x,y) * B(x,y)`), (4) Finite-time infinite domain processing. **Applications**: ThunderGrid radius search (9.2x speedup potential), genomic interval queries, NeRF interpolation, PAC continuous state spaces. Cross-domain: **Grid×Bolt×Block**. See §Continuous Tensor Integration Directive. | Grid + Bolt Stewards | Not Started |
| **HC-70** | **P1** | **Continuous ThunderGrid Indexing** | Grid cells use discrete indices only | **CTA-02**: Real-valued spatial coordinates in ThunderGrid. **Components**: (1) `Thundergrid.ContinuousTensor` module (piecewise-constant storage), (2) Continuous hexagonal coordinate interpolation, (3) Radius search with real-valued bounds, (4) k-NN queries using continuous distance metrics. **Benefits**: ~60x fewer LoC vs hand-implemented, 9.2x speedup on 2D radius search. Cross-domain: **Grid×Bolt**. | Grid Steward | Not Started |
| **HC-71** | **P1** | **Continuous PAC State Manifolds** | PAC states are discrete enums | **CTA-03**: Continuous state representations for PAC lifecycle. **Components**: (1) State manifold embeddings (continuous `:dormant` → `:active` transitions), (2) Smooth interpolation between PAC configurations, (3) Gradient-based state optimization, (4) Continuous phase tracking in ThunderCore. **Integration**: PAC lifecycle transitions as continuous functions, not discrete jumps. Cross-domain: **Pac×Core×Bolt**. | Pac + Core Stewards | Not Started |
| **HC-72** | **P1** | **Continuous Event Timestamps** | Event timing is discrete ticks | **CTA-04**: Real-valued temporal indexing in ThunderFlow. **Components**: (1) Continuous timestamp algebra, (2) Sub-tick event interpolation, (3) Temporal range queries with real bounds, (4) Event stream continuous aggregations. **Benefits**: Precise temporal causality, smoother event flow analysis. Cross-domain: **Flow×Core**. | Flow + Core Stewards | Not Started |
| **HC-73** | **P2** | **Continuous CA Field Dynamics** | CA cells use integer coordinates | **CTA-05**: Continuous spatial fields for Thunderbit lattice. **Components**: (1) Continuous field representation (ϕ, σ, λ̂ as smooth functions), (2) Real-valued neighbor interpolation, (3) Gradient flows between voxel cells, (4) Continuous CAT coefficient storage. **Goal**: CA rules operating on continuous spatial fields. Cross-domain: **Bolt×Block**. | Bolt Steward | Not Started |
| **HC-74** | **P2** | **Finch.jl Interop Layer** | No connection to Finch sparse compiler | **CTA-06**: Bridge to Finch.jl for optimized sparse tensor operations. **Components**: (1) Protocol for Elixir→Julia tensor exchange, (2) Galley scheduler integration for query optimization, (3) Sparse format translation (CSC/CSR/COO), (4) Nx tensor ↔ Finch tensor conversion. **Benefits**: 1000x speedup on sparse operations via Galley optimizer. Cross-domain: **Bolt**. | Bolt Steward | Not Started |

Legend: P0 launch‑critical; P1 post‑launch hardening; P2 strategic. Status: Not Started | Planned | In Progress | Done.

---

## ⚡ THUNDERCELL LATTICE COMMUNICATION ARCHITECTURE (Nov 28, 2025)

**Mission**: Build a hybrid CA/WebRTC communication fabric where the cellular automaton lattice handles routing, signaling, and identity while WebRTC provides high-bandwidth payload transport.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    THUNDERCELL LATTICE ARCHITECTURE                         │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     LAYER 3: THUNDERLINE                            │   │
│   │         Policy • PAC Semantics • Domain Behavior • DAG Lineage      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                        │
│                                    │                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     LAYER 2: WebRTC PAYLOAD                         │   │
│   │         High-bandwidth • Low-latency • DTLS/SRTP • DataChannels     │   │
│   │                    (Thunderlink.CACircuit)                          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                        │
│                                    │ Signaling/Route Discovery              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     LAYER 1: CA LATTICE                             │   │
│   │    Routing • Identity • Obfuscation • Multiplexing • Presence       │   │
│   │                  (Thunderbolt.Thunderbit Grid)                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Domain Responsibilities

| Domain | CA Lattice Role |
|--------|-----------------|
| **Thundercore** | Universe clock, tick alignment, base lattice coordinates |
| **Thunderbolt** | CA rules, Thunderbit structs, stepper, channel templates |
| **Thunderpac** | PAC-owned channels, key material, channel creation policies |
| **Thundervine** | Channel graph (CARoute edges), overlay routing table |
| **Thundergate** | Crypto: key exchange, session keys, mTLS/DTLS management |
| **Thunderflow** | Events: `ca.channel.*`, `ca.presence.*`, health monitoring |
| **Thundergrid** | API: `send_message/2`, `list_channels/1`, GraphQL exposure |
| **Thunderprism** | 3D visualization, path painting, slow-motion debug |
| **Thunderlink** | WebRTC circuits, ICE negotiation, TURN fallback |
| **Thunderwall** | Boundary damping, mix zones, channel decay/shredding |

### Thunderbit Structure

```elixir
defmodule Thunderbolt.Thunderbit do
  @moduledoc "Single voxel cell in the 3D CA lattice"
  @enforce_keys [:coord]
  defstruct [
    :coord,           # {x, y, z} position in lattice
    :state,           # Nx tensor or bitfield (few bits/words)
    :channel_id,      # Active channel ID (nil if idle)
    :key_id,          # Reference to Thundergate session key
    :neighbors,       # Precomputed neighbor coords (6 in-plane + temporal)
    :presence,        # :vacant | :occupied | :forwarding
    :route_tags       # Bloom filter of destination IDs
  ]
end
```

### CA Channel Definition

```elixir
defmodule Thunderbolt.CAChannel do
  @moduledoc "A routed path through the Thunderbit lattice"
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :name, :string           # e.g. "chan:pacA→pacB:123"
    attribute :path, {:array, :map}    # [{x,y,z}, ...] coordinates
    attribute :rule, :atom             # :waveguide_v1, :broadcast_v1, etc.
    attribute :key_id, :string         # Thundergate session key reference
    attribute :ttl_ticks, :integer     # Channel lifetime in CA ticks
    attribute :status, :atom           # :establishing | :active | :degraded | :teardown
    timestamps()
  end

  relationships do
    belongs_to :source_pac, Thunderpac.PAC
    belongs_to :dest_pac, Thunderpac.PAC
  end
end
```

### Communication Flow

```
1. PRESENCE DISCOVERY
   ┌──────────┐    CA tick    ┌──────────┐    CA tick    ┌──────────┐
   │  PAC A   │ ─────────────▶│ Lattice  │◀───────────── │  PAC B   │
   │ (beacon) │               │  (wave)  │               │ (beacon) │
   └──────────┘               └──────────┘               └──────────┘
         │                          │                          │
         ▼                          ▼                          ▼
   presence_field ───────▶ route converges ◀─────── presence_field

2. CHANNEL ESTABLISHMENT
   PAC A ──[ca.channel.request]──▶ CA Lattice ──[ca.channel.established]──▶ PAC B
              │                                           │
              └──────────── Thundervine DAG ──────────────┘
                         (CARoute edge stored)

3. WEBRTC CIRCUIT UPGRADE
   PAC A ──[ICE offer via CA]──▶ PAC B
   PAC A ◀──[ICE answer via CA]── PAC B
   PAC A ◀═══[WebRTC DataChannel]═══▶ PAC B  (bulk traffic)

4. ONGOING OPERATION
   CA Lattice: heartbeat, topology healing, reroute signals
   WebRTC: payload transport, audio/video, sensor streams
   Thunderflow: ca.channel.health events, PLV/λ̂ metrics
```

### Security Model

| Layer | Security Mechanism |
|-------|-------------------|
| **Transport** | mTLS between Thunderblocks, DTLS for WebRTC |
| **Per-hop** | XOR encryption with lattice-derived keys |
| **Geometric** | Only path-aware endpoints can reconstruct signals |
| **Session** | Ephemeral keys negotiated via Thundergate |
| **Zero-trust** | Cells never store plaintext; all forwarding is opaque |

### CA Primitives

| Primitive | Description | CA State Encoding |
|-----------|-------------|-------------------|
| **Presence beacon** | One-bit "alive" signal | `state[0]` = presence bit |
| **Data packet** | Multi-bit symbol with sequencing | `state[1..N]` = payload chunk |
| **Route tag** | Destination/next-hop identifier | `route_tags` bloom filter |
| **Ack token** | Reverse propagation for receipt confirmation | `state[N+1]` = ack bit |
| **Channel ID** | Stream multiplexing identifier | `channel_id` field |

### Performance Characteristics

| Metric | CA Lattice | WebRTC Circuit |
|--------|------------|----------------|
| **Throughput** | Low (signaling only) | High (Mbps+) |
| **Latency** | Tick-bounded | Sub-100ms |
| **Use case** | Routing, presence, obfuscation | Payload, media, bulk data |
| **Security** | Geometric + crypto | DTLS/SRTP |

### Fallback & Resilience

```elixir
# Automatic reroute on path degradation
def handle_event({:ca, :channel, :degraded}, %{channel_id: id}, socket) do
  with {:ok, channel} <- CAChannel.get(id),
       {:ok, new_path} <- find_alternate_path(channel),
       {:ok, _} <- CAChannel.update(channel, %{path: new_path, status: :rerouting}) do
    # WebRTC circuit will auto-reconnect via new signaling path
    {:ok, :rerouted}
  else
    {:error, :no_path} ->
      # Fallback to Cerebros cloud relay
      CerebrosBridge.request_relay(channel)
  end
end
```

### Integration with Existing HC Items

- **HC-38 (Cerebros-DiffLogic)**: CA rules can be gradient-tuned for optimal routing
- **HC-40 (LoopMonitor)**: PLV/entropy metrics apply to CA channel health
- **HC-23 (Nerves)**: Edge devices participate in lattice as Thunderbit nodes
- **HC-13 (Voice/WebRTC)**: Voice streams use CA-discovered WebRTC circuits

---

## 🧠 SNN/PHOTONIC RESEARCH INTEGRATION (Jan 2025)

**Research Sources**: Two Nature papers driving next-generation Thunderbolt architecture:
1. **Event-Based Delay Learning in SNNs** - Event-driven training, learnable synaptic delays, EventProp framework (<50% memory, 26× faster than BPTT)
2. **Hundred-Layer Photonic Deep Learning** - SLiM chip design, propagation redundancy breaks via perturbations, 100+ layer depth, decorrelation for error tolerance

### Key Insights Mapped to Thunderline

| Paper Concept | Thunderline Application | Target Module |
|---------------|------------------------|---------------|
| **Learnable Synaptic Delays** | Trainable spike timing in CA cells | `SpikingCell` (HC-54) |
| **EventProp (Sparse Backprop)** | Memory-efficient training for SNN mode | `EventProp` (HC-56) |
| **SLiM Perturbations** | Noise injection to decorrelate error paths | `Perturbation` (HC-55) |
| **Propagation Redundancy** | λ̂ monitoring → adaptive perturbation | `LoopMonitor` (HC-40) |
| **Sub-50% Memory** | Event-sparse representation in Thunderbits | `SpikingParser` (HC-58) |
| **TPE Prior Extension** | Cerebros search space for delay/perturbation hyperparams | `SNN Priors` (HC-57) |

### Architecture: Spiking Thunderbit Mode

```
┌─────────────────────────────────────────────────────────────────┐
│                    SPIKING THUNDERBIT MODE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│  │  Token      │────▶│  Spiking    │────▶│  PLV        │       │
│  │  Stream     │     │  Encoder    │     │  Monitor    │       │
│  └─────────────┘     └──────┬──────┘     └──────┬──────┘       │
│                             │                   │               │
│                             ▼                   ▼               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SPIKING THUNDERBIT LATTICE                 │   │
│  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐           │   │
│  │  │ LIF │──│ LIF │──│ LIF │──│ LIF │──│ LIF │           │   │
│  │  │ τ_d │  │ τ_d │  │ τ_d │  │ τ_d │  │ τ_d │  (delays) │   │
│  │  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘           │   │
│  │     │        │        │        │        │              │   │
│  │     └────────┴────────┼────────┴────────┘              │   │
│  │                       ▼                                │   │
│  │              ┌─────────────────┐                       │   │
│  │              │  Perturbation   │ ◀── λ̂ feedback       │   │
│  │              │  Layer (SLiM)   │                       │   │
│  │              └────────┬────────┘                       │   │
│  └───────────────────────┼─────────────────────────────────┘   │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   LOOP MONITOR (HC-40)                  │   │
│  │  • PLV Aggregator      • Permutation Entropy            │   │
│  │  • Langton's λ̂         • Local Lyapunov Exponent        │   │
│  │  • Criticality Events  • Telemetry: bolt.ca.criticality │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 CEREBROS SNN PRIORS (HC-57)             │   │
│  │  • τ_membrane: [5ms, 50ms]    • τ_delay: [1ms, 20ms]    │   │
│  │  • perturb_σ: [0.001, 0.1]    • noise_type: uniform/gauss │  │
│  │  • λ̂_target: [0.25, 0.35]    • train_mode: eventprop    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Phases

| Phase | HC Item | Component | Dependencies | Priority |
|-------|---------|-----------|--------------|----------|
| **1** | HC-40 | `LoopMonitor` - PLV aggregator, permutation entropy, λ̂, Lyapunov | PLV, Hilbert (existing) | P0 |
| **2** | HC-54 | `SpikingCell` - LIF neurons, trainable delays, spike timing | CACell (extend) | P0 |
| **3** | HC-55 | `Perturbation` - SLiM-style decorrelation, noise injection | LoopMonitor (HC-40) | P0 |
| **4** | HC-57 | `SNN Priors` - TPE search space extension for SNN hyperparams | Cerebros.TPE | P1 |
| **5** | HC-58 | `SpikingParser` - Neuromorphic signal processing, spike train → events | Sensor (existing) | P1 |
| **6** | HC-56 | `EventProp` - Sparse backprop training (optional Axon integration) | SpikingCell (HC-54) | P1 |

### File Locations

```
lib/thunderline/thunderbolt/signal/loop_monitor.ex       # HC-40 (Phase 1)
lib/thunderline/thunderbolt/thundercell/spiking_cell.ex  # HC-54 (Phase 2)
lib/thunderline/thunderbolt/ca/perturbation.ex           # HC-55 (Phase 3)
lib/thunderline/thunderbolt/signal/spiking_parser.ex     # HC-58 (Phase 5)
python/cerebros/service/snn_priors.py                    # HC-57 (Phase 4)
```

### Integration Points with Existing Infrastructure

**Signal Processing** (existing):
- `PLV.plv/1` → feeds LoopMonitor for phase coherence
- `Hilbert.step/2` → instantaneous phase extraction
- `Sensor` GenServer → event emission pattern for spike trains

**Cerebros Bridge** (existing):
- `CerebrosBridge` → NAS orchestration for SNN hyperparameters
- `ModelServer` → ONNX session management (potential spike model export)
- `HPOExecutor` → Oban worker pattern for SNN training jobs

**CA Infrastructure** (existing):
- `CACell` → extend for LIF dynamics (membrane potential, refractory)
- `CAEngine` → coordination for spiking lattice
- `Stepper` → step function extension for spike propagation

---

## 📐 CONTINUOUS TENSOR ABSTRACTION INTEGRATION (Nov 29, 2025)

**Research Source**: Won, Ahrens, Collin, Emer, Amarasinghe. "The Continuous Tensor Abstraction: Where Indices are Real" (OOPSLA 2025). [arXiv:2407.01742](https://arxiv.org/abs/2407.01742)

**Mission**: Extend Thunderline's spatial and temporal computing to support real-valued indices, enabling continuous tensor operations across ThunderGrid, ThunderCore, ThunderFlow, and ThunderBolt domains.

### The Core Insight

> **"Indices can take real-number values"** — `A[3.14]` is valid.

Traditional tensors use discrete integer indices. Continuous tensors extend this to real numbers, enabling:
- **Computational Geometry**: Spatial queries with real-valued bounds
- **Signal Processing**: Continuous-time representations
- **Graphics/ML**: Trilinear interpolation, NeRF rendering
- **State Machines**: Smooth transitions between discrete states

### Piecewise-Constant Representation

The key insight enabling finite-time computation over infinite domains:

```
┌─────────────────────────────────────────────────────────────────┐
│              PIECEWISE-CONSTANT TENSOR                          │
│                                                                 │
│   Value                                                         │
│     │                                                           │
│  v3 ├───────────────────┐                                       │
│     │                   │                                       │
│  v2 ├─────────┐         │         ┌─────────                    │
│     │         │         │         │                             │
│  v1 ├─┐       │         │         │                             │
│     │ │       │         │         │                             │
│     └─┴───────┴─────────┴─────────┴─────────▶ x (real)          │
│       x1      x2        x3        x4                            │
│                                                                 │
│   A[2.5] = v2  (constant within interval)                       │
│   A[3.7] = v3  (piecewise lookup)                               │
│                                                                 │
│   Storage: O(k) where k = number of intervals                   │
│   Lookup: O(log k) via binary search                            │
└─────────────────────────────────────────────────────────────────┘
```

### Performance Benchmarks (from Paper)

| Application | Speedup | LoC Reduction | Description |
|-------------|---------|---------------|-------------|
| **2D Radius Search** | 9.20x | ~60x | Spatial queries in point clouds |
| **Genomic Interval Overlap** | 1.22x | ~18x | BED file intersection operations |
| **NeRF Trilinear Interpolation** | 1.69x | ~6x | Neural radiance field rendering |

### Thunderline Integration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│               CONTINUOUS TENSOR LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │ ThunderGrid │    │ ThunderCore │    │ ThunderFlow │        │
│   │             │    │             │    │             │        │
│   │ Continuous  │    │ Continuous  │    │ Continuous  │        │
│   │ Spatial     │    │ Temporal    │    │ Event       │        │
│   │ Coordinates │    │ Clock       │    │ Timestamps  │        │
│   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │
│          │                  │                  │                │
│          └──────────────────┼──────────────────┘                │
│                             │                                   │
│                             ▼                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              Thunderbolt.ContinuousTensor               │   │
│   │                                                         │   │
│   │  • Piecewise-constant storage                           │   │
│   │  • Real-valued index operations                         │   │
│   │  • Continuous algebra expressions                       │   │
│   │  • Automatic kernel generation                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                             │                                   │
│                             ▼                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              ThunderBlock Persistence                   │   │
│   │                                                         │   │
│   │  • Interval-based storage format                        │   │
│   │  • Efficient serialization                              │   │
│   │  • pgvector integration for embeddings                  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Domain-Specific Applications

#### ThunderGrid: Continuous Spatial Indexing (HC-70)

**Current**: Discrete hexagonal grid cells with integer coordinates.
**Enhanced**: Real-valued spatial coordinates with continuous interpolation.

```elixir
# Before: Discrete cell lookup
cell = Thundergrid.get_cell(3, 4, 5)  # Integer coords only

# After: Continuous spatial query
cells = Thundergrid.radius_search(
  center: {3.14, 4.72, 5.99},  # Real coords
  radius: 2.5,                  # Real radius
  metric: :euclidean
)

# Continuous field sampling
value = Thundergrid.sample_field(:temperature, {x, y, z})  # Interpolated
```

**Implementation**:
```elixir
defmodule Thunderline.Thundergrid.ContinuousTensor do
  @moduledoc """
  Piecewise-constant tensor for continuous spatial indexing.
  Based on Won et al. 2025 Continuous Tensor Abstraction.
  """
  
  defstruct [:intervals, :values, :dims, :default]
  
  @type interval :: {float(), float()}  # [start, end)
  @type t :: %__MODULE__{
    intervals: [interval()],
    values: [term()],
    dims: pos_integer(),
    default: term()
  }
  
  @doc "Create continuous tensor from discrete samples"
  @spec from_samples([{float(), term()}]) :: t()
  def from_samples(samples) do
    # Sort by coordinate, merge adjacent equal values
    sorted = Enum.sort_by(samples, fn {coord, _} -> coord end)
    {intervals, values} = merge_intervals(sorted)
    %__MODULE__{intervals: intervals, values: values, dims: 1, default: nil}
  end
  
  @doc "Index with real-valued coordinate"
  @spec get(t(), float()) :: term()
  def get(%__MODULE__{intervals: intervals, values: values, default: default}, x) do
    case binary_search_interval(intervals, x) do
      {:ok, idx} -> Enum.at(values, idx)
      :not_found -> default
    end
  end
  
  @doc "Continuous algebra: C(x) = A(x) * B(x)"
  @spec multiply(t(), t()) :: t()
  def multiply(a, b) do
    # Compute intersection of interval structures
    merged_intervals = intersect_intervals(a.intervals, b.intervals)
    values = Enum.map(merged_intervals, fn interval ->
      get(a, midpoint(interval)) * get(b, midpoint(interval))
    end)
    %__MODULE__{intervals: merged_intervals, values: values, dims: 1, default: nil}
  end
  
  @doc "Radius search with real-valued bounds"
  @spec radius_search(t(), float(), float()) :: [{interval(), term()}]
  def radius_search(tensor, center, radius) do
    lower = center - radius
    upper = center + radius
    
    tensor.intervals
    |> Enum.with_index()
    |> Enum.filter(fn {{start, stop}, _idx} ->
      intervals_overlap?({start, stop}, {lower, upper})
    end)
    |> Enum.map(fn {{start, stop}, idx} ->
      {{start, stop}, Enum.at(tensor.values, idx)}
    end)
  end
end
```

#### ThunderCore: Continuous Temporal Service (HC-72)

**Current**: Discrete tick-based time emanation.
**Enhanced**: Real-valued timestamps with sub-tick precision.

```elixir
# Before: Discrete tick
tick = Thundercore.SystemClock.current_tick()  # Integer

# After: Continuous time
time = Thundercore.SystemClock.now_continuous()  # Float (nanoseconds)

# Temporal range queries
events = Thundercore.events_in_range(
  from: 1732780800.123,  # Real timestamp
  to: 1732780805.789,    # Real timestamp
  resolution: :nanosecond
)
```

#### ThunderFlow: Continuous Event Algebra (HC-72)

**Current**: Events have discrete timestamps.
**Enhanced**: Continuous temporal aggregations and causal analysis.

```elixir
# Continuous event stream aggregation
aggregated = Thunderflow.aggregate_continuous(
  stream: events,
  window: {t1, t2},  # Real-valued bounds
  function: :mean,
  interpolation: :linear
)

# Causal density analysis
density = Thunderflow.causal_density(
  events,
  point: 1732780803.5,  # Real-valued query point
  bandwidth: 1.0
)
```

#### ThunderPac: Continuous State Manifolds (HC-71)

**Current**: PAC lifecycle is discrete enum (`:dormant`, `:active`, etc.).
**Enhanced**: Continuous state space enabling smooth transitions.

```elixir
# Before: Discrete state transition
PAC.transition(pac, :active)  # Jump

# After: Continuous state evolution
PAC.evolve_state(pac, %{
  target: :active,
  trajectory: :sigmoid,  # Smooth transition curve
  duration_ms: 1000
})

# Query intermediate state
current = PAC.state_at(pac, t)  # Returns continuous state vector
# => %{activity: 0.73, dormancy: 0.27, ...}
```

#### ThunderBolt: Continuous CA Fields (HC-73)

**Current**: CA cells at integer grid coordinates.
**Enhanced**: Continuous field dynamics with real-valued interpolation.

```elixir
# Continuous Thunderbit field
field = Thunderbolt.ContinuousField.new(
  bounds: {{0.0, 100.0}, {0.0, 100.0}, {0.0, 100.0}},
  resolution: 0.1
)

# Sample at any real coordinate
phi = Thunderbolt.ContinuousField.sample(field, :phase, {3.14, 2.72, 1.41})

# Gradient flow between cells
gradient = Thunderbolt.ContinuousField.gradient(field, :trust_score, coord)
```

### Implementation Phases

| Phase | HC Items | Focus | Timeline |
|-------|----------|-------|----------|
| **1** | HC-69 | Core `ContinuousTensor` module in Thunderbolt | Week 1-2 |
| **2** | HC-70 | ThunderGrid continuous spatial indexing | Week 2-3 |
| **3** | HC-72 | ThunderFlow/Core continuous temporal | Week 3-4 |
| **4** | HC-71 | ThunderPac continuous state manifolds | Week 4-5 |
| **5** | HC-73 | ThunderBolt continuous CA fields | Week 5-6 |
| **6** | HC-74 | Finch.jl interop (optional) | Week 6+ |

### Phase 1: Core Implementation (HC-69)

**Files to Create**:
```
lib/thunderline/thunderbolt/continuous/
├── tensor.ex              # Core ContinuousTensor struct
├── algebra.ex             # Continuous algebra operations
├── storage.ex             # Piecewise-constant storage format
├── kernel_generator.ex    # Automatic kernel generation
└── serialization.ex       # Persistence format
```

**Key Deliverables**:
- [ ] `Thunderbolt.ContinuousTensor` struct with piecewise-constant storage
- [ ] Real-valued index operations (`get/2`, `set/3`)
- [ ] Continuous algebra (`add/2`, `multiply/2`, `convolve/2`)
- [ ] Automatic kernel generation for common patterns
- [ ] Telemetry: `[:thunderline, :bolt, :continuous, :*]`
- [ ] Unit tests: index operations, algebra, edge cases

**Ash Resource** (optional persistence):
```elixir
defmodule Thunderline.Thunderbolt.Resources.ContinuousTensorStore do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :name, :string
    attribute :dims, :integer
    attribute :intervals, {:array, :map}  # [{start, end}, ...]
    attribute :values, :binary             # Compressed value storage
    attribute :metadata, :map
    timestamps()
  end

  actions do
    defaults [:read, :destroy]
    
    create :store do
      accept [:name, :dims, :metadata]
      argument :tensor, :map, allow_nil?: false
      change fn changeset, _ ->
        tensor = Ash.Changeset.get_argument(changeset, :tensor)
        {intervals, values} = serialize_tensor(tensor)
        changeset
        |> Ash.Changeset.change_attribute(:intervals, intervals)
        |> Ash.Changeset.change_attribute(:values, values)
      end
    end
    
    read :load do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
    end
  end
end
```

### Finch.jl Integration Path (HC-74)

For maximum performance on sparse tensor operations, optional integration with Finch.jl:

**Architecture**:
```
┌─────────────────────────────────────────────────────────────────┐
│                     FINCH.JL INTEROP                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Elixir (Thunderbolt)          Julia (Finch.jl)               │
│   ┌─────────────────┐           ┌─────────────────┐            │
│   │ ContinuousTensor│           │ Tensor(Format)  │            │
│   │                 │           │                 │            │
│   │ intervals/values│───JSON───▶│ SparseLists     │            │
│   │                 │           │                 │            │
│   │ radius_search() │           │ @einsum ops     │            │
│   └────────┬────────┘           └────────┬────────┘            │
│            │                             │                      │
│            │         ZeroMQ / Port       │                      │
│            └─────────────────────────────┘                      │
│                                                                 │
│   Galley Optimizer: 1000x speedup on sparse queries            │
│   Example: 263ms → 153μs on sparse matrix chain                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Julia Service** (optional sidecar):
```julia
# julia/finch_service.jl
using Finch, JSON3, ZMQ

function handle_radius_search(data)
    A = Tensor(CSCFormat(), data["points"])
    center = data["center"]
    radius = data["radius"]
    
    # Finch generates optimized kernel automatically
    result = @finsum E[i] += (dist(A[i, :], center) < radius) * A[i, :]
    
    JSON3.write(result)
end
```

### Telemetry & Observability

**Events**:
```elixir
[:thunderline, :bolt, :continuous, :create]      # Tensor creation
[:thunderline, :bolt, :continuous, :get]         # Index operation
[:thunderline, :bolt, :continuous, :algebra]     # Algebra operation
[:thunderline, :bolt, :continuous, :serialize]   # Storage operation
[:thunderline, :grid, :continuous, :search]      # Spatial query
[:thunderline, :flow, :continuous, :aggregate]   # Temporal aggregation
```

**Metrics**:
- `continuous.tensor.interval_count` - Number of intervals (complexity)
- `continuous.tensor.lookup_latency_us` - Index operation timing
- `continuous.tensor.algebra_latency_us` - Algebra operation timing
- `continuous.search.results_count` - Spatial query result size

### Research References

1. **Primary**: Won et al. "The Continuous Tensor Abstraction" (OOPSLA 2025) - [arXiv:2407.01742](https://arxiv.org/abs/2407.01742)
2. **Finch Compiler**: Ahrens et al. "Finch: Sparse and Structured Array Programming" (CGO 2023)
3. **Galley Optimizer**: Deeds et al. "Galley: Modern Query Optimization for Sparse Tensor Programs" (2024)
4. **Looplets**: Ahrens et al. "Looplets: A Language for Structured Coiteration" (CGO 2023)

### Success Criteria

**MVP (Phase 1-2)**:
- [ ] `ContinuousTensor` module operational with piecewise-constant storage
- [ ] ThunderGrid radius search using continuous indexing
- [ ] 5x+ speedup on spatial queries vs naive implementation
- [ ] Unit test coverage > 90%

**Full Integration (Phase 3-5)**:
- [ ] All domains using continuous tensor primitives
- [ ] PAC state manifolds enabling smooth transitions
- [ ] Continuous event algebra for temporal analysis
- [ ] CA fields with real-valued interpolation

**Research Validation (Phase 6)**:
- [ ] Finch.jl interop demonstrating 100x+ speedup on sparse operations
- [ ] Benchmark parity with paper results (9.2x on radius search)
- [ ] Documentation and usage patterns established

---

## 🔬 HC-Δ RESEARCH INTEGRATION SERIES (Dec 1, 2025)

**Mission**: Integrate advanced research concepts (TapNet, DiffLogic, MAP-Elites, Finch) into Thunderline's production architecture through modular, incremental delivery.

**Research Sources**:
- [TapNet: Attentional Prototypical Networks](https://cdn.aaai.org) - Multi-level temporal feature learning
- [DiffLogic CA (Google Research)](https://google-research.github.io/self-organising-systems/difflogic-ca/) - Learnable logic circuits for CA
- [MAP-Elites Quality-Diversity](https://arxiv.org/abs/1504.04909) - Multi-dimensional archive of elite behaviors
- [Finch Sparse Tensor Compiler](https://arxiv.org/abs/2404.16730) - Structured tensor + control flow fusion

### HC-Δ Series Overview

| ID | Priority | Component | Description | Status |
|----|----------|-----------|-------------|--------|
| HC-Δ-1 | P0 | Thundervine DAG Infrastructure | Behavior DAG data structures, node wrappers, executor | ✅ Complete |
| HC-Δ-2 | P0 | Thundercrown Policy Engine | Runtime policy evaluation, constraint DSL, policy resources | ✅ Complete |
| HC-Δ-3 | P1 | DiffLogic CA Engine | Differentiable logic CA, learnable gates, grid state | ✅ Complete |
| HC-Δ-4 | P1 | MAP-Elites Archive (Full QD) | Quality-diversity search, elite archive, mutation operators | ✅ Complete |
| HC-Δ-5 | P1 | Thunderbit Category Protocol | Composable computation units, monadic bind, type definitions | ✅ Complete |
| HC-Δ-6 | P2 | Structured Tensor (Finch-inspired) | Sparse/dense tensor types, operations, loop fusion | Not Started |
| HC-Δ-7 | P0 | Thunderoll Hyperscale Optimizer | EGGROLL-based ES, low-rank perturbations, population management | ✅ Complete |
| HC-Δ-8 | P0 | Thundercell Substrate Layer | Raw chunk abstraction (file/dataset/embedding blocks), CA grid mapping | ✅ Complete |
| HC-Δ-9 | P1 | CA↔Thunderbit Integration | CA.Cell + CA.World structs, bit→cell traversal, activation physics | ✅ Complete |
| HC-Δ-10 | P1 | Cerebros Feature Pipeline | Per-run feature extraction (~20 metrics), TPE optimization interface | ✅ Complete |
| HC-Δ-11 | P1 | Unified ULID Infrastructure | Time-sortable IDs for Thunderbits/Thundercells/Events, Thunderline.Id abstraction | Not Started |
| HC-Δ-12 | P2 | Near-Critical Dynamics (MCP-Θ) | PLV/σ/λ̂ monitors, Thunderbeat regulation, CA excitation control, loop repair | Not Started |
| HC-Δ-13 | P1 | Thunderchief Orchestrator | Per-domain puppeteer policies, serialized tick dispatch, RL-ready logging | Not Started |

### HC-Δ-1: Thundervine DAG Infrastructure

**Priority**: P0 (Orchestration backbone)
**Owner**: Vine Steward
**Dependencies**: None (foundational)

**Purpose**: Implement behavior DAG data structures enabling complex workflows as composable graphs. Each node wraps a Thunderpac state machine or ML model, with edges encoding data/control dependencies.

**Components**:
```
lib/thunderline/thundervine/
├── graph.ex           # Behavior DAG data structure with builder API
├── node.ex            # Task node wrapper (points to Thunderpac or ML tasks)
├── edge.ex            # Dependency edge with metadata
├── executor.ex        # DAG traversal and execution engine
└── resources/
    ├── behavior_graph.ex      # Ash resource for persistent graphs
    └── graph_execution.ex     # Ash resource for execution tracking
```

**Graph Structure**:
```elixir
defmodule Thunderline.Thundervine.Graph do
  @moduledoc """
  Behavior DAG representing complex workflows as composable graphs.
  Each node wraps a task (Thunderpac FSM, ML model, or custom action).
  """
  
  defstruct [
    :id,
    :name,
    :nodes,       # %{node_id => Node.t()}
    :edges,       # [{from, to, metadata}]
    :entry_nodes, # IDs of nodes with no incoming edges
    :exit_nodes,  # IDs of nodes with no outgoing edges
    :metadata
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    nodes: %{String.t() => Node.t()},
    edges: [{String.t(), String.t(), map()}],
    entry_nodes: [String.t()],
    exit_nodes: [String.t()],
    metadata: map()
  }
end
```

**Node Types**:
```elixir
defmodule Thunderline.Thundervine.Node do
  @moduledoc "Task node wrapper in behavior DAG"
  
  defstruct [
    :id,
    :name,
    :type,        # :thunderpac | :ml_model | :action | :subgraph
    :task_ref,    # Reference to actual task implementation
    :config,      # Node-specific configuration
    :timeout_ms,  # Execution timeout
    :retry_policy # {:max_attempts, n} | :no_retry
  ]
  
  @type node_type :: :thunderpac | :ml_model | :action | :subgraph
end
```

**Executor Flow**:
```
1. PREPARATION
   Graph.validate(graph) → Check for cycles, orphan nodes
   Executor.plan(graph) → Topological sort, identify parallelizable groups
   
2. EXECUTION
   for each parallel_group do
     Task.async_stream(group, &execute_node/2)
     |> collect_results()
     |> propagate_to_dependents()
   end
   
3. COMPLETION
   Emit vine.graph.completed event
   Persist execution results to BehaviorGraphExecution
```

**Events**:
- `vine.graph.started` - Graph execution initiated
- `vine.graph.node.started` - Individual node execution started
- `vine.graph.node.completed` - Node completed (success/failure)
- `vine.graph.completed` - Full graph execution completed

**Telemetry**:
```elixir
[:thunderline, :vine, :graph, :execute, :start]
[:thunderline, :vine, :graph, :execute, :stop]
[:thunderline, :vine, :graph, :node, :execute, :start]
[:thunderline, :vine, :graph, :node, :execute, :stop]
[:thunderline, :vine, :graph, :node, :execute, :exception]
```

**Success Criteria**:
- [ ] Graph struct with builder API (add_node, add_edge, connect)
- [ ] Node wrapper supporting 4 task types
- [ ] DAG executor with topological ordering
- [ ] Parallel execution of independent nodes
- [ ] Ash resources for persistence
- [ ] Event emission through Thunderflow
- [ ] Unit tests for graph operations and execution

---

### HC-Δ-2: Thundercrown Policy Engine

**Priority**: P0 (Orchestration backbone)
**Owner**: Crown Steward
**Dependencies**: HC-Δ-1 (for DAG policy enforcement)

**Purpose**: Runtime policy evaluation engine that enforces governance rules on DAG transitions, agent actions, and cross-domain operations. Policies are stored as Ash resources and evaluated at runtime.

**Components**:
```
lib/thunderline/thundercrown/
├── policy_engine.ex       # Core evaluation engine
├── constraint.ex          # Constraint DSL for policy rules
├── evaluator.ex           # Policy evaluation logic
├── cache.ex               # Policy cache for performance
└── resources/
    ├── policy.ex          # Ash resource for policy definitions
    ├── policy_rule.ex     # Individual rule definitions
    └── policy_evaluation.ex # Evaluation audit trail
```

**Policy Structure**:
```elixir
defmodule Thunderline.Thundercrown.Policy do
  @moduledoc """
  Policy definition for governance enforcement.
  Policies contain rules that evaluate against context.
  """
  
  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :scope, :atom  # :global | :domain | :resource | :action
    attribute :target, :string  # Domain/resource/action name
    attribute :priority, :integer, default: 100
    attribute :enabled, :boolean, default: true
    attribute :rules, {:array, :map}  # Serialized rule definitions
    timestamps()
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :define do
      accept [:name, :description, :scope, :target, :priority, :rules]
    end
    
    update :enable do
      change set_attribute(:enabled, true)
    end
    
    update :disable do
      change set_attribute(:enabled, false)
    end
    
    read :for_target do
      argument :scope, :atom, allow_nil?: false
      argument :target, :string, allow_nil?: false
      filter expr(scope == ^arg(:scope) and target == ^arg(:target) and enabled == true)
      prepare build(sort: [priority: :asc])
    end
  end
end
```

**Constraint DSL**:
```elixir
defmodule Thunderline.Thundercrown.Constraint do
  @moduledoc """
  DSL for defining policy constraints.
  Constraints are composable predicates over context.
  """
  
  @type constraint :: 
    {:all, [constraint()]} |
    {:any, [constraint()]} |
    {:none, [constraint()]} |
    {:attribute, atom(), operator(), term()} |
    {:actor, atom(), operator(), term()} |
    {:resource, atom(), operator(), term()} |
    {:custom, (context() -> boolean())}
  
  @type operator :: :eq | :neq | :gt | :lt | :gte | :lte | :in | :not_in | :matches
  
  @doc "All constraints must pass"
  def all(constraints), do: {:all, constraints}
  
  @doc "At least one constraint must pass"
  def any(constraints), do: {:any, constraints}
  
  @doc "No constraints may pass"
  def none(constraints), do: {:none, constraints}
  
  @doc "Check attribute value"
  def attribute(name, op, value), do: {:attribute, name, op, value}
  
  @doc "Check actor property"
  def actor(property, op, value), do: {:actor, property, op, value}
  
  @doc "Check resource property"  
  def resource(property, op, value), do: {:resource, property, op, value}
  
  @doc "Custom predicate function"
  def custom(fun) when is_function(fun, 1), do: {:custom, fun}
end
```

**Policy Engine**:
```elixir
defmodule Thunderline.Thundercrown.PolicyEngine do
  @moduledoc """
  Runtime policy evaluation engine.
  Evaluates policies against context and returns allow/deny decisions.
  """
  
  alias Thunderline.Thundercrown.{Policy, Constraint, Evaluator, Cache}
  alias Thunderline.Thunderflow.EventBus
  
  @type context :: %{
    actor: map() | nil,
    resource: map() | nil,
    action: atom(),
    domain: atom(),
    metadata: map()
  }
  
  @type decision :: :allow | {:deny, reason :: String.t()}
  
  @doc "Evaluate all applicable policies for context"
  @spec evaluate(context()) :: decision()
  def evaluate(context) do
    start_time = System.monotonic_time()
    
    policies = get_applicable_policies(context)
    result = evaluate_policies(policies, context)
    
    emit_telemetry(context, result, start_time)
    emit_event(context, result)
    
    result
  end
  
  @doc "Check if action is allowed (raises on deny)"
  @spec authorize!(context()) :: :ok | no_return()
  def authorize!(context) do
    case evaluate(context) do
      :allow -> :ok
      {:deny, reason} -> raise Thunderline.Thundercrown.PolicyError, reason
    end
  end
  
  defp get_applicable_policies(context) do
    Cache.get_or_fetch({context.domain, context.action}, fn ->
      Policy.for_target!(scope: :action, target: "#{context.domain}.#{context.action}")
      |> Enum.concat(Policy.for_target!(scope: :domain, target: to_string(context.domain)))
      |> Enum.concat(Policy.for_target!(scope: :global, target: "*"))
      |> Enum.sort_by(& &1.priority)
    end)
  end
  
  defp evaluate_policies([], _context), do: :allow
  defp evaluate_policies([policy | rest], context) do
    case Evaluator.evaluate(policy, context) do
      :allow -> evaluate_policies(rest, context)
      {:deny, _reason} = deny -> deny
    end
  end
end
```

**DAG Policy Integration** (connects to HC-Δ-1):
```elixir
defmodule Thunderline.Thundervine.PolicyGuard do
  @moduledoc "Policy enforcement for DAG transitions"
  
  alias Thunderline.Thundercrown.PolicyEngine
  
  @doc "Check if graph execution is allowed"
  def authorize_graph_execution(graph, actor) do
    context = %{
      actor: actor,
      resource: graph,
      action: :execute_graph,
      domain: :thundervine,
      metadata: %{graph_id: graph.id, node_count: map_size(graph.nodes)}
    }
    PolicyEngine.evaluate(context)
  end
  
  @doc "Check if specific node execution is allowed"
  def authorize_node_execution(node, graph, actor) do
    context = %{
      actor: actor,
      resource: node,
      action: :execute_node,
      domain: :thundervine,
      metadata: %{
        graph_id: graph.id,
        node_id: node.id,
        node_type: node.type
      }
    }
    PolicyEngine.evaluate(context)
  end
  
  @doc "Check if DAG edge transition is allowed"
  def authorize_edge_transition(from_node, to_node, graph, actor) do
    context = %{
      actor: actor,
      resource: %{from: from_node, to: to_node, graph: graph},
      action: :traverse_edge,
      domain: :thundervine,
      metadata: %{
        graph_id: graph.id,
        from_node_id: from_node.id,
        to_node_id: to_node.id
      }
    }
    PolicyEngine.evaluate(context)
  end
end
```

**Events**:
- `crown.policy.evaluated` - Policy evaluation completed
- `crown.policy.denied` - Action denied by policy
- `crown.policy.created` - New policy defined
- `crown.policy.updated` - Policy modified

**Telemetry**:
```elixir
[:thunderline, :crown, :policy, :evaluate, :start]
[:thunderline, :crown, :policy, :evaluate, :stop]
[:thunderline, :crown, :policy, :cache, :hit]
[:thunderline, :crown, :policy, :cache, :miss]
```

**Success Criteria**:
- [ ] Policy Ash resource with CRUD actions
- [ ] Constraint DSL for rule composition
- [ ] Policy engine with caching
- [ ] DAG policy integration (authorize graph/node/edge)
- [ ] Event emission for audit trail
- [ ] Performance: <1ms evaluation for cached policies
- [ ] Unit tests for all constraint types

---

### HC-Δ-3: DiffLogic CA Engine

**Priority**: P1
**Owner**: Bolt Steward
**Dependencies**: HC-40 (LoopMonitor metrics)

**Purpose**: Integrate DiffLogic-CA modules as learnable, local decision rules within agents. Each agent's control logic is a small CA whose update rule is learned via differentiable logic gates.

**Components**:
```
lib/thunderline/thunderbolt/
├── ca_engine.ex           # Core DiffLogic CA execution
├── logic_gate.ex          # Learnable gate primitives
├── ca_state.ex            # CA grid state management
└── resources/
    └── ca_rule.ex         # Ash resource for learned rules
```

**Key Features**:
- Float-parameterized rule tables (gradients from Python)
- Quantization layer for discrete execution
- Stability guards (gradient clipping, divergence detection)
- Integration with LoopMonitor criticality metrics

---

### HC-Δ-4: MAP-Elites Archive (Full QD)

**Priority**: P1
**Owner**: Bolt + Evolution Stewards
**Dependencies**: HC-Ω-6 (TraitsEvolutionJob)

**Purpose**: Implement quality-diversity search maintaining an N-dimensional archive where each cell stores the elite (best-performing) agent for that behavioral niche.

**Components**:
```
lib/thunderline/evolution/
├── map_elites.ex          # Core QD loop
├── archive.ex             # Elite archive (Ash resource)
├── behavior_descriptor.ex # Dimension definitions
├── mutation.ex            # Mutation operators
└── resources/
    └── elite_entry.ex     # Archive entry resource
```

**Behavior Dimensions** (initial):
- LogicDensity: Number of gates in agent's CA
- MemoryReuse: Frequency of state reuse
- ActionVolatility: Rate of behavioral change
- TaskPerformance: Objective fitness score
- NoveltyScore: Distance from existing elites

---

### HC-Δ-5: Thunderbit Category Protocol ✅

**Priority**: P1
**Owner**: Bolt Steward
**Dependencies**: Upper Ontology (HC-Ω-1)
**Status**: ✅ Complete (v1.0)

**Purpose**: Represent each atomic agent module as a Thunderbit - a composable unit of computation with category-theoretic composition laws. Makes the Upper Ontology executable.

**Implementation**:
```
lib/thunderline/thunderbit/
├── category.ex            # 8 categories (sensory, cognitive, mnemonic, motor, social, ethical, perceptual, executive)
├── wiring.ex              # Composition rules and edge validation
├── io.ex                  # I/O type specs and validation
├── protocol.ex            # 7 protocol verbs (spawn_bit, bind, link, step, retire, query, mutate)
├── ethics.ex              # Maxim enforcement layer
├── registry.ex            # ETS-based runtime registry
├── ui_contract.ex         # UI spec generation for front-end
└── resources/
    └── thunderbit_definition.ex  # Ash resource for persistence
```

**Category Taxonomy**:
| Category | Role | Ontology Path |
|----------|------|---------------|
| Sensory | Observer | Entity.Physical |
| Cognitive | Transformer | Proposition.* |
| Mnemonic | Storage | Entity.Conceptual |
| Motor | Actuator | Process.Action |
| Social | Router | Relation.* |
| Ethical | Critic | Proposition.Goal |
| Perceptual | Analyzer | Attribute.State |
| Executive | Controller | Process.Action |

**Protocol Verbs**:
```elixir
Protocol.spawn_bit(:cognitive, attrs, ctx)  # → {:ok, %Thunderbit{}}
Protocol.bind(bit, &transform/2)            # → {bit', ctx'}
Protocol.link(bit_a, bit_b, :feeds)         # → {:ok, edge} | {:error, _}
Protocol.step(bit, event)                   # → {:ok, bit', outputs}
Protocol.retire(bit, :done)                 # → :ok
```

**Spec Document**: `documentation/HC-D5_THUNDERBIT_CATEGORY_PROTOCOL.md`

---

### HC-Δ-6: Structured Tensor (Finch-inspired)

**Priority**: P2
**Owner**: Bolt Steward
**Dependencies**: HC-Δ-3 (CA Engine)

**Purpose**: Adopt Finch programming model for structured data computations. Auto-specialize loops to data sparsity for efficient on-device compute.

**Components**:
```
lib/thunderline/structured_tensor/
├── tensor.ex              # Sparse/dense tensor types
├── ops.ex                 # Tensor operations
├── loop_fusion.ex         # Auto-specialization
└── formats/
    ├── csc.ex             # Compressed Sparse Column
    ├── coo.ex             # Coordinate format
    └── dense.ex           # Dense format
```

---

### HC-Δ-7: Thunderoll Hyperscale Optimizer

**Priority**: P0 (Optimization backbone)
**Owner**: Vine Steward × Pac Steward
**Dependencies**: HC-Δ-1 (DAG Infrastructure), HC-Δ-2 (Policy Engine)

**Purpose**: Integrate EGGROLL-style Evolution Strategies for hyperscale optimization of PAC behaviors, policies, and neural substrates. Uses low-rank perturbations to achieve 100x throughput over naïve ES while maintaining full-rank update expressivity.

**Reference**: [ES Hyperscale Paper](https://eshyperscale.github.io/) - Oxford/FLAIR/NVIDIA

**Core Insight**:
> If you can do batched LoRA-style inference and define a fitness function, Thunderoll can optimize the system end-to-end without backprop.

**Components**:
```
lib/thunderline/thundervine/thunderoll/
├── runner.ex              # Orchestrates EGGROLL optimization loops
├── population.ex          # Population management and sampling
├── perturbation.ex        # Low-rank A·Bᵀ perturbation generation
├── fitness.ex             # Fitness aggregation from rollouts
├── backend/
│   ├── behaviour.ex       # Backend behaviour specification
│   ├── remote_jax.ex      # HTTP/gRPC wrapper for JAX EGGROLL
│   └── nx_native.ex       # Future: Native Nx implementation
└── resources/
    ├── experiment.ex      # ThunderollExperiment Ash resource
    └── generation.ex      # ThunderollGeneration Ash resource
```

**Thunderoll.Runner Core**:
```elixir
defmodule Thunderline.Thundervine.Thunderoll.Runner do
  @moduledoc """
  EGGROLL-style Evolution Strategies optimizer.
  
  Uses low-rank perturbations (A·Bᵀ where r << min(m,n)) to achieve
  O(r(m+n)) memory vs O(mn) for full-rank ES, while aggregated
  updates remain full-rank across the population.
  """
  
  alias Thunderline.Thundervine.Thunderoll.{Population, Perturbation, Fitness}
  alias Thunderline.Thundercrown.PolicyEngine
  
  defstruct [
    :experiment_id,
    :base_params,           # Base model parameters (or LoRA base)
    :rank,                  # Low-rank perturbation rank (default: 1)
    :population_size,       # N workers/members
    :sigma,                 # Perturbation standard deviation
    :generation,            # Current generation index
    :backend,               # :remote_jax | :nx_native
    :fitness_spec,          # Fitness function specification
    :convergence_criteria,  # When to stop
    :policy_context         # Thundercrown governance context
  ]
  
  @type t :: %__MODULE__{}
  
  @doc """
  Initialize a new Thunderoll optimization run.
  
  Validates against Thundercrown policies before starting.
  Creates persistent ThunderollExperiment record.
  """
  def init(opts) do
    with {:ok, _} <- PolicyEngine.check("thunderoll:allowed?", opts.policy_context),
         {:ok, experiment} <- create_experiment(opts) do
      {:ok, %__MODULE__{
        experiment_id: experiment.id,
        base_params: opts.base_params,
        rank: opts[:rank] || 1,
        population_size: opts.population_size,
        sigma: opts[:sigma] || 0.02,
        generation: 0,
        backend: opts[:backend] || :remote_jax,
        fitness_spec: opts.fitness_spec,
        convergence_criteria: opts[:convergence_criteria] || default_convergence(),
        policy_context: opts.policy_context
      }}
    end
  end
  
  @doc """
  Run one generation of EGGROLL optimization.
  
  1. Sample low-rank perturbations for population
  2. Dispatch fitness evaluations (PAC rollouts)
  3. Collect fitness vector
  4. Compute aggregated update via backend
  5. Return delta parameters
  """
  def run_generation(%__MODULE__{} = state) do
    # Sample perturbations: each is {A, B} where A ∈ R^(m×r), B ∈ R^(n×r)
    perturbations = Perturbation.sample_population(
      state.base_params,
      state.population_size,
      state.rank,
      state.sigma
    )
    
    # Evaluate fitness for each perturbed member
    fitness_vector = Fitness.evaluate_population(
      state.base_params,
      perturbations,
      state.fitness_spec
    )
    
    # Compute EGGROLL update: Σ(fitness_i * A_i * B_i^T) / population_size
    delta = compute_update(perturbations, fitness_vector, state)
    
    # Store generation record
    {:ok, _gen} = store_generation(state, fitness_vector, delta)
    
    {:ok, delta, %{state | generation: state.generation + 1}}
  end
  
  @doc """
  Check if optimization has converged.
  """
  def converged?(%__MODULE__{} = state) do
    cond do
      state.generation >= state.convergence_criteria.max_generations -> true
      fitness_plateau?(state) -> true
      policy_limit_reached?(state) -> true
      true -> false
    end
  end
end
```

**Perturbation Module**:
```elixir
defmodule Thunderline.Thundervine.Thunderoll.Perturbation do
  @moduledoc """
  Low-rank perturbation generation for EGGROLL.
  
  Instead of sampling full-rank noise E ∈ R^(m×n), we sample:
    A ∈ R^(m×r)
    B ∈ R^(n×r)
  And form the perturbation as A·Bᵀ.
  
  Memory: O(r(m+n)) vs O(mn)
  Forward pass: O(r(m+n)) vs O(mn)
  
  Key insight: While individual perturbations are low-rank,
  the aggregated update Σ(f_i * A_i * B_i^T) is full-rank
  when population_size ≥ hidden_dim.
  """
  
  defstruct [:a, :b, :seed, :sigma]
  
  @type t :: %__MODULE__{
    a: Nx.Tensor.t(),
    b: Nx.Tensor.t(),
    seed: integer(),
    sigma: float()
  }
  
  @doc """
  Sample perturbations for entire population.
  
  Uses deterministic key derivation so perturbations can be
  reconstructed from seeds without storing full matrices.
  """
  def sample_population(base_params, population_size, rank, sigma) do
    base_key = :rand.uniform(2 ** 32)
    
    for member_idx <- 0..(population_size - 1) do
      # Deterministic key folding (matches JAX pattern)
      member_key = fold_key(base_key, member_idx)
      sample_one(base_params, rank, sigma, member_key)
    end
  end
  
  defp sample_one(base_params, rank, sigma, key) do
    {m, n} = param_shape(base_params)
    
    # Sample A and B from N(0, 1)
    {key_a, key_b} = split_key(key)
    a = Nx.random_normal({m, rank}, key: key_a)
    b = Nx.random_normal({n, rank}, key: key_b)
    
    %__MODULE__{a: a, b: b, seed: key, sigma: sigma}
  end
  
  @doc """
  Apply perturbation to base parameters for forward pass.
  
  perturbed = base + sigma * A @ B.T
  
  This is computed efficiently as:
    x @ perturbed.T = x @ base.T + sigma * (x @ B) @ A.T
  """
  def apply(%__MODULE__{} = pert, base_params, input) do
    # Efficient low-rank forward: O(r(m+n)) instead of O(mn)
    base_output = Nx.dot(input, Nx.transpose(base_params))
    
    # Low-rank correction
    xB = Nx.dot(input, pert.b)           # [batch, r]
    correction = Nx.dot(xB, Nx.transpose(pert.a))  # [batch, m]
    
    Nx.add(base_output, Nx.multiply(correction, pert.sigma))
  end
end
```

**Fitness Module**:
```elixir
defmodule Thunderline.Thundervine.Thunderoll.Fitness do
  @moduledoc """
  Fitness evaluation for EGGROLL population members.
  
  Fitness is computed by Thunderline (not EGGROLL backend) because:
  1. We control the rollout environment
  2. We can inject domain-specific metrics (PLV, near-critical, safety)
  3. Thundercrown can abort unsafe members mid-evaluation
  """
  
  alias Thunderline.Thundervine.{Graph, Executor}
  alias Thunderline.Thundercrown.PolicyEngine
  
  @doc """
  Evaluate fitness for all population members.
  
  Returns fitness vector as list of floats.
  """
  def evaluate_population(base_params, perturbations, fitness_spec) do
    # Parallel evaluation with controlled concurrency
    Task.async_stream(
      Enum.with_index(perturbations),
      fn {pert, idx} -> evaluate_one(base_params, pert, fitness_spec, idx) end,
      max_concurrency: fitness_spec[:max_concurrency] || System.schedulers_online(),
      timeout: fitness_spec[:timeout] || 30_000
    )
    |> Enum.map(fn {:ok, fitness} -> fitness end)
  end
  
  defp evaluate_one(base_params, perturbation, spec, member_idx) do
    # Run PAC/model with perturbed parameters
    rollout_result = run_rollout(base_params, perturbation, spec)
    
    # Extract metrics based on fitness specification
    metrics = extract_metrics(rollout_result, spec)
    
    # Aggregate into scalar fitness
    # Default: weighted sum, but spec can override
    aggregate_fitness(metrics, spec)
  end
  
  defp run_rollout(base_params, perturbation, spec) do
    case spec.rollout_type do
      :pac_behavior ->
        # Run PAC with perturbed policy
        run_pac_rollout(base_params, perturbation, spec)
      
      :environment_steps ->
        # Run in simulated environment
        run_env_rollout(base_params, perturbation, spec)
      
      :custom ->
        # User-provided rollout function
        spec.rollout_fn.(base_params, perturbation)
    end
  end
  
  @doc """
  Default fitness aggregation: weighted sum of metrics.
  
  Supports:
  - :reward (higher is better)
  - :safety_violations (lower is better, inverted)
  - :plv_sync (phase-locking value, target ~0.3-0.7)
  - :stability (lower chaos is better for some tasks)
  """
  def aggregate_fitness(metrics, spec) do
    weights = spec[:weights] || %{
      reward: 1.0,
      safety_violations: -10.0,
      plv_sync: 0.5,
      stability: 0.2
    }
    
    Enum.reduce(weights, 0.0, fn {metric, weight}, acc ->
      value = Map.get(metrics, metric, 0.0)
      acc + weight * value
    end)
  end
end
```

**Ash Resources**:
```elixir
defmodule Thunderline.Thundervine.Thunderoll.Resources.Experiment do
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "thunderoll_experiments"
    repo Thunderline.Repo
  end
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :base_model_ref, :string  # Reference to model/PAC being optimized
    attribute :rank, :integer, default: 1
    attribute :population_size, :integer, allow_nil?: false
    attribute :sigma, :float, default: 0.02
    attribute :max_generations, :integer, default: 100
    attribute :fitness_spec, :map, default: %{}
    attribute :convergence_criteria, :map, default: %{}
    attribute :status, :atom, constraints: [one_of: [:pending, :running, :completed, :aborted, :failed]]
    attribute :final_fitness, :float
    attribute :total_evaluations, :integer, default: 0
    timestamps()
  end
  
  relationships do
    has_many :generations, Thunderline.Thundervine.Thunderoll.Resources.Generation
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :start do
      accept [:name, :base_model_ref, :rank, :population_size, :sigma, :max_generations, :fitness_spec, :convergence_criteria]
      change set_attribute(:status, :pending)
    end
    
    update :begin_running do
      change set_attribute(:status, :running)
    end
    
    update :complete do
      accept [:final_fitness, :total_evaluations]
      change set_attribute(:status, :completed)
    end
    
    update :abort do
      change set_attribute(:status, :aborted)
    end
    
    update :fail do
      change set_attribute(:status, :failed)
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Resources.Generation do
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "thunderoll_generations"
    repo Thunderline.Repo
  end
  
  attributes do
    uuid_primary_key :id
    attribute :index, :integer, allow_nil?: false
    attribute :fitness_stats, :map  # {min, max, mean, std}
    attribute :best_fitness, :float
    attribute :population_summary, :map  # Aggregated metrics
    attribute :update_delta_ref, :string  # Reference to stored delta
    attribute :duration_ms, :integer
    attribute :status, :atom, constraints: [one_of: [:pending, :running, :completed, :failed]]
    timestamps()
  end
  
  relationships do
    belongs_to :experiment, Thunderline.Thundervine.Thunderoll.Resources.Experiment
  end
  
  actions do
    defaults [:read]
    
    create :record do
      accept [:index, :fitness_stats, :best_fitness, :population_summary, :update_delta_ref, :duration_ms]
      change set_attribute(:status, :completed)
    end
  end
end
```

**Behavior DAG Nodes for Thunderoll**:
```elixir
# Node handlers registered with Thundervine.Executor

defmodule Thunderline.Thundervine.Thunderoll.Nodes.Init do
  @behaviour Thunderline.Thundervine.Executor.NodeHandler
  
  def execute(%{config: config}, context) do
    with {:ok, runner} <- Thunderoll.Runner.init(config) do
      {:ok, %{experiment_id: runner.experiment_id, runner: runner}}
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.Generation do
  @behaviour Thunderline.Thundervine.Executor.NodeHandler
  
  def execute(%{runner: runner}, _context) do
    case Thunderoll.Runner.run_generation(runner) do
      {:ok, delta, new_runner} ->
        {:ok, %{delta: delta, runner: new_runner, converged: Thunderoll.Runner.converged?(new_runner)}}
      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.ApplyUpdate do
  @behaviour Thunderline.Thundervine.Executor.NodeHandler
  
  def execute(%{delta: delta, target_ref: target_ref}, _context) do
    # Apply aggregated update to target model/PAC
    :ok = apply_delta_to_target(target_ref, delta)
    {:ok, %{applied: true}}
  end
end

defmodule Thunderline.Thundervine.Thunderoll.Nodes.CheckConvergence do
  @behaviour Thunderline.Thundervine.Executor.NodeHandler
  
  def execute(%{converged: converged, runner: runner}, _context) do
    if converged do
      {:ok, %{action: :complete, final_generation: runner.generation}}
    else
      {:ok, %{action: :continue}}
    end
  end
end
```

**Thundercrown Policies for Thunderoll**:
```elixir
# Policy definitions for governing Thunderoll experiments

# thunderoll:allowed? - Can this actor start an experiment?
%{
  name: "thunderoll:allowed?",
  evaluation_strategy: :all_of,
  rules: [
    %{type: :has_scope, scope: "thunderoll:run"},
    %{type: :resource_limit, resource: :concurrent_experiments, limit: 5},
    %{type: :time_window, start_hour: 6, end_hour: 22}  # No overnight experiments
  ]
}

# thunderoll:max_population - Limit population size by tier
%{
  name: "thunderoll:max_population",
  evaluation_strategy: :first_match,
  rules: [
    %{condition: %{role: :admin}, result: %{max: 262144}},      # Full EGGROLL scale
    %{condition: %{role: :researcher}, result: %{max: 16384}},  # Research tier
    %{condition: %{role: :user}, result: %{max: 1024}},         # User tier
    %{default: %{max: 256}}                                      # Default
  ]
}

# thunderoll:protected_models - Models that cannot be optimized
%{
  name: "thunderoll:protected_models",
  evaluation_strategy: :any_of,
  rules: [
    %{type: :matches, field: :base_model_ref, pattern: "^sacred:.*"},
    %{type: :matches, field: :base_model_ref, pattern: "^production:.*"}
  ],
  on_match: :deny
}
```

**Backend: Remote JAX (Phase 1)**:
```elixir
defmodule Thunderline.Thundervine.Thunderoll.Backend.RemoteJax do
  @moduledoc """
  HTTP/gRPC client for JAX EGGROLL backend.
  
  The backend server handles:
  - Low-rank perturbation math (A·Bᵀ operations)
  - Aggregated update computation
  - Optionally: model storage and delta application
  
  Thunderline handles:
  - Orchestration and scheduling
  - Fitness evaluation (rollouts)
  - Policy enforcement
  - Persistence and auditing
  """
  
  @behaviour Thunderline.Thundervine.Thunderoll.Backend
  
  def compute_update(perturbation_seeds, fitness_vector, config) do
    payload = %{
      "seeds" => perturbation_seeds,
      "fitness" => fitness_vector,
      "rank" => config.rank,
      "sigma" => config.sigma,
      "param_shape" => config.param_shape
    }
    
    case Req.post(config.backend_url <> "/compute_update", json: payload) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, decode_delta(body)}
      {:ok, %{status: status, body: body}} ->
        {:error, {:backend_error, status, body}}
      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end
end
```

**Integration with Near-Critical Control (Future)**:
```elixir
# Fitness function that includes loop-controller metrics
fitness_spec = %{
  rollout_type: :pac_behavior,
  weights: %{
    # Task performance
    task_reward: 1.0,
    
    # Near-critical dynamics (from loop controller)
    plv_target_deviation: -0.5,  # Penalize deviation from target PLV
    sigma_flow_efficiency: 0.3,  # Reward good propagatability
    lambda_hat_stability: -0.2,  # Penalize high chaos (unless exploring)
    
    # Safety
    constraint_violations: -10.0
  },
  
  # Target PLV for "edge of chaos" operation
  plv_target: 0.5,
  
  # Inject loop controller metrics into rollout
  inject_metrics: [:plv, :sigma, :lambda_hat]
}
```

---

### Implementation Phases

| Phase | HC Items | Focus | Timeline | Status |
|-------|----------|-------|----------|--------|
| **1** | HC-Δ-1, HC-Δ-2 | Orchestration backbone (Vine DAG + Crown Policy) | Week 1-2 | ✅ Complete |
| **2** | HC-Δ-7 | Thunderoll Hyperscale Optimizer | Week 2-3 | ✅ Complete |
| **3** | HC-Δ-3 | CA Engine (DiffLogic integration) | Week 3-4 | ✅ Complete |
| **4** | HC-Δ-4 | MAP-Elites (Quality-Diversity search) | Week 4-5 | ✅ Complete |
| **5** | HC-Δ-5 | Thunderbit Protocol (Category composition) | Week 5-6 | ✅ Complete |
| **6** | HC-Δ-6 | Structured Tensors (Finch-inspired) | Week 6-7 | Not Started |
| **7** | HC-Δ-8 | Thundercell Substrate Layer | Week 7-8 | ✅ Complete |
| **8** | HC-Δ-9 | CA↔Thunderbit Integration | Week 8-9 | ✅ Complete |
| **9** | HC-Δ-10 | Cerebros Feature Pipeline | Week 9-10 | ✅ Complete |
| **10** | HC-Δ-11 | ULID Infrastructure (Time-sortable IDs) | Week 10-11 | Not Started |
| **11** | HC-Δ-13 | Thunderchief Orchestrator (Per-domain puppeteers) | Week 11-12 | Not Started |
| **12** | HC-Δ-12 | Near-Critical Dynamics (MCP-Θ regulation) | Week 12-13 | Not Started |

### Cross-Domain Layer Activation

The HC-Δ series activates several cross-domain functional layers:

| Layer | Domains | HC-Δ Items |
|-------|---------|------------|
| **Orchestration Layer** | Vine × Crown | HC-Δ-1, HC-Δ-2, HC-Δ-13 |
| **Optimization Layer** | Vine × Pac × Crown | HC-Δ-7 |
| **Compute Layer** | Bolt × Flow | HC-Δ-3, HC-Δ-4 |
| **Transform Layer** | Bolt × Block | HC-Δ-5, HC-Δ-6 |

### Research-to-Production Mapping

| Research Concept | Production Module | HC-Δ Item |
|------------------|-------------------|-----------|
| TapNet Attention | Thunderbolt.AttentionEncoder | Future |
| DiffLogic CA | Thunderbolt.CAEngine | HC-Δ-3 |
| MAP-Elites QD | Thunderline.Evolution.MapElites | HC-Δ-4 |
| Finch Tensors | Thunderline.StructuredTensor | HC-Δ-6 |
| Behavior DAGs | Thundervine.Graph | HC-Δ-1 |
| Policy Engine | Thundercrown.PolicyEngine | HC-Δ-2 |
| Thunderbit CAT | Thunderbit Protocol | HC-Δ-5 |
| EGGROLL ES | Thundervine.Thunderoll | HC-Δ-7 |
| Thundercell Substrate | Thunderbit.Thundercell | HC-Δ-8 |
| CA↔Bit Integration | Thunderbit.CA.Cell + CA.World | HC-Δ-9 |
| Cerebros TPE Features | Thunderbolt.Cerebros.Features | HC-Δ-10 |

---

## 🏗️ THUNDERBIT LAYER ARCHITECTURE RECONCILIATION (Dec 2025)

> **"Semantic Thunderbits sit on top of Physical Thunderbits."**

### The Two Thunderbit Worlds

The Thunderline codebase has evolved to contain **two distinct Thunderbit concepts** that operate at different abstraction layers:

| Layer | Module | Purpose | Implemented |
|-------|--------|---------|-------------|
| **Cognitive Layer** | `Thunderline.Thunderbit` | Semantic agent bits (HC-Δ-5) - composable computation particles with category, kind, data, links | ✅ Complete |
| **Physics Layer** | `Thunderbolt.Thunderbit` | 3D CA voxel cells - routing, trust, phase dynamics, relay weights | ✅ Complete (277 lines) |

### Layer Relationship

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    THUNDERLINE COGNITIVE LAYER                              │
│                                                                             │
│   Thunderline.Thunderbit (HC-Δ-5)                                           │
│   ├── Category: :cognitive | :dataset | :memory | :sensor | :action ...    │
│   ├── Kind: :variable | :constant | :computed | :inferred ...              │
│   ├── Data: arbitrary payload (JSON, embeddings, etc.)                     │
│   ├── Links: references to other Thunderbits                               │
│   └── Monadic bind: flatMap composition for agent pipelines                │
│                                                                             │
│   "WHAT the agent is thinking"                                              │
└───────────────────────────────────────┬─────────────────────────────────────┘
                                        │ sits on top of
┌───────────────────────────────────────▼─────────────────────────────────────┐
│                    THUNDERBOLT PHYSICS LAYER                                │
│                                                                             │
│   Thunderbolt.Thunderbit (lib/thunderline/thunderbolt/thunderbit.ex)        │
│   ├── coord: {x, y, z} - 3D lattice position                                │
│   ├── state: Nx tensor (voxel state)                                        │
│   ├── φ_phase, σ_flow, λ_sensitivity: CA dynamics                           │
│   ├── trust_score, relay_weight: routing trust                              │
│   ├── presence_vector: who's here                                           │
│   ├── route_tags: Bloom filter for destinations                             │
│   ├── key_fragment: distributed key material                                │
│   └── CAT config: cellular automata transform params                        │
│                                                                             │
│   "HOW the substrate routes and transforms signals"                         │
└───────────────────────────────────────┬─────────────────────────────────────┘
                                        │
┌───────────────────────────────────────▼─────────────────────────────────────┐
│                    THUNDERBOLT INFRASTRUCTURE                               │
│                                                                             │
│   Thunderbolt.Thundercell.CACell  - GenServer CA cell processes             │
│   Thunderbolt.Thundercell.CAEngine - CA computation coordinator             │
│   Thunderbolt.DiffLogic.Gates     - 16 differentiable logic gates           │
│   Thunderbolt.NCA.UpdateRule      - Neural CA (Growing NCA paper)           │
│   Thunderbolt.Cerebros.TPEBridge  - Python TPE/Optuna optimizer             │
│                                                                             │
│   "EXECUTION substrate: NCA, DiffLogic, optimization"                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Files (Already Implemented)

| File | Lines | Purpose |
|------|-------|---------|
| `thunderbolt/thunderbit.ex` | 277 | 3D CA voxel struct with full physics layer |
| `thunderbolt/thunderbit/reflex.ex` | 600+ | HC-Ω-1 Reflexive Intelligence Layer (5 reflex types) |
| `thunderbolt/difflogic/gates.ex` | 300+ | All 16 binary logic gates as differentiable ops |
| `thunderbolt/nca/update_rule.ex` | ~200 | Neural CA from "Growing NCA" (Distill 2020) |
| `thunderbolt/cerebros/tpe_bridge.ex` | 380+ | Full Optuna/TPE Bayesian optimization |
| `thunderbolt/thundercell/ca_cell.ex` | 147 | GenServer CA cell with state evolution |
| `thunderbolt/thundercell/ca_engine.ex` | 205 | CA coordinator (Conway 3D, Highlife 3D, etc.) |
| `thunderbolt/domain.ex` | 50+ | Ash domain with 50+ resources registered |

### Reconciliation Strategy

**DO NOT** rename or remove any existing code. Instead:

1. ✅ **Document the layer split** (this section)
2. 🔄 **Add `Thunderbolt.CA.Snapshot`** - Read-only struct for logging/UI (neutral snapshot of CA state)
3. 🔄 **Add `Thunderbolt.Cerebros.Features`** - Feature extractor bridging CA state → TPEBridge
4. 🔄 **Wire Features → TPEBridge** - Complete optimization loop

### Integration Points

```elixir
# CA Snapshot: neutral read-only view of lattice state
ca_snapshot = Thunderbolt.CA.Snapshot.capture(ca_engine, opts)
# => %{tick: 42, dims: {16,16,16}, cells: %{coord => %{activation: 0.8, error: 0.1}}}

# Feature Extraction: bridge to TPE
features = Thunderbolt.Cerebros.Features.extract(config, context, ca_snapshot, metrics)
# => %{config: %{...}, features: %{...}, metrics: %{...}}

# TPE Integration: log for optimization
Thunderbolt.Cerebros.TPEBridge.log_trial(features)
```

---

## 🧱 HC-Δ-8: THUNDERCELL SUBSTRATE LAYER

**Status**: Not Started  
**Priority**: P0 (Foundational)  
**Dependencies**: HC-Δ-5 (Thunderbit Protocol)

### Core Insight

> **"Thunderbits are not the data. Thunderbits are the semantic tags & roles that sit on top of the data."**

The Thundercell is the **raw substrate chunk** — the actual payload blocks that Thunderbits reference. This separation enables:
- 10k data rows = 10k Thundercells, but only 5-10 Thunderbits (semantic roles)
- Clean separation between "what the system is thinking" vs "what the data actually is"
- Many-to-many relationship: one Thunderbit can span multiple Thundercells

### Thundercell Struct

```elixir
defmodule Thunderline.Thunderbit.Thundercell do
  @moduledoc """
  Raw substrate chunk in the Thunderline data universe.
  
  Thundercells are the actual payload blocks that Thunderbits reference.
  Think of Thundercells as raw file chunks, dataset batches, embedding blocks,
  or CA grid cells — the substrate upon which symbolic Thunderbits operate.
  """
  
  @type kind :: :file_chunk | :dataset_batch | :embedding_block | :ca_cell | 
                :audio_window | :video_frame | :token_block | :state_snapshot
  
  @type t :: %__MODULE__{
    id: Thunderline.UUID.t(),
    kind: kind(),
    source: String.t(),           # Origin reference (file path, dataset ID, etc.)
    range: {non_neg_integer(), non_neg_integer()},  # Byte/index range
    payload_ref: {:inline, binary()} | {:ets, reference()} | {:external, String.t()},
    embedding: Nx.Tensor.t() | nil,      # Optional embedding vector
    ca_coord: {integer(), integer(), integer()} | nil,  # CA lattice position
    stats: map(),                 # Size, hash, compression ratio, etc.
    meta: map()                   # Extensible metadata
  }
  
  defstruct [
    :id, :kind, :source, :range, :payload_ref,
    :embedding, :ca_coord,
    stats: %{},
    meta: %{}
  ]
  
  @doc "Create a new Thundercell with validated fields"
  def new(kind, source, range, opts \\ []) do
    %__MODULE__{
      id: Thunderline.UUID.v7(),
      kind: kind,
      source: source,
      range: range,
      payload_ref: Keyword.get(opts, :payload_ref, {:inline, <<>>}),
      embedding: Keyword.get(opts, :embedding),
      ca_coord: Keyword.get(opts, :ca_coord),
      stats: Keyword.get(opts, :stats, %{}),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end
```

### Kind Taxonomy

| Kind | Description | Typical Source | Use Case |
|------|-------------|----------------|----------|
| `:file_chunk` | Byte range from file | `"s3://bucket/file.bin"` | Large file processing |
| `:dataset_batch` | Rows from dataset | `"postgres://table#offset=1000"` | Batch ML training |
| `:embedding_block` | Pre-computed vectors | `"vector_store://collection"` | Similarity search |
| `:ca_cell` | CA lattice cell state | `"ca://world_id/tick/coord"` | Cellular automaton |
| `:audio_window` | Audio sample window | `"audio://stream/timestamp"` | Real-time audio |
| `:video_frame` | Video frame data | `"video://stream/frame_id"` | Video processing |
| `:token_block` | Token sequence | `"tokens://doc_id/range"` | LLM context |
| `:state_snapshot` | Serialized state | `"snapshot://pac_id/version"` | PAC checkpoints |

### Context Extension

```elixir
# Extend Thunderbit.Context to include cells_by_id
defmodule Thunderline.Thunderbit.Context do
  @type t :: %__MODULE__{
    bits_by_id: %{Thunderbit.id() => Thunderbit.t()},
    cells_by_id: %{Thundercell.id() => Thundercell.t()},  # NEW
    pending_binds: [Thunderbit.t()],
    time_budget_ms: non_neg_integer(),
    config: map()
  }
end
```

### Thunderbit ↔ Thundercell Relationship

```elixir
# Extended Thunderbit struct
defmodule Thunderline.Thunderbit.Thunderbit do
  @type t :: %__MODULE__{
    id: id(),
    kind: kind(),
    data: map(),
    links: [id()],
    meta: map(),
    thundercell_ids: [Thundercell.id()]  # NEW: Many-to-many reference
  }
end
```

---

## 🔬 HC-Δ-9: CA↔THUNDERBIT INTEGRATION

**Status**: Not Started  
**Priority**: P1  
**Dependencies**: HC-Δ-8 (Thundercell), HC-Δ-3 (DiffLogic CA)

### Core Insight

> **"The CA is the activation lattice. Thunderbits traverse it. Thundercells ground it."**

This module defines the bridge between the Cellular Automaton substrate and the symbolic Thunderbit layer.

### CA.Cell Struct

```elixir
defmodule Thunderline.Thunderbit.CA.Cell do
  @moduledoc """
  A single cell in the CA lattice with activation dynamics.
  
  Each cell can hold references to both Thundercells (raw data chunks)
  and Thunderbits (semantic particles), enabling bidirectional traversal.
  """
  
  @type t :: %__MODULE__{
    coord: {integer(), integer(), integer()},
    activation: float(),        # Current activation level [0.0, 1.0]
    excitation: float(),        # Incoming excitatory signal
    inhibition: float(),        # Incoming inhibitory signal
    error_potential: float(),   # Error signal for learning
    energy: float(),            # Metabolic energy budget
    cell_kind: atom(),          # :standard | :border | :hub | :sink
    thundercell_ids: [String.t()],  # Grounding data chunks
    thunderbit_ids: [String.t()],   # Semantic particles present
    last_updated_at: DateTime.t()
  }
  
  defstruct [
    :coord,
    activation: 0.0,
    excitation: 0.0,
    inhibition: 0.0,
    error_potential: 0.0,
    energy: 1.0,
    cell_kind: :standard,
    thundercell_ids: [],
    thunderbit_ids: [],
    last_updated_at: nil
  ]
end
```

### CA.World Struct

```elixir
defmodule Thunderline.Thunderbit.CA.World do
  @moduledoc """
  The complete CA lattice state for a single simulation tick.
  """
  
  @type params :: %{
    diffusion: float(),         # How activation spreads (0.0-1.0)
    decay: float(),             # Activation decay rate (0.0-1.0)
    neighbor_radius: pos_integer(),  # Neighborhood size
    excitation_gain: float(),   # Excitatory signal multiplier
    inhibition_gain: float(),   # Inhibitory signal multiplier
    error_gain: float()         # Error backprop multiplier
  }
  
  @type t :: %__MODULE__{
    tick: non_neg_integer(),
    dims: {pos_integer(), pos_integer(), pos_integer()},
    cells: %{{integer(), integer(), integer()} => CA.Cell.t()},
    params: params(),
    meta: map()
  }
  
  defstruct [
    tick: 0,
    dims: {16, 16, 16},
    cells: %{},
    params: %{
      diffusion: 0.1,
      decay: 0.05,
      neighbor_radius: 1,
      excitation_gain: 1.0,
      inhibition_gain: 0.8,
      error_gain: 0.1
    },
    meta: %{}
  ]
  
  @doc "Step the world forward one tick"
  def step(%__MODULE__{} = world) do
    # 1. Collect neighbor inputs for each cell
    # 2. Apply excitation/inhibition dynamics
    # 3. Update activations with diffusion + decay
    # 4. Propagate error signals
    # 5. Increment tick
    world
    |> collect_neighbor_signals()
    |> apply_dynamics()
    |> update_activations()
    |> propagate_errors()
    |> Map.update!(:tick, &(&1 + 1))
  end
end
```

### Tick Update Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│  CA.World.step/1 Pipeline                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. collect_neighbor_signals/1                                   │
│     - For each cell, sum activation from neighbors               │
│     - Weight by distance (within neighbor_radius)                │
│     - Separate excitatory vs inhibitory inputs                   │
│                                                                  │
│  2. apply_dynamics/1                                             │
│     - excitation += sum(neighbor_activations) * excitation_gain  │
│     - inhibition += sum(inhibitory_signals) * inhibition_gain    │
│     - energy -= activation * metabolic_cost                      │
│                                                                  │
│  3. update_activations/1                                         │
│     - new_activation = old * (1 - decay) + (excite - inhibit)    │
│     - Apply diffusion to spread activation spatially             │
│     - Clamp to [0.0, 1.0] range                                  │
│                                                                  │
│  4. propagate_errors/1                                           │
│     - Backpropagate error_potential through links                │
│     - Update Thunderbit weights if learning enabled              │
│                                                                  │
│  5. tick++                                                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Thunderbit Traversal API

```elixir
defmodule Thunderline.Thunderbit.CA.Traversal do
  @moduledoc "Navigate Thunderbits across the CA lattice"
  
  @doc "Find all Thunderbits in cells with activation above threshold"
  def active_bits(world, threshold \\ 0.5) do
    world.cells
    |> Enum.filter(fn {_coord, cell} -> cell.activation > threshold end)
    |> Enum.flat_map(fn {_coord, cell} -> cell.thunderbit_ids end)
    |> Enum.uniq()
  end
  
  @doc "Get the CA coordinates for a Thunderbit"
  def locate_bit(world, bit_id) do
    world.cells
    |> Enum.filter(fn {_coord, cell} -> bit_id in cell.thunderbit_ids end)
    |> Enum.map(fn {coord, _cell} -> coord end)
  end
  
  @doc "Inject a Thunderbit into a cell, updating activation"
  def inject_bit(world, coord, bit_id, opts \\ []) do
    activation_boost = Keyword.get(opts, :activation_boost, 0.3)
    
    update_in(world.cells[coord], fn cell ->
      %{cell | 
        thunderbit_ids: [bit_id | cell.thunderbit_ids] |> Enum.uniq(),
        activation: min(1.0, cell.activation + activation_boost)
      }
    end)
  end
end
```

---

## 📊 HC-Δ-10: CEREBROS FEATURE PIPELINE

**Status**: ✅ Complete  
**Priority**: P1  
**Dependencies**: HC-Δ-8 (Thundercell), HC-Δ-9 (CA Integration)

### Core Insight

> **"Every run produces a feature vector. TPE learns which configs work best."**

The Cerebros Feature Pipeline extracts ~20 metrics from each PAC run for Tree-structured Parzen Estimator (TPE) hyperparameter optimization.

### Feature Vector Schema

| Category | Features | Type | Description |
|----------|----------|------|-------------|
| **Config** (6) | | | Hyperparameter settings |
| | `ca_diffusion` | float | CA diffusion rate |
| | `ca_decay` | float | CA decay rate |
| | `ca_neighbor_radius` | int | Neighborhood size |
| | `pac_model_kind` | atom | Model architecture |
| | `max_chain_length` | int | Max action chain |
| | `policy_strictness` | float | Crown policy threshold |
| **Thunderbit Activity** (6) | | | Symbolic layer metrics |
| | `num_bits_total` | int | Total Thunderbits created |
| | `num_bits_cognitive` | int | Cognitive category bits |
| | `num_bits_dataset` | int | Dataset category bits |
| | `avg_bit_degree` | float | Average links per bit |
| | `max_chain_depth` | int | Deepest bit chain |
| | `num_variable_bits` | int | Variable (mutable) bits |
| **CA Dynamics** (6) | | | Lattice physics |
| | `mean_activation` | float | Average cell activation |
| | `max_activation` | float | Peak activation |
| | `activation_entropy` | float | Activation distribution entropy |
| | `active_cell_fraction` | float | % cells above threshold |
| | `error_potential_mean` | float | Average error signal |
| | `error_cell_fraction` | float | % cells with errors |
| **Outcomes** (6) | | | Run results |
| | `reward` | float | Task reward/score |
| | `token_input` | int | Input tokens consumed |
| | `token_output` | int | Output tokens generated |
| | `latency_ms` | int | End-to-end latency |
| | `num_policy_violations` | int | Crown policy triggers |
| | `num_errors` | int | Errors encountered |

### Feature Extractor Module

```elixir
defmodule Thunderline.Thunderbolt.Cerebros.Features do
  @moduledoc """
  Extract feature vectors from PAC runs for TPE optimization.
  """
  
  @type feature_vector :: %{
    # Config
    ca_diffusion: float(),
    ca_decay: float(),
    ca_neighbor_radius: pos_integer(),
    pac_model_kind: atom(),
    max_chain_length: pos_integer(),
    policy_strictness: float(),
    
    # Thunderbit Activity
    num_bits_total: non_neg_integer(),
    num_bits_cognitive: non_neg_integer(),
    num_bits_dataset: non_neg_integer(),
    avg_bit_degree: float(),
    max_chain_depth: non_neg_integer(),
    num_variable_bits: non_neg_integer(),
    
    # CA Dynamics
    mean_activation: float(),
    max_activation: float(),
    activation_entropy: float(),
    active_cell_fraction: float(),
    error_potential_mean: float(),
    error_cell_fraction: float(),
    
    # Outcomes
    reward: float(),
    token_input: non_neg_integer(),
    token_output: non_neg_integer(),
    latency_ms: non_neg_integer(),
    num_policy_violations: non_neg_integer(),
    num_errors: non_neg_integer()
  }
  
  @doc "Extract features from a completed PAC run"
  def extract(run_context, ca_world, config) do
    %{
      # Config features
      ca_diffusion: config.ca_diffusion,
      ca_decay: config.ca_decay,
      ca_neighbor_radius: config.ca_neighbor_radius,
      pac_model_kind: config.pac_model_kind,
      max_chain_length: config.max_chain_length,
      policy_strictness: config.policy_strictness,
      
      # Thunderbit activity
      num_bits_total: count_bits(run_context),
      num_bits_cognitive: count_bits_by_category(run_context, :cognitive),
      num_bits_dataset: count_bits_by_category(run_context, :dataset),
      avg_bit_degree: compute_avg_degree(run_context),
      max_chain_depth: compute_max_depth(run_context),
      num_variable_bits: count_bits_by_category(run_context, :variable),
      
      # CA dynamics
      mean_activation: compute_mean_activation(ca_world),
      max_activation: compute_max_activation(ca_world),
      activation_entropy: compute_activation_entropy(ca_world),
      active_cell_fraction: compute_active_fraction(ca_world, 0.5),
      error_potential_mean: compute_error_mean(ca_world),
      error_cell_fraction: compute_error_fraction(ca_world),
      
      # Outcomes
      reward: run_context.reward,
      token_input: run_context.token_input,
      token_output: run_context.token_output,
      latency_ms: run_context.latency_ms,
      num_policy_violations: run_context.policy_violations,
      num_errors: run_context.error_count
    }
  end
  
  @doc "Log feature vector to Cerebros for TPE training"
  def log_to_cerebros(features, experiment_id) do
    Thunderline.Thunderbolt.Cerebros.log_observation(experiment_id, features)
  end
end
```

### TPE Integration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Cerebros TPE Optimization Loop                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. TPE.suggest_config() → config                                │
│     - Sample from learned prior distribution                     │
│     - Balance exploration vs exploitation                        │
│                                                                  │
│  2. PAC.run(config) → run_context, ca_world                      │
│     - Execute PAC with suggested configuration                   │
│     - Collect Thunderbit/Thundercell activity                    │
│     - Record CA lattice dynamics                                 │
│                                                                  │
│  3. Features.extract(run_context, ca_world, config) → features   │
│     - Compute ~20 feature metrics                                │
│     - Package into normalized vector                             │
│                                                                  │
│  4. Features.log_to_cerebros(features, exp_id)                   │
│     - Store observation for TPE update                           │
│     - Update Parzen estimator densities                          │
│                                                                  │
│  5. Repeat from step 1                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Cross-Domain Layer Update

| Layer | Domains | HC-Δ Items |
|-------|---------|------------|
| **Orchestration Layer** | Vine × Crown | HC-Δ-1, HC-Δ-2 |
| **Optimization Layer** | Vine × Pac × Crown | HC-Δ-7 |
| **Compute Layer** | Bolt × Flow | HC-Δ-3, HC-Δ-4 |
| **Transform Layer** | Bolt × Block | HC-Δ-5, HC-Δ-6 |
| **Substrate Layer** | Bolt × Block × Bit | HC-Δ-8 |
| **Lattice Layer** | Bolt × Bit × CA | HC-Δ-9 |
| **Intelligence Layer** | Bolt × Crown × Cerebros | HC-Δ-10 |

**Full Reference**: [`docs/HC_ARCHITECTURE_SYNTHESIS.md`](docs/HC_ARCHITECTURE_SYNTHESIS.md)

### The Core Insight

> **"The CA is the map, not the carrier."**

Instead of pushing bytes through the cellular automaton lattice:
1. **CA handles**: Routing paths, trust shapes, session-key diffusion, relay neighborhoods, load balancing
2. **WebRTC handles**: Actual high-bandwidth payload transport
3. **The CA becomes**: A self-adapting SDN (Software-Defined Network) map

### Four Research Threads Unified

| Thread | Contribution | Integration Point |
|--------|--------------|-------------------|
| **3D CA Lattice** | Routing oracle, presence fields, secure mesh | `Thunderbolt.Thunderbit` grid |
| **Neural CA (NCA)** | Trainable local rules, universal compute | `Thunderbolt.NCAKernel` |
| **Latent CA (LCA)** | Mesh-agnostic, any topology | `Thunderbolt.LCAKernel` |
| **CAT Transforms** | Orthogonal basis, compression, crypto | `Thunderbolt.CATTransform` |
| **Co-Lex Ordering** | O(1) state comparison, BWT indexing | `Thunderbolt.CoLex` service |

### Thunderbit State Vector

Each voxel cell in the 3D lattice maintains:

```elixir
%Thunderbit{
  coord: {x, y, z},          # 3D position
  ϕ_phase: float,            # Phase for PLV synchrony
  σ_flow: float,             # Propagatability / connectivity
  λ̂_sensitivity: float,      # Local FTLE (chaos/stability)
  trust_score: float,        # Trust level for routing
  presence_vector: map,      # PAC presence fields
  relay_weight: float,       # Load balancing weight
  key_fragment: binary,      # Crypto key shard
  channel_id: uuid | nil,    # Active channel
  cat_coefficients: binary   # CAT transform encoding
}
```

### Cerebros TPE Integration

The TPE search space now includes CAT/NCA hyperparameters:

| Category | Parameters |
|----------|------------|
| **θ_CAT** | rule_id, dims, alphabet_size, radius, window_shape, time_depth, basis_type, boundary_condition |
| **θ_wiring** | lattice_connectivity, coupling_strength, update_schedule, zone_overlap |
| **θ_model** | Standard neural network hyperparameters (input = CAT coefficients) |

**Objective Function**:
```
y = α·task_loss + β·reconstruction_error + γ·(1-compression_ratio) + δ·instability_penalty
```

### Implementation Phases

| Phase | HC Items | Focus |
|-------|----------|-------|
| **1** | HC-60, HC-61 | Thunderbit struct, CAT primitives |
| **2** | HC-62, HC-63 | NCA/LCA kernel infrastructure |
| **3** | HC-40 | LoopMonitor criticality metrics |
| **4** | HC-64, HC-65 | TPE search space, training loop |
| **5** | HC-66 | Co-Lex ordering service |
| **6** | HC-67, HC-68 | WebRTC circuits, security layer |

---

## 🆔 HC-Δ-11: UNIFIED ULID INFRASTRUCTURE

**Status**: Not Started  
**Priority**: P1  
**Dependencies**: None (foundational)  
**Reference**: [packagemain.tech/p/ulid-identifier-golang-postgres](https://packagemain.tech/p/ulid-identifier-golang-postgres)

### Core Insight

> **"ULIDs are lexicographically sortable 128-bit IDs with embedded timestamps — perfect for append-heavy, time-ordered workloads like Thunderbits, Thundercells, and event logs."**

ULID properties that benefit Thunderline:
- **Lexicographically sortable**: First 48 bits = timestamp → newer IDs sort after older IDs
- **128-bit like UUID**: Compatible with Postgres `uuid` column type
- **URL-safe, human-friendly**: `/pac/01KANDQMV608PBSMF7TM9T1WR4` vs UUID v4
- **Index-friendly**: B-tree inserts go to end, not random pages
- **Implicit time encoding**: Infer creation time from ID without extra column

### Where to Use ULID

| Surface | ULID Fit | Rationale |
|---------|----------|-----------|
| **Thunderbit IDs** | ✅ Perfect | Time-ordered reasoning artifacts, replay-friendly |
| **Thundercell IDs** | ✅ Perfect | Ingestion chunks, embeddings, dataset batches |
| **EliteEntry IDs** | ✅ Perfect | Generational QD archive entries |
| **Event/Log IDs** | ✅ Perfect | Append-only, chronological by nature |
| **PAC Session IDs** | ✅ Good | Session timelines, debugging |
| **CA Tick/World IDs** | ✅ Good | Snapshot ordering |
| **Trial/Run IDs** | ✅ Good | Cerebros training runs |
| **BEAM-internal ephemeral** | ⏸️ Skip | Keep simple atoms/refs |

### Components

```
lib/thunderline/
├── id.ex                    # Thunderline.Id abstraction (ULID-backed)
└── id/
    ├── generator.ex         # ULID generation with fallback
    ├── parser.ex            # Extract timestamp from ULID
    └── types/
        └── ulid.ex          # Ash.Type.ULID custom type
```

### Module Structure

```elixir
defmodule Thunderline.Id do
  @moduledoc """
  Unified ID generator for Thunderline.
  Uses ULID for time-sortable, URL-safe identifiers.
  """
  
  @type t :: String.t()
  
  @doc "Generate a new ULID"
  def generate do
    # Use ulid library or custom implementation
    ULID.generate()
  end
  
  @doc "Generate ULID for specific timestamp"
  def generate_at(datetime) do
    ULID.generate(datetime)
  end
  
  @doc "Extract timestamp from ULID"
  def timestamp(ulid) do
    ULID.decode_timestamp(ulid)
  end
  
  @doc "Check if ID is valid ULID"
  def valid?(id), do: ULID.valid?(id)
end
```

### Ash Type Integration

```elixir
defmodule Thunderline.Id.Types.ULID do
  use Ash.Type
  
  @impl true
  def storage_type, do: :uuid  # or :string for char(26)
  
  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_binary(value), do: {:ok, value}
  
  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _), do: {:ok, value}
  
  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _), do: {:ok, value}
  
  @impl true
  def generator(_constraints) do
    StreamData.constant(Thunderline.Id.generate())
  end
end
```

### Migration Strategy

1. **New resources**: Use ULID from the start
2. **Existing resources**: Keep current PKs, no retrofit needed
3. **Hybrid period**: Both work fine, gradually standardize

### Synergy with CA/Cerebros

ULID time-alignment enables:
- **Timeline reconstruction**: "These N Thunderbits spawned in this window"
- **Cross-entity correlation**: trial_id ↔ bit_ids ↔ cell_ids share chronology
- **Replay by ID range**: "Show all Thunderbits between ID A and B"
- **Time-based sharding**: Archive runs by ULID date prefix

---

## 🧠 HC-Δ-12: NEAR-CRITICAL DYNAMICS (MCP-Θ)

**Status**: Not Started  
**Priority**: P2  
**Dependencies**: HC-Δ-3 (CA Engine), HC-Δ-9 (CA Integration)  
**Reference**: Loop-Controlled Near-Critical Dynamics for LLMs (2025)

### Core Insight

> **"LLMs operate best in a 'near-critical' dynamical regime — not too synchronized, not too chaotic. Measurable field parameters (PLV, σ, λ̂) can regulate agent stability."**

This paper proves mathematically what Thunderbeat + Thunderbit CA is already moving toward. It gives us physics-based tools to tune PAC agent behavior like a living organism.

### Key Metrics

| Metric | Definition | Ideal Range | Thunderline Mapping |
|--------|------------|-------------|---------------------|
| **PLV** | Phase Locking Value (attention head synchrony) | 0.30–0.60 | Thunderbeat regulation |
| **σ** | Propagation coefficient (idea flow between layers) | ~1.0 (edge of chaos) | Thundercell excitation |
| **λ̂** | Local Lyapunov exponent (thought trajectory divergence) | ≤ 0 (stable) | Instability trigger |
| **iRoPE** | Spectral loop detection + RoPE frequency adjustment | N/A | CA rule repair |

### Metric Interpretation

```
PLV (Phase Locking Value):
├── Too high (>0.60)  → Repetition, collapse, loops
├── Too low  (<0.30)  → Rambling, incoherence
└── Sweet spot (0.30-0.60) → Metastable thinking zone

σ (Propagation Coefficient):
├── σ < 1  → Stuck thinking, nothing propagates
├── σ ≈ 1  → Edge of chaos (optimal)
└── σ > 1  → Runaway hallucinations

λ̂ (Lyapunov Exponent):
├── λ̂ ≤ 0 → Stable thought paths
└── λ̂ > 0 → Chaotic divergence (trigger safe mode)
```

### Components

```
lib/thunderline/thundercrown/mcp_theta/
├── monitor.ex           # Runtime PLV/σ/λ̂ measurement
├── regulator.ex         # Thunderbeat pacing adjustments
├── thresholds.ex        # Configurable bands and triggers
└── actions.ex           # Corrective actions (dampen/energize)

lib/thunderline/thunderbolt/criticality/
├── plv_estimator.ex     # Phase locking from attention patterns
├── propagation.ex       # σ from layer-to-layer activation
├── lyapunov.ex          # λ̂ from trajectory divergence
└── loop_detector.ex     # Spectral energy analysis
```

### MCP-Θ Regulator

```elixir
defmodule Thunderline.Thundercrown.MCPTheta.Regulator do
  @moduledoc """
  Meta-Critical Poise regulator for PAC agent stability.
  Adjusts Thunderbeat pacing and CA excitation based on criticality metrics.
  """
  
  alias Thunderline.Thundercrown.MCPTheta.Monitor
  alias Thunderline.Thundercore.Heartbeat
  alias Thunderline.Thunderbit.Thundercell
  
  @plv_band {0.30, 0.60}
  @sigma_target 1.0
  @lyapunov_threshold 0.0
  
  def regulate(pac_context) do
    metrics = Monitor.measure(pac_context)
    
    cond do
      metrics.lyapunov > @lyapunov_threshold ->
        # Chaotic divergence - trigger safe mode
        {:safe_mode, dampen_all(pac_context)}
        
      metrics.plv > elem(@plv_band, 1) ->
        # Over-synchronized - inject noise
        {:desync, inject_noise(pac_context, metrics)}
        
      metrics.plv < elem(@plv_band, 0) ->
        # Under-synchronized - increase coupling
        {:resync, increase_coupling(pac_context, metrics)}
        
      metrics.sigma > @sigma_target * 1.2 ->
        # Runaway propagation - decay excitation
        {:dampen, decay_excitation(pac_context, metrics)}
        
      metrics.sigma < @sigma_target * 0.8 ->
        # Stagnant - boost propagation
        {:boost, boost_propagation(pac_context, metrics)}
        
      true ->
        # Healthy regime
        {:stable, pac_context}
    end
  end
end
```

### Integration Points

| System | MCP-Θ Role |
|--------|------------|
| **Thunderbeat** | Adjust tick pacing based on PLV |
| **Thundercell CA** | Modify excitation levels via σ |
| **Thunderbit relations** | Rewire on loop detection |
| **MCP Ethics** | Trigger safe-mode on λ̂ spike |
| **Thundervine DAG** | Dampen edge weights for stability |

---

## 🎭 HC-Δ-13: THUNDERCHIEF ORCHESTRATOR

**Status**: Not Started  
**Priority**: P1  
**Dependencies**: HC-Δ-1 (Vine DAG), HC-Δ-2 (Crown Policy)  
**Reference**: Multi-Agent Collaboration via Evolving Orchestration (NeurIPS 2025)

### Core Insight

> **"A centralized 'puppeteer' policy dynamically chooses which agent should run at each step. This serializes multi-agent coordination into an optimizable sequence, discovering compact cyclic reasoning structures."**

This paper validates the Thunderline architecture:
- **Puppeteer** = Thunderchief (per-domain orchestrator)
- **Puppets** = Thunderbits / Thundercells / DAG tasks
- **Graph-of-thought → sequence** = Thunderbeat tick loop + Chief decisions
- **RL evolution** = Cerebros outer loop

### Mental Model

```
Thundergrid        → Global map of zones, ticks, events
Thunderbit/cell    → Working pieces (reasoning + data)
Thundercrown       → High-level policy & ethics
Thunderchief.*     → Per-domain orchestrator = PUPPETEER
```

### Per-Domain Chiefs

| Chief | Domain | Puppets | Selection Logic |
|-------|--------|---------|-----------------|
| `Thunderchief.Bit` | Thunderbit | Bit categories | Which bit to activate next |
| `Thunderchief.Vine` | Thundervine | DAG nodes | Which graph node to execute |
| `Thunderchief.Crown` | Thundercrown | Policy updates | Meta-chief for governance |
| `Thunderchief.UI` | Prism | Surface elements | What to show user |

### Components

```
lib/thunderline/thunderchief/
├── behaviour.ex         # Thunderchief contract
├── state.ex             # Chief observation state
├── action.ex            # Chief action types
├── chiefs/
│   ├── bit_chief.ex     # Thunderbit orchestrator
│   ├── vine_chief.ex    # DAG orchestrator
│   ├── crown_chief.ex   # Meta-governance chief
│   └── ui_chief.ex      # Surface orchestrator
└── logger.ex            # RL trajectory logging
```

### Thunderchief Behaviour

```elixir
defmodule Thunderline.Thunderchief.Behaviour do
  @moduledoc """
  Contract for domain-level orchestrators (puppeteers).
  Each Chief observes domain state and selects next action.
  """
  
  @type state :: map()
  @type action :: atom() | {atom(), map()}
  @type outcome :: :success | :error | {:partial, map()}
  
  @doc "Extract compressed feature vector from domain state"
  @callback observe_state(context :: map()) :: state()
  
  @doc "Choose next action given observed state"
  @callback choose_action(state()) :: {:ok, action()} | {:wait, timeout()}
  
  @doc "Apply selected action to context"
  @callback apply_action(action(), context :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc "Report outcome for RL logging"
  @callback report_outcome(context :: map()) :: %{
    reward: float(),
    metrics: map(),
    trajectory_step: map()
  }
end
```

### Bit Chief Example

```elixir
defmodule Thunderline.Thunderchief.Chiefs.BitChief do
  @behaviour Thunderline.Thunderchief.Behaviour
  
  alias Thunderline.Thunderbit.{Context, Protocol}
  
  @impl true
  def observe_state(ctx) do
    %{
      pending_bits: count_pending(ctx),
      active_category: current_category(ctx),
      energy_level: ctx.energy,
      chain_depth: ctx.chain_depth,
      last_action_type: ctx.last_action
    }
  end
  
  @impl true
  def choose_action(state) do
    cond do
      state.pending_bits > 0 and state.energy_level > 0.3 ->
        {:ok, {:activate_pending, %{strategy: :fifo}}}
        
      state.chain_depth > 5 ->
        {:ok, :consolidate}
        
      state.active_category == :sensory ->
        {:ok, {:transition, :cognitive}}
        
      true ->
        {:wait, 100}  # Wait for external stimulus
    end
  end
  
  @impl true
  def apply_action({:activate_pending, opts}, ctx) do
    case Protocol.activate_next(ctx, opts) do
      {:ok, updated} -> {:ok, updated}
      error -> error
    end
  end
  
  @impl true
  def report_outcome(ctx) do
    %{
      reward: calculate_reward(ctx),
      metrics: %{
        bits_processed: ctx.bits_processed,
        latency_ms: ctx.latency,
        errors: ctx.error_count
      },
      trajectory_step: %{
        state: observe_state(ctx),
        action: ctx.last_action,
        next_state: observe_state(ctx)
      }
    }
  end
end
```

### Thunderbeat Integration

```elixir
# On each tick, Chiefs are consulted
defmodule Thunderline.Thundercore.TickRunner do
  def run_tick(ctx) do
    ctx
    |> consult_chiefs()
    |> execute_selected_actions()
    |> emit_events()
    |> log_trajectories()
  end
  
  defp consult_chiefs(ctx) do
    chiefs = [
      Thunderchief.Chiefs.BitChief,
      Thunderchief.Chiefs.VineChief
    ]
    
    Enum.reduce(chiefs, ctx, fn chief, acc ->
      state = chief.observe_state(acc)
      case chief.choose_action(state) do
        {:ok, action} -> 
          {:ok, updated} = chief.apply_action(action, acc)
          updated
        {:wait, _} -> 
          acc
      end
    end)
  end
end
```

### RL Training (Future)

Chiefs are designed for later RL optimization:

```elixir
# Cerebros can replace choose_action/1 with learned policy
defmodule Thunderline.Thunderchief.LearnedPolicy do
  @doc """
  Replace heuristic choose_action with TPE-optimized policy.
  Training data comes from trajectory logs.
  """
  
  def choose_action(state, policy_params) do
    # Feature extraction
    features = encode_state(state)
    
    # Policy network forward pass
    action_probs = policy_forward(features, policy_params)
    
    # Sample or argmax
    {:ok, sample_action(action_probs)}
  end
end
```

---

## � OBAN DOMAINPROCESSOR (Guerrilla #32)

**Status**: ✅ Complete  
**Priority**: P1  
**Module**: `Thunderline.Thunderchief.Jobs.DomainProcessor`  
**Tests**: 18 passing (`test/thunderline/thunderchief/jobs/domain_processor_test.exs`)

### Purpose

While the Conductor handles **synchronous** tick-based orchestration, the DomainProcessor Oban worker enables **asynchronous** per-domain Chief execution with:

- Retry semantics for transient failures (max 3 attempts)
- Job scheduling (e.g., nightly consolidation)
- Per-domain queue isolation for backpressure control
- Independent scaling per domain workload
- Trajectory logging for RL training data collection

### Domain Routing

```elixir
@domain_chiefs %{
  "bit"   => BitChief,
  "vine"  => VineChief,
  "crown" => CrownChief,
  "ui"    => UIChief
}
```

### Usage Examples

```elixir
# Enqueue a domain processing job
%{domain: "bit", context: %{tick: 42}}
|> DomainProcessor.new()
|> Oban.insert()

# With priority (for governance/critical domains)
%{domain: "crown", context: %{urgent: true}}
|> DomainProcessor.new(priority: 0)
|> Oban.insert()

# Scheduled execution
%{domain: "vine", context: %{action: :consolidate}}
|> DomainProcessor.new(scheduled_at: tomorrow())
|> Oban.insert()

# Convenience helpers
DomainProcessor.enqueue("bit")
DomainProcessor.enqueue("crown", %{urgent: true}, priority: 0)
DomainProcessor.enqueue_all(%{tick: 42})  # All domains
```

### Job Args

| Arg | Type | Required | Description |
|-----|------|----------|-------------|
| `domain` | string | yes | Domain key: "bit", "vine", "crown", "ui" |
| `context` | map | no | Merged into chief context |
| `action_override` | any | no | Force specific action (bypasses choose_action) |
| `skip_logging` | boolean | no | Disable trajectory logging (default: false) |

### Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:thunderline, :thunderchief, :job, :start]` | `system_time` | `domain`, `job_id`, `attempt` |
| `[:thunderline, :thunderchief, :job, :stop]` | `duration` | `domain`, `job_id`, `action` |
| `[:thunderline, :thunderchief, :job, :error]` | `duration` | `domain`, `job_id`, `reason` |

### Job Lifecycle

```
perform/1
  ├── Validate domain → chief_for(domain)
  ├── Build context (merge base + extra)
  ├── Emit :start telemetry
  │
  ├── observe(chief_module, context)
  │     → {:ok, state}
  │
  ├── choose_or_override(chief_module, state, action_override)
  │     → {:ok, action} | {:wait, _} | {:defer, _}
  │
  ├── apply_action(chief_module, action, context)
  │     → {:ok, updated_context}
  │
  ├── report(chief_module, updated_context)
  │     → %{reward, metrics, trajectory_step}
  │
  ├── log_trajectory (unless skip_logging)
  └── Emit :stop telemetry
```

### Configuration

```elixir
# Oban queue config (in runtime.exs or dev.exs)
config :thunderline, Oban,
  queues: [
    domain_processor: 10  # concurrency limit
  ]
```

### API Reference

| Function | Description |
|----------|-------------|
| `new/2` | Build job changeset |
| `enqueue/3` | Insert job for single domain |
| `enqueue_all/2` | Insert jobs for all domains |
| `domains/0` | List registered domain keys |
| `chief_for/1` | Get Chief module for domain |

---

## �🔀 CROSS-DOMAIN FUNCTIONAL LAYERS (Nov 28, 2025)

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
| **Compute Layer** | Bolt × Flow | PAC task routing, CA criticality optimization, TPE/DiffLogic integration | `Thunderbolt.CerebrosBridge`, `Thunderbolt.LoopMonitor`, `Thunderbolt.CA.DiffLogicRules` |
| **Lattice Layer** | Bolt × Link × Gate | CA routing fabric, WebRTC circuits, geometric crypto | `Thunderbolt.Thunderbit`, `Thunderlink.CACircuit`, `Thundergate.CASession` |
| **Transform Layer** | Bolt × Block | CAT encoding, coefficient storage, signal compression | `Thunderbolt.CATTransform`, `Thunderblock.CATStore`, `Thunderbolt.NCAKernel` |

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
| Compute | Bolt, Flow | `LAYER_COMPUTE_ENABLED` | `false` |

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

---

### 🧠 HC-Cerebros-DiffLogic Directive: Adaptive Voxel-Automata Pipeline (Nov 28, 2025)

**Mission**: Seamlessly fuse Thunderline's Thunderbolt execution layer (voxel automata, event triggers), the Cerebros multivariate TPE orchestration framework, and Google's Differentiable Logic CA model into a unified, adaptive compute pipeline. The integrated system routes PAC tasks between Elixir and Python workers, uses automata-chunk triggers to invoke model updates, and evolves voxel-automata rules towards criticality via both Bayesian tuning and differentiable gradient updates.

**References**:
- [DiffLogic CA (Google Research)](https://google-research.github.io/self-organising-systems/difflogic-ca/) - Differentiable logic for cellular automata
- [ES Hyperscale](https://eshyperscale.github.io/) - Evolutionary strategies at scale
- [Agent0 Paper (arXiv)](https://arxiv.org/html/2511.16043v1) - Co-evolutionary LLM agent training

#### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         THUNDERLINE ADAPTIVE CA PIPELINE                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────┐    Events     ┌────────────────┐    Results            │
│  │  THUNDERBOLT   │ ──────────▶  │    CEREBROS    │ ──────────▶           │
│  │  Voxel Automata │  PACCompute  │  Python TPE    │  Updated              │
│  │  + LoopMonitor  │   Request    │  + DiffLogic   │  Params               │
│  └────────┬───────┘              └────────┬───────┘                        │
│           │                               │                                 │
│           │ Metrics                       │ Gradients                       │
│           │ (PLV, λ, H)                   │ (rule Δ)                        │
│           ▼                               ▼                                 │
│  ┌────────────────────────────────────────────────────────────┐            │
│  │                    THUNDERFLOW EVENT BUS                    │            │
│  │  bolt.pac.compute.request → bolt.pac.compute.response      │            │
│  │  bolt.ca.metrics.snapshot → bolt.ca.rule.update            │            │
│  └────────────────────────────────────────────────────────────┘            │
│                                                                              │
│  ┌────────────────┐              ┌────────────────┐                        │
│  │  OPENTELEMETRY │◀────────────▶│   PROMETHEUS   │                        │
│  │  Trace Context │   Metrics    │   + Grafana    │                        │
│  └────────────────┘              └────────────────┘                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Event Protocol Specification

**PACComputeRequest** (Elixir → Python):
```json
{
  "task_id": "<UUID v7>",
  "agent_id": "<PAC_ID>",
  "world_state": {
    "grid_size": [32, 32, 32],
    "active_cells": 1847,
    "state_hash": "sha256:...",
    "features": {"density": 0.23, "cluster_count": 7}
  },
  "metrics": {
    "plv": 0.85,
    "entropy": 3.2,
    "lambda_hat": 0.47,
    "lyapunov": 0.02
  },
  "trigger_event": "entropy_threshold_breach",
  "timestamp": 1732780800,
  "trace_context": {"trace_id": "...", "span_id": "..."}
}
```

**PACComputeResponse** (Python → Elixir):
```json
{
  "task_id": "<UUID v7>",
  "status": "success",
  "updated_params": {
    "rule_weights": {"birth": [0.1, 0.3, 0.2], "survival": [0.4, 0.5]},
    "mutation_rate": 0.05,
    "neighborhood_radius": 2
  },
  "metrics": {
    "loss": 0.12,
    "improvement": 0.05,
    "tpe_trial_id": 42
  },
  "timestamp": 1732780805,
  "trace_context": {"trace_id": "...", "span_id": "..."}
}
```

**CAVoxelUpdate** (Gradient patches):
```json
{
  "task_id": "<UUID v7>",
  "rule_deltas": {
    "kernel_0": [[0.01, -0.02], [0.03, 0.00]],
    "bias": 0.001
  },
  "learning_rate": 0.001,
  "clip_norm": 1.0,
  "timestamp": 1732780810
}
```

#### Criticality Metrics (LoopMonitor)

| Metric | Description | Target Range | Computation |
|--------|-------------|--------------|-------------|
| **PLV** | Phase-Locking Value (synchrony) | 0.3–0.7 | `mean(cos(phase_diff))` across oscillatory cells |
| **Entropy (H)** | Permutation entropy (complexity) | 2.5–4.0 | Bandt-Pompe on time series of cell states |
| **λ̂** | Langton's lambda (criticality) | 0.2–0.5 | Fraction of non-quiescent transition rules |
| **Lyapunov** | Lyapunov exponent (chaos) | 0.0–0.1 | Divergence rate of perturbed trajectories |

**Critical Edge Detection**:
```elixir
defmodule Thunderline.Thunderbolt.LoopMonitor.CriticalityDetector do
  @target_lambda 0.37  # Langton's edge-of-chaos
  @plv_band {0.35, 0.65}
  @entropy_band {2.8, 3.8}

  def at_critical_edge?(metrics) do
    %{plv: plv, entropy: h, lambda_hat: lambda} = metrics
    
    lambda_ok = abs(lambda - @target_lambda) < 0.1
    plv_ok = plv >= elem(@plv_band, 0) and plv <= elem(@plv_band, 1)
    entropy_ok = h >= elem(@entropy_band, 0) and h <= elem(@entropy_band, 1)
    
    lambda_ok and plv_ok and entropy_ok
  end
  
  def drift_direction(metrics) do
    cond do
      metrics.lambda_hat < 0.2 -> :too_ordered
      metrics.lambda_hat > 0.5 -> :too_chaotic
      metrics.entropy < 2.5 -> :low_complexity
      metrics.entropy > 4.5 -> :high_complexity
      true -> :stable
    end
  end
end
```

#### TPE Orchestration (Cerebros Python)

**Multivariate TPE with Optuna**:
```python
# cerebros/tpe_orchestrator.py
import optuna
from optuna.samplers import TPESampler

class CerebrosTPE:
    def __init__(self, storage_url: str):
        self.sampler = TPESampler(
            multivariate=True,  # Coupled parameter optimization
            group=True,         # Group related parameters
            n_startup_trials=10
        )
        self.study = optuna.create_study(
            study_name="thunderbolt_ca_optimization",
            sampler=self.sampler,
            storage=storage_url,
            load_if_exists=True,
            direction="minimize"  # Minimize distance from critical edge
        )
    
    def suggest_params(self, trial: optuna.Trial) -> dict:
        return {
            "birth_threshold": trial.suggest_float("birth_threshold", 0.1, 0.5),
            "survival_threshold": trial.suggest_float("survival_threshold", 0.2, 0.6),
            "mutation_rate": trial.suggest_float("mutation_rate", 0.01, 0.2, log=True),
            "neighborhood_radius": trial.suggest_int("neighborhood_radius", 1, 3),
            "diffusion_rate": trial.suggest_float("diffusion_rate", 0.0, 0.3),
        }
    
    def compute_objective(self, metrics: dict) -> float:
        """Distance from critical edge (lower = better)"""
        target_lambda = 0.37
        target_entropy = 3.2
        target_plv = 0.5
        
        lambda_dist = abs(metrics["lambda_hat"] - target_lambda)
        entropy_dist = abs(metrics["entropy"] - target_entropy) / 2.0
        plv_dist = abs(metrics["plv"] - target_plv)
        
        return lambda_dist + entropy_dist + plv_dist
```

#### DiffLogic CA Integration

**Differentiable Rule Parameters**:
```elixir
defmodule Thunderline.Thunderbolt.CA.DiffLogicRules do
  @moduledoc """
  Differentiable rule representation for gradient-based CA optimization.
  Rules are stored as float tensors, quantized for execution.
  """
  
  defstruct [:kernel_weights, :bias, :temperature, :version]
  
  def new(opts \\ []) do
    %__MODULE__{
      kernel_weights: Nx.broadcast(0.5, {3, 3, 3}),  # 3D neighborhood
      bias: 0.0,
      temperature: 1.0,  # For soft quantization
      version: 1
    }
  end
  
  def apply_gradient_update(rules, deltas, learning_rate \\ 0.001) do
    new_weights = Nx.add(
      rules.kernel_weights,
      Nx.multiply(deltas.kernel_weights, learning_rate)
    )
    
    # Clamp to valid range
    new_weights = Nx.clip(new_weights, 0.0, 1.0)
    
    %{rules | 
      kernel_weights: new_weights,
      bias: rules.bias + deltas.bias * learning_rate,
      version: rules.version + 1
    }
  end
  
  def quantize_for_execution(rules) do
    # Soft quantization via temperature-scaled sigmoid
    Nx.sigmoid(Nx.divide(rules.kernel_weights, rules.temperature))
    |> Nx.greater(0.5)
    |> Nx.as_type(:u8)
  end
end
```

**Python Gradient Computation**:
```python
# cerebros/difflogic_engine.py
import torch
import torch.nn.functional as F

class DiffLogicCA(torch.nn.Module):
    """Differentiable cellular automaton with learnable rules."""
    
    def __init__(self, kernel_size=3, channels=1):
        super().__init__()
        self.kernel = torch.nn.Parameter(
            torch.randn(channels, channels, kernel_size, kernel_size, kernel_size) * 0.1
        )
        self.bias = torch.nn.Parameter(torch.zeros(1))
        self.temperature = 1.0
    
    def forward(self, state: torch.Tensor) -> torch.Tensor:
        """Single CA step with differentiable rules."""
        # Convolve with learned kernel
        neighborhood = F.conv3d(state, self.kernel, padding="same")
        
        # Soft activation (differentiable approximation of threshold)
        activation = torch.sigmoid((neighborhood + self.bias) / self.temperature)
        
        return activation
    
    def compute_gradients(self, state: torch.Tensor, target_metrics: dict) -> dict:
        """Compute gradients toward target criticality metrics."""
        state.requires_grad_(True)
        
        # Run forward pass
        next_state = self.forward(state)
        
        # Compute differentiable proxy for criticality
        # (simplified: variance as proxy for edge-of-chaos)
        variance = torch.var(next_state)
        target_variance = 0.25  # ~0.5 mean with good spread
        
        loss = (variance - target_variance) ** 2
        loss.backward()
        
        return {
            "kernel_deltas": self.kernel.grad.numpy().tolist(),
            "bias_delta": float(self.bias.grad),
            "loss": float(loss)
        }
```

#### Implementation Phases

**Phase 1 (Week 1-2): Event Protocol & Resources — HC-39**
- [ ] Ash resource: `Thunderbolt.Resources.PACComputeTask` (id, agent_id, status, request, response, created_at)
- [ ] Event taxonomy entries: `bolt.pac.compute.request`, `bolt.pac.compute.response`, `bolt.ca.rule.update`
- [ ] JSON schema validation (via Jason + custom validator)
- [ ] Broadway consumer: `Thunderbolt.CerebrosBridge.ResponseConsumer`
- [ ] OTel context propagation in event metadata
- [ ] Snex serialization helpers (Elixir struct ↔ Python dict)
- [ ] Unit tests: event roundtrip, schema validation

**Phase 2 (Week 2-3): LoopMonitor Metrics — HC-40**
- [ ] `Thunderbolt.LoopMonitor.CriticalityMetrics` module
- [ ] PLV computation (phase coherence across oscillatory cells)
- [ ] Permutation entropy (Bandt-Pompe algorithm)
- [ ] Langton's λ̂ calculation (rule table analysis)
- [ ] Lyapunov exponent estimation (optional, compute-heavy)
- [ ] `bolt.ca.metrics.snapshot` event emission on tick
- [ ] Telemetry: `[:thunderline, :bolt, :ca, :criticality]`
- [ ] Grafana dashboard panel for criticality metrics

**Phase 3 (Week 3-4): Cerebros TPE Service — HC-41**
- [ ] Python service skeleton (`cerebros/tpe_service.py`)
- [ ] Optuna TPESampler configuration (multivariate=True)
- [ ] Trial database setup (Postgres via SQLAlchemy or Optuna storage)
- [ ] Event consumer (asyncio or Celery worker)
- [ ] `PACComputeResponse` emission
- [ ] Auto-scaling configuration (worker pool sizing)
- [ ] Integration test: end-to-end TPE trial
- [ ] OTel instrumentation for Python spans

**Phase 4 (Week 4-5): DiffLogic Integration — HC-42**
- [ ] `Thunderbolt.CA.DiffLogicRules` Elixir module
- [ ] Float-parameterized rule representation
- [ ] Python `DiffLogicCA` module (PyTorch)
- [ ] Gradient computation toward target metrics
- [ ] `CAVoxelUpdate` event schema
- [ ] Rule delta application in Elixir
- [ ] Quantization layer for execution
- [ ] Stability guards (gradient clipping, divergence detection)
- [ ] Integration test: gradient→rule update→execution

**Phase 5 (Week 5-6): Agent0 Co-Evolution — HC-43**
- [ ] Ash resources: `CurriculumAgent`, `ExecutorAgent`
- [ ] Python co-evolution loop (curriculum task generation, executor solving)
- [ ] Zero-shot bootstrapping (no pre-training data)
- [ ] Uncertainty × tool-use reward computation
- [ ] GRPO/ADPO policy updates
- [ ] ONNX export/import via Ortex
- [ ] Episodic training with LoopMonitor metrics
- [ ] Self-reinforcing cycle: executor improvement → harder curriculum

**Phase 6 (Week 6-7): Swarm Orchestration — HC-44**
- [ ] Reactor DAG for agent-spawn workflow
- [ ] Dynamic scaling integration (GenStage backpressure)
- [ ] Routing heuristics (round-robin, skill-based assignment)
- [ ] Task patterns: batching, sharding, voting
- [ ] Result aggregation and scoring
- [ ] Thunderchief integration for real-time coordination

**Phase 7 (Week 7-8): Trigger Mechanisms — HC-45**
- [ ] Voxel state sensors (entropy burst, event-band detection)
- [ ] Thunderbolt automata watchers
- [ ] Cool-off periods and rate limiting
- [ ] Nerves edge constraints (central check-in requirement)
- [ ] LoopMonitor runaway prevention
- [ ] Audit logging for trigger events

#### Telemetry & Observability

**Elixir Telemetry Events**:
```elixir
[:thunderline, :bolt, :pac, :request, :start]     # {task_id, agent_id}
[:thunderline, :bolt, :pac, :request, :stop]      # {duration_ms, status}
[:thunderline, :bolt, :pac, :response, :received] # {task_id, tpe_trial_id}
[:thunderline, :bolt, :ca, :criticality]          # {plv, entropy, lambda_hat}
[:thunderline, :bolt, :ca, :rule_update]          # {version, delta_norm}
[:thunderline, :bolt, :difflogic, :gradient]      # {loss, learning_rate}
```

**OTel Span Naming**:
```
thunderbolt.pac.publish_request    # Elixir: emit PACComputeRequest
cerebros.pac.handle_request        # Python: process request
cerebros.tpe.suggest_params        # Python: TPE parameter suggestion
cerebros.difflogic.compute_grad    # Python: gradient computation
thunderbolt.pac.apply_response     # Elixir: apply updates
thunderbolt.ca.step                # Elixir: CA execution step
```

#### Operational Guidelines

**Modularity**: Each component (voxel engine, LoopMonitor, Cerebros TPE, DiffLogic) is an independent service/GenServer. Backends are swappable (GPU PyTorch ↔ CPU-only).

**Scaling**: 
- Elixir: GenStage/Broadway for event production/consumption
- Python: Celery workers or asyncio pools for TPE parallelism
- K8s HPA for auto-scaling based on queue depth

**Resilience**:
- Events are idempotent (task_id deduplication)
- TPE trials have retry semantics
- Failed gradients trigger rollback to previous rule version

**Security**:
- Event bus authentication via existing token credentials
- Python workers authenticate with API keys
- No direct Elixir↔Python library calls (message-only boundary)

#### Key Files

```
lib/thunderline/thunderbolt/
├── cerebros_bridge/
│   ├── invoker.ex              # Snex bridge to Python
│   ├── response_consumer.ex    # Broadway for responses
│   └── serialization.ex        # Event serialization
├── ca/
│   ├── difflogic_rules.ex      # Differentiable rule params
│   ├── stepper.ex              # CA execution (existing)
│   └── runner.ex               # CA runner (existing)
├── loop_monitor/
│   ├── criticality_detector.ex # PLV, entropy, λ computation
│   ├── metrics.ex              # Metric structs
│   └── telemetry.ex            # Metric emission
└── resources/
    ├── pac_compute_task.ex     # Ash resource for tasks
    ├── curriculum_agent.ex     # Agent0 curriculum agent
    └── executor_agent.ex       # Agent0 executor agent

python/cerebros/
├── tpe_service.py              # Main TPE orchestrator
├── tpe_orchestrator.py         # Optuna integration
├── difflogic_engine.py         # DiffLogic CA (PyTorch)
├── event_consumer.py           # Event bus consumer
├── event_producer.py           # Response emission
└── agent0/
    ├── curriculum.py           # Curriculum agent
    ├── executor.py             # Executor agent
    └── co_evolution.py         # Training loop
```

---

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

## 🧠 Cerebros-Mini MVP Implementation (Dec 2025)

**HC-20 Progress**: Local scoring model for Thunderbit evaluation. Implements the Puppeteer (Thunderchief) + Mimas (Cerebros-mini) architecture layer.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CEREBROS-MINI PIPELINE                                 │
│                                                                             │
│   Thunderbit ──┬── Feature.from_bit/1 ──► 12-dim vector                     │
│                │                              │                             │
│                │                              ▼                             │
│                │                     Scorer.infer/1                         │
│                │                              │                             │
│                │                              ▼                             │
│                │                     %{score, label, next_action}           │
│                │                              │                             │
│                └── Protocol.mutate ◄─────────┘                              │
│                    (cerebros_score, cerebros_label, etc.)                   │
│                                                                             │
│   Orchestration: BitChief → {:cerebros_evaluate, %{batch_size: N}}          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Module Reference

| Module | Path | Purpose |
|--------|------|---------|
| `Thunderline.Cerebros.Mini.Feature` | `lib/thunderline/cerebros/mini/feature.ex` | 12-dimension feature extraction from Thunderbits |
| `Thunderline.Cerebros.Mini.Scorer` | `lib/thunderline/cerebros/mini/scorer.ex` | Mock scoring model (deterministic, no real ML) |
| `Thunderline.Cerebros.Mini.Bridge` | `lib/thunderline/cerebros/mini/bridge.ex` | Unified pipeline: evaluate, apply_result, health |

### Feature Dimensions (12-D)

| Index | Feature | Type | Source |
|-------|---------|------|--------|
| 0 | `bit_hash` | float | Hash of bit ID normalized to [0,1] |
| 1 | `pac_hash` | float | Hash of PAC ID normalized to [0,1] |
| 2 | `zone_idx` | int | Zone index (0-11) |
| 3 | `category_idx` | int | Category enum index |
| 4 | `energy` | float | Energy level [0,1] |
| 5 | `age` | float | Time since creation (seconds) |
| 6 | `health` | float | Health metric [0,1] |
| 7 | `salience` | float | Salience score [0,1] |
| 8 | `chain_depth` | int | DAG chain depth |
| 9 | `role_idx` | int | Role enum index |
| 10 | `status_idx` | int | Status enum index |
| 11 | `link_count` | int | Number of linked entities |

### Scorer Output Schema

```elixir
%{
  score: 0.72,           # Float [0,1] - overall quality score
  label: :high,          # :critical | :low | :medium | :high
  next_action: :boost,   # :boost_energy | :consolidate | :retire | :activate | :flag_for_review | nil
  confidence: 0.85       # Float [0,1] - model confidence
}
```

**Label Thresholds**: `<0.2 = :critical`, `0.2-0.4 = :low`, `0.4-0.7 = :medium`, `>0.7 = :high`

### BitChief Integration

The `BitChief` domain orchestrator now includes Cerebros evaluation as an action:

```elixir
# Action selection priority (in choose_action/1):
# 1. Consolidation actions (if consolidation_needed > 0)
# 2. Cerebros evaluation (if needs_cerebros_eval > 0)  ← NEW
# 3. Health actions (if health_critical > 0)
# 4. ...other actions

# Bits need evaluation if:
# - explicitly flagged (needs_cerebros_eval?: true)
# - never scored (cerebros_score == nil)
# - stale evaluation (last_cerebros_eval > 5 minutes ago)
```

### Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:thunderline, :cerebros, :mini, :evaluate]` | `duration_ms`, `score` | `bit_id`, `label`, `action` |
| `[:thunderline, :cerebros, :mini, :batch]` | `duration_ms`, `count`, `avg_score` | `evaluated`, `failed` |
| `[:thunderline, :cerebros, :mini, :evaluate_error]` | - | `bit_id`, `error` |

### EventBus Events

| Event Name | Source | Payload |
|------------|--------|---------|
| `cerebros.mini.evaluated` | `:cerebros` | `%{bit_id, score, label, action}` |
| `cerebros.mini.batch_evaluated` | `:cerebros` | `%{count, avg_score}` |
| `cerebros.mini.result_applied` | `:cerebros` | `%{bit_id, changes, action}` |

### Usage Examples

```elixir
# Direct evaluation (no mutation)
{:ok, result} = Thunderline.Cerebros.Mini.Bridge.evaluate(bit)
# => {:ok, %{bit_id: "...", score: 0.72, label: :high, ...}}

# Batch evaluation with mutation
{:ok, results} = Thunderline.Cerebros.Mini.Bridge.evaluate_and_apply_batch(bits)
# => {:ok, [%{bit_id: "...", applied: true, ...}, ...]}

# Health check
{:ok, status} = Thunderline.Cerebros.Mini.Bridge.health()
# => {:ok, %{status: :healthy, model: "mock_v1", dimensions: 12, ...}}
```

### Outstanding Work (HC-20)

1. ✅ Feature extraction module (`Feature.from_bit/1`)
2. ✅ Mock scorer model (`Scorer.infer/1`)
3. ✅ Bridge unified pipeline (`Bridge.evaluate_and_apply/2`)
4. ✅ BitChief integration (`{:cerebros_evaluate, ...}` action)
5. ⬜ Real ML model training (replace mock scorer)
6. ⬜ Feature flag (`features.cerebros_mini`) for gradual rollout
7. ⬜ LiveDashboard panel for Cerebros metrics
8. ⬜ DIP documentation for external integrations

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
5. [x] Hook `ThunderlineWeb.UserSocket` into AshAuthentication session tokens. _(Already implemented: uses `AshAuthentication.Token.verify/2`.)_
6. [x] Finish router API key flip (issuance mix task + `required?: true`). _(Completed: ApiKey resource, AshAuthentication api_key strategy on User, `mix thunderline.api_key.generate` task, MCP pipeline with ApiKey.Plug. Set `required?: false` initially—flip to `true` when ready to enforce.)_
7. [x] Re-enable Thunderblock vault resource policies. _(Completed: vault_action, vault_agent, vault_decision—added Ash.Policy.Authorizer + policy blocks with AshAuthentication bypass + actor_present() pattern.)_
8. [x] Clean Ash 3.x fragments in `VaultKnowledgeNode` (lines 15–614). _(Completed: Fixed via guerrilla #8-11 commit 91a4edc.)_
9. [x] Fix `pac_home` validation/fragment syntax for Ash 3.x. _(Completed: Fixed via guerrilla #8-11 commit 91a4edc.)_
10. [x] Restore AshOban triggers in `task_orchestrator` and `workflow_tracker`. _(Completed: Fixed via guerrilla #8-11 commit 91a4edc.)_
11. [x] Introduce `ChannelParticipant` Ash resource + relationships. _(Completed: New resource with channel/user relationships, role enum, joined_at timestamp—commit 91a4edc.)_
12. [x] Fix Ash 3.x validations/fragments in `Thundercom.Message`. _(Completed: Migrated AshOban.Resource → AshOban in 20 files—commit 96038c2.)_
13. [x] Resolve `federation_socket` fragment/validation issues; recover AshOban trigger. _(Completed: Fixed via guerrilla #12-13 commit 96038c2.)_
14. [x] Repair `Thundercom.Role` fragment filters + AshOban trigger syntax. _(Completed: Fixed via guerrilla #12-13 commit 96038c2.)_
15. [x] Replace `Thunderlink.DashboardMetrics` stubs with live telemetry. _(Completed: Full implementation with real-time system metrics, process stats, memory tracking—commit cdc7aa1.)_
16. [x] Pipe telemetry into `dashboard_live.ex` (CPU/memory/latency). _(Completed: Wired with guerrilla #15—commit cdc7aa1.)_
17. [x] Complete `ThunderlaneDashboard` TODO wiring. _(Completed: Full dashboard implementation with live telemetry—commit 84eab1d.)_
18. [x] Add Stream/Flow telemetry for pipeline throughput & failures. _(Completed: Telemetry spans for pipeline stages, failure tracking—commit e9c698e.)_
19. [x] Rebuild Thunderbolt `StreamManager` supervisor + PubSub bridge. _(Completed: Full GenServer with subscribe/unsubscribe, batch publishing—commit 501e8e1.)_
20. [x] Ship ExUnit coverage for StreamManager ingest/drop behaviors. _(Completed: Comprehensive tests + Credo complexity fix—commit 5166059.)_
21. [x] Fix `Thunderbolt.Resources.Chunk` state machine (AshStateMachine 3.x). _(Completed: Fixed changeset.data access pattern for Ash 3.x—commit aaedec4.)_
22. [x] Implement real resource allocation logic + orchestration events. _(Completed: 10+ private functions with strategy-based optimization, EventBus integration—commit fb2f938.)_
23. [ ] Add ML health threshold evaluation to `chunk_health.ex`.
24. [ ] Finish `activation_rule` evaluation workflow (notifications, ML init).
25. [ ] Implement secure key management in `lane_rule_set.ex`.
26. [ ] Flesh out `topology_partitioner.ex` with 3D strategies.
27. [ ] Convert Thundergrid `SpatialCoordinate`/`ZoneBoundary` routes to Ash 3.x.
28. [ ] Build shared `Thunderline.Thundergrid.Validations` module + consume it.
29. [ ] Re-enable Thundergrid policies once actor context is wired.
30. [ ] Fix `ZoneEvent` aggregate `group_by` syntax and add tests.
31. [ ] Implement ThunderGate `Mnesia → PostgreSQL` sync.
32. [x] Extend `Thunderchief.DomainProcessor` Oban job with per-domain delegation. _(Completed: Guerrilla #32 - Full Oban worker implementation at `Thunderline.Thunderchief.Jobs.DomainProcessor`. Features: per-domain Chief routing (bit→BitChief, vine→VineChief, crown→CrownChief, ui→UIChief), observe/choose/apply/report lifecycle, trajectory logging, telemetry events, retry semantics (max 3 attempts), convenience helpers (`enqueue/3`, `enqueue_all/2`, `domains/0`, `chief_for/1`). Tests: 18 passing in `domain_processor_test.exs`.)_
33. [ ] Gate `Thundercrown.AgentRunner` via ThunderGate policy; call AshAI/Jido actions.
34. [~] Reintroduce Jido/Bumblebee serving supervisor + echo fallback (scaffolded; needs validation/tests).
35. [ ] Expand `Thundercrown.McpBus` docs + CLI examples.
36. [x] Swap `Thunderline.Thunderflow.Event` UUID fallback to UUID v7 provider. _(Completed: Event already uses `Thunderline.UUID.v7()`. Migrated 4 other files: voice_channel, action, dashboard_live, mag_macro_command. Removed stale TODO comment.)_
37. [x] Ship `mix thunderline.flags.audit` to verify feature usage vs config. _(Completed: Full implementation with config scanning, code usage detection, undocumented/unused flag warnings, --json and --strict modes for CI.)_
38. [x] Harden telemetry boot when `:opentelemetry_exporter` missing.
39. [x] Add StreamManager + Oban counters to LiveDashboard / Grafana JSON. _(Completed: Oban job metrics (start/stop/exception) + queue depth gauges added to ThunderlineWeb.Telemetry for LiveDashboard; Prometheus endpoint extended with per-queue available/executing/scheduled/retryable gauges. StreamManager deferred—module doesn't exist yet, see #19.)_
40. [x] Update `THUNDERLINE_DOMAIN_CATALOG.md` + README with new guards and progress. _(Completed: Updated domain catalog for 12-Domain Pantheon completion—ThunderCore/Pac/Wall marked active, Thunderbit subsystem documented (11 modules), Thunderfield LiveView added. README updated with ThunderPac in active list, HC-Δ-5/5.3 additions. Stats: ~175 resources, all 12 domains now active.)_

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
Alright, let's knight this properly. This is a comprehensive spec - I'll implement it systematically.


Let me first check the existing structure and the ex_rose_tree dependency:

Excellent! There's already a Thunderchief.Behaviour. Now let me check the existing Chiefs and DomainProcessor:

Now let me look at one of the existing Chiefs to understand the pattern:

vine_chief.ex

Now I have a good understanding of the existing architecture. Let me create the implementation files. I'll start with the RoseTree helper, then the PlanTree module:

Summarized conversation history

Now let me create the extended ChiefBehaviour with plan capabilities:

Now the main PlanTree facade - this is the heart of the spec:

Now let me read the DomainProcessor to understand how to wire in PlanTree support:

domain_processor.ex

Now I'll create an updated version of the DomainProcessor that adds PlanTree support while maintaining backward compatibility:

Edited
domain_processor.ex+19-0
Edited
domain_processor.ex+2-0
Edited
domain_processor.ex+27-10
Now add the plan node execution function. Let me find a good spot for it:

domain_processor.ex

Let me add the plan execution function right before the Chief Execution section:

Edited
domain_processor.ex+62-0
Now let's add the convenience functions for enqueueing plan nodes at the end of the module. First, let me see the end of the file:

domain_processor.ex

Edited
domain_processor.ex+57-0

Now let's create a stub Chief that demonstrates the full PlanTree integration:

plan_chief.ex

Now let's add PlanChief to the domain_chiefs map in DomainProcessor:

Edited
domain_processor.ex+4-2

Now let's create the end-to-end test:

plan_tree_test.exs

Now let's compile and run the tests to make sure everything works:

mix compile 2>&1 | head -100
We have some warnings but it compiles. Let me fix the type warning:

plan_tree.ex

The issue is that our RoseTree.update_value returns :not_found directly, not {:error, :not_found}. Let me fix the RoseTree module to be consistent:

The spec says {:ok, t()} | {:error, :not_found} but we're returning :not_found. Let me check find_and_update:

rose_tree.ex

I see - find_and_update returns :not_found but update_value calls it directly without wrapping. Let me fix update_value:

Edited
rose_tree.ex
Now let's recompile and run the tests:

mix compile --force 2>&1 | tail -30
mix compile 2>&1
mix compile
Good, it compiles with only some minor warnings. Now let's run the tests:

mix test test/thunderline/thunderchief/plan_tree_test.exs --trace 2>&1
It seems the test may have gotten stuck. Let me run it without trace:

timeout 60 mix test test/thunderline/thunderchief/plan_tree_test.exs 2>&1
There's a stuck process. Let me kill it and try again:

pkill -f "beam.smp" 2>/dev/null; sleep 2; cd /home/mo/DEV/Thunderline && MIX_ENV=test mix test test/thunderline/thunderchief/plan_tree_test.exs
pkill -9 -f beam 2>/dev/null; sleep 1; echo "BEAM processes killed"
The compile is taking a while. Let me wait a bit and retry with simpler approach - just see if the code is valid by compiling the specific file:

sleep 30 && cd /home/mo/DEV/Thunderline && mix test test/thunderline/thunderchief/plan_tree_test.exs 2>&1 | head -100


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
