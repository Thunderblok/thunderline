# ThunderBit Domain Overview

**Vertex Position**: Data Plane Ring — Autonomous Agent Unit Surface

**Purpose**: Domain managing Thunderbit autonomous agents - the fundamental units of intelligence in the Thunderline system.

## Charter

ThunderBit manages the lifecycle and behavior of Thunderbits - autonomous AI agents that operate within the Unified Perceptron model. Each Thunderbit is a specialized agent with defined capabilities, policies, and behavioral contracts. The domain handles Thunderbit creation, configuration, and operational state.

## Core Responsibilities

1. **Thunderbit Lifecycle** — create, configure, activate, and deactivate Thunderbit agents.
2. **Behavior Contracts** — enforce behavioral contracts and capability boundaries.
3. **Category Protocol** — implement the Thunderbit category protocol (HC-D5 spec).
4. **State Management** — track Thunderbit operational state and context.
5. **API Surface** — expose Thunderbit API v1 for external interaction.

## Relationship to PAC

Thunderbits are related to but distinct from PACs (Personality-Agent-Companion):
- **PAC**: User-facing agent personality with memory and traits
- **Thunderbit**: Internal autonomous unit with specific capabilities
- Thunderbits can serve as the "engine" powering PAC behaviors

## System Cycle Position

ThunderBit is a **data plane** domain:
- **Upstream**: ThunderCrown (policy/orchestration)
- **Downstream**: ThunderBolt (ML/automata execution)
- **Domain Vector**: Crown → Bolt (policy → execute)

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thunderbit.Agent` | Thunderbit agent definitions |
| `Thunderline.Thunderbit.Capability` | Agent capability registry |
| `Thunderline.Thunderbit.Contract` | Behavioral contracts |

## Key Specifications

- [Thunderbit API v1 Contract](../../hc-specs/THUNDERBIT_V1_API_CONTRACT.md)
- [Thunderbit Behavior Contract](../../hc-specs/THUNDERBIT_BEHAVIOR_CONTRACT.md)
- [Category Protocol (HC-D5)](../../hc-specs/HC-D5_THUNDERBIT_CATEGORY_PROTOCOL.md)

---

*Last Updated: December 2025*
