# Thunderline Domain Resource Guide

> Version: 2025-11-17 | Maintainers: Thunderline Architecture Guild
> Scope: Unified reference for domain responsibilities, canonical resources, contracts, and operational guardrails.
> Architecture Grade: A (9/10) | Total Resources: ~150 | Active Domains: 8

## 0. Orientation

- **Purpose**: Provide a single annotated map of Thunderline domains, tying architectural doctrine, resource inventories, and operational controls into a living guide.
- **Audience**: Platform engineers, domain stewards, SRE/observability teams, governance reviewers, and AI orchestration partners.
- **Update cadence**: Reviewed each sprint by domain stewards. Changes require PR referencing this guide and related source docs.
- **Change control**: Updates demand cross-linking with source-of-truth files such as [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md), [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md), [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md) and [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md).
- **Architecture status**: Following comprehensive November 17, 2025 review: 8 active domains, ~150 Ash resources, 6 major consolidations completed, clean Ash.Domain usage throughout. See [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md) for detailed findings.

## 1. Domain Atlas

The Thunderline platform is organized into sovereign domains with explicit contracts. Containers align with the C4 views captured in [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md).

### 1.1 Thundergate — Security, Authentication, External Services, Federation, Policy, Monitoring

- **Resources**: **19 Ash Resources** across 6 categories
- **Consolidation**: ThunderStone + ThunderEye + Accounts + ThunderWatch → Thundergate (November 2025)
- **Mission**: Unified security, authentication, external service integration, federation, policy enforcement, and comprehensive system monitoring.
- **Extensions**: AshAdmin.Domain
- **Categories**:
  - **Authentication & Authorization** (2): User, Token
  - **External Services** (3): ExternalService, ServiceCredential, ServiceHealthCheck
  - **Federation** (3): FederationNode, FederationSession, FederationRoute
  - **Policy** (2): Policy, PolicyRule
  - **Monitoring** (9): HealthCheck, SystemMetric, LogEntry, AuditLog, AlertConfiguration, DeploymentStatus, ErrorTracking, ServiceDependency, PerformanceSnapshot
- **Code Interfaces**: User operations (create/read/update), Token management (generate/validate/revoke), Policy operations (evaluate/audit), HealthCheck operations (run/report)
- **Key Services**: Authentication (sessions, tokens), external integrations (Magika file classification), federation routing, policy evaluation, comprehensive monitoring (9 resources covering health, metrics, logs, alerts, deployments, errors, dependencies, performance)
- **Event responsibilities**: `ui.command.*` for ingress intents, `system.*` for policy results, `presence.*` for session state, `system.monitoring.*` for observability events; see [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md).
- **Observability**: Emits `[:thunderline, :security, :]` and `[:thunderline, :monitoring, :]` telemetry, feeds audit logs and metrics into ThunderBlock vault.
- **Magika Integration**: ExternalService resource manages Magika file classification (Python subprocess via System.cmd or Req HTTP client, outputs JSONB with file_type/mime_type/confidence).
- **Monitoring Unification**: All ThunderWatch monitoring resources (9 total) now consolidated under Thundergate.Monitoring for unified observability.

### 1.2 Thunderlink — Communication, Community, Voice, Node Registry

- **Resources**: **17 Ash Resources** across 4 categories (⚠️ Consolidation INCOMPLETE)
- **Consolidation Status**: ⚠️ ThunderCom→ThunderLink INCOMPLETE (both domains active simultaneously)
  - **Critical Issue**: 5 resources duplicated in both ThunderCom and ThunderLink domains
  - **Duplicate Resources**: Community, Channel, Message, Role, FederationSocket
  - **Voice Namespace Mismatch**: ThunderCom uses VoiceRoom, ThunderLink uses Voice.Room
  - **Active ThunderCom Usage**: community_live.ex, channel_live.ex, seeds_chat_demo.exs still use ThunderCom
- **Mission**: Serve communities, channels, support tickets, voice/WebRTC experiences, and distributed node registry.
- **Extensions**: AshAdmin, AshOban, AshGraphql, AshTypescript.Rpc (4 extensions for comprehensive API exposure)
- **Categories**:
  - **Support** (1): Ticket
  - **Community & Channels** (5): Community, Channel, Message, Role, FederationSocket
    - ⚠️ **DUPLICATES**: Also defined in ThunderCom domain (consolidation incomplete)
  - **Voice & WebRTC** (3): Voice.Room, Voice.Participant, Voice.Device
    - Note: ThunderCom uses different namespace (VoiceRoom vs Voice.Room)
  - **Node Registry & Cluster** (6): Node, Heartbeat, LinkSession, NodeCapability, NodeGroup, NodeGroupMembership
  - **Additional Infrastructure** (2): Other network components
