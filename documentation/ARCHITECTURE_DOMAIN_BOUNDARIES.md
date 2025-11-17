# Thunderline Domain Architecture - Canonical Boundaries

**Version**: 1.0  
**Date**: 2024-11-16  
**Status**: ✅ Realigned

---

## 🌿 ThunderVine - Workflow & DAG Orchestration

**Mission**: THE workflow/saga engine. Owns ALL DAG-related orchestration logic.

### Responsibilities

- **Workflow Specifications**: Parse and validate workflow rules/specs
- **DAG Orchestration**: Coordinate DAG execution via resources in ThunderBlock
- **Reactor Sagas**: Manage complex multi-step workflows with compensation
- **Workflow Lifecycle**: Compaction, sealing, garbage collection of inactive workflows
- **Event Coordination**: Emit dag.* events for workflow state transitions

### Key Modules

```
lib/thunderline/thundervine/
├── events.ex                      # DAG event emission & workflow rules
├── spec_parser.ex                 # Workflow specification parsing
├── workflow_compactor.ex          # Lifecycle management GenServer
└── workflow_compactor_worker.ex   # Oban worker for async compaction
```

### Data Layer Integration

ThunderVine **orchestrates** but does NOT own the DAG resources. Persistence lives in **ThunderBlock**:

```elixir
# ThunderVine orchestrates...
Thunderline.Thundervine.Events.persist_workflow(spec)

# ...but resources live in ThunderBlock
### ThunderBlock (Infrastructure & Persistence)

(DAG resources moved to ThunderVine domain as of Nov 17, 2025 - see HC-29)

### ThunderVine (Workflow Orchestration)

Thunderline.Thundervine.Resources.Workflow
Thunderline.Thundervine.Resources.WorkflowNode
Thunderline.Thundervine.Resources.WorkflowEdge
Thunderline.Thundervine.Resources.WorkflowSnapshot
```

This separation follows **domain boundaries**: ThunderVine = business logic, ThunderBlock = persistence.

### Event Taxonomy

- `dag.commit` - Workflow committed
- `dag.workflow.sealed` - Workflow sealed (inactive)
- `dag.node.created` - DAG node created
- `dag.edge.created` - DAG edge created

---

## 📊 ThunderPrism - Observability & Analytics

**Mission**: System metrics, telemetry, alerting, and distributed tracing. NOT DAG execution.

### Responsibilities

- **Metrics Collection**: Gather system-wide performance metrics
- **Telemetry Pipeline**: Process and aggregate telemetry events
- **Alerting Engine**: Threshold-based alerts and notifications
- **Distributed Tracing**: OpenTelemetry integration for request flows
- **Analytics Dashboards**: Query and visualize system health

### Current Implementation

**Scratchpad Resources** (for PAC decision visualization):
```
lib/thunderline/thunderprism/resources/
├── prism_node.ex    # PAC decision nodes (model, iteration, probabilities)
└── prism_edge.ex    # Decision flow edges (next, alt, feedback)
```

**Controller** (for graph visualization):
```
lib/thunderline_web/controllers/thunderprism_controller.ex
# Endpoints: create node, get node, create edge, get edges, build 3d-force graph
```

### Missing Modules (To Be Implemented)

Per original domain architecture:

```
lib/thunderline/thunderprism/
├── metrics.ex        # Metrics aggregation (event throughput, latency, etc.)
├── telemetry.ex      # Telemetry event processing
├── alerts.ex         # Alert threshold management
└── trace.ex          # Distributed trace correlation
```

### MLTap Integration (Planned)

```elixir
# Asynchronous logging from ML layer
Thunderline.Thunderprism.MLTap.log(%{
  model: "gpt-4o-mini",
  iteration: 5,
  decision: :accept,
  probabilities: [0.8, 0.15, 0.05],
  metadata: %{...}
})
```

### Graph Visualization UI

ThunderPrism CAN include graph visualization for:
- Node topology (ThunderLink registry)
- DAG visualization (ThunderVine workflows)
- Decision flow (PAC choices)

This is UI/analytics, NOT execution logic.

---

## 🌊 ThunderFlow - Event Processing Infrastructure

**Mission**: Event bus, Broadway pipelines, message queuing. The event backbone for ALL domains.

### Responsibilities

- **Event Bus**: Central publish/subscribe infrastructure
- **Broadway Pipelines**: Stream processing for events
- **Event Validation**: Schema validation and taxonomy enforcement
- **Message Queuing**: Buffering, batching, delivery guarantees
- **Telemetry**: Event throughput, latency, drop metrics

### Key Modules

