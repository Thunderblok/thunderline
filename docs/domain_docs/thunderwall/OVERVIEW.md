# ThunderWall Domain Overview

**Vertex Position**: Control Plane Ring — Entropy & Garbage Collection Surface

**Purpose**: System containment domain managing entropy, resource cleanup, and graceful degradation.

## Charter

ThunderWall is the terminus of the system cycle, responsible for containing entropy and cleaning up resources. It handles garbage collection of stale data, manages system degradation under load, and ensures the system returns to stable states. ThunderWall closes the Spark-to-Containment loop that begins in ThunderCore.

## Core Responsibilities

1. **Entropy Management** — track and bound system entropy metrics across domains.
2. **Garbage Collection** — schedule and execute cleanup of stale PACs, events, and transient data.
3. **Resource Reclamation** — free resources from terminated sessions, expired tokens, and orphaned processes.
4. **Graceful Degradation** — shed load intelligently when system approaches capacity limits.
5. **Cycle Closure** — complete the system cycle by feeding containment signals back to ThunderCore.

## System Cycle Position

ThunderWall is the **terminus** of the system cycle:
- **Upstream**: ThunderCore (cycle origin)
- **Downstream**: Back to ThunderCore (cycle closure)
- **Emits**: `entropy.contained`, `gc.completed`, `degradation.triggered`

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thunderwall.EntropyMetric` | Entropy tracking records |
| `Thunderline.Thunderwall.GCJob` | Garbage collection job definitions |

## Key Modules

- `Thunderline.Thunderwall.EntropyTracker` - Entropy measurement
- `Thunderline.Thunderwall.Collector` - GC execution engine

## Oban Integration

ThunderWall uses Oban for scheduled cleanup:
- `Thunderline.Thunderwall.Workers.StaleDataWorker` - Cleans old records
- `Thunderline.Thunderwall.Workers.EntropyWorker` - Periodic entropy assessment

---

*Last Updated: December 2025*
