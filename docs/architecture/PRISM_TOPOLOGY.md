# Prism Topology Architecture

## Overview

Thunderline's architecture is organized as a **12-domain hexagonal prism** consisting of two 6-node rings (control plane and data plane) connected by vertical deployment edges.

```
        Control Plane Ring (Top)
     Crown ──── Bolt ──── Forge
       │ \      │  \      │  \
       │  \     │   \     │   \
     Jam ──── Grid ──── Sec
       ║        ║        ║
       ║ Vertical Deployment Edges
       ║        ║        ║
     Clock ─── Block ─── Link
       │  /     │   /     │  /
       │ /      │  /      │ /
     Vine ──── Flow ──── Pac
        Data Plane Ring (Bottom)
```

## The 12 Vertices

### Control Plane (Top Ring - Strategy/Compilation/Policy)

1. **Thundercrown** (Vertex 1) - Governance & Policy
   - Policy definitions and enforcement
   - Access control rules
   - Compliance and audit requirements
   - Domain: `Thunderline.Thundercrown`

2. **Thunderbolt** (Vertex 2) - Orchestrator & HPO
   - Workflow orchestration via Reactor
   - HPO/TPE for hyperparameter optimization
   - Experiment scheduling and management
   - Domain: `Thunderline.Thunderbolt`

3. **Thunderforge** (Vertex 3) - Compiler & Toolchain
   - ThunderDSL → IR → Target compilation
   - Pegasus primitives (Partition/Map/SumReduce)
   - Fuzzy index tree generation
   - Multi-backend codegen (Nx/eBPF/P4)
   - Domain: `Thunderline.Thunderforge` (NEW)

4. **Thundergrid** (Vertex 4) - Zone Topology & Placement
   - Zone and region management
   - Resource placement decisions
   - Capacity planning
   - Domain: `Thunderline.Thundergrid`

5. **Thundersec** (Vertex 5) - AuthN/Z & Security
   - Authentication and authorization
   - Key management and rotation
   - Security attestation
   - Domain: `Thunderline.Thundersec` (SPLIT FROM GATE)
   - **Note**: Rate limiting functionality consolidated into `Thunderline.Thundergate.RateLimiting` (see domain reorganization)

### Data Plane (Bottom Ring - Execution/IO/Storage)

7. **Thunderblock** (Vertex 7) - Unikernel Runtime & Storage
   - Persistence layer (currently)
   - ThunderDSL runtime execution (future)
   - Container/unikernel OS primitives
   - Domain: `Thunderline.Thunderblock`

8. **Thunderlink** (Vertex 8) - I/O & Transports
   - Network I/O and federation
   - eBPF/XDP hooks (future)
   - P4 pipeline integration (future)
   - Domain: `Thunderline.Thunderlink`

9. **Thunderflow** (Vertex 9) - Events & Telemetry Bus
   - Event routing and delivery
   - Telemetry collection and aggregation
   - Real-time metrics streaming
   - Domain: `Thunderline.Thunderflow`

10. **Thunderpac** (Vertex 10) - PAC Execution Sandbox
    - Partition/Map/SumReduce runtime
    - Isolated execution environments
    - Security boundaries for untrusted code
    - Domain: `Thunderline.Thunderpac` (NEW)
    - **Note**: Timer/scheduler functionality consolidated into `Thunderline.Thunderblock.Timing` (see domain reorganization)

11. **Thundervine** (Vertex 11) - 3D DAG & Provenance
    - State history tracking
    - Causality graph maintenance
    - Provenance queries
    - Domain: `Thunderline.Thundervine` (NEW)

## Edge Types

### Vertical Edges (Control → Data Deployments)

Vertical edges connect control plane vertices to their corresponding data plane vertices, representing deployment and configuration flow:

- **Crown → Clock**: Policy enforcement on timers
- **Bolt → Block**: Orchestrated deployments to runtime
- **Forge → Link**: Compiled programs to I/O layer
- **Grid → Flow**: Zone-aware event routing
- **Sec → Pac**: Security constraints on execution
- **Jam → Vine**: Rate limits on provenance writes