- **Code Interfaces**: Node operations (register/update/heartbeat/query), Heartbeat management (record/prune), LinkSession management (create/update/expire), NodeCapability operations (add/remove/query)
- **GraphQL API**: Ticket system (get_ticket, list_tickets, create_ticket, close_ticket, process_ticket, escalate_ticket queries/mutations)
- **TypeScript RPC API**: list_tickets, create_ticket (via AshTypescript.Rpc extension)
- **Key Services**: LiveView UI, WebSocket federation client, VoiceChannel signalling, Dashboard ThunderBridge, distributed node coordination.
- **Event responsibilities**: Emits `ui.command.*`, `system.voice.*`, `voice.signal.*`, and `system.node.*` families. Constructor enforcement per Honey Badger plan.
- **Supervision**: Dynamic `RoomPipeline` supervisors transitioning to `Membrane.WebRTC` (see gap analysis in [`architecture/system_architecture_webrtc.md`](Thunderline/documentation/architecture/system_architecture_webrtc.md)).
- **Feature flags**: Gated by `:voice_input`, `:ai_chat_panel`, `:presence_debug` per [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md).
- **Bug #18 Integration**: LinkSession.meta attribute uses AtomMap custom type to preserve Elixir atoms through JSONB storage (Registry constructs with string keys, converts to atoms on load). See `lib/thunderline/thunderblock/types/atom_map.ex`.
- **Consolidation Action Required**: Complete migration before MVP (P0 backlog item)

### 1.3 Thunderflow — Event Bus & Broadway Pipelines

- **Resources**: **9 Ash Resources** across 7 categories
- **Mission**: Normalize, route, and persist events via Broadway pipelines, enforcing taxonomy contracts and DLQ policy.
- **Extensions**: AshAdmin.Domain
- **Categories**:
  - **Event Streams** (2): EventStream, EventSubscription
  - **System Actions** (1): SystemAction
  - **Events** (1): Event
  - **Probe System** (3): Probe, ProbeResult, ProbeAlert
  - **Features** (1): FeatureWindow
  - **Lineage** (1): Lineage.Edge
- **Broadway Pipelines** (4 production pipelines):
  - **EventPipeline**: General-purpose event processing with batching and backpressure
  - **CrossDomainPipeline**: Inter-domain event routing with DLQ for failed deliveries
  - **RealTimePipeline**: Low-latency processing for real-time events
  - **EventProducer**: Mnesia-backed event production with partition tolerance
- **Pipeline Features**: Batching, backpressure management, dead letter queues (DLQ), error recovery with exponential backoff + jitter
- **Key Services**: `EventBus`, Broadway supervisors, DLQ handlers, lineage tracking, probe-based monitoring.
- **Pipeline Functions**: `start_broadway_pipelines/0` (supervisor initialization), `process_event/3` (event handling with retry logic)
- **Event responsibilities**: Owns `flow.reactor.*`, ensures every domain obeys correlation/causation rules (Section 13 of [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md)).
- **Observability**: KPIs `[:flow, :market, :lag_ms]`, retry metrics, DLQ depth dashboards per [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md).
- **Backlog**: Implement taxonomy mix task (Section 14) and DLQ surfacing (Next Enhancements item in domain top-down architecture doc).

### 1.4 Thunderbolt — Compute, ML, Task Orchestration, Automata

- **Resources**: **50+ Ash Resources** across 11 categories (largest domain)
- **Consolidation**: ThunderCore + ThunderLane + ThunderMag + ThunderCell + Thunder_Ising → Thunderbolt (5-domain merger)
- **Mission**: Execute computational workloads including ML training, task orchestration, ThunderCell CA engine, Lane orchestrators, Model of Experts, and Cerebros bridges.
- **Extensions**: AshAdmin, AshOban, AshJsonApi, AshGraphql (4 extensions for comprehensive API and background job support)
- **Categories** (11 subsystems):
  - **Core** (5): Agent, AgentCapability, AgentTask, Workflow, WorkflowExecution
  - **Ising/VIM** (3): IsingProblem, IsingSolution, VIM.Audit
  - **Lane** (10): Lane orchestration resources (task management, scheduling, dependencies)
  - **Task** (3): Task, TaskDependency, TaskResult
  - **Automata** (5): Automaton, AutomatonState, AutomatonTransition, AutomatonExecution, AutomatonHistory
  - **Cerebros Bridge** (7): Run, RunOptions, Summary, Checkpoint, Metric, Artifact, ExperimentTag
  - **RAG** (1): RagChunk (retrieval-augmented generation)
  - **ML** (6): Model, ModelVersion, TrainingDataset, TrainingRun, Prediction, ModelMetric
  - **MLflow** (2): Experiment, Run
  - **UPM** (4): UPMTrainer, UPMSnapshot, UPMAdapter, UPMDriftWindow
  - **MoE** (3): Expert, ExpertRouter, ExpertMetric