```
lib/thunderline/thunderflow/
├── event_bus/
│   ├── event_bus.ex              # Core pub/sub API
│   ├── event_validator.ex        # Schema validation
│   ├── broadway_producer.ex      # ✅ REALIGNED (was in event_bus/)
│   └── event_buffer.ex           # ✅ REALIGNED (was in event_bus/)
├── mnesia_producer.ex            # Mnesia-backed event source
└── heartbeat.ex                  # System tick generator
```

### Compatibility Layer

```
lib/thunderline/event_bus.ex      # Thin wrapper for backwards compatibility
```

This module delegates to `Thunderline.Thunderflow.EventBus` but is kept at root namespace to avoid breaking existing code.

### Infrastructure Usage

Other domains USE ThunderFlow's infrastructure but do NOT own it:

- **ThunderBolt.ML.ModelSelectionConsumer**: Uses Broadway + MnesiaProducer
- **ThunderVine.Events**: Emits events via EventBus
- **ThunderLink.Registry**: Emits cluster.* events

All `EventBus.publish_event()` calls route through ThunderFlow.

---

## 🔗 ThunderLink - Node Registry & Cluster Topology

**Mission**: BEAM cluster + Hotline edge node discovery, heartbeats, link sessions.

### Responsibilities

- **Node Registration**: Register BEAM and edge nodes
- **Heartbeat Tracking**: Liveness and metrics collection
- **Link Sessions**: Track active connections between nodes
- **Capability Routing**: Route requests based on node capabilities
- **Topology Graph**: Build network graph for visualization

### Resources (ThunderBlock)

```
lib/thunderline/thunderblock/resources/
├── thunderlink_node.ex                    # Node registry
├── thunderlink_heartbeat.ex               # Metrics & liveness
├── thunderlink_link_session.ex            # Connection tracking
├── thunderlink_node_capability.ex         # Capability routing
├── thunderlink_node_group.ex              # Logical groupings
└── thunderlink_node_group_membership.ex   # Many-to-many
```

### Registry Module

```
lib/thunderline/thunderlink/
└── registry.ex                   # Core API with ETS cache
```

**Functions**:
- `ensure_node/1` - Register or update node
- `mark_online/2` - Mark online + create link session
- `mark_status/2` - Update status (:online | :degraded | :offline)
- `heartbeat/2` - Record metrics (cpu, memory, latency)
- `list_nodes/0` - Query by status/role/domain
- `graph/0` - Build topology graph for UI

### Event Emissions

- `cluster.node.registered` - Node created/updated
- `cluster.node.online` - Node marked online
- `cluster.node.offline` - Node marked offline
- `cluster.node.status_changed` - Status updated
- `cluster.node.heartbeat` - Metrics recorded
- `cluster.link.established` - Link session created
- `cluster.link.closed` - Link session ended

---

## 🧱 ThunderBlock - Persistence Layer

**Mission**: ALL Ash resources and migrations. Data layer for every domain.

### Responsibilities

- **Resource Definitions**: Ash resources for all domains
- **Database Migrations**: PostgreSQL schema management via AshPostgres
- **Data Integrity**: Constraints, validations, relationships
- **Query Interface**: Ash read actions and filters

### Resource Organization

```
lib/thunderline/thunderblock/resources/
├── dag_workflow.ex                # ThunderVine workflows
├── dag_node.ex                    # ThunderVine workflow nodes
├── dag_edge.ex                    # ThunderVine workflow edges
├── prism_node.ex                  # ThunderPrism decision nodes
├── prism_edge.ex                  # ThunderPrism decision edges
├── thunderlink_node.ex            # ThunderLink node registry
├── thunderlink_heartbeat.ex       # ThunderLink metrics
├── thunderlink_link_session.ex    # ThunderLink connections
├── thunderlink_node_capability.ex # ThunderLink capabilities
├── thunderlink_node_group.ex      # ThunderLink groups
└── thunderlink_node_group_membership.ex  # ThunderLink memberships
```

### Domain Separation Pattern

- **Resources live in ThunderBlock**
- **Business logic lives in domain modules**
- **Domains orchestrate via Ash actions**

Example:
```elixir
# ThunderVine orchestrates
defmodule Thunderline.Thundervine.Events do
  def persist_workflow(spec) do
    Thunderline.Thunderblock.Resources.DAGWorkflow
    |> Ash.Changeset.for_create(:create, spec)
    |> Ash.create!()
  end
end
```

---

## 🧠 ThunderBolt - ML Operations

**Mission**: Probabilistic model selection, ML pipelines, adaptive routing.

### Responsibilities

- **Model Selection**: PAC-based adaptive model routing
- **ML Pipelines**: Broadway consumers for ML events
- **Persona Management**: Dynamic persona creation and tuning
- **Capability Routing**: ML-aware request routing

### Key Modules

```
lib/thunderline/thunderbolt/
├── ml/
│   ├── model_selection_consumer.ex   # Broadway consumer for ml.* events
│   └── controller.ex                 # ML selection logic
└── persona/
    └── adaptor.ex                    # Persona-based routing
```

