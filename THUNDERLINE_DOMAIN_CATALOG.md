# 🌩️ THUNDERLINE DOMAIN & RESOURCE CATALOG

> **SYSTEMS THEORY AUGMENT (2025)** – Domain ecology & governance layers integrated. See added sections: Interaction Matrix, Event Taxonomy, Anti-Corruption, Stewardship.

> **UNIFIED ARCHITECTURE** - Last Updated: October 3 2025  
> **Status**: 🔥 **7-DOMAIN ARCHITECTURE OPERATIONAL (Auth + Realtime Chat Baseline Added)**  
> **Compilation**: ✅ **CLEAN BUILD SUCCESSFUL**  
> **Purpose**: Complete catalog of consolidated domain architecture with all resources

---

## ⚡ **ARCHITECTURE OVERVIEW: 7 UNIFIED DOMAINS**

### 🆕 Recent Delta (Oct 2025)
| Change | Domains | Impact |
|--------|---------|--------|
| Unified Persistent Model (UPM) charter ratified | ThunderBolt, ThunderBlock, ThunderFlow, ThunderCrown | Establishes real-time shared model fed by pipelines; agents gain unified embeddings |
| AshAuthentication (password strategy) integrated with Phoenix | ThunderGate, ThunderLink | Enables session auth, actor context for policies |
| AuthController + Live on_mount (`ThunderlineWeb.Live.Auth`) | Cross Web Layer | Centralized current_user assignment & Ash actor set |
| Discord-style Community & Channel LiveViews | ThunderLink | Real-time navigation & messaging surface established |
| AI Panel & Thread (stub) | ThunderLink / ThunderCrown (future) | Placeholder for AshAI tool execution pipeline |
| Post-login redirect to first community/channel | ThunderLink | Immediate immersion, reduces friction after sign-in |
| Probe analytics resources & worker added | ThunderFlow | Added `ProbeRun`, `ProbeLap`, `ProbeAttractorSummary` + Oban processing & telemetry |
| VIM DIP introduced | Cross (Bolt/Flow/Link) | Shared Virtual Ising Machine optimization layer draft (DIP-VIM-001) |
| Parser error consolidation | Cross | Integrated parser addendum into `ERROR_CLASSES.md` |
| Attractor recompute + canonical Lyapunov selection | ThunderFlow | Supports parameterized recomputation & stability metrics |
| Dependabot + CI workflow introduced | Cross | Automated dependency/security drift management & quality gates |

Planned Next: Stand up UPM trainer/adapters (HC-22), replace AI stub with AshAI actions, authenticated presence, channel policy enforcement, email automation slice DIP.

### 🧬 Domain Interaction Matrix (Allowed Directions)

Legend:
- ✔ Allowed (direct call or action)
- △ Indirect via normalized events / Ash action boundary (no raw struct coupling)
- ✖ Forbidden (introduce Bridge/Reactor or re-evaluate responsibility)ets c

| From \ To | Block | Bolt | Crown | Flow | Gate | Grid | Link |
|-----------|-------|------|-------|------|------|------|------|
| Block | — | ✔ infra scheduling | △ model provisioning | ✔ metrics infra | ✔ auth bootstrap | ✔ spatial persistence | △ UI boot events |
| Bolt | ✔ infra requests | — | ✔ model lifecycle | ✔ pipeline control | △ auth queries | ✔ spatial job deploy | ✔ user interaction triggers |
| Crown | △ image pulls | ✔ orchestrated runs | — | ✔ governance metrics | △ policy auth | △ simulation context | ✔ oversight dashboards |
| Flow | ✔ instrumentation reg | ✔ ingest signals | ✔ model output metrics | — | △ auth telemetry | △ spatial heatmaps | ✔ live dashboards |
| Gate | △ cluster keys | △ job signing | △ key policy feed | △ metrics guard rails | — | △ location auth | △ secure channels |
| Grid | ✔ provisioning | ✔ scheduling | △ AI placement hints | ✔ spatial metrics | △ actor gating | — | ✔ spatial UI streams |
| Link | △ infra status | ✔ orchestrator control | ✔ AI oversight UI | ✔ observability UI | ✔ auth flows | ✔ spatial viewer | — |

Guidelines:
1. Any new edge requires DIP Issue + justification.
2. △ edges must not introduce compile-time struct dependencies (use events or defined public actions).
3. Escalate to Reactor if chatter on a △ edge exceeds 5 events/min sustained.
 4. Optimization (VIM) adaptors MUST treat domains as data suppliers only; no reverse coupling from solver to raw domain structs (only via published results or actions).

---

### 📦 Event Taxonomy (Canonical Event Shape)

All cross-domain events MUST conform:
```
%Thunderline.Event{
    id: UUID.t(),
    domain: atom(),
    type: atom(),
    version: 1..n,
    occurred_at: DateTime.t(),
    causation_id: UUID.t() | nil,
    correlation_id: UUID.t() | nil,
    source: String.t(),
    payload: map(),
    meta: map()
}
```
Reserved type prefixes: `reactor.`, `system.`, `audit.`, `ui.` (see Handbook for semantics). Version increments mandatory on breaking payload changes.

VIM Telemetry Names (planned; see DIP-VIM-001):
`[:vim,:router,:solve,:start|:stop|:error]`, `[:vim,:persona,:solve,:start|:stop|:error]` – shadow & active differentiation via metadata `mode`.

