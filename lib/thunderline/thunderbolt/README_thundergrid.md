# Thundergrid: Two-Layer Thunderbit Architecture

> **TL;DR**: There are **two** Thunderbit concepts: semantic bits (cognitive layer) and CA voxels (physics layer). This is intentional.

## Quick Reference

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SEMANTIC LAYER                               │
│  Thunderline.Thunderbit = cognitive/data/variable bits (HC-Δ-5)    │
│  - Ash Resource with domain actions                                │
│  - Categories: :cognitive, :dataset, :variable                     │
│  - Links form DAG for reasoning chains                             │
└─────────────────────────────────────────────────────────────────────┘
                              ↓ sits on top of
┌─────────────────────────────────────────────────────────────────────┐
│                        PHYSICS LAYER                                │
│  Thunderbolt.Thunderbit = CA voxels (inner NCA/DiffLogic core)     │
│  - Struct with activation/error_potential floats                   │
│  - Lives inside CACell GenServer processes                         │
│  - Forms 3D lattice managed by Cluster                             │
└─────────────────────────────────────────────────────────────────────┘
```

## File Inventory

### Semantic Layer (`Thunderline.Thunderbit`)
| File | Purpose |
|------|---------|
| `lib/thunderline/thunderbit.ex` | Ash Resource definition |
| `lib/thunderline/thunderbit/thunderlink.ex` | Link relationships |

### Physics Layer (`Thunderbolt.*`)
| File | Purpose |
|------|---------|
| `thunderbolt/thunderbit.ex` | CA voxel struct (activation, error) |
| `thunderbolt/thundercell/ca_cell.ex` | GenServer per CA cell |
| `thunderbolt/thundercell/cluster.ex` | 3D lattice manager |
| `thunderbolt/thundercell/ca_engine.ex` | Evolution coordinator |
| `thunderbolt/ca/snapshot.ex` | Read-only lattice snapshot |

### Optimization Pipeline (`Cerebros.*`)
| File | Purpose |
|------|---------|
| `thunderbolt/cerebros/features.ex` | Extract 24-feature vector |
| `thunderbolt/cerebros/tpe_bridge.ex` | Python TPE integration |

## Architecture Diagram

```
          PAC Run Context                Config Params
                │                              │
                ▼                              ▼
    ┌───────────────────────────────────────────────────────┐
    │           Thunderline.Thunderbit (Semantic)           │
    │   [ThunderbitA] ──ThunderLink──▶ [ThunderbitB]       │
    │        │                              │               │
    │   category: :cognitive          category: :dataset   │
    └───────────────────────────────────────────────────────┘
                              │
                    projects down to
                              ▼
    ┌───────────────────────────────────────────────────────┐
    │           Thunderbolt.ThunderCell.Cluster             │
    │   ┌─────────────────────────────────────────────┐    │
    │   │              3D CA Lattice                  │    │
    │   │  ┌───┬───┬───┐                              │    │
    │   │  │ v │ v │ v │  v = CACell (GenServer)     │    │
    │   │  ├───┼───┼───┤  Each contains Thunderbit   │    │
    │   │  │ v │ v │ v │  struct with activation     │    │
    │   │  └───┴───┴───┘                              │    │
    │   └─────────────────────────────────────────────┘    │
    └───────────────────────────────────────────────────────┘
                              │
                     evolves via CA rules
                              ▼
    ┌───────────────────────────────────────────────────────┐
    │           Thunderbolt.CA.Snapshot                     │
    │   - capture(cluster_id) → read-only lattice state    │
    │   - aggregate_stats() → mean/max activation, etc.    │
    └───────────────────────────────────────────────────────┘
                              │
                    feeds into
                              ▼
    ┌───────────────────────────────────────────────────────┐
    │           Thunderbolt.Cerebros.Features               │
    │   extract(config, context, snapshot, metrics)         │
    │   → 24-feature vector across 4 categories            │
    │   → fitness score for TPE optimization               │
    └───────────────────────────────────────────────────────┘
                              │
                    logs trial to
                              ▼
    ┌───────────────────────────────────────────────────────┐
    │           Thunderbolt.Cerebros.TPEBridge              │
    │   - suggest() → next hyperparameter suggestion       │
    │   - record(params, fitness) → log trial result       │
    │   - optimize() → run full TPE loop                   │
    └───────────────────────────────────────────────────────┘
