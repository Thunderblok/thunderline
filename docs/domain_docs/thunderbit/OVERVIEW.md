# ThunderBit Domain Overview

**Vertex Position**: Data Plane Ring — Quantitative Automata & State Machine Surface

**Purpose**: Automata domain managing Quantitative Automata (QuAK), Cellular Automata (CA) patterns, state machines, and the computational primitives that power Thunderline's intelligent behaviors.

## Charter

ThunderBit is the **automata engine** of Thunderline. It defines and executes quantitative automata - formal state machines with weighted transitions that can be evaluated, scored, and composed. Each Thunderbit is a discrete computational unit with defined categories, wiring rules, and I/O specifications based on the Upper Ontology.

## Core Responsibilities

1. **Quantitative Automata** — define and execute QuAK-style automata with weighted transitions and value functions.
2. **Category Protocol** — implement the 8-category Thunderbit taxonomy (Sensory, Cognitive, Mnemonic, Motor, Social, Ethical, Perceptual, Executive).
3. **Wiring & Composition** — enforce valid composition rules between Thunderbit categories.
4. **CA Pattern Engine** — execute cellular automata patterns for clustering and state evolution.
5. **State Machine Execution** — run discrete state machines with formal transition semantics.
6. **ThunderCell Chunks** — manage cell chunks that compose into larger automata structures.

## Relationship to ThunderBolt (ML Domain)

ThunderBit provides the **automata substrate** that ThunderBolt trains and orchestrates:
- **ThunderBit**: Defines automata structure, categories, transitions, scoring
- **ThunderBolt**: Trains models, orchestrates ThunderCells, runs ML inference

ThunderBit ↔ ThunderBolt is like CPU ↔ GPU: ThunderBit defines the logical automata, ThunderBolt accelerates with ML.

## Relationship to ThunderPac (Agent Domain)

ThunderBits can serve as the computational engine powering PAC behaviors:
- **ThunderPac**: High-level autonomous agent personality and lifecycle
- **ThunderBit**: Low-level automata executing the agent's decisions

## System Cycle Position

ThunderBit is a **data plane** domain on the Crown→Bolt vector:
- **Upstream**: ThunderCrown (policy/orchestration)
- **Adjacent**: ThunderBolt (ML training/inference)
- **Downstream**: Execution results flow to ThunderFlow

## 8 Thunderbit Categories (Upper Ontology)

| Category | Role | Ontology Mapping |
|----------|------|-----------------|
| Sensory | Observer | Entity.Physical |
| Cognitive | Transformer | Proposition.* |
| Mnemonic | Storage | Entity.Conceptual |
| Motor | Actuator | Process.Action |
| Social | Router | Relation.* |
| Ethical | Critic | Proposition.Goal |
| Perceptual | Analyzer | Attribute.State |
| Executive | Controller | Process.Action |

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thunderbit.Resources.Automaton` | Automaton definitions |
| `Thunderline.Thunderbit.Resources.Transition` | State transitions |

## Key Modules

- `Thunderline.Thunderbit.Category` - Category definitions and wiring rules
- `Thunderline.Thunderbit.Protocol` - Thunderbit protocol implementation
- `Thunderline.Thunderbit.Thundercell` - Cell chunk management
- `Thunderline.Thunderbit.CA.*` - Cellular automata patterns

## Key Specifications

- [Thunderbit API v1 Contract](../../hc-specs/THUNDERBIT_V1_API_CONTRACT.md)
- [Thunderbit Behavior Contract](../../hc-specs/THUNDERBIT_BEHAVIOR_CONTRACT.md)
- [Category Protocol (HC-D5)](../../hc-specs/HC-D5_THUNDERBIT_CATEGORY_PROTOCOL.md)
- [QuAK Cerebros Spec](../../hc-specs/HC_DELTA_14_18_QUAK_CEREBROS_SPEC.md)

---

*Last Updated: December 2025*