UPM Event & Telemetry Names:
- Events: `ai.upm.snapshot.created`, `ai.upm.snapshot.activated`, `ai.upm.shadow_delta`, `ai.upm.rollback` (all gated by taxonomy registry).
- Telemetry: `[:upm,:trainer,:update]`, `[:upm,:snapshot,:freshness]`, `[:upm,:drift,:score]`, `[:upm,:adapter,:sync]` with metadata `mode`, `tenant`, `version`.

Bridge Telemetry (Phase-1 scaffold):
`[:cerebros,:bridge,:invoke,:start|:stop|:exception]` — invocation lifecycle (timeout & exception coverage). Future cache events: `[:cerebros,:bridge,:cache,:hit|:miss]`.

---

### 🛡 Anti-Corruption & Bridges

External protocol ingestion MUST isolate via `bridge/` modules inside the receiving domain. Responsibilities:
1. Normalize provider payload → canonical event/action attrs.
2. Emit `bridge.success` / `bridge.failure` events.
3. Provide contract tests (`test/<domain>/bridge/`).
4. Enforce provider struct quarantine (no leakage beyond bridge boundary).

---

### 🧭 Stewardship & Invariants

Each domain has a Steward role responsible for invariant evolution & deletion approvals. Resource catalog entries SHOULD grow invariant annotations incrementally:
`Invariants: ["status lifecycle", "idempotent emit", ...]`

Missing invariants MUST be tracked with an issue tag `invariant:pending`.

---

After the **Great Domain Consolidation of December 2024**, Thunderline now operates with a clean, efficient 7-domain architecture that eliminates redundancy and creates clear boundaries:

```
🌩️ Thunderline Root
├── 🏗️ ThunderBlock   - Infrastructure & Memory Management
├── ⚡ ThunderBolt    - Resource & Lane Management (Multi-Domain Consolidation)
├── 👑 ThunderCrown   - AI Governance & Orchestration
├── 🌊 ThunderFlow    - Event Processing & System Monitoring
├── 🚪 ThunderGate    - Security, Authorization, Access Control & External Integration
├── 🌐 ThunderGrid    - Spatial Computing & Zone Management
└── 🔗 ThunderLink    - Communication & Social Systems
```

---

## 🎯 **DOMAIN BREAKDOWN: COMPLETE RESOURCE MAPPING**

### 🏗️ **ThunderBlock** - Infrastructure & Memory Foundation
**Path**: `lib/thunderline/thunderblock/`  
**Purpose**: Core infrastructure, distributed systems, and unified memory management  
**Integration**: Consolidates all infrastructure and vault resources into single domain

#### **Infrastructure Resources** (12 resources)
- **cluster_node.ex** - Distributed cluster node management and coordination
- **community.ex** - Community infrastructure and organization management
- **distributed_state.ex** - Cross-node state synchronization and consistency
- **execution_container.ex** - Container runtime management and orchestration
- **load_balancing_rule.ex** - Load balancing policies and traffic distribution
- **rate_limit_policy.ex** - Rate limiting configuration and enforcement
- **supervision_tree.ex** - Fault-tolerant supervision hierarchies
- **system_event.ex** - Infrastructure event tracking and logging
- **task_orchestrator.ex** - Cross-domain task orchestration and scheduling
- **zone_container.ex** - Zone-based containerization and resource isolation

#### **Memory & Knowledge Resources** (11 resources)
- **vault_action.ex** - Action tracking and audit trails in memory system
- **vault_agent.ex** - Agent entities and behavioral memory storage
- **vault_cache_entry.ex** - Distributed caching system with intelligent eviction
- **vault_decision.ex** - Decision records for learning and replay capabilities
- **vault_embedding_vector.ex** - Vector embeddings for AI/ML operations
- **vault_experience.ex** - Experience accumulation and learning records
- **vault_knowledge_node.ex** - Knowledge graph nodes with semantic relationships
- **vault_memory_node.ex** - Memory system nodes for distributed cognition
- **vault_memory_record.ex** - Individual memory records with temporal tracking
- **vault_query_optimization.ex** - Query optimization for large-scale memory operations
- **vault_user.ex** - User management with memory-based personalization
- **vault_user_token.ex** - Authentication tokens with memory-backed sessions

#### **Supporting Infrastructure**
- **thunder_memory.ex** - Core memory operations and distributed coordination

#### ♻️ Retention Registry & Lifecycle Jobs
- **resources/retention_policy.ex** – Declarative Ash registry describing TTL, grace, and action semantics per resource/scope.
- **retention.ex** – Helper module for seeding defaults, resolving effective policies, and normalizing interval metadata.
- **retention/sweeper.ex** – Batch-aware sweeper with dry-run guardrails, telemetry emission (`[:thunderline, :retention, :sweep]`), and policy caching to prune expired rows safely.
- **telemetry/retention.ex** – Named telemetry handler that aggregates sweep results, publishes PubSub updates, and exposes stats for dashboards/tests.
- **jobs/retention_sweep_worker.ex** – Oban worker scheduled via `RETENTION_SWEEPER_CRON` (hourly by default) that fans out across configured sweep targets.

#### 🌩️ Thundra & Nerves Integration (HC-23)