### Event Flow

1. Emit `ml.model.evaluation_ready` → ThunderFlow
2. ModelSelectionConsumer processes via Broadway
3. Invoke ML controller for adaptive selection
4. Emit `ml.model.selected` → ThunderFlow

Uses ThunderFlow infrastructure but owns ML logic.

---

## 🏗️ ThunderGrid - 3D Automata Simulation (P3 - Planned)

**Mission**: Voxel-based 3D cellular automata, zone management, force-layout embedding.

### Planned Resources

- `ZoneNode` - 3D zone boundaries
- `ChunkNode` - Voxel chunks within zones
- `VoxelNode` - Individual voxel states

### Integration Points

- **ThunderLink**: Cluster topology for distributed zones
- **ThunderVine**: DAG outputs for automata rules
- **ThunderPrism**: Metrics and visualization

Currently conceptual; awaiting foundation stability.

---

## 📐 Architecture Principles

### 1. Domain Ownership

Each domain owns its **business logic**, not necessarily its **data**:

- **ThunderVine** orchestrates workflows → data in **ThunderBlock**
- **ThunderPrism** analyzes metrics → data in **ThunderBlock**
- **ThunderLink** manages topology → data in **ThunderBlock**

### 2. Event-Driven Communication

Domains communicate via **ThunderFlow** events, never direct coupling:

```elixir
# ✅ GOOD: Event-based coupling
Thunderline.Thunderflow.EventBus.publish_event(%{
  name: "cluster.node.registered",
  source: :thunderlink,
  payload: %{node_id: id}
})

# ❌ BAD: Direct coupling
Thunderline.Thunderprism.Metrics.record_node_registration(node)
```

### 3. Separation of Concerns

- **Business Logic**: Domain modules (ThunderVine, ThunderPrism, etc.)
- **Persistence**: ThunderBlock resources
- **Infrastructure**: ThunderFlow event bus, Broadway pipelines

### 4. No Circular Dependencies

Dependency flow:

```
ThunderBlock (persistence layer)
    ↑
    │
ThunderFlow (event infrastructure)
    ↑
    │
Business Domains (ThunderVine, ThunderPrism, ThunderLink, ThunderBolt)
```

Business domains depend on Flow and Block, never vice versa.

---

## 🔧 Migration Status

### ✅ Completed (2024-11-16)

1. **EventBus Components Realigned**:
   - Moved `Thunderline.EventBus.BroadwayProducer` → `Thunderline.Thunderflow.EventBus.BroadwayProducer`
   - Moved `Thunderline.EventBus.EventBuffer` → `Thunderline.Thunderflow.EventBus.EventBuffer`
   - Removed empty `lib/thunderline/event_bus/` directory
   - Updated all module references
   - Verified compilation ✅

2. **ThunderLink Node Registry**:
   - Created 6 resources in ThunderBlock (Node, Heartbeat, LinkSession, Capability, Group, Membership)
   - Generated and applied migration (20251116052600)
   - Implemented Registry module with ETS cache
   - Integrated with ThunderFlow.EventBus

### ⏳ Pending

1. **ThunderPrism Observability Modules**:
   - Implement `Metrics.ex` - Event throughput, latency aggregation
   - Implement `Telemetry.ex` - Telemetry event processing
   - Implement `Alerts.ex` - Threshold management
   - Implement `Trace.ex` - Distributed trace correlation
   - Integrate MLTap logging

2. **ThunderLink Integration**:
   - Wire Registry into ThunderGate (ensure_node on handshake)
   - Wire Registry into ThunderLink (mark_online on connection)
   - Add periodic heartbeat calls
   - Expose HTTP API endpoints
   - Add Phoenix Channel for realtime topology

3. **ThunderGrid Planning**:
   - Define ZoneNode, ChunkNode, VoxelNode schemas
   - Design force-layout embedding rules
   - Plan compression strategies

---

## 📚 References

- [Domain Catalog](../THUNDERLINE_DOMAIN_CATALOG.md) - Original domain architecture
- [Node Registry Progress](./thunderlink_node_registry_progress.md) - Implementation tracking
- [Master Playbook](../THUNDERLINE_MASTER_PLAYBOOK.md) - System overview
- [Handbook](../thunderline_handbook.md) - Technical reference

---

**Conclusion**: Architecture is now clean and domain boundaries are explicit. ThunderVine owns workflow orchestration, ThunderPrism handles observability, ThunderFlow provides the event backbone, ThunderLink manages cluster topology, ThunderBlock persists data, and ThunderBolt routes ML decisions. Each domain has a clear mission and respects the boundaries of others.

**Next**: Finish ThunderLink Registry integration, implement ThunderPrism observability modules, plan ThunderGrid cellular automata foundation.