- **GraphQL API**: core_agents queries and mutations for agent management
- **Code Interfaces**: TrainingDataset operations (create/read/update, add_samples, export), Agent management, Workflow execution
- **Key Services**: `ThunderCell` CA engine, `Lane` orchestrators, expert registries, `ErlangBridge` for neuro handoff, `CerebrosBridge` helpers (`RunOptions`, `Summary`).
- **RAG System**: Native PostgreSQL semantic search via `Document.semantic_search/2` (~7-10ms queries). Feature flag `:rag_enabled` (dev default). See `RAG_REFACTOR_HANDOFF.md` for complete API documentation.
- **Event responsibilities**: `ml.run.*`, `ai.tool_*`, `dag.commit`, `cmd.workflow.*`; cross-domain dispatch to Flow pipelines.
- **Roadmap**: Phase B policy/orchestration unification; NAS integration phases (Section 10 in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md)). Flower federation runs exclusively through Keras backend wiring (`python/cerebros/keras/flower_app.py`) so PyTorch dependencies dropped from NAS control plane images.
- **Feature flags**: `:ml_nas`, `:signal_stack`, `:vim`, `:vim_active`, `:rag_enabled` gating advanced features.
- **Recommendation**: **Consider splitting** - Thunderbolt is the largest domain (50+ resources). Potential split: Core/Lane/Task orchestration vs ML/RAG/Cerebros subsystems.

**ML Infrastructure Status (Nov 2025):**
- ✅ **Python Stack Ready**: TensorFlow 2.20.0, tf2onnx 1.8.4, ONNX 1.19.1, Keras 3.12.0 (`.venv` Python 3.13)
- ✅ **Elixir Stack Ready**: Req 0.5.15 (HTTP client), Ortex 0.1.10 (ONNX runtime), PythonX 0.4.0, Venomous 0.7
- ✅ **Build Status**: Successful compilation (dependency warnings non-blocking: Jido, LiveExWebRTC, ExWebRTC)
- ✅ **Foundation Code**: Python NLP CLI with JSON contract v1.0, Elixir Port supervisor (400 lines), telemetry framework
- ✅ **Architecture Spec**: Complete 10,000-word integration document (`docs/MAGIKA_SPACY_KERAS_INTEGRATION.md`)
- 🟡 **Pending Implementation** (specs complete, ready to code):
  - `lib/thunderline/thundergate/magika.ex` - File classification wrapper (System.cmd or Req)
  - `lib/thunderline/thunderbolt/models/keras_onnx.ex` - ONNX model loader via Ortex + Nx.Serving
  - `lib/thunderline/thunderbolt/voxel.ex` - DAG artifact packaging (Voxel v0 schema)
- 📋 **Event Pipeline**: `system.ingest.classified` → `ai.nlp.analyzed` → `ai.ml.run.completed` → `dag.commit` → ThunderBlock
- 🎯 **Next Actions**: Implement 3 pending modules (Magika, ONNX adapter, Voxel), wire Broadway pipeline, add supervision trees

### 1.5 Thundercrown — Governance, AI Orchestration, MCP Integration

- **Resources**: **4 Ash Resources** across 3 categories
- **Consolidation**: ThunderChief → Thundercrown (November 2025) - Executive control and governance unified
- **Mission**: Provide policy enforcement, AI intent derivation, tool selection, and MCP (Model Context Protocol) bus integration.
- **Extensions**: AshAdmin, AshAi (MCP tool exposure)
- **Categories**:
  - **Orchestration UI** (1): OrchestrationDashboard
  - **Agent Runner** (1): AgentRunner
  - **Conversation Tools** (2): ConversationContext, ConversationHistory
- **MCP Tools** (4 exposed via AshAi):
  - `run_agent` - Execute agent with context
  - `conversation_context` - Retrieve conversation context
  - `conversation_run_digest` - Generate conversation summary
  - `conversation_reply` - Generate conversation reply
- **Key Services**: MCP bus, workflow orchestrator, Daisy cognitive modules, AI governance hooks.
- **Planned Resources**: AIPolicy, McpBus, WorkflowOrchestrator (future AI governance hooks per Honey Badger Phase C3)
- **Event responsibilities**: `ai.intent.*`, `ai.tool_*`, and governance `system.*` events; ensures correlation propagation with Flow.
- **Compliance**: Policy centralization plan (Phase B1) and taxonomy governance from [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md) Section 9.

### 1.6 Thunderblock — Persistence, Provisioning, Knowledge Vault

- **Resources**: **33 Ash Resources** across 4 categories
- **Consolidation**: ThunderVault → Thunderblock (storage and persistence unification)
- **Mission**: Own persistent state (Postgres, Mnesia), provisioning, vault memories, cluster nodes, and runtime management.
- **Extensions**: AshAdmin.Domain
- **Categories**:
  - **Vault** (13): VaultKnowledgeNode, VaultMemory, VaultQuery, VaultIndex, VaultEmbedding, VaultMetadata, VaultRelation, VaultSnapshot, VaultAudit, VaultPolicy, VaultEncryption, VaultRetention, VaultReplication
  - **Infrastructure** (8): ExecutionContainer, Provisioner, ClusterNode, ResourcePool, CapacityPlan, InfrastructureMetric, ServiceRegistry, NetworkTopology
  - **Orchestration** (4): WorkflowTracker, WorkflowState, WorkflowCheckpoint, WorkflowSchedule
  - **ThunderVine Workflows** (4): Workflow, WorkflowNode, WorkflowEdge, WorkflowSnapshot
  - **Timing** (4): ScheduledJob, CronExpression, JobExecution, JobHistory