**Thundra VM Responsibilities** (Cloud Execution):
- **PAC State Storage**: Persist voxelized time-state for all Thunderbit/Thunderbolt/Sage/Magus agents
- **Voxel Data Persistence**: Store 3D cellular automata state across 12-zone hexagonal lattice
- **Memory Vault APIs**: Provide high-performance read/write APIs for Thundra VM state access
- **Zone Configuration Storage**: Maintain zone metadata (timing, chakra mappings, active agents)
- **Snapshot & Replay**: Support GraphQL-driven state snapshots and temporal replay of PAC executions

**Nerves Runtime Responsibilities** (Edge Execution):
- **Device Association Records**: Map hardware devices to their enrolled PAC instances
- **Firmware Version Tracking**: Store deployed firmware versions, certificates, and build metadata
- **Last-Seen Telemetry**: Track device heartbeats and connection status for offline detection
- **Local State Persistence**: Cache device-specific configuration for offline PAC execution
- **Telemetry Buffer Storage**: Queue device telemetry for backhaul when connectivity restored

**Key Integration Points**:
- ThunderBolt coordinates Thundra VM lifecycle → Block persists state
- ThunderGate device enrollment → Block stores device certificates & associations
- ThunderLink TOCP transport → Block buffers telemetry queue for devices
- Retention policies apply to voxel snapshots, device logs, and telemetry buffers

**Total**: **23 Resources** - Complete infrastructure and memory foundation

---

### ⚡ **ThunderBolt** – Orchestration, Optimization & ML Control Plane
**Path**: `lib/thunderline/thunderbolt/`  
**Purpose**: Coordinate computational lanes, numerical solvers, and ML experimentation while enforcing domain boundaries.  
**Integration**: Hosts core workflow DAGs, lane automation, Ising/VIM numerics, and the full Cerebros NAS bridge + model ledger.

#### 🔁 Core Orchestration Resources
- `core_agent.ex`, `core_workflow_dag.ex`, `core_task_node.ex`, `core_system_policy.ex`, `core_timing_event.ex`
    - Drive long-running orchestrations, enforce invariant policies, and timestamp execution phases.
- `activation_rule.ex`, `orchestration_event.ex`, `resource_allocation.ex`
    - Govern resource activation signals and persistence of orchestration milestones.
- `chunk.ex`, `chunk_health.ex`
    - Track compute substrate slices and their health metrics.

#### 🛤 Lane Automation & Cellular Systems
- `lane_cell_topology.ex`, `lane_consensus_run.ex`, `lane_cross_lane_coupling.ex`, `lane_lane_configuration.ex`, `lane_lane_coordinator.ex`
    - Declare topology, configuration, and coordination primitives for adaptive lanes.
- `lane_lane_metrics.ex`, `lane_performance_metric.ex`, `lane_rule_oracle.ex`, `lane_rule_set.ex`, `lane_telemetry_snapshot.ex`
    - Persist metrics, rule evaluations, and telemetry snapshots for downstream analytics.
- `mag_macro_command.ex`, `mag_task_assignment.ex`, `mag_task_execution.ex`
    - Run macro task batches and coordinate execution assignment for humans/agents.
- `ca/` + `thundercell/`
    - ThunderCell cellular automata engine (Elixir-native) with supervisors, teleport bridge, and telemetry wrappers powering distributed lane simulations.

#### 🧠 Numerical Optimization & VIM Surface
- `ising_optimization_problem.ex`, `ising_optimization_run.ex`, `ising_performance_metric.ex`
    - State Ising energy problems, capture execution runs, and score performance for Virtual Ising Machine (VIM) workloads.
- `numerics/`, `ising_machine/`, `vim/`
    - Provide solver kernels, topology partitioners, and VIM control surfaces used by higher-level orchestration.

#### 🤖 ML Experiment Ledger & Registry
- `model_run.ex`, `model_artifact.ex` under `resources/`
    - Canonical Ash resources capturing NAS pulse lifecycle and serialized artifacts.
- `ml/` namespace (`model_spec.ex`, `model_version.ex`, `training_run.ex`, `training_dataset.ex`, `feature_view.ex`, `consent_record.ex`, `emitter.ex`, `types.ex`)
    - Higher-level ML registry, dataset descriptors, telemetry emitters, and Axon trainer integrations.
- `changes/` & `export/`
    - Contain change-logging helpers and export pipelines for promoting artifacts beyond the domain boundary.

#### 🌐 Unified Persistent Model (UPM)
- `upm_trainer.ex`, `upm_snapshot.ex`, `upm_adapter.ex`, `upm_drift_window.ex` under `upm/`
    - Trainer performs online SGD against ThunderFlow feature windows; snapshots persist to ThunderBlock vault; adapters stream embeddings/actions to ThunderBlock agents.
- `upm/shadow_supervisor.ex`
    - Supervises shadow-mode training & drift monitors, emits telemetry (`[:upm, :trainer, :update]`).
- `upm/policy.ex`
    - Provides Ash actions for ThunderCrown policies to gate activation (`:unified_model` feature flag aware).
- `upm/telemetry.ex`
    - Aggregates freshness, drift score, adoption metrics, and surfaces them to Observability dashboards.
- Event Outputs: `ai.upm.snapshot.created`, `ai.upm.snapshot.activated`, `ai.upm.shadow_delta`, with correlation back to originating command/event.
- Dependencies: Consumes ThunderFlow `feature_window` resources, persists snapshots via ThunderBlock retention policies, coordinates rollout with ThunderCrown policy verdicts.

