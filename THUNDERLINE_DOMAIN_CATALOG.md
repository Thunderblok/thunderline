# Thunderline Domain Catalog  
**Audit Date:** November 18, 2025  
**Auditor:** Domain Architecture Review Team  
**Status:** ✅ COMPLETE – Full domain review with resource counts and consolidation history  
**Review Report:** See `DOMAIN_ARCHITECTURE_REVIEW.md` for comprehensive findings  
**Overall Architecture Grade:** A (9/10)  
**Total Resources:** ~160 Ash resources across all domains  

---

### ⚡ ThunderBlock Domain  
- **Location:** `lib/thunderline/thunderblock/`  
- **Purpose:** Persistence, Storage, Infrastructure, Timing & Scheduling  
- **Status:** ✅ ACTIVE – Core persistence layer with 33 resources  
- **Resource Count:** **33 Ash Resources**
- **Consolidation History:** Merged ThunderVault → ThunderBlock (storage/persistence focus)
- **Extensions:** AshAdmin.Domain
- **Resource Categories:**
  - **Vault Subsystem** (13 resources): Knowledge graph, semantic memory, entities
    - VaultKnowledgeNode, VaultEntity, VaultRelationship, VaultCluster, etc.
  - **Infrastructure** (8 resources): Checkpoints, migrations, health monitoring
    - SystemCheckpoint, DAGSnapshot, MigrationRecord, DataRetention, etc.
  - **Orchestration** (4 resources): Task execution, workflow coordination
    - OrchestratorTaskNode, TaskEdge, WorkflowRegistry, JobQueue
  - **DAG Management** (4 resources): Graph structures, workflow definitions
    - DAGExecution, DAGDependency, DAGNode, WorkflowDefinition
  - **Custom Types**: AtomMap (preserves Elixir atoms through PostgreSQL JSONB)
- **Key Responsibilities:**
  - Vault memory & persistence (knowledge graph backend)
  - Semantic entity storage & relationship management
  - DAG workflow definitions & execution tracking
  - System checkpoint management
  - Data retention policies & cleanup
  - Migration orchestration
  - Health monitoring infrastructure
  - Timer/scheduler management (timing/ subdomain)
  - Delayed execution & cron job orchestration
- **Code Interfaces:**
  - VaultKnowledgeNode delegation (add_relationship!, search_knowledge!, etc.)
  - Checkpoint management (create_checkpoint!, restore!, list_recent!)
  - Retention policy execution
