# Migration Guide: Operation TIGER LATTICE

> **Date**: December 6, 2025
> **Scope**: Thunderprism → Thundergrid.Prism consolidation, Reward Loop, Side-Quest Metrics, **Doctrine Layer**

This guide helps developers migrate code that used the old Thunderprism domain to the new Thundergrid.Prism namespace, and documents new Doctrine Layer features (algotype classification, hidden channels, delayed gratification detection).

---

## Summary of Changes

| Old Location | New Location | Notes |
|--------------|--------------|-------|
| `Thunderline.Thunderprism.Domain` | `Thunderline.Thundergrid.Domain` | Domain consolidated |
| `Thunderline.Thunderprism.PrismNode` | `Thunderline.Thundergrid.Prism.PrismNode` | Ash resource moved |
| `Thunderline.Thunderprism.PrismEdge` | `Thunderline.Thundergrid.Prism.PrismEdge` | Ash resource moved |
| `Thunderline.Thunderprism.MLTap` | `Thunderline.Thundergrid.Prism.MLTap` | Async logging moved |
| N/A | `Thunderline.Thundergrid.Prism.AutomataSnapshot` | **NEW** - automata metrics |
| N/A | `Thunderline.Thundercore.Reward.*` | **NEW** - reward loop system |
| N/A | `Thunderline.Thundercore.Doctrine` | **NEW** - Ising spin encoding |
| N/A | `Thunderline.Thundercore.Reward.DelayedGratificationDetector` | **NEW** - dip/recover detection |
| N/A | `Thunderline.Thundercore.Telemetry` | **NEW** - doctrine telemetry |
| N/A | `Thunderline.Thunderbolt.Rules.HiddenDiffusion` | **NEW** - hidden channel demo |

---

## Backward Compatibility

The old Thunderprism modules still exist as **thin delegators**. Your existing code will continue to work, but you should migrate to the new locations.

### Deprecated Modules (Still Work, But Migrate)

```elixir
# OLD - still works, but deprecated
Thunderline.Thunderprism.MLTap.log_node(attrs)
Thunderline.Thunderprism.Domain.create_prism_node!(...)

# NEW - use these instead
Thunderline.Thundergrid.Prism.MLTap.log_node(attrs)
Thunderline.Thundergrid.Prism.log_decision(attrs)  # Preferred shorthand
```

---

## Migration Steps

### 1. Update Aliases

**Before:**
```elixir
alias Thunderline.Thunderprism.{PrismNode, PrismEdge, MLTap}
alias Thunderline.Thunderprism.Domain
```

**After:**
```elixir
alias Thunderline.Thundergrid.Prism
alias Thunderline.Thundergrid.Prism.{PrismNode, PrismEdge, MLTap}
```

### 2. Update ML Logging Calls

**Before:**
```elixir
Thunderline.Thunderprism.MLTap.log_node(%{
  pac_id: "controller_1",
  iteration: 42,
  chosen_model: :model_a,
  model_probabilities: %{model_a: 0.7, model_b: 0.3}
})
```

**After:**
```elixir
# Option 1: Direct call (preferred)
Thunderline.Thundergrid.Prism.log_decision(%{
  pac_id: "controller_1",
  iteration: 42,
  chosen_model: :model_a,
  model_probabilities: %{model_a: 0.7, model_b: 0.3}
})

# Option 2: Via MLTap (same as before, different namespace)
Thunderline.Thundergrid.Prism.MLTap.log_node(%{...})
```

### 3. Update GraphQL Queries

The GraphQL schema now has queries under Thundergrid.Domain:

| Old Query | New Query | Notes |
|-----------|-----------|-------|
| `prism_nodes` | `prism_nodes` | Same name, now in Thundergrid |
| `prism_node` | `prism_node` | Same name |
| N/A | `automata_snapshots` | **NEW** - CA/NCA metrics |
| N/A | `reward_snapshots` | **NEW** - reward history |

### 4. Update Config References

If you had `Thunderline.Thunderprism.Domain` in your `config.exs`:

**Before:**
```elixir
config :thunderline, :ash_domains, [
  # ...
  Thunderline.Thunderprism.Domain,
  # ...
]
```

**After:**
```elixir
config :thunderline, :ash_domains, [
  # ...
  Thunderline.Thundergrid.Domain,  # Includes Prism resources
  # ...
]
```