#### � RAG System - Semantic Search & Document Retrieval
- `rag/document.ex` (Ash resource with AshPostgres + ash_ai extension)
    - Stores documents with automatic vectorization via sentence-transformers/all-MiniLM-L6-v2 (384-dim embeddings)
    - PostgreSQL pgvector storage for native vector operations and cosine similarity search
    - Actions: `create_document`, `update_embeddings`, `semantic_search` (sub-10ms query performance)
- `rag/embedding_model.ex`
    - Adapter implementing `AshAi.Embedding` behavior for Bumblebee model serving
    - Converts text to 384-dimensional vectors using transformer models
- `rag/serving.ex`
    - Manages Bumblebee model lifecycle via supervision tree (~7-8s initial load, persistent thereafter)
- **Feature flag**: `:rag_enabled` (enabled by default in dev, set `RAG_ENABLED=1` for production)
- **Performance**: 95% faster than previous Chroma HTTP implementation (~7-10ms vs ~150ms queries)
- **Architecture**: Unified PostgreSQL storage (removed external Chroma dependency, 65% code reduction)
- **Testing**: Run `test_rag_acceptance.exs` for end-to-end validation
- See `RAG_REFACTOR_HANDOFF.md` for complete migration documentation

#### �🛰 Cerebros Bridge & Event Surface
- `cerebros/adapter.ex`, `cerebros/artifacts.ex`, `cerebros/simple_search.ex`, `cerebros/telemetry.ex`
    - Adapter between Ash model ledger and bridge, artifact hydration, placeholder search strategy, and telemetry helpers.
- `cerebros_bridge/client.ex`, `translator.ex`, `invoker.ex`, `cache.ex`, `contracts.ex`
    - Anti-corruption boundary for executing Python Cerebros runners with feature gating, structured contracts, retries, and ETS-backed caching.
- Emits canonical events (`ml.run.start|stop|exception`, `ml.run.trial`) through `Thunderline.Thunderflow.EventBus` and telemetry spans under `[:cerebros, :bridge, ...]`.

##### Activation Guardrails & Feature Flags
- **Feature switch:** The Cerebros bridge is protected by the `:ml_nas` feature flag. Keep it disabled until validation passes; setting `CEREBROS_ENABLED=1` (or `true`) flips the runtime feature map automatically, or you can hardcode `config :thunderline, :features, [:ml_nas, ...]` if you prefer static config. The validator marks the flag as an error when missing.
- **Config gating:** Runtime config under `:thunderline, :cerebros_bridge` must set `enabled: true`, point `repo_path`/`script_path` at the cloned Cerebros repository, and provide a usable `python_executable`. Export `CEREBROS_ENABLED=1` once validation passes to toggle this at runtime; leave it `false` for cold installs.

##### Cerebros Bridge Validator CLI
Use the Mix task to exercise the guardrails without booting the full NAS loop:

```bash
mix thunderline.ml.validate
```

Key switches:
- `--require-enabled` – fail if `:cerebros_bridge` is still disabled (default is warning).
- `--json` – emit the check report as prettified JSON for automation.

The task returns exit code 1 when any check errors, ensuring CI/CD or ops scripts can gate deployments. Run it locally with `SKIP_JIDO=true` when the agent stack is unavailable.

**Key Capabilities**
- Declarative orchestration DAGs with Ash persistence and policy hooks.
- Adaptive lane topology + ThunderCell CA simulations to test coordination strategies.
- Virtual Ising Machine workflows feeding both human and automated solvers.
- First-class ML experiment ledger wired to Cerebros NAS, including artifact tracking and Axon trainers.
- Hardened bridge boundary with caching, retries, structured error classes, and canonical event emission.
- Flower federation wiring lives in `python/cerebros/keras/flower_app.py`, providing a Keras-only client/server for Flower Deployment Engine and eliminating PyTorch from the baseline superexec images.

#### 🌩️ Thundra & Nerves Integration (HC-23)

**Thundra VM Responsibilities** (Cloud Execution):
- **Thundra VM Hosting**: Run GenServer-based Thundra VM instances with 12-zone hexagonal lattice
- **PAC Orchestration**: Coordinate ~3M Thunderbits organized into Thunderbolt → Sage → Magus → Thunderchief hierarchy
- **Tick Scheduling**: Drive tick-tock execution cycles (12-second active zones, 132-second full rotation)
- **Zone Failover Coordination**: Detect zone failures and migrate PAC state to healthy zones via ThunderBlock
- **GraphQL State Exposure**: Provide real-time PAC state queries via ThunderGrid (`thundraState { zone tickCount voxelData }`)
- **ML Offload for Edge**: Execute heavy compute requests from Nerves devices (TensorFlow inference, rendering)

**Nerves Runtime Responsibilities** (Edge Execution):
- **Cloud PAC Coordination**: Coordinate with edge devices when they go offline → spin up cloud Thundra VM as failover
- **Heavy Compute Offload**: Accept ML inference, image processing, signal processing requests from resource-constrained devices
- **VM Spinup for Edge PACs**: Instantiate Thundra VM instances for edge PACs requiring cloud execution
- **Policy Enforcement Bridge**: Relay Crown policy decisions to offline devices via cached manifests in ThunderBlock