- **Notes:** Well-organized domain with clear subsystem boundaries. AtomMap custom type solves JSONB atom preservation (Bug #18). Vault subsystem is the largest single component with 13 resources for knowledge graph operations.

---

### ⚙️ ThunderBolt Domain  
- **Location:** `lib/thunderline/thunderbolt/`  
- **Purpose:** ML/AI Execution, Processing, HPO, AutoML & Numeric Computation  
- **Status:** ✅ ACTIVE – Largest domain with 50+ resources across multiple ML subsystems  
- **Resource Count:** **50+ Ash Resources** (consider splitting in future)
- **Consolidation History:** Merged ThunderCore + ThunderLane + ThunderMag + ThunderCell + Thunder_Ising → ThunderBolt
- **Extensions:** AshAdmin.Domain, AshOban.Domain, AshJsonApi.Domain, AshGraphql.Domain
- **Resource Categories:**
  - **Core Processing** (5 resources): Task execution, resource allocation, workflow management
  - **Ising Optimization** (3 resources): Quadratic optimization, QUBO solving
  - **Lane Processing** (10 resources): Pipeline orchestration, lane coupling
  - **Task Execution** (3 resources): Async task management
  - **Automata** (5 resources): State machines, cellular automata
  - **Cerebros ML** (7 resources): Neural architecture search, training jobs, model management
  - **RAG** (1 resource): Retrieval-augmented generation
  - **ML Stack** (6 resources): Training datasets, model artifacts, experiments
  - **MLflow** (2 resources): Experiment tracking integration
  - **UPM** (4 resources): Unified project management, drift detection
  - **MoE** (3 resources): Mixture of Experts routing
- **Key Responsibilities:**
  - ML workflow execution & orchestration
  - Hyperparameter Optimization (HPO) execution
  - AutoML driver management
  - MLflow integration & experiment tracking
  - Cerebros NAS bridge (neural architecture search)
  - UPM (Unified Project Management) coordination
  - Numeric computation & solver routines
  - Model training job execution
  - Lane coupling pipeline orchestration
  - Task DAG execution
  - Ising problem solving (quadratic optimization)
- **GraphQL API:**
  - Queries: core_agents (list/get)
  - Mutations: core_agents (create/update/destroy)
- **Code Interfaces:**
  - TrainingDataset (create_training_dataset!, freeze_dataset!, update_corpus_path!)
  - CoreAgent management
  - Cerebros job execution
- **Notes:** Largest domain by resource count. Well-structured with clear subsystem boundaries. Cerebros extraction complete (migrated to `/home/mo/DEV/cerebros`). Bridge layer operational via `CerebrosBridge.*` gated by `features.ml_nas`. Execution domain - does NOT handle governance (see ThunderCrown for policies). **Recommendation:** Consider splitting into smaller focused domains (e.g., ThunderBolt.ML, ThunderBolt.Ising, ThunderBolt.Lane).  

---

### 🔮 ThunderCrown Domain  
- **Location:** `lib/thunderline/thundercrown/`  
- **Purpose:** AI Governance, Policy Decisions & Orchestration Coordination  
- **Status:** ✅ ACTIVE – Minimal implementation with 4 resources, AI integration ready  
- **Resource Count:** **4 Ash Resources**
- **Consolidation History:** Merged ThunderChief → ThunderCrown (orchestration governance focus)
- **Extensions:** AshAdmin.Domain, AshAi
- **Resource Categories:**
  - **Orchestration UI** (1 resource): Dashboard and management interface
  - **Agent Execution** (1 resource): AgentRunner for agent lifecycle
  - **Conversation Tools** (2 resources): AI conversation management and context
- **Key Responsibilities:**
  - AI governance policy definitions & enforcement
  - Agent orchestration coordination (coordinates, doesn't execute)
  - Policy decision logic & rule evaluation
  - Agent runner management & lifecycle
  - Signing service for security attestation
  - Job orchestration coordination (not job execution)
  - Cross-domain governance boundaries
  - AI conversation context management
- **AshAi MCP Tools Exposed:**
  - `run_agent` (AgentRunner, :run)
  - `conversation_context` (ConversationTools, :context_snapshot)
  - `conversation_run_digest` (ConversationTools, :run_digest)
  - `conversation_reply` (ConversationAgent, :respond)
- **Planned Resources (TODOs):**
  - AiPolicy (policy enforcement)
  - McpBus (MCP protocol bus)
  - WorkflowOrchestrator (workflow coordination)
- **Notes:** Governance domain with AI integration. Coordinates orchestration but does NOT execute workflows (see ThunderBolt for execution). AshAi integration enables MCP tool exposure for AI agents. Minimal current implementation suggests room for expansion. Key directive modules verified in event ledger.

---

### 🚦 ThunderFlow Domain  
- **Location:** `lib/thunderline/thunderflow/`  
- **Purpose:** Event Processing, Event Sourcing, Telemetry & Broadway Pipelines  
- **Status:** ✅ ACTIVE – Event bus and 3 Broadway pipelines operational with 9 resources  
- **Resource Count:** **9 Ash Resources**
- **Extensions:** AshAdmin.Domain
- **Resource Categories:**
  - **Event Streams** (2 resources): ConsciousnessFlow, EventStream
  - **System Actions** (1 resource): SystemAction
  - **Events** (1 resource): Events.Event
  - **Probe System** (3 resources): ProbeRun, ProbeResult, ProbeMetric
  - **Features** (1 resource): Features.FeatureWindow
  - **Lineage** (1 resource): Lineage.Edge
- **Broadway Pipelines:**
  1. **EventPipeline**: General domain event processing with batching
  2. **CrossDomainPipeline**: Inter-domain communication and routing
  3. **RealTimePipeline**: Low-latency processing for live updates
  4. **EventProducer**: Captures PubSub events for pipeline processing
- **Key Responsibilities:**
  - Event Bus implementation & management
  - Event validation & routing
  - Broadway pipeline orchestration (3 pipelines)
  - Telemetry collection & aggregation
  - Observability infrastructure
  - Event sourcing & replay capabilities
  - Automatic batching and backpressure handling
  - Dead letter queues for failed events
  - Structured error recovery and retries
  - Event flow monitoring
  - Metrics pipeline (NOT rate limiting - see ThunderGate)
- **Pipeline Functions:**
  - `start_broadway_pipelines/0` - Initialize all pipelines
  - `process_event/3` - Route events with automatic pipeline selection
- **Notes:** Production-ready event processing infrastructure. Broadway integration provides automatic batching, backpressure, and error handling. Boundary violation noted (Flow→Gate metrics) tracked in AUDIT-02. EventBus, pipelines, telemetry, and observability tools all operational.

---

### 🛡️ ThunderGate Domain  
- **Location:** `lib/thunderline/thundergate/`  
- **Purpose:** Security, Authentication, Authorization, Rate Limiting & Monitoring  
- **Status:** ✅ ACTIVE – Comprehensive security layer with 19 resources  
- **Resource Count:** **19 Ash Resources**
- **Consolidation History:** Merged ThunderStone + ThunderEye + Accounts → ThunderGate (security/monitoring focus)
- **Extensions:** AshAdmin.Domain
- **Resource Categories:**
  - **Authentication** (2 resources): User, Token
  - **External Services** (3 resources): ExternalService, DataAdapter, service management
  - **Federation** (3 resources): FederatedRealm, RealmIdentity, FederatedMessage
  - **Policy** (2 resources): DecisionFramework, PolicyRule
  - **Monitoring** (9 resources): AlertRule, AuditLog, ErrorLog, HealthCheck, PerformanceTrace, SystemAction, SystemMetric, ThunderbitMonitor, ThunderboltMonitor
- **Key Responsibilities:**
  - Authentication (magic link, OAuth, API keys)
  - Authorization & policy enforcement
  - User and token management
  - Rate limiting & throttling (rate_limiting/ subdomain)
  - QoS policies
  - Token bucket algorithms
  - Sliding window limits
  - AI file classification (Magika integration)
  - Content type detection (ML-based + extension fallback)
  - Audit logging & security monitoring
  - Health checks & performance tracing
  - Alert rule management
  - Error tracking & logging
  - External service integration
  - Federation protocol support
  - Security bridges to external systems
  - Ingress hardening
- **Rate Limiter:** Uses Ash's default rate limiting extension
- **Magika:** Production-ready AI classifier integrated with ThunderFlow Broadway pipeline (see `docs/MAGIKA_QUICK_START.md`)
- **Code Interfaces:**
  - User authentication and management
  - Token generation and validation
  - Policy rule evaluation
  - Health check execution
  - Audit log queries
- **Notes:** Comprehensive security and monitoring domain. Successfully consolidated three legacy domains (ThunderStone for policy, ThunderEye for monitoring, Accounts for auth). Magika AI-powered file classification production-ready. Core gateway active with proper boundary enforcement.  

---

### 🌐 ThunderGrid Domain  
- **Location:** `lib/thunderline/thundergrid/`  
- **Purpose:** Spatial Data, Grid Management, GraphQL API & Zone Orchestration  
- **Status:** ✅ ACTIVE – Hexagonal grid system with 5 resources and GraphQL API  
- **Resource Count:** **5 Ash Resources**
- **Extensions:** AshGraphql.Domain, AshJsonApi.Domain
- **Resource Categories:**
  - **Spatial** (1 resource): SpatialCoordinate
  - **Zones** (2 resources): Zone, ZoneBoundary
  - **Events** (1 resource): ZoneEvent
  - **State** (1 resource): ChunkState
- **Key Responsibilities:**
  - Spatial coordinate management
  - Hexagonal grid zone orchestration
  - Zone boundary definitions
  - GraphQL API layer & schema mapping
  - Network topology modeling
  - ECS-like grid for runtime orchestration
  - Spatial query optimization
  - Zone lifecycle management (spawn, activate, deactivate)
  - Entropy adjustment for zones
  - Chunk state tracking
- **GraphQL API:**
  - **Queries:** zones, available_zones, zone_by_coordinates
  - **Mutations:** spawn_zone, adjust_zone_entropy, activate_zone, deactivate_zone
- **JSON API:**
  - RESTful endpoints for zone management
- **Notes:** Clean spatial domain with dual API exposure (GraphQL + JSON:API). Used by Crown orchestration and Vine pipelines. No broken dependencies. Hexagonal grid system enables efficient spatial queries and zone management.

---

- **Location:** `lib/thunderline/thunderlink/`  
- **Purpose:** Network Connections, Communication, Transport Layer & Presence  
- **Status:** ✅ ACTIVE – Communication hub with 17 resources (ThunderCom fully consolidated)  
- **Resource Count:** **17 Ash Resources**
- **Consolidation History:** ThunderCom + ThunderWave → ThunderLink (Completed Nov 18, 2025)
- **Consolidation Status:** 
  - ✅ Community/Channel stack now single implementation (Community, Channel, Message, Role, FederationSocket)
  - ✅ Voice namespace unified on `Voice.*` modules; legacy `VoiceRoom` removed
  - ✅ All LiveViews, seeds, and workers reference ThunderLink resources exclusively
- **Extensions:** AshAdmin.Domain, AshOban.Domain, AshGraphql.Domain, AshTypescript.Rpc
- **Resource Categories:**
  - **Support** (1 resource): Ticket
  - **Community/Channels** (5 resources): Community, Channel, Message, Role, FederationSocket
    - ⚠️ **DUPLICATES**: Also defined in ThunderCom domain (consolidation incomplete)
  - **Voice/WebRTC** (3 resources): Voice.Room, Voice.Participant, Voice.Device
    - Note: ThunderCom uses different namespace (VoiceRoom vs Voice.Room)
  - **Node Registry & Cluster** (6 resources): Node, Heartbeat, LinkSession, NodeCapability, NodeGroup, NodeGroupMembership
  - **Additional Infrastructure** (2 resources): Other network components
- **Key Responsibilities:**
  - TCP/UDP connection management
  - WebSocket connections
  - Node registry and discovery
  - Presence tracking & heartbeat monitoring
  - Transport layer protocols
  - Connection pooling
  - Network-level operations
  - Community and channel management
  - Voice communication infrastructure
  - WebRTC connection orchestration
  - Link session management (uses AtomMap for meta field - Bug #18)
  - Node capability tracking
  - Support ticket system
- **GraphQL API:**
  - **Ticket Queries:** get_ticket, list_tickets
  - **Ticket Mutations:** create_ticket, close_ticket, process_ticket, escalate_ticket
- **TypeScript RPC:**
  - `list_tickets` (Ticket, :read)
  - `create_ticket` (Ticket, :create)
- **Code Interfaces:**
  - Node management (register_node!, mark_node_online!, online_nodes!)
  - Heartbeat tracking (record_heartbeat!, recent_heartbeats!)
  - LinkSession operations (active_link_sessions!, establish_link_session!)
  - NodeCapability queries
- **Bug #18 Integration:**
  - LinkSession.meta uses AtomMap custom type for atom preservation through PostgreSQL JSONB
  - Registry constructs meta with string keys, AtomMap converts to atoms during load
- **Notes:** Comprehensive communication domain combining networking infrastructure with community features. Consolidation of ThunderCom (messaging/community) and ThunderWave (voice/WebRTC) is complete; ThunderLink is the canonical source for all communications resources. TypeScript RPC enables type-safe frontend integration. Handles both CONNECTIONS (transport, presence, WebSocket) and CONTENT (messages, chat, voice).  

---

### 🍇 ThunderVine Domain  
- **Location:** `lib/thunderline/thundervine/`  
- **Purpose:** Event-driven workflow orchestration with durable lineage tracking  
- **Status:** ✅ ACTIVE – Domain created Nov 17, 2025 (HC-29)  
- **Resource Count:** **4 Ash Resources**
- **Resources:**
  - **Workflow**: Primary orchestration resource tracking workflow lifecycle and status (`:building` or `:sealed`)
    - Table: `dag_workflows`
    - Actions: `:start`, `:seal`, `:update_metadata`
    - Relationships: `has_many :nodes`, `has_many :edges`, `has_many :snapshots`
  - **WorkflowNode**: Individual action execution tracking with timing metrics
    - Table: `dag_nodes`
    - Actions: `:record_start`, `:mark_success`, `:mark_error`
    - Calculation: `duration_ms` (time from start to completion)
  - **WorkflowEdge**: Causal relationships between workflow nodes
    - Table: `dag_edges`
    - Edge types: `:causal`, `:follows`, `:child`
    - Identity: `unique_edge` [workflow_id, from_node_id, to_node_id, edge_type]
  - **WorkflowSnapshot**: Immutable workflow serialization for replay debugging
    - Table: `dag_snapshots`
    - Features: pgvector embedding support for semantic search
    - Action: `:capture` (creates immutable snapshot of workflow state)
- **Utility Modules:**
  - `events.ex` - Event definition utilities
  - `spec_parser.ex` - Workflow specification parsing
  - `workflow_compactor.ex` - Workflow optimization logic (GenServer)
  - `workflow_compactor_worker.ex` - Oban worker for async compaction
- **Key Responsibilities:**
  - Event-driven workflow orchestration
  - Durable lineage tracking (audit trail of all operations)
  - Workflow lifecycle management (start → execute → seal)
  - Causal relationship tracking between operations
  - Immutable snapshot capture for replay debugging
  - Semantic search via pgvector embeddings
  - Workflow compaction & optimization
  - Async workflow processing via Oban
- **Migration Notes:** Migrated from `ThunderBlock.Resources.DAG*` (Nov 17, 2025, HC-29). Resources renamed for clarity (`DAGWorkflow` → `Workflow`, `DAGNode` → `WorkflowNode`, `DAGEdge` → `WorkflowEdge`, `DAGSnapshot` → `WorkflowSnapshot`). Database tables unchanged (`dag_workflows`, `dag_nodes`, `dag_edges`, `dag_snapshots`). Zero breaking changes, backward compatible.
- **Benefits of Domain Creation:**
  - ✅ API Exposure: Can now expose Workflow mutations via GraphQL/JSON:API
  - ✅ Policy Enforcement: Can define Ash policies for workflow management at domain level
  - ✅ Clearer Ownership: Workflows conceptually belong to orchestration, not infrastructure
  - ✅ Improved Naming: "Workflow" is clearer than "DAGWorkflow" for domain users
  - ✅ Reduced Coupling: ThunderVine no longer depends on ThunderBlock internals
  - ✅ Exclusive Usage: Verified only ThunderVine uses Workflow resources (migration was straightforward)

---

### 🔨 ThunderForge Domain  
- **Location:** `lib/thunderline/thunderforge/` (REMOVED Nov 17, 2025)
- **Purpose:** Centralized Infrastructure Provisioning & Asset Lifecycle (Placeholder)  
- **Status:** ✅ REMOVED – Deleted as part of HC-30 cleanup (Nov 17, 2025)
- **Previous State:** Empty domain with 3 implementation files (~75 lines total)
- **Files Removed:** 
  - domain.ex (empty resources block)
  - blueprint.ex (25-line YAML parser)
  - factory_run.ex (40-line telemetry executor)
- **Removal Rationale:**
  - Zero production dependencies (verified via comprehensive grep)
  - Explicitly marked as "orphaned design" in ORPHANED_CODE_REPORT.md
  - HC-30 recommendation: "Remove for MVP"
  - HC-24 (future sensor pipeline) can reimplement if needed
  - Code preserved in git history
- **Notes:** ✅ REMOVED (Nov 17, 2025). Entire directory deleted after investigation confirmed no active usage. ThunderForge namespace now available for future use if HC-24 sensor pipeline requires it.

---

### 👑 ThunderChief Domain  
- **Location:** `lib/thunderline/thunderchief/`  
- **Purpose:** Executive Control (DEPRECATED – Consolidated)  
- **Status:** ✅ DEPRECATED – Merged into ThunderCrown (Verified Nov 17, 2025)  
- **Verification:** No domain.ex file exists (confirmed via direct codebase access)
- **Remaining Files:** Only utility modules (orchestrator.ex, jobs/, workers/) - no Ash resources
- **Consolidation History:** ThunderChief → ThunderCrown (November 2025)  
- **Migration Details:**
  - All executive control resources moved to ThunderCrown
  - Orchestration governance now in ThunderCrown
  - Agent runner functionality consolidated
  - Conversation tools integrated into ThunderCrown
- **Final State:**
  - Directory exists with utility modules only
  - No domain.ex file present
  - All functionality now in `lib/thunderline/thundercrown/`
  - Domain successfully removed
- **Notes:** ✅ Deprecation CONFIRMED (Nov 17, 2025). ThunderChief directory contains only utility modules. All executive control and governance capabilities now managed under ThunderCrown umbrella. Migration complete. See ThunderCrown section for current resource details (4 Ash resources).

---

### 👁️ ThunderWatch Domain  
- **Location:** `lib/thunderline/thunderwatch/`  
- **Purpose:** Observability & Monitoring (MIGRATED)  
- **Status:** ⚠️ MIGRATED – Resources moved to ThunderGate  
- **Resource Count:** **0 Ash Resources** (all migrated)
- **Migration History:** ThunderWatch → ThunderGate.Monitoring (November 2025)  
- **Migration Details:**
  - All monitoring resources (9 total) moved to ThunderGate
  - Health check functionality consolidated
  - Metrics tracking integrated into ThunderGate.Monitoring
  - Log correlation moved to ThunderGate
  - Deployment status monitoring transferred
  - Alert management capabilities merged
- **Former Resources (now in ThunderGate.Monitoring):**
  - HealthCheck → ThunderGate.Monitoring.HealthCheck
  - SystemMetric → ThunderGate.Monitoring.SystemMetric
  - LogEntry → ThunderGate.Monitoring.LogEntry
  - DeploymentStatus → ThunderGate.Monitoring.DeploymentStatus
  - AlertConfiguration → ThunderGate.Monitoring.AlertConfiguration
  - Plus 4 additional monitoring resources
- **Notes:** Successfully migrated to ThunderGate as part of security/monitoring consolidation (ThunderStone + ThunderEye + Accounts + ThunderWatch → ThunderGate). ThunderWatch directory retained for backward compatibility only. All active observability features now under ThunderGate.Monitoring namespace. See ThunderGate section for current monitoring capabilities (9 resources).  

---

-### 💬 ThunderCom Domain  
- **Status:** ✅ REMOVED – Directory deleted after full consolidation on Nov 18, 2025  
- **Disposition:** All Community/Channel and Voice resources now live under ThunderLink. Any historical references are preserved in git for audit purposes.

---

### ✅ ThunderVine Domain (Implementation Complete)
- **Location:** `lib/thunderline/thundervine/`
- **Purpose:** Workflow Orchestration, Event-driven DAG Processing & TAK Persistence
- **Status:** ✅ ACTIVE – Workflow (Nov 17, 2025 HC-29) + TAK Persistence (Nov 21, 2025)
- **Resource Count:** **6 Ash Resources** (4 Workflow + 2 TAK Persistence)
- **Extensions:** AshGraphql.Domain
- **Resource Categories:**
  - **Workflow Orchestration** (4 resources): Event-sourced DAG management
    - Workflow, WorkflowNode, WorkflowEdge, WorkflowSnapshot
  - **TAK Persistence** (2 resources): Cellular automaton event recording
    - TAKChunkEvent, TAKChunkState
- **Implementation History:**
  - **Workflow Migration** (Nov 17, 2025):
    - Migrated 4 resources from `ThunderBlock.Resources.DAG*` → `Thundervine.Resources.Workflow*`
    - Database tables unchanged (dag_workflows, dag_nodes, dag_edges, dag_snapshots)
    - Zero breaking changes, fully backward compatible
  - **TAK Persistence** (Nov 21, 2025):
    - Created TAKEventRecorder GenServer for PubSub-driven event capture
    - Implemented TAKChunkEvent/TAKChunkState Ash resources
    - Added Thundervine.Supervisor for recorder lifecycle management
    - Integrated auto-start with TAK.Runner
    - Database tables: tak_chunk_events, tak_chunk_states (JSONB storage)
- **Files:** 15 total (1 domain + 6 resources + 5 workflow utils + 3 TAK components)
  - **Domain:** `domain.ex` - ThunderVine.Domain definition with GraphQL
  - **Workflow Resources:** workflow.ex, workflow_node.ex, workflow_edge.ex, workflow_snapshot.ex
  - **TAK Resources:** tak_chunk_event.ex, tak_chunk_state.ex
  - **TAK Components:** consumers/tak_event_recorder.ex (GenServer), supervisor.ex (DynamicSupervisor)
  - **Workflow Utils:** events.ex, spec_parser.ex, workflow_compactor.ex, workflow_compactor_worker.ex
- **Key Responsibilities:**
  - **Workflow Orchestration:**
    - Event-sourced workflow tracking via correlation_id
    - DAG node/edge management for execution graphs
    - Workflow snapshot/replay capabilities
    - Lineage analysis for distributed observability
  - **TAK Persistence:**
    - Real-time CA evolution event capture via PubSub
    - Event-sourced recording of voxel state transitions
    - Historical CA state reconstruction and replay
    - Performance metrics and rule analysis
    - Scientific reproducibility for CA experiments
- **GraphQL API:**
  - Workflow queries: workflow, workflows, workflow_by_correlation, workflow_nodes, workflow_edges, workflow_snapshots
  - Workflow mutations: start_workflow, seal_workflow, update_workflow_metadata, record_node_start, mark_node_success, mark_node_error, create_workflow_edge, capture_workflow_snapshot
- **Code Interfaces:**
  - **TAK Recording:** TAKEventRecorder.start_link/1, get_stats/1; Supervisor.start_recorder/1, stop_recorder/1, list_recorders/0
  - **Workflow:** Standard Ash actions via domain
- **Integration Points:**
  - TAK.Runner auto-starts event recorder (configurable via `enable_recording?`)
  - Phoenix.PubSub subscription to `"ca:#{run_id}"` for CA deltas
  - Thunderline.Repo PostgreSQL persistence via AshPostgres
- **Data Flow (TAK Persistence):**
  ```
  TAK.Runner → PubSub ("ca:#{run_id}") → TAKEventRecorder → TAKChunkEvent → PostgreSQL
               {:ca_delta, msg}          normalize cells    persist via Ash  (JSONB)
                                         track stats
  ```
- **Database Schema:**
  - **tak_chunk_events:** zone_id, chunk_coords (int[]), tick_id, diffs (jsonb array), rule_hash, meta (jsonb)
    - Unique: (zone_id, chunk_coords, tick_id); Indexes: zone_id, tick_id, rule_hash
  - **tak_chunk_states:** zone_id, chunk_coords (int[]), tick_id, state_snapshot (jsonb)
    - Unique: (zone_id, chunk_coords)
- **Verification Results:**
  - ✅ Compilation: Zero errors
  - ✅ Tests: TAK persistence tests passing (6 tests, 1 skipped pending TAK.RuleParser)
  - ✅ Integration: Auto-start from TAK.Runner verified
  - ✅ Persistence: Events successfully written to PostgreSQL
  - ✅ Stats Tracking: events_received/persisted/failed counters functional
  - ✅ Documentation: Full architecture docs in `documentation/TAK_PERSISTENCE_ARCHITECTURE.md`
- **Benefits Realized:**
  1. **Workflow:** API exposure via GraphQL, policy enforcement, clearer ownership, improved naming
  2. **TAK Persistence:** Event-sourced CA history, scientific reproducibility, time-travel debugging, automatic recording
- **Performance:** Handles 130-5,200 events/tick (1-10% change rate on 64³ grid); JSONB compression
- **Future Enhancements:** Batch persistence, delta encoding, state snapshots, retention policies, LiveView dashboard, Parquet export
- **Decision Status:** ✅ **ACTIVE DEVELOPMENT**
  - Workflow migration: Nov 17, 2025 (HC-29) - See `HC-29_COMPLETION_REPORT.md`
  - TAK persistence: Nov 21, 2025 - See `documentation/TAK_PERSISTENCE_ARCHITECTURE.md`

---

### �🌩️ Additional Supporting Namespaces
| Domain | Location | Purpose | Status | Resources |
|---------|-----------|----------|--------|-----------|
| RAG | `lib/thunderline/rag/` | Retrieval-Augmented Generation models | ✅ ACTIVE | 1 resource (RagChunk) |
| Dev | `lib/thunderline/dev/` | Internal diagnostics and linting | ✅ ACTIVE | Utility modules (no domain) |
| Maintenance | `lib/thunderline/maintenance/` | Cleanup utilities | ✅ ACTIVE | Utility modules (no domain) |
| ServiceRegistry | `lib/thunderline/service_registry/` | Service health & discovery | ✅ ACTIVE | 0 resources (placeholder) |

---

## ❌ Deprecated Domains

### ThunderJam (DEPRECATED — Consolidated into ThunderGate)
- **Former Location:** `lib/thunderline/thunderjam/`
- **Former Purpose:** Rate limiting, throttling, QoS policies, token bucket algorithms
- **Deprecation Date:** November 5, 2025
- **Migration Target:** `ThunderGate.RateLimiting` (subdomain)
- **New Location:** `lib/thunderline/thundergate/rate_limiting/`
- **Rationale:** Rate limiting is a security/ingress concern, not a standalone domain. Consolidating into ThunderGate aligns with architectural principle that rate limiting, throttling, and QoS are fundamentally security boundaries.
- **Action Required:** 
  - Update all references: `Thunderline.Thunderjam.*` → `Thunderline.Thundergate.RateLimiting.*`
  - Use Ash's default rate limiting extension for new implementations
  - See `DOMAIN_REORGANIZATION_PLAN.md` for complete migration checklist
- **Status:** ⚠️ MIGRATION IN PROGRESS — Documentation updated, code migration pending

### ThunderClock (DEPRECATED — Consolidated into ThunderBlock)
- **Former Location:** `lib/thunderline/thunderclock/`
- **Former Purpose:** Timers, schedulers, cron jobs, delayed execution, temporal coordination
- **Deprecation Date:** November 5, 2025
- **Migration Target:** `ThunderBlock.Timing` (subdomain)
- **New Location:** `lib/thunderline/thunderblock/timing/`
- **Rationale:** Timing and scheduling are runtime management concerns, not separate infrastructure. Consolidating into ThunderBlock aligns with architectural principle that timer/scheduler management is intrinsically tied to VM lifecycle and runtime operations.
- **Action Required:**
  - Update all references: `Thunderline.Thunderclock.*` → `Thunderline.Thunderblock.Timing.*`
  - Integrate timer resources with VM runtime lifecycle
  - See `DOMAIN_REORGANIZATION_PLAN.md` for complete migration checklist
- **Status:** ⚠️ MIGRATION IN PROGRESS — Documentation updated, code migration pending

---

## Summary Statistics
| Classification | Count | Domains |
|----------------|--------|----------|
| ✅ Active (Core) | 7 | ThunderBlock (33), ThunderBolt (50+), ThunderCrown (4), ThunderFlow (9), ThunderGate (19), ThunderGrid (5), ThunderLink (17) |
| ✅ Active (Support) | 2 | ThunderVine (6 resources), RAG (1 resource) |
| ✅ Removed | 2 | ThunderForge (HC-30 cleanup - Nov 17, 2025), ThunderCom (HC-27/28 completion - Nov 18, 2025) |
| ⚠️ Deprecated/Consolidated | 2 | ThunderChief (→ThunderCrown), ThunderWatch (→ThunderGate) |
| ⚠️ Migration In Progress | 2 | ThunderJam (→ThunderGate.RateLimiting), ThunderClock (→ThunderBlock.Timing) |

**Total Active Domains:** 8 (7 core + 1 support with resources)  
**Total Ash Resources:** ~162 across all active domains (ThunderVine +2 for TAK persistence)  
**Deprecated Domains:** 4 (2 consolidated complete, 2 migrations in progress)  
**Consolidation Success:** 6 major consolidations completed (ThunderVault→ThunderBlock, 5 domains→ThunderBolt, ThunderChief→ThunderCrown, ThunderCom+ThunderWave→ThunderLink, ThunderStone+ThunderEye+Accounts→ThunderGate, ThunderWatch→ThunderGate)  
**Cleanup Success:** 2 orphaned domains removed (ThunderForge - Nov 17, 2025; ThunderCom - Nov 18, 2025)

**Note:** Domain count reflects post-consolidation architecture. Resource counts verified through comprehensive domain review (November 17, 2025). All active domains properly configured with Ash.Domain. See `DOMAIN_ARCHITECTURE_REVIEW.md` for detailed findings.  

---

## Cerebros Findings Summary  
- Cerebros modules under `thunderbolt/cerebros_*` fully migrated to standalone repo `/home/mo/DEV/cerebros`.  
- Bridge layer (`Thunderline.Thunderbolt.CerebrosBridge.*`) remains operational and gated by `features.ml_nas`.  
- Resources referencing old `Thunderbolt.Cerebros.*` paths are deprecated; all live references routed through Bridge.  
- Migration tracked in docs:  
  - `docs/documentation/phase3_cerebros_bridge_complete.md`  
  - `CEREBROS_REACT_SETUP.md`  
  - `CEREBROS_BRIDGE_PLAN.md`  

---

**✅ Deliverable ready:** `docs: domain catalog audited (Cerebros extraction noted)`