---

## New Features: Reward Loop

Operation TIGER LATTICE added a complete reward loop system in Thundercore:

### Attaching Rewards to a CA Run

```elixir
# Start a CA run (existing code)
{:ok, _pid} = Thunderline.Thunderbolt.CA.Runner.start_link(
  run_id: "demo-run-1",
  ruleset: %{rule_module: Thunderline.Thunderbolt.Rules.NCA, ...},
  tick_ms: 100
)

# Attach reward loop (NEW)
:ok = Thunderline.Thundercore.Reward.attach("demo-run-1")

# The loop now:
# 1. Listens for criticality metrics (PLV, λ̂, entropy, Lyapunov)
# 2. Listens for side-quest metrics (clustering, emergence, healing)
# 3. Computes reward signal [0, 1]
# 4. Applies tuning deltas to CA.Runner (lambda, temperature, coupling)
```

### Manual Reward Computation

```elixir
alias Thunderline.Thundercore.Reward

criticality = %{
  plv: 0.42,
  entropy: 0.48,
  lambda_hat: 0.28,
  lyapunov: 0.01,
  edge_score: 0.85,
  zone: :critical
}

side_quest = %{
  clustering: 0.6,
  sortedness: 0.55,
  healing_rate: 0.75,
  pattern_stability: 0.58,
  emergence_score: 0.7
}

{:ok, result} = Reward.compute(criticality, side_quest, tick: 42)
# => %{
#      reward: 0.78,
#      components: %{edge_score: 0.85, emergence: 0.7, ...},
#      tuning: %{lambda_delta: -0.007, temp_delta: 0.002, ...},
#      zone: :critical
#    }
```

### Querying Reward History

```elixir
# Get history for a run
{:ok, history} = Reward.history("run_123")

# Get average reward
{:ok, avg} = Reward.average_reward("run_123")

# Get current tuning params
{:ok, params} = Reward.current_params("run_123")
# => %{lambda: 0.273, temperature: 1.0, coupling: 0.5}
```

---

## New Features: Side-Quest Metrics

CA/NCA runs now emit side-quest metrics alongside criticality:

### Metrics Emitted

| Metric | Description | Range |
|--------|-------------|-------|
| `clustering` | Spatial clustering coefficient | [0, 1] |
| `sortedness` | Order/sortedness measure (Kendall tau) | [0, 1] |
| `healing_rate` | Damage recovery rate | [0, 1] |
| `pattern_stability` | Pattern persistence over time | [0, 1] |
| `emergence_score` | Novel structure detection | [0, 1] |

### Telemetry Events

```elixir
# Side-quest metrics
[:thunderbolt, :automata, :side_quest]

# Criticality metrics
[:thunderline, :bolt, :ca, :criticality]

# Reward computed
[:thunderline, :core, :reward, :computed]
```

### EventBus Events

```
bolt.ca.metrics.snapshot        # Criticality (PLV, λ̂, etc.)
bolt.automata.side_quest.snapshot  # Side-quest metrics
core.reward.computed            # Reward + tuning signals
```

---

## Custom Rules: Emitting Metrics

If you have custom CA rules, update them to return side-quest metrics:

### Implementing the Rule Behaviour

```elixir
defmodule MyApp.CustomRule do
  @behaviour Thunderline.Thunderbolt.Rule

  @impl true
  def update(bit, neighbors, ruleset) do
    # ... your logic ...

    # Return delta with metrics for side-quest analysis
    delta = %{
      coord: bit.coord,
      old_state: bit.state,
      new_state: new_state,
      sigma_flow: computed_flow,
      state: new_state
    }

    {:ok, delta, %{clustering: local_clustering, entropy: local_entropy}}
  end

  @impl true
  def init(opts), do: {:ok, opts}
end
```

### Using Your Rule

```elixir
ruleset = %{
  rule_module: MyApp.CustomRule,
  rule_params: %{...},
  rule_version: 2  # Required for side-quest metrics
}

{:ok, _pid} = CA.Runner.start_link(
  run_id: "custom-run",
  ruleset: ruleset,
  emit_criticality: true  # Enable metrics
)
```

---

## Domain Map Update

The canonical 11-domain Thunderline architecture is now:

| # | Domain | Focus |
|---|--------|-------|
| 1 | **Thundercore** | Ticks, rewards, clocks, identity |
| 2 | **Thundervine** | DAG / world-graph |
| 3 | **Thunderblock** | Persistence / storage |
| 4 | **Thunderlink** | Connection & comms |
| 5 | **Thunderflow** | Event bus |
| 6 | **Thunderchief** | Orchestration |
| 7 | **Thundercrown** | Policy / governance |
| 8 | **Thunderbolt** | Automata + ML (CA/NCA/Ising) |
| 9 | **Thundergate** | Security |
| 10 | **Thundergrid** | Visibility (GraphQL + UI + Prism) |
| 11 | **Thunderforge** | Compilers, parsers, learning |

**Thunderprism** is now `Thundergrid.Prism` (a submodule, not a domain).

---

## New Features: Doctrine Layer (Dec 6, 2025)

The Doctrine Layer adds algotype (behavioral classification) and hidden channels to Thunderbits.

### Thunderbit Fields

All Thunderbits now have:

```elixir
%Thunderbit{
  # ... existing fields ...
  doctrine: :general,                    # :router | :healer | :compressor | :explorer | :guardian | :general
  hidden_state: %{v: [], dim: 0}         # Hidden channel vector for inter-bit communication
}
```

### Doctrine Module

```elixir
alias Thunderline.Thundercore.Doctrine

# Spin encoding for Ising model
Doctrine.encode_spin(:router)    # => 1.0 (cooperative)
Doctrine.encode_spin(:explorer)  # => -1.0 (exploratory)
Doctrine.encode_spin(:general)   # => 0.0 (neutral)

# Interaction energy
Doctrine.interaction_energy(:router, :healer)    # => -1.0 (favorable)
Doctrine.interaction_energy(:router, :explorer)  # => 1.0 (unfavorable)

# Distribution analysis
bits = [%{doctrine: :router}, %{doctrine: :router}, %{doctrine: :explorer}]
Doctrine.distribution(bits)         # => %{router: 2, explorer: 1}
Doctrine.distribution_entropy(bits) # => 0.63 (normalized entropy)
```

### New Algotype Metrics

SideQuestMetrics now includes:

| Metric | Description |
|--------|-------------|
| `algotype_clustering` | Same-doctrine spatial clustering [0, 1] |
| `algotype_ising_energy` | Ising energy from doctrine spins |
| `doctrine_distribution` | Map of doctrine → count |

### Delayed Gratification Detection

```elixir
alias Thunderline.Thundercore.Reward.DelayedGratificationDetector

# Analyze reward history for dip-then-recover patterns
history = [0.5, 0.5, 0.3, 0.2, 0.15, 0.25, 0.4, 0.5]
events = DelayedGratificationDetector.analyze(history)
# => [%{tick_start: 2, tick_bottom: 4, tick_recover: 7, depth: 0.35, duration: 5}]
```

### New GraphQL Queries

```graphql
# Get doctrine distribution for a run
query {
  doctrine_distribution(run_id: "run-123") {
    algotype_clustering
    algotype_ising_energy
    doctrine_distribution
    doctrine_entropy
    algotype_score
  }
}

# Get doctrine history
query {
  doctrine_history(run_id: "run-123", limit: 50) {
    tick
    algotype_clustering
    algotype_ising_energy
  }
}
```

### Telemetry Events

```elixir
# Attach handlers
Thunderline.Thundercore.Telemetry.attach_handlers(log_level: :info)

# Events emitted:
# [:thunderbolt, :automata, :algotype] - algotype metrics
# [:thundercore, :reward, :delayed_gratification] - gratification detected
```

### HiddenDiffusion Rule (Demo)

```elixir
# Use the HiddenDiffusion rule to test hidden channels
ruleset = %{
  rule_module: Thunderline.Thunderbolt.Rules.HiddenDiffusion,
  rule_params: %{dim: 4, diffusion_rate: 0.3, noise_scale: 0.01}
}
```

---

## Questions?

If you encounter issues migrating, check:

1. **Compilation errors about Thunderprism.Domain** → Update config.exs
2. **MLTap.log_node not found** → Update alias to new namespace
3. **GraphQL queries failing** → Ensure Thundergrid.Domain is registered

For further help, see the main playbook or the HC Architecture Synthesis docs.