**Key Integration Points**:
- ThunderBlock persists Thundra VM state → Bolt reads/writes voxel data via memory vault APIs
- ThunderGate validates device enrollments → Bolt provisions cloud VM when device offline
- ThunderFlow routes zone tick events → Bolt consumes for PAC state transitions
- ThunderCrown policies gate zone activations → Bolt enforces via feature flag checks (`:unified_model`, `:ml_nas`)
- ThunderLink TOCP transport → Bolt coordinates device-to-cloud failover messaging

**Total**: **30 resources + supporting modules** (Ash resources under `resources/` and ML registry modules under `ml/`) – the command center for orchestration, numerics, and Cerebros-driven model experimentation.

---

### 👑 **ThunderCrown** - AI Governance & Orchestration
**Path**: `lib/thunderline/thundercrown/`  
**Purpose**: AI policy management, MCP integration, and high-level workflow orchestration  
**Integration**: Central AI governance and policy coordination

#### **AI Governance Resources** (4 resources)
- **ai_policy.ex** - AI behavior policies, safety rules, and governance frameworks
- **mcp_bus.ex** - Model Context Protocol bus for AI tool coordination
- **orchestration_ui.ex** - User interface for system orchestration and control
- **workflow_orchestrator.ex** - High-level workflow orchestration across domains

**Key Capabilities**:
- **MCP Integration**: Seamless AI tool coordination and governance
- **Policy Enforcement**: AI safety and behavior constraint management
- **Workflow Orchestration**: Cross-domain process coordination
- **UI Management**: Central control interface for system operations

#### 🌩️ Thundra & Nerves Integration (HC-23)

**Thundra VM Responsibilities** (Cloud Execution):
- **Thundra VM Policy Enforcement**: Evaluate zone-level governance rules for PAC tick cycles
- **Zone-Level Governance**: Enforce chakra-aligned policies per zone (security for Zone 2/Orange, computation for Zone 3/Yellow, etc.)
- **PAC Action Authorization**: Validate PAC actions against AI safety policies before execution in Thundra zones
- **Dynamic Policy Updates**: Push policy updates to active Thundra VM instances via ThunderFlow events
- **Audit Trail Generation**: Emit `crown.policy.*` events for all Thundra VM governance decisions

**Nerves Runtime Responsibilities** (Edge Execution):
- **Edge Policy Manifest Generation**: Generate device-specific policy caches for offline enforcement
- **Device-Specific Policy Caching**: Create compressed policy bundles for local PAC execution on Nerves devices
- **Offline Governance Mode**: Support PACs making policy decisions using cached manifests when disconnected from cloud
- **Certificate Lifecycle Management**: Issue/renew/revoke device client certificates via ThunderGate integration
- **Fallback Phone-Home Protocol**: Define escalation rules when edge PACs encounter ambiguous policy cases
- **Policy Sync on Reconnect**: Update device policy cache when connectivity restored

**Key Integration Points**:
- ThunderGate mTLS handshake → Crown validates device cert and issues policy manifest
- ThunderBolt Thundra VM requests → Crown provides zone activation policies
- ThunderBlock caches edge policy manifests → Crown updates when policies change
- ThunderLink TOCP transport → Crown pushes policy updates to connected devices
- ThunderFlow emits `crown.policy.evaluated` events → Crown tracks policy decision metrics

**Total**: **4 Resources** - AI governance and orchestration control center

---

### 🌊 **ThunderFlow** - Event Processing & System Monitoring
**Path**: `lib/thunderline/thunderflow/`  
**Purpose**: Event streaming, real-time processing, and comprehensive system monitoring  
**Integration**: Broadway pipelines, monitoring, and event coordination

#### **Core Resources** (14 resources)
- **consciousness_flow.ex** - Consciousness state flows and awareness processing
- **event_stream.ex** - Core event streaming infrastructure with Broadway integration
- **telemetry_seeder.ex** - Telemetry data seeding and initialization

#### **Event System Infrastructure**
- **event_bus.ex** - Central event bus for cross-domain communication
- **mnesia_producer.ex** - Mnesia-based event producer for persistent queues
- **mnesia_tables.ex** - Mnesia table definitions for event persistence

#### **Pipeline Infrastructure**
- **pipelines/event_pipeline.ex** - Broadway-based event processing pipelines

**Key Capabilities**:
- **Broadway Pipelines**: Real-time event processing with backpressure control
- **Mnesia Integration**: Persistent event queues with distributed coordination
- **Cross-Domain Events**: Structured inter-domain communication
- **Real-Time Monitoring**: Comprehensive system observability

**Total**: **14 Resources** - Complete event processing and monitoring platform

---

### 🚪 **ThunderGate** - Security, Authorization, Access Control & External Integration
**Path**: `lib/thunderline/thundergate/`  
**Purpose**: Complete security framework, authentication (AshAuthentication), authorization (policy & role), external service integration, and federation protocols  
**Integration**: External connectivity, policy decision engines, and comprehensive security management (CONSOLIDATED FROM THUNDEREYE & THUNDERGUARD)