- **Code Interfaces**: VaultKnowledgeNode operations (delegation pattern for knowledge storage), Checkpoint management (create/restore/list)
- **Custom Types**: **AtomMap** (`lib/thunderline/thunderblock/types/atom_map.ex`) - Preserves Elixir atoms through PostgreSQL JSONB storage (Bug #18 solution). Storage format converts atom keys to strings for JSONB, converts back to atoms on load for idiomatic Elixir usage.
- **Key Services**: Vault storage, provisioning orchestrators, checkpointing, DAG execution, timing/scheduling services.
- **Migration governance**: Track namespace moves via [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md); enforce CI gating for deprecated modules.
- **Resilience**: Provide DR notes, retention tiers, and event emission `system.persistence.*`.
- **Migration In Progress**: ThunderClock → Thunderblock.Timing (scheduling as runtime concern)

### 1.7 Thundergrid — Spatial Runtime, ECS, Zones

- **Resources**: **5 Ash Resources** across 4 categories
- **Mission**: Coordinate zones, spatial coordinates, ECS placement for PAC agents and automata.
- **Extensions**: AshGraphql, AshJsonApi (dual API exposure)
- **Categories**:
  - **Spatial** (1): SpatialCoordinate
  - **Zones** (2): Zone, ZoneBoundary
  - **Events** (1): ZoneEvent
  - **State** (1): ChunkState
- **GraphQL API**:
  - **Queries**: zones, available_zones, zone_by_coordinates
  - **Mutations**: spawn_zone, adjust_zone_entropy, activate_zone, deactivate_zone
- **JSON API**: Spatial zone operations (create/read/update zones, coordinate queries)
- **Event responsibilities**: Publish spatial updates to Flow (`grid.*` → EventBus). Feed placement metadata to ThunderBolt orchestrations.
- **Future work**: Voice agents targeting zones, advanced placement heuristics (Section 2 in [`architecture/domain_topdown.md`](Thunderline/documentation/architecture/domain_topdown.md)).

### 1.8 ThunderChief — DEPRECATED (Consolidated into Thundercrown)

- **Status**: ⚠️ **DEPRECATED** - Merged into Thundercrown (November 2025)
- **Migration**: All executive control and orchestration resources moved to Thundercrown
- **Former Responsibilities**: Batch job scheduling, domain processors, scheduled workflow execution
- **Migration Path**: 
  - `domain_processor` → Thundercrown.AgentRunner
  - `scheduled_workflow_processor` → Thundercrown.WorkflowOrchestrator (planned)
  - Export jobs now managed through Thunderbolt orchestration
- **Note**: Directory may still exist for backward compatibility, but all active resources are in Thundercrown (4 resources). See Thundercrown section (1.5) for current resource details.

### 1.9 ThunderCom — Communication & Social Features (⚠️ CONSOLIDATION INCOMPLETE)

- **Resources**: **8 Ash Resources** (⚠️ Being consolidated into ThunderLink)
- **Consolidation Status**: ⚠️ **INCOMPLETE** - Both ThunderCom and ThunderLink currently active
- **Mission**: Legacy communication, community, and social features (being phased into ThunderLink)
- **Extensions**: AshAdmin.Domain
- **Categories**:
  - **Community & Chat** (5): Community, Channel, Message, Role, FederationSocket
    - ⚠️ **DUPLICATED in ThunderLink** - canonical implementation TBD
  - **Voice** (3): VoiceRoom, VoiceParticipant, VoiceDevice
    - Note: ThunderLink uses namespaced Voice.Room (differs from VoiceRoom)
- **Active Usage** (NOT deprecated):
  - `lib/thunderline_web/live/community_live.ex`
  - `lib/thunderline_web/live/channel_live.ex`
  - `priv/repo/seeds_chat_demo.exs`
- **Duplicate Resources**: 5 resources also defined in ThunderLink domain:
  - Community, Channel, Message, Role, FederationSocket
  - **Issue**: Unclear which implementation is canonical
  - **Impact**: Potential conflicts, confusion in API usage
- **Voice Namespace Discrepancy**:
  - ThunderCom: `VoiceRoom`, `VoiceParticipant`, `VoiceDevice`
  - ThunderLink: `Voice.Room`, `Voice.Participant`, `Voice.Device`
  - **Decision Required**: Standardize on one approach
- **Consolidation Plan** (7 steps):
  1. Audit which LiveViews use which domain's resources
  2. Determine canonical implementation for each duplicate
  3. Migrate LiveViews to canonical implementations
  4. Update seeds to use target domain
  5. Remove duplicate resources
  6. Verify voice implementation consistency
  7. Remove ThunderCom domain after complete migration
- **Former HC Review Claim**: "0 resources, fully deprecated" - **INCORRECT** (verified Nov 17, 2025)

### 1.10 ThunderVine — Workflow Orchestration (Utility Namespace)

- **Resources**: **0 Ash Resources** (utility namespace, not an Ash.Domain)
- **Files**: 4 utility modules (no domain.ex)
- **Mission**: Workflow orchestration and DAG processing business logic layer
- **Current Pattern**: Business logic calling ThunderBlock.Resources.{DAGWorkflow, DAGNode, DAGEdge}
- **Architecture**: "ThunderVine = business logic, ThunderBlock = persistence"
- **Modules** (4 files):
  - **events.ex**: Workflow lifecycle management, DAG resource creation
  - **spec_parser.ex**: Workflow DSL parser using NimbleParsec
  - **workflow_compactor.ex**: GenServer for workflow sealing coordination
  - **workflow_compactor_worker.ex**: Oban worker for async compaction
- **Key Services**:
  - Workflow specification parsing (DSL → internal representation)
  - DAG resource management via ThunderBlock
  - Workflow compaction and sealing (mark as immutable)
  - Event-driven workflow lifecycle management
- **Exclusive DAG Usage**: Only ThunderVine uses DAG resources (verified via grep - 17 matches)
- **Current Pattern Issues**:
  1. Business logic calling persistence layer for domain concepts
  2. Can't enforce Ash policies on ThunderBlock's resources from ThunderVine
  3. Conceptual ownership unclear (workflows belong to ThunderVine, not infrastructure)
  4. API exposure limitation (no "resources that can be called")
- **Architectural Decision Pending**: Should ThunderVine become an Ash.Domain?
- **Agent Recommendation**: **Create ThunderVine.Domain** with Workflow/WorkflowNode/WorkflowEdge resources
- **Recommendation Rationale** (5 reasons):
  1. **Exclusive Usage**: Only ThunderVine uses DAG resources (verified)
  2. **Conceptual Ownership**: Workflows are ThunderVine's domain concern, not infrastructure
  3. **API Exposure**: User wants "resources that can be called"
  4. **Policy Enforcement**: Need Ash policies on workflow resources (can't define on another domain's resources)
  5. **Clearer Naming**: Workflow/WorkflowNode/WorkflowEdge vs DAGWorkflow/DAGNode/DAGEdge
- **Implementation Approach**: Create domain.ex, move DAG resources from ThunderBlock, update references

### 1.12 Unified Persistent Model (UPM) — Cross-Domain Intelligence Fabric

- **Resources**: **4 Ash Resources** (part of Thunderbolt domain)
- **Mission**: Maintain a single, continuously trained model that ingests ThunderFlow feature windows and synchronizes embeddings/actions to every ThunderBlock agent.
- **Primary resources**: `upm_trainer`, `upm_snapshot`, `upm_adapter`, `upm_drift_window` (Ash resources under `Thunderline.Thunderbolt.Resources.UPM.*`).
- **Event responsibilities**: Emit `ai.upm.snapshot.created`, `ai.upm.shadow_delta`, and drift telemetry via EventBus; consume `feature_window` events from ThunderFlow.
- **Operational hooks**: Trainer runs inside ThunderBolt orchestrators, snapshots persisted through ThunderBlock vault policies, rollout gated by ThunderCrown policies and feature flag `:unified_model`.
- **Key KPIs**: Snapshot freshness, drift score, agent adoption percentage, rollback invocation count.

## 2. Resource Reference Tables

### 2.1 Active Core Domains (November 17, 2025)

| Domain | Resources | Extensions | Categories | Status |
|--------|-----------|------------|------------|--------|
| **Thundergate** | 19 | AshAdmin | Auth (2), External (3), Federation (3), Policy (2), Monitoring (9) | ✅ Active |
| **Thunderlink** | 17 | AshAdmin, AshOban, AshGraphql, AshTypescript.Rpc | Support (1), Community (5), Voice (3), Registry (6), Infrastructure (2) | ✅ Active (⚠️ Duplicates) |
| **Thundercom** | 8 | AshAdmin | Community (5), Voice (3) | ⚠️ Consolidation Incomplete |
| **Thunderflow** | 9 | AshAdmin | Streams (2), Actions (1), Events (1), Probes (3), Features (1), Lineage (1) | ✅ Active |
| **Thunderbolt** | 50+ | AshAdmin, AshOban, AshJsonApi, AshGraphql | Core (5), Ising (3), Lane (10), Task (3), Automata (5), Cerebros (7), RAG (1), ML (6), MLflow (2), UPM (4), MoE (3) | ✅ Active |
| **Thundercrown** | 4 | AshAdmin, AshAi | UI (1), AgentRunner (1), Conversation (2) | ✅ Active |
| **Thunderblock** | 33 | AshAdmin | Vault (13), Infrastructure (8), Orchestration (4), DAG (4), Timing (4) | ✅ Active |
| **Thundergrid** | 5 | AshGraphql, AshJsonApi | Spatial (1), Zones (2), Events (1), State (1) | ✅ Active |
| **RAG** | 1 | - | Documents (1) | ✅ Active |

**Total Active Resources**: ~150 across 8 domains

### 2.2 Support & Utility Domains

| Domain | Type | Resources | Purpose | Status |
|--------|------|-----------|---------|--------|
| **Thundervine** | Utility | 0 (modules only) | Workflow parsing, compaction | ✅ Active |
| **Dev** | Utility | 0 (modules only) | Development tools, diagnostics | ✅ Active |
| **Maintenance** | Utility | 0 (modules only) | Cleanup utilities | ✅ Active |
| **ServiceRegistry** | Placeholder | 0 | Service discovery (planned) | 🟡 Placeholder |
| **Thunderforge** | Placeholder | 0 | Infrastructure provisioning (planned) | 🟡 Placeholder |

### 2.3 Deprecated/Consolidated Domains

| Domain | Status | Consolidated Into | Resources Migrated | Migration Date |
|--------|--------|-------------------|--------------------|-----------------|
| **ThunderChief** | ⚠️ Deprecated | Thundercrown | 4 (executive control) | Nov 2025 |
| **ThunderCom** | ⚠️ In Progress | Thunderlink | 0 of 8 (INCOMPLETE - both domains active) | In Progress |
| **ThunderWatch** | ⚠️ Deprecated | Thundergate.Monitoring | 9 (observability) | Nov 2025 |
| **ThunderJam** | ⚠️ In Progress | Thundergate.RateLimiting | N/A (rate limiting) | In Progress |
| **ThunderClock** | ⚠️ In Progress | Thunderblock.Timing | 4 (scheduling) | In Progress |
| **ThunderVault** | ✅ Complete | Thunderblock | 13 (vault subsystem) | Complete |
| **ThunderCore** | ✅ Complete | Thunderbolt | 5 (core processing) | Complete |
| **ThunderLane** | ✅ Complete | Thunderbolt | 10 (lane processing) | Complete |
| **ThunderMag** | ✅ Complete | Thunderbolt | 3 (task execution) | Complete |
| **ThunderCell** | ✅ Complete | Thunderbolt | 5 (automata) | Complete |
| **Thunder_Ising** | ✅ Complete | Thunderbolt | 3 (optimization) | Complete |
| **ThunderStone** | ✅ Complete | Thundergate | 2 (policy) | Complete |
| **ThunderEye** | ✅ Complete | Thundergate.Monitoring | 7 (monitoring subset) | Complete |
| **Accounts** | ✅ Complete | Thundergate | 2 (authentication) | Complete |

**Consolidation Summary**: 5 major consolidations completed, 3 in progress (ThunderCom→ThunderLink INCOMPLETE), 14 legacy domains unified into 8 modern domains.

**Feature flag crosswalk** (see [`FEATURE_FLAGS.md`](Thunderline/documentation/FEATURE_FLAGS.md)):

| Flag | Controls | Default | Lifecycle |
|------|----------|---------|-----------|
| `:voice_input` | Membrane-ready voice pipeline enablement | false | Planned |
| `:ml_nas` | NAS export + expert auto-tuning | false | Experimental |
| `:signal_stack` | Signal/phase processing stack | false | Experimental |
| `:tocp` | Thunderline Open Circuit Protocol runtime | false | Scaffold |
| `:tocp_presence_insecure` | Controlled insecure mode for TOCP perf tests | false | Debug |
| `:ai_chat_panel` | Dashboard AI assistant experience | false | Experimental |
| `:unified_model` | Unified Persistent Model rollout (shadow/canary/global) | false | Preview |

## 3. Event and Telemetry Contracts

- **Envelope**: All events instantiate `%Thunderline.Event{}` via constructor enforcing UUIDv7 `id`, `correlation_id`, allowed category mapping (Section 5 & 12 in [`EVENT_TAXONOMY.md`](Thunderline/documentation/EVENT_TAXONOMY.md)).
- **Taxonomy governance**: New events require DIP, payload schema, and tests; `mix thunderline.events.lint` target pending (Section 14).
- **Reliability tiers**: `persistent` events recorded durably (e.g., `system.email.sent`), `transient` events best-effort (e.g., `voice.signal.*`).
- **Correlation rules**: Root commands set `correlation_id` to their `id`; derived intents and tool invocations maintain causation chains per Section 13 matrix.
- **Telemetry catalogue**: Key metrics include `[:flow, :market, :lag_ms]`, `[:router, :assignment, :experts_per_token]`, `[:thunderline, :error, :classified]`, and voice KPIs (active rooms, speaking bursts).
- **Alerting**: Establish thresholds for pipeline lag, DLQ depth, router load imbalance, and policy evaluation latency; align dashboards with `Thundereye` instrumentation.

## 4. Error and Recovery Surfaces

- **Classifier contract**: `%Thunderline.Thunderflow.ErrorClass{origin, class, severity, visibility, code, reason}` as defined in [`ERROR_CLASSES.md`](Thunderline/documentation/ERROR_CLASSES.md).
- **Retry matrix**: Transient (5 attempts, exponential backoff), timeout (3 attempts), dependency (7 attempts) before DLQ transfer.
- **DLQ event**: `system.dlq.message` payload captures queue, attempts, reason; escalate security classified events to audit channel.
- **Telemetry**: Emit `[:thunderline, :error, :classified]` and `[:thunderline, :dlq, :enqueue]` with class/origin metadata; correlate with event categories.
- **Governance workflow**: New error patterns require issue tagged `error-taxonomy`, classifier update, tests, observability steward approval.
- **AI tool hooks**: Reserve codes `AI-TOOL-*`, `AI-STREAM-*` to align with `ai_emit/2` path, ensuring `correlation_id` propagation.

## 5. Cross-Domain Bridges and DIP Governance

- **Sanctioned bridges**: ThunderBridge (external ingest), Dashboard ThunderBridge (observability), ErlangBridge (Cerebros handoff).
- **Pending proposals**: Honey Badger tasks A10 (bridge collision audit) and C1 (rename execution) require registry updates.
- **DIP requirements**: Purpose, latency tolerance, event vs direct call rationale, telemetry spec, security hooks (Honey Badger Section DIP Outline).
- **Compliance**: PRs introducing cross-domain calls must reference DIP ID and update this guide; lint rule forbids unauthorized aliases (Honey Badger Quality Gates).

## 6. Operational Playbooks

- **Voice HC-13 rollout**: Follow Phase A tasks (resource relocation, feature flag gating, Membrane stub, event enforcement). Monitor KPIs listed in Honey Badger telemetry table.
- **Market → MoE → NAS pipeline**: Execute Phase 0–5 sequence in [`architecture/market_moe_pipeline.md`](Thunderline/documentation/architecture/market_moe_pipeline.md) for ingestion scaffolding, routing, drift detection, and NAS integration.
- **TOCP operations**: Reference security & telemetry expectations in [`TOCP_SECURITY.md`](Thunderline/documentation/TOCP_SECURITY.md) and `tocp` documentation set.
- **Flower Power federated training**: Use runbooks in [`docs/flower-power/runbooks/*`](Thunderline/documentation/docs/flower-power/runbooks) and architecture overview in [`docs/flower-power/architecture.md`](Thunderline/documentation/docs/flower-power/architecture.md).
- **Deprecation monitoring**: Attach to `[:thunderline, :deprecated_module, :used]` telemetry to enforce migration matrix (Phase 3–4 tasks in [`MIGRATIONS.md`](Thunderline/documentation/MIGRATIONS.md)).

## 7. Roadmap and Open Actions (Updated November 17, 2025)

| Item | Domain | Priority | Owner | Status |
|------|--------|----------|-------|--------|
| Complete Thunderforge implementation or remove | Thunderforge | Low | Arch guild | TODO |
| Split Thunderbolt domain (50+ resources) | Thunderbolt | Medium | Bolt steward | Recommended |
| Complete ThunderJam → Thundergate.RateLimiting migration | Thundergate | High | Gate steward | In Progress |
| Complete ThunderClock → Thunderblock.Timing migration | Thunderblock | High | Block steward | In Progress |
| Implement planned Thundercrown resources (AIPolicy, McpBus, WorkflowOrchestrator) | Thundercrown | Medium | Crown steward | Planned |
| Event taxonomy lint task | Thunderflow | Medium | Observability guild | TODO |
| Feature helper implementation | Global | Low | Core platform | TODO |
| DLQ dashboard surfacing | Thunderflow | Medium | Flow steward | TODO |
| AI governance hooks | Thundercrown | Medium | Crown steward | Planned |
| NAS export loop Phase 5 | Thunderbolt | Low | Bolt steward | Planned |
| Unified Persistent Model trainer + adapters | Thunderbolt/Thunderblock/Thundercrown | Medium | Bolt steward | Not Started |
| Expand code interfaces across domains | All Domains | Low | Domain stewards | Ongoing |
| Add comprehensive integration tests | All Domains | Medium | QA guild | Ongoing |
| Documentation expansion (Broadway, ML, spatial algorithms) | Thunderflow, Thunderbolt, Thundergrid | Medium | Doc guild | TODO |

**Architecture Health Metrics** (from November 17, 2025 review):
- Overall Grade: A (9/10)
- Active Domains: 8 core + support
- Total Resources: ~150 Ash resources
- Consolidations: 6 major consolidations completed (14 legacy domains → 8 modern domains)
- Zero Repo violations detected
- Consistent extension usage
- Strong code interface patterns

**Risks and Mitigations**:
- **Thunderbolt size** (50+ resources) - Mitigation: Plan domain split into Core/Lane/Task vs ML/RAG/Cerebros
- **Placeholder domains** (Thunderforge, ServiceRegistry) - Mitigation: Implement or remove to reduce confusion
- **Migration completion** (ThunderJam, ThunderClock) - Mitigation: Complete documented migrations, remove legacy code
- **Documentation gaps** - Mitigation: Add Broadway pipeline guide, ML workflow docs, spatial grid examples

## 8. Appendices

- **Glossary**: Maintain shared definitions for domains, resources, and telemetry tags; align with runbook nomenclature.
- **Naming conventions**: Enforce singular nouns in event names, Ash resource naming consistent with domain (see domain top-down Section 4 resource coverage note).
- **Change log template**:

```markdown
## YYYY-MM-DD – Summary
- Domains touched:
- Source references:
- Flags toggled:
- Event/Telemetry changes:
- Follow-up actions:
```

- **Legacy references**: Retain access to prior deep dives (e.g., `architecture/system_architecture_webrtc.md`, `docs/flower-power/README.md`, `TOCP_TELEMETRY.md`) for historical context; this guide supersedes their scattered status sections.

---

## 9. November 17, 2025 Architecture Review Summary

### Review Highlights

**Comprehensive Domain Review Completed**: Full audit of all 19+ domains with detailed resource counts, consolidation histories, and architectural validation. See [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md) for complete findings.

**Overall Architecture Grade**: **A (9/10)** - Excellent foundation with room for documentation enhancement

**Key Achievements**:
- ✅ 8 active production domains with ~150 Ash resources
- ✅ 6 major consolidations completed (14 legacy domains unified)
- ✅ Zero Repo violations detected (proper Ash boundary enforcement)
- ✅ Consistent Ash.Domain usage across all domains
- ✅ Strong code interface patterns
- ✅ Clear extension usage (AshAdmin, AshOban, AshGraphql, AshJsonApi, AshAi)
- ✅ Proper subsystem organization within domains

**Consolidation Success Stories**:
1. **ThunderVault → Thunderblock** - Unified storage and persistence (13 vault resources)
2. **5 Domains → Thunderbolt** - Unified compute and ML (ThunderCore, ThunderLane, ThunderMag, ThunderCell, Thunder_Ising)
3. **4 Domains → Thundergate** - Unified security and monitoring (ThunderStone, ThunderEye, Accounts, ThunderWatch)
4. **2 Domains → Thunderlink** - Unified communication (ThunderCom, ThunderWave)
5. **ThunderChief → Thundercrown** - Unified governance and AI orchestration
6. **ThunderClock → Thunderblock.Timing** - Scheduling as runtime concern (in progress)

**Areas for Improvement**:
- 📚 Documentation expansion (Broadway pipelines, ML workflows, spatial algorithms)
- 🚧 Placeholder cleanup (Thunderforge, ServiceRegistry)
- 🔄 Migration completion (ThunderJam, ThunderClock)
- ⚖️ Domain size balancing (Thunderbolt with 50+ resources should consider splitting)

**Documentation References**:
- **Architecture Review**: [`DOMAIN_ARCHITECTURE_REVIEW.md`](DOMAIN_ARCHITECTURE_REVIEW.md) - Comprehensive findings and recommendations
- **Domain Catalog**: [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md) - Updated with resource counts and consolidation history
- **This Guide**: Living documentation for operational domain reference

### Quick Reference Card

**8 Active Core Domains** (~150 resources):
```
Thundergate (19)  → Security, Auth, External, Federation, Policy, Monitoring
Thunderlink (14)  → Communication, Community, Voice, Node Registry
Thunderflow (9)   → Event Bus, Broadway Pipelines, Telemetry
Thunderbolt (50+) → Compute, ML, Task Orchestration, Automata [Consider Splitting]
Thundercrown (4)  → Governance, AI Orchestration, MCP Integration
Thunderblock (33) → Persistence, Vault, Provisioning, DAG, Timing
Thundergrid (5)   → Spatial, Zones, ECS
RAG (1)           → Retrieval-Augmented Generation
```

**Top Extensions Used**:
- `AshAdmin` - 7 domains (admin interface)
- `AshOban` - 2 domains (background jobs: Thunderlink, Thunderbolt)
- `AshGraphql` - 2 domains (GraphQL API: Thunderlink, Thunderbolt, Thundergrid)
- `AshJsonApi` - 2 domains (REST API: Thunderbolt, Thundergrid)
- `AshAi` - 1 domain (MCP tools: Thundercrown)
- `AshTypescript.Rpc` - 1 domain (TypeScript RPC: Thunderlink)

**Bug #18 Solution**: AtomMap custom type in Thunderblock (`lib/thunderline/thunderblock/types/atom_map.ex`) preserves Elixir atoms through PostgreSQL JSONB. Used by Thunderlink.LinkSession.meta.

---

_This guide is living documentation. Submit PRs with updated resource tables, bridge inventories, and roadmap actions as domains evolve. Last comprehensive review: November 17, 2025 - Overall Grade: A (9/10)._