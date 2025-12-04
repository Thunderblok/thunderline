# ThunderPac Domain Overview

**Vertex Position**: Data Plane Ring — Autonomous Agent Lifecycle Surface

**Purpose**: Autonomous Agent domain managing PAC (Personal Autonomous Construct) lifecycle, intents, roles, and state persistence. The "soul" of Thunderline agents.

## Charter

ThunderPac is the **autonomous agent domain** of Thunderline. A PAC (Personal Autonomous Construct) is a user-facing autonomous agent with personality, memory, roles, and intent execution capabilities. ThunderPac manages the entire agent lifecycle from creation through activation, suspension, and archival.

## PAC = Personal Autonomous Construct

| Component | Description |
|-----------|-------------|
| **Personal** | User-facing, personalized agent with memory |
| **Autonomous** | Self-directed behavior based on intents |
| **Construct** | Built from ThunderBit automata + ThunderBolt ML |

## Relationship to ThunderBit & ThunderBolt

ThunderPac is the **high-level agent layer** that uses ThunderBit and ThunderBolt as its computational substrate:

```
ThunderPac (Agent)
    ├── Uses ThunderBit (Automata) for decision logic
    └── Uses ThunderBolt (ML) for inference/learning
```

- **ThunderPac**: Agent personality, memory, lifecycle, intents
- **ThunderBit**: Automata patterns the PAC executes  
- **ThunderBolt**: ML models the PAC uses for inference

## Core Responsibilities

1. **PAC Lifecycle** — manage state transitions (dormant → active → suspended → archived).
2. **Intent Management** — declare, execute, and track PAC intents.
3. **Role Definitions** — define PAC behavioral roles and capabilities.
4. **State Persistence** — maintain cross-session PAC memory and context.
5. **Identity Binding** — connect PACs to ThunderCore identity kernels.
6. **Evolution Tracking** — track PAC evolution and learning over time.

## PAC Lifecycle States

```
dormant → active → suspended → archived
    ↑__________|        |
              reactivate
```

| State | Description |
|-------|-------------|
| `dormant` | Created but not yet activated |
| `active` | Running, processing intents |
| `suspended` | Temporarily paused, state preserved |
| `archived` | Permanently deactivated, read-only |

## System Cycle Position

ThunderPac is on the **Pac → Block → Vine** domain vector:
- **Upstream**: ThunderCrown (governance/policy)
- **Downstream**: ThunderBlock (persistence), ThunderVine (DAG tracking)
- **Emits**: `pac.lifecycle.*`, `pac.intent.*`, `pac.state.*`

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thunderpac.Resources.PAC` | Core PAC state container |
| `Thunderline.Thunderpac.Resources.PACRole` | Role definitions and capabilities |
| `Thunderline.Thunderpac.Resources.PACIntent` | Intent management |
| `Thunderline.Thunderpac.Resources.PACState` | State snapshots for persistence |

## Key Modules

- `Thunderline.Thunderpac.Domain` - Ash domain definition
- `Thunderline.Thunderpac.Evolution` - PAC evolution tracking
- `Thunderline.Thunderpac.Runtime` - PAC runtime execution
- `Thunderline.Thunderpac.Workers.*` - Background PAC workers

## Event Categories

```elixir
# Lifecycle events
"pac.lifecycle.created"
"pac.lifecycle.activated" 
"pac.lifecycle.suspended"
"pac.lifecycle.archived"

# Intent events
"pac.intent.declared"
"pac.intent.executing"
"pac.intent.completed"
"pac.intent.cancelled"

# State events
"pac.state.updated"
"pac.state.snapshot"
```

## Integration Points

### ThunderCore → ThunderPac
PACs receive identity kernels from ThunderCore for stable identity.

### ThunderCrown → ThunderPac
PAC behavior is governed by ThunderCrown policies.

### ThunderPac → ThunderBlock
PAC state is persisted to ThunderBlock vaults.

### ThunderPac → ThunderVine
PAC provenance and lineage is tracked in ThunderVine DAGs.

## Telemetry Events

```elixir
[:thunderline, :thunderpac, :lifecycle, :transition]
[:thunderline, :thunderpac, :intent, :execution]
[:thunderline, :thunderpac, :state, :snapshot]
[:thunderline, :thunderpac, :evolution, :step]
```

---

*Last Updated: December 2025*