#### **Security & Authorization Resources** (18 resources)
- **alert_rule.ex** - Alerting rules and security monitoring (migrated from ThunderEye)
- **audit_log.ex** - Comprehensive audit logging for compliance (migrated from ThunderEye)
- **data_adapter.ex** - Adapters for external data sources and format conversion
- **decision_framework.ex** - Core decision-making frameworks and logic engines
- **error_log.ex** - Error tracking and security incident logging (migrated from ThunderEye)
- **external_service.ex** - External service integrations and API management
- **federated_message.ex** - Cross-realm messaging and federation protocols
- **federated_realm.ex** - Federated realm management and coordination
- **performance_trace.ex** - Performance monitoring for security systems (migrated from ThunderEye)
- **policy_rule.ex** - Policy rule evaluation and governance enforcement
- **realm_identity.ex** - Cross-realm identity management and authentication
- **system_action.ex** - Security action tracking and audit (migrated from ThunderEye)
- **system_metric.ex** - Security metrics and monitoring (migrated from ThunderEye)
- **thunderbit_monitor.ex** - AI behavior monitoring for security (migrated from ThunderEye)
- **thunderbolt_monitor.ex** - Resource security monitoring (migrated from ThunderEye)
- **health_check.ex** - Security health monitoring (migrated from ThunderEye)
- **thunder_bridge.ex** - Bridge infrastructure for cross-domain communication
- **thunderlane.ex** - Lane management and routing for secure communications

**Key Capabilities**:
- **AshAuthentication Integration**: Password strategy with session management & secure token signing
- **Complete Security Framework**: Authentication, authorization, and access control
- **Centralized Actor Assignment**: `ThunderlineWeb.Live.Auth` on_mount sets Ash actor for LiveViews
- **Security Monitoring**: Advanced threat detection and incident response (from ThunderEye)
- **ActivityPub Protocol**: Federation with external systems and communities
- **External API Integration**: Seamless connectivity to third-party services
- **Decision Engines**: Policy-driven decision making and rule evaluation
- **Cross-Realm Identity**: Secure identity federation across different systems
- **Performance Security**: Security-focused performance monitoring and optimization

#### 🌩️ Thundra & Nerves Integration (HC-23)

**Thundra VM Responsibilities** (Cloud Execution):
- **Thundra VM Registration**: Register new Thundra VM instances and assign zone allocations
- **Tick Event Validation**: Validate zone tick events for timing accuracy and integrity before ThunderFlow routing
- **Zone Assignment Logic**: Determine optimal zone placement for new PACs based on load and chakra progression
- **VM Health Monitoring**: Track Thundra VM heartbeats and zone rotation status for failover detection
- **Cross-Zone Authorization**: Enforce security boundaries between Thundra zones (prevent Zone 2/Security from accessing Zone 7/Crown directly)

**Nerves Runtime Responsibilities** (Edge Execution):
- **mTLS Device Authentication**: Validate device client certificates against Crown CA during enrollment
- **Client Certificate Validation**: Verify certificate chain, expiration, and revocation status (CRL/OCSP)
- **Enrollment Lifecycle Management**: 
  1. Device presents client cert
  2. Gate validates cert chain
  3. Checks Crown revocation list
  4. ThunderLink establishes TOCP session
  5. Device downloads Crown policy manifest
- **Firmware Handshake Protocol**: Coordinate signed firmware delivery with Crown signature verification
- **Device Re-enrollment**: Handle certificate renewal and policy refresh for existing devices
- **Offline Device Detection**: Mark devices as offline after heartbeat timeout → trigger Bolt cloud failover

**Key Integration Points**:
- ThunderCrown provides device CA and policy manifests → Gate enforces during mTLS handshake
- ThunderBlock stores device association records → Gate queries for enrollment status
- ThunderLink TOCP establishes transport session → Gate controls admission and rate limiting
- ThunderBolt requests VM registration → Gate validates identity and assigns zones
- ThunderFlow emits `device.enrolled` events → Gate publishes after successful handshake

**Total**: **18 Resources** - Complete security and external integration gateway

---

### 🌐 **ThunderGrid** - Spatial Computing & Zone Management
**Path**: `lib/thunderline/thundergrid/`  
**Purpose**: Spatial computing, zone-based resource management, and grid-based coordination  
**Integration**: Advanced spatial algorithms and zone-based system organization

#### **Spatial Computing Resources** (7 resources)
- **chunk_state.ex** - Chunk-based state management for spatial data processing
- **grid_resource.ex** - Grid-based resource allocation and spatial optimization
- **grid_zone.ex** - Zone definitions and spatial boundary management
- **spatial_coordinate.ex** - Coordinate systems and spatial transformations
- **zone_boundary.ex** - Dynamic zone boundary calculation and management
- **zone_event.ex** - Zone-based event processing and spatial triggers
- **zone.ex** - Core zone entities for spatial organization and coordination

#### **Supporting Infrastructure**
- **unikernel_data_layer.ex** - Specialized data layer for high-performance spatial computing

**Key Capabilities**:
- **Spatial Indexing**: Advanced grid-based spatial data organization
- **Zone Management**: Dynamic zone creation and boundary management
- **Resource Coordination**: Spatial-aware resource allocation and optimization
- **Event Processing**: Zone-based event triggers and spatial notifications
- **Unikernel Integration**: High-performance spatial computing optimizations

**Total**: **8 Resources** - Complete spatial computing and zone management platform

---

### 🔗 **ThunderLink** - Communication & Social Systems
**Path**: `lib/thunderline/thunderlink/`  
**Purpose**: Communication channels, social systems, community management & authenticated real-time UX  
**Integration**: Real-time communication and social coordination (Discord-style navigation established Aug 2025)

