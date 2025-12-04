# ThunderCore Domain Overview

**Vertex Position**: Control Plane Ring — System Identity & Tick Surface

**Purpose**: Core domain managing system identity, tick lifecycle, and domain activation. The heartbeat of Thunderline.

## Charter

ThunderCore is the foundational domain that provides tick-based scheduling and domain activation. It manages the system's identity, produces tick events that drive the unified perceptron model, and orchestrates domain registration. All other domains depend on ThunderCore for their activation and timing synchronization.

## Core Responsibilities

1. **Tick Generation** — produce periodic tick events that drive PAC lifecycle and domain processing.
2. **Domain Registration** — maintain the active domain registry and coordinate domain activation.
3. **System Identity** — provide stable identity primitives for nodes, sessions, and entities.
4. **Health Monitoring** — track domain health and emit telemetry for system observability.
5. **Spark-to-Containment Lifecycle** — initiate the system cycle that flows through all domains.

## System Cycle Position

ThunderCore is the **origin** of the system cycle:
- **Upstream**: None (cycle origin)
- **Downstream**: ThunderWall (cycle terminus)
- **Emits**: `tick.generated`, `domain.activated`, `domain.deactivated`

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thundercore.Tick` | Tick event record |
| `Thunderline.Thundercore.DomainRegistry` | Active domain tracking |

## Key Modules

- `Thunderline.Thundercore.Ticker` - GenServer producing tick events
- `Thunderline.Thundercore.DomainActivation` - Domain registration logic

---

*Last Updated: December 2025*