**Protocol**: Ash actions initiated from control plane create/update resources in data plane domains.

### Horizontal Edges (Ring Interconnections)

#### Top Ring (Control Plane Feedback Loops)

- **Crown → Bolt**: Policies define orchestration constraints
- **Bolt → Forge**: HPO triggers recompilation with new configs
- **Forge → Grid**: Compilation artifacts inform placement
- **Grid → Sec**: Topology determines security zones
- **Sec → Jam**: Auth requirements influence rate limits
- **Jam → Crown**: QoS violations trigger policy updates

**Protocol**: Synchronous Ash action calls and asynchronous event notifications via Thunderflow.

#### Bottom Ring (Data Plane Pipelines)

- **Clock → Block**: Periodic ticks trigger storage operations
- **Block → Link**: Persisted data flows to I/O
- **Link → Flow**: Network packets generate events
- **Flow → Pac**: Events trigger execution
- **Pac → Vine**: Execution results recorded in DAG
- **Vine → Clock**: Provenance queries inform scheduling

**Protocol**: Low-latency message passing, Broadway pipelines, direct function calls where performance-critical.

### Diagonal Edges (Optional Fast Lanes)

Cross-cutting paths for performance optimization:

- **Sec → Link**: Direct security enforcement at I/O boundary
- **Grid → Block**: Placement decisions bypass Bolt for hot path
- **Forge → Pac**: Compiled code directly deployed to sandbox
- **Crown → Vine**: Policy-driven provenance queries

**Protocol**: Carefully controlled bypass mechanisms with explicit authorization.

## Design Principles

### 1. Domain Isolation
Each vertex is an independent Ash domain with:
- Own resources and actions
- Explicit inter-domain contracts
- No direct database access across domains
- Event-based integration where appropriate

### 2. Ring Coherence
- Top ring = deterministic, policy-driven, slower (milliseconds)
- Bottom ring = probabilistic, data-driven, faster (microseconds)
- Vertical edges = deployment checkpoints
- Horizontal edges = feedback loops

### 3. Fault Containment
- Vertex failure doesn't cascade to ring
- Vertical edge failure blocks deployment but not execution
- Horizontal edge failure degrades features but doesn't halt

### 4. Observable Everywhere
- All edges emit telemetry to Thunderflow
- All deployments tracked in Thundervine
- All decisions auditable in Thundercrown

## Migration Path

### Current State (6 Domains)
```
Crown, Bolt, Grid, Gate ───────── Control
                ║
              Vertical
                ║
Block, Link, Flow ───────────────── Data
```

### Target State (12 Domains)
```
Crown, Bolt, Forge, Grid, Sec, Gate─── Control Ring
              ║║║║║║
         Vertical Edges
              ║║║║║║
Chief, Block, Link, Flow, Pac, Vine ── Data Ring
```

### Evolution Strategy
1. **Phase 0**: Document current 6 domains
2. **Phase 1**: Create new domain modules (empty shells)
3. **Phase 2**: Implement Forge domain (ThunderDSL compiler)
4. **Phase 3**: Split Gate → Sec (formalize security)
5. **Phase 4**: Implement Jam (consolidate rate limiting)
6. **Phase 5**: Implement Pac (execution sandbox)
7. **Phase 6**: Implement Clock (consolidate timers)
8. **Phase 7**: Implement Vine (formalize provenance)

## Implementation Checklist

- [ ] Document all 12 domain charters
- [ ] Design Ash resource schemas for each domain
- [ ] Define inter-domain protocols (synchronous/async)
- [ ] Create domain relationship diagram
- [ ] Implement domain isolation tests
- [ ] Performance benchmark ring latencies
- [ ] Security review of edge protocols

## References

- [Vertical Edges Specification](VERTICAL_EDGES.md)
- [Horizontal Rings Protocol](HORIZONTAL_RINGS.md)
- [Domain Migration Plan](DOMAIN_MIGRATION_PLAN.md)
- [ThunderDSL Specification](../THUNDERDSL_SPECIFICATION.md)