#### **Communication Resources** (9 resources)
- **channel.ex** - Communication channels with real-time messaging capabilities
- **community.ex** - Community organization, governance, and management
- **federation_socket.ex** - WebSocket connections for federated real-time communication
- **message.ex** - Core message entities with routing and delivery tracking
- **pac_home.ex** - PAC (Protocol Actor Community) home coordination and management
- **role.ex** - Role-based permissions and community hierarchy management
- **thunder_bridge.ex** - Bridge connections for cross-domain communication
- **thunderlane.ex** - Communication lane management and routing
- **user.ex** - User management and social profiles

**Key Capabilities**:
- **Discord-Style Navigation**: Community + channel sidebar layout with active context
- **Post-Auth Redirect Flow**: Users land directly in first community & channel after login
- **Real-Time Communication**: WebSocket-based messaging with federation support
- **Community Management**: Hierarchical community organization and governance
- **Role-Based Access**: Flexible permission systems for community participation
- **AI Panel Stub**: Placeholder LiveView region for upcoming AshAI tool execution
- **PAC Coordination**: Personal/collaborative space management

**LiveView Auth Integration**:
- `on_mount ThunderlineWeb.Live.Auth` ensures `current_user` + Ash actor assignment
- Layout wiring prepared for presence & channel membership policies (next phase)

#### 🌩️ Thundra & Nerves Integration (HC-23)

**Thundra VM Responsibilities** (Cloud Execution):
- **Inter-Zone Event Routing**: Route tick/tock events between Thundra zones with proper correlation_id/causation_id lineage
- **Cross-PAC Communication Fabric**: Enable PAC-to-PAC messaging within Thundra VM for swarm coordination
- **Zone Boundary Enforcement**: Validate events crossing zone boundaries comply with chakra progression rules (e.g., Zone 2 → Zone 3 allowed, Zone 2 → Zone 7 blocked)
- **Event DAG Construction**: Build causation chains for full Thundra execution audit trails
- **ThunderFlow Integration**: Emit zone tick events to ThunderFlow pipelines for persistence and analytics

**Nerves Runtime Responsibilities** (Edge Execution):
- **TOCP Transport Protocol**: Implement Thunderlink Transport (formerly TOCP) for device-to-cloud messaging
- **Device Heartbeat Management**: Send periodic `device.heartbeat` events to cloud via TOCP store-and-forward
- **Telemetry Backhaul Queue**: 
  - Local SQLite queue for offline telemetry buffering
  - Priority transmission (errors first, then metrics, then logs)
  - Batch compression for bandwidth efficiency
  - Cloud acknowledgment → prune local queue
  - Fallback: Persist locally >24hrs if connectivity lost
- **Mesh Connectivity Protocol**: Enable device-to-device communication for local PAC coordination
- **Network Failover Logic**: Detect offline state → queue events locally → resume backhaul when reconnected
- **Bandwidth Management**: Throttle telemetry transmission based on connection quality (WiFi vs cellular)

**Key Integration Points**:
- ThunderGate establishes TOCP session → Link manages transport lifecycle
- ThunderBlock provides telemetry buffer storage → Link reads queue for transmission
- ThunderCrown policy updates → Link pushes via TOCP to connected devices
- ThunderBolt coordinates device failover → Link detects offline state via heartbeat timeout
- ThunderFlow consumes device telemetry → Link publishes `device.*` events after backhaul

**Transport Feature Gate**:
- TOCP/Thunderlink Transport is FEATURE GATED (`:tocp` flag)
- Supervisor: `Thunderline.Thunderlink.Transport.Supervisor`
- Config: `config :thunderline, :tocp` (port=5088, gossip=1000±150ms, window=32)
- See `documentation/tocp/TOCP_DECISIONS.md` for architecture decisions
- Security: Control frame signing planned, replay window (30s), admission tokens required

**Total**: **9 Resources** - Complete communication and social platform

---

## 📊 **SYSTEM STATISTICS & HEALTH**

### **Domain Completion Status**
```
✅ ThunderBlock  - 23 resources (100% operational)
✅ ThunderBolt   - 34 resources (100% operational) 
✅ ThunderCrown  - 4 resources  (100% operational)
✅ ThunderFlow   - 14 resources (100% operational)
✅ ThunderGate   - 18 resources (100% operational, includes ThunderEye & ThunderGuard consolidation)
✅ ThunderGrid   - 8 resources  (100% operational)
✅ ThunderLink   - 9 resources  (100% operational)
🛰️ Thunderlink Transport (formerly TOCP) — FEATURE GATED (scaffold only). Not part of the original 7; emerging transport layer for membership, routing, reliability & store/forward. Code has been consolidated under `Thunderline.Thunderlink.Transport.*` (TOCP modules remain as shims). Feature flag `:tocp` still controls activation. Zero‑logic scaffold merged Aug 2025 (Orders Θ‑01).
    - Supervisor: `Thunderline.Thunderlink.Transport.Supervisor` (feature‑gated)
    - Core behaviours & components: `Admission`, `Config`, `FlowControl`, `Fragments`, `Membership`, `Reliability`, `Router`, `Routing.*`, `Security.*`, `Store`, `Telemetry.*`, `Wire` — under `Thunderline.Thunderlink.Transport.*`
    - Transport scaffold: `Thunderline.TOCP.Transport.UDP` (legacy stub, logs only; no bind)
    - Simulation harness: `Thunderline.TOCP.Sim.Fabric` / `NodeModel` (JSON report via `mix tocp.sim.run`)
    - Config surface: `config :thunderline, :tocp` (port=5088, gossip=1000±150ms, window=32, ack_batch=10ms, ttl=8)
    - Decisions & Telemetry docs: see `documentation/tocp/TOCP_DECISIONS.md`, `documentation/tocp/TOCP_TELEMETRY.md` (apply to Thunderlink Transport; telemetry prefix remains `[:tocp, *]` for compatibility; top-level TOCP_*.md are shims)
        - Security posture (v0.1): Control frame signing planned, replay window (30s), admission tokens required, fragment & credit caps hardened.
        - Security Battle Plan: `documentation/tocp/TOCP_SECURITY.md` (Operation Iron Veil)
```