```

## Usage Patterns

### 1. Capture CA State for Logging

```elixir
alias Thunderline.Thunderbolt.CA.Snapshot

# Capture current lattice state
{:ok, snapshot} = Snapshot.capture(cluster_id)

# Get aggregate statistics
stats = Snapshot.aggregate_stats(snapshot)
# => %{mean_activation: 0.42, max_activation: 0.95, ...}

# Log to telemetry or database
:telemetry.execute([:thunderline, :ca, :snapshot], stats, %{cluster_id: cluster_id})
```

### 2. Extract Features for TPE

```elixir
alias Thunderline.Thunderbolt.CA.Snapshot
alias Thunderline.Thunderbolt.Cerebros.{Features, TPEBridge}

# After PAC run completes
{:ok, snapshot} = Snapshot.capture(cluster_id)

# Extract full feature vector
result = Features.extract(
  config,                      # %{ca_diffusion: 0.1, pac_model_kind: :gpt4, ...}
  context,                     # %{thunderbit_ids: [...], thunderbit_links: [...]}
  snapshot,                    # CA.Snapshot struct
  metrics                      # %{reward: 0.85, latency_ms: 150, ...}
)

# Log trial to TPE optimizer
TPEBridge.record(bridge, result.params, fitness: result.fitness)
```

### 3. Run TPE Optimization Loop

```elixir
alias Thunderline.Thunderbolt.Cerebros.TPEBridge

# Start TPE bridge with Python backend
{:ok, bridge} = TPEBridge.start_link(
  name: {:global, :pac_optimizer},
  study_name: "pac_hyperparams"
)

# Get next suggestion
{:ok, params} = TPEBridge.suggest(bridge)
# => %{ca_diffusion: 0.12, ca_decay: 0.03, ...}

# Run PAC with suggested params, then record result
TPEBridge.record(bridge, params, fitness: computed_fitness)
```

## Feature Vector Schema (HC-Δ-10)

| Category | Features |
|----------|----------|
| **Config** (6) | `ca_diffusion`, `ca_decay`, `ca_neighbor_radius`, `pac_model_kind`, `max_chain_length`, `policy_strictness` |
| **Thunderbit Activity** (6) | `num_bits_total`, `num_bits_cognitive`, `num_bits_dataset`, `avg_bit_degree`, `max_chain_depth`, `num_variable_bits` |
| **CA Dynamics** (6) | `mean_activation`, `max_activation`, `activation_entropy`, `active_cell_fraction`, `error_potential_mean`, `error_cell_fraction` |
| **Outcomes** (6) | `reward`, `token_input`, `token_output`, `latency_ms`, `num_policy_violations`, `num_errors` |

## Fitness Function

```elixir
fitness = 
  (reward * 0.6) +                           # Primary objective
  (latency_efficiency * 0.2) +               # Lower latency = better
  (activation_stability * 0.1) +             # Moderate activation preferred
  (error_penalty * 0.1)                      # Penalize errors/violations
```

## Why Two Layers?

1. **Separation of Concerns**: Semantic reasoning (what bits mean) vs physics simulation (how activation flows)
2. **Different Data Layers**: Ash/Postgres for semantic bits, ETS/GenServer for CA cells
3. **Optimization Target**: TPE optimizes CA hyperparameters, not semantic relationships
4. **Observability**: Snapshot the physics layer without touching the semantic layer

## Related Playbook Sections

- **HC-Δ-5**: Thunderbit Ash Resource schema
- **HC-Δ-8**: CA Engine and Thundercell architecture  
- **HC-Δ-10**: Cerebros Feature Pipeline (this spec)
- **THUNDERBIT LAYER ARCHITECTURE RECONCILIATION**: Layer split documentation

## Common Questions

**Q: Why not merge them?**  
A: Different lifecycles. Semantic bits persist across sessions; CA cells reset each run.

**Q: How do they connect?**  
A: Semantic bits → project down to CA lattice → evolve → snapshot → extract features

**Q: Which one does TPE optimize?**  
A: The CA layer parameters (diffusion, decay, etc.), not the semantic graph structure.
