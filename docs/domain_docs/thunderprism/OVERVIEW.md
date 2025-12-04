# ThunderPrism Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thunderprism/domain.ex`  
**Purpose**: DAG scratchpad for ML decision trails

## Purpose

ThunderPrism provides **persistent memory rails** for ML decision recording:
- Record ML decision nodes (pac_id, iteration, model selection)
- Track connections between decisions
- Enable visualization and AI context querying

## Domain Extensions

```elixir
use Ash.Domain
```

No additional extensions — basic Ash domain.

## Registered Resources (2)

| Resource | Module |
|----------|--------|
| PrismNode | `Thunderline.Thunderprism.PrismNode` |
| PrismEdge | `Thunderline.Thunderprism.PrismEdge` |

## Code Interfaces

### PrismNode
- `create_prism_node/7` — Create with pac_id, iteration, chosen_model, model_probabilities, model_distances, meta, timestamp
- `get_prism_node/1` — Get by ID
- `list_prism_nodes/0` — List all

### PrismEdge
- `create_prism_edge/4` — Create with from_id, to_id, relation_type, meta
- `get_prism_edge/1` — Get by ID
- `list_prism_edges/0` — List all

## Phase

Phase 4.0 — November 15, 2025