### **Architecture Metrics**
- **Total Domains**: 7 (down from 21+ - 67% reduction in complexity)
- **Total Resources**: 110 operational resources
- **Domain Consolidation**: Successfully merged ThunderEye and ThunderGuard into ThunderGate
- **Security Consolidation**: All security, monitoring, and access control unified under ThunderGate
- **Code Cleanup**: Eliminated redundant domain references and legacy code
- **Compilation Status**: ✅ Clean compilation with zero critical errors

### **Strategic Benefits**
1. **🎯 Clear Boundaries**: Each domain has distinct, non-overlapping responsibilities
2. **🔄 Reduced Complexity**: 62% reduction in domain count while maintaining functionality
3. **⚡ Improved Performance**: Consolidated resources reduce inter-domain communication overhead
4. **🛠️ Easier Maintenance**: Clear resource ownership and simplified dependency graphs
5. **📈 Scalability**: Well-defined domain boundaries support independent scaling
6. **🏗️ Future-Ready**: Architecture supports growth without structural changes
7. **🌐 Spatial Computing**: Advanced grid-based spatial coordination and zone management

---

## 🎯 **DOMAIN INTERACTION MATRIX**

### **Primary Data Flow**
```
ThunderLink (User Input) 
    → ThunderCrown (AI Processing) 
    → ThunderBolt (Resource Coordination) 
    → ThunderGrid (Spatial Coordination)
    → ThunderFlow (Event Processing) 
    → ThunderGate (External Actions)
    → ThunderBlock (State Persistence)
```

### **Cross-Domain Dependencies**

Change Governance:
1. Additions require updating Interaction Matrix table above.
2. If a dependency shifts from △ to ✔ justify reason (latency, consistency, transactional need).
3. Quarterly review: prune obsolete edges & flag high-fanout hotspots.

Validation (future automation): `mix thunderline.catalog.validate` will parse code references to ensure declared edges match actual usage.

---
- **ThunderBlock** ← All domains (infrastructure and memory foundation)
- **ThunderFlow** ← All domains (event processing and monitoring)
- **ThunderCrown** ↔ All domains (orchestration and AI governance)
- **ThunderBolt** ↔ ThunderFlow (resource allocation and monitoring)
- **ThunderGrid** ↔ ThunderBolt (spatial resource coordination)
- **ThunderGrid** ↔ ThunderFlow (zone-based event processing)
- **ThunderGate** ↔ ThunderLink (external federation)

---

## 🚀 **NEXT PHASE: DASHBOARD & AI INTEGRATION**

### **Immediate Priorities**
1. **🎨 Dashboard Completion**: Complete LiveView integration with real-time components
2. **🤖 MCP Integration**: Activate ThunderCrown MCP bus for AI tool coordination
3. **� ThunderGate Security Enhancement**: Complete security and authorization resource implementation
4. **📱 Mobile Interface**: User-facing applications for PAC management

### **Production Readiness**
- **Event System**: ✅ Broadway + Mnesia architecture operational
- **State Management**: ✅ Ash 3.x + AshStateMachine fully integrated  
- **Resource Layer**: ✅ All domains compiling cleanly with proper data layers
- **API Layer**: ✅ AshJsonApi integration across all operational domains

---

## 🎊 **CONCLUSION: ARCHITECTURAL VICTORY ACHIEVED**

The **Great Domain Consolidation** has successfully transformed Thunderline from a complex multi-domain architecture to a streamlined, efficient 7-domain system. This represents a **major strategic victory** that delivers:

- **67% reduction in architectural complexity**
- **Zero critical compilation errors**
- **Complete security consolidation** (ThunderEye + ThunderGuard → ThunderGate)
- **Complete event-driven coordination**
- **Advanced spatial computing capabilities**
- **Production-ready foundation**
- **Future-proof scalability**

### **🔥 CONSOLIDATION HIGHLIGHTS**
- **ThunderGuard REMOVED** - All security moved to ThunderGate ✅
- **ThunderEye CONSOLIDATED** - All monitoring moved to ThunderGate ✅
- **Domain References FIXED** - All cross-references updated ✅
- **Resource Registration CORRECTED** - All domains properly registered ✅
- **Compilation CLEAN** - Zero errors, only warnings remain ✅

The system is now positioned for rapid feature development, AI integration, spatial computing applications, and user-facing interfaces while maintaining the robustness and performance characteristics that make Thunderline a cutting-edge distributed AI orchestration platform.

**🌩️ Thunderline is ready to storm the future with unified intelligence! ⚡🚪**
