# ⚡ HIGH COMMAND QUANTUM SUBSTRATE SPECIFICATION

> **The Virtual Compute Substrate: QCA-Inspired Architecture for Thunderline**
>
> This document synthesizes cutting-edge research on Ternary QCA, Reversible Logic,
> Phase Transitions, Topological Memory, and Titans/MIRAS Deep Memory into a unified
> specification for Thunderline's next-generation compute substrate.

**Document Status**: CANONICAL RESEARCH SYNTHESIS | **Phase 1 IMPLEMENTED**  
**Created**: December 5, 2025  
**Last Updated**: December 5, 2025  
**Implementation Complete**: HC-86, HC-87, HC-88, HC-89, HC-90, HC-95 (Core Substrate)  
**Related**: [HC_ARCHITECTURE_SYNTHESIS.md](HC_ARCHITECTURE_SYNTHESIS.md), [THUNDERLINE_MASTER_PLAYBOOK.md](../../THUNDERLINE_MASTER_PLAYBOOK.md)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Research Foundation](#research-foundation)
3. [Thunderbit Formal Definition v2](#thunderbit-formal-definition-v2)
4. [4-Phase Thunderclock Protocol](#4-phase-thunderclock-protocol)
5. [Reversible Logic Substrate](#reversible-logic-substrate)
6. [Ternary State Model](#ternary-state-model)
7. [MIRAS Deep Memory Integration](#miras-deep-memory-integration)
8. [Topological Stability (Braids)](#topological-stability-braids)
9. [Fault Tolerance Model](#fault-tolerance-model)
10. [Domain Module Mapping](#domain-module-mapping)
11. [Implementation Roadmap](#implementation-roadmap)
12. [Research Citations](#research-citations)

---

## Executive Summary

### The Vision

Thunderline is evolving from a traditional web platform into a **virtual compute substrate** that:

1. **Models itself as physics** (Ising spins, QCA cells, thermodynamic phases)
2. **Learns its own rules** (DiffLogic CA, GNCA, NCA)
3. **Self-heals and self-organizes** (topological braids, regenerating patterns)
4. **Operates at criticality** (edge-of-chaos for maximum information capacity)
5. **Supports reversible computation** (no information loss, undo-capable)
6. **Implements deep memory** (MIRAS/Titans surprise-gated updates)

### Key Insight

> **"Thunderbits are not just data - they are spin variables in a virtual Ising machine."**

By treating each Thunderbit as a ternary spin with local coupling, we get:
- A **virtual Ising machine** for optimization (inside Thunderbolt)
- **Reversible state transitions** for rollback/undo
- **Phase transitions** for emergent computation
- **Topological stability** for corruption resistance

### Unification Moment

Six research threads converge:

| Research Thread | Key Insight | Thunderline Integration |
|----------------|-------------|------------------------|
| **Ternary QCA** | 3-state reversible logic, lower entropy | Thunderbit state model |
| **Reversible Computing** | Bijective transitions, no info loss | Thunderbolt rule constraints |
| **Phase Transitions** | Spin coupling → emergent order | LoopMonitor criticality |
| **Topological Memory** | Braid invariants resist corruption | Thunderpac memory braids |
| **Titans/MIRAS** | Surprise-gated deep MLP memory | Thunderpac MemoryModule |
| **DiffLogic CA** | Trainable discrete logic gates | Thunderbolt NCA kernels |

---

## Research Foundation

### Source Documents

#### 1. Ternary QCA & Reversible Logic
- **Paper**: "Ternary Reversible Feynman and Toffoli Gates in TQCA"
- **Key Findings**:
  - TQCA cells have 3+ stable polarization states (mapped to A/B/C/D configurations)
  - Reversible gates (Feynman, Toffoli) provide bijective input→output mapping
  - No information destroyed → minimal entropy production
  - 77-92% fault tolerance under cell omission defects
  - Very small area/delay at physical level

#### 2. Phase Transitions & Ising Models
- **Paper**: Akin's Phase Transitions & Quantum Ising research
- **Key Findings**:
  - Phase transitions emerge when units are constrained to small state sets
  - Local coupling + external field + temperature/noise → emergent order
  - Identical to how Thunderbits should operate:
    ```
    Thunderbit.state ∈ { -1, 0, +1 }    # ternary spin
    Thunderbit.neighbors = spin coupling field
    Thunderbit.bias = PAC intent / Crown policy field
    ```

#### 3. Topological Stability (Kitaev/Sen)
- **Paper**: "0612426v1 - Qutrits & Topological Stabilizers"
- **Key Findings**:
  - Qutrits (ternary quantum states)
  - Fusion rules & braid invariants
  - Topological stabilizers cannot be corrupted without destroying the braid
  - Maps to: agents, tasks, goals, long-term memories as stable composite structures

#### 4. DiffLogic Cellular Automata
- **Paper**: Google Research "Growing Self-Organizing Systems with DiffLogic CA"
- **Key Findings**:
  - NCA + Differentiable Logic Gate Networks
  - Logic gates as neurons (AND, OR, XOR, etc.)
  - 16 possible binary operations with continuous relaxations
  - Self-healing, fault tolerance, asynchronicity emerges naturally
  - Pathway to "Computronium" - learnable, local, discrete programmable matter

#### 5. Titans/MIRAS Memory
- **Paper**: Google "Titans: Learning to Memorize at Test Time" (2025)
- **Paper**: "MIRAS: Unlocking Expressivity" (2025)
- **Key Findings**:
  - Deep MLP as memory substrate
  - Surprise-gated writes: only high |∇ℓ| triggers updates
  - Momentum-based surprise smoothing (β-EMA)
  - Adaptive decay gate for forgetting
  - 4-Choice Framework: Memory, Attention, Retention, Update

---

## Thunderbit Formal Definition v2

### Core Structure

```elixir
defmodule Thunderbolt.Thunderbit do
  @moduledoc """
  A single voxel cell in the 3D CA lattice.
  
  Each Thunderbit is:
  - TERNARY (QCA-inspired state model)
  - REVERSIBLE (bijective transition functions)
  - ENERGY-MINIMIZING (Ising-inspired coupling)
  - SURPRISE-UPDATE-DRIVEN (MIRAS/Titans memory)
  """
  
  @enforce_keys [:id, :coord]
  defstruct [
    # === IDENTITY ===
    :id,                    # UUID v7 (time-ordered)
    :coord,                 # {x, y, z} position in lattice
    :pac_id,                # Owning PAC identifier (nil if unassigned)
    
    # === TERNARY STATE ===
    :state,                 # :neg | :zero | :pos (or -1, 0, +1)
    :state_vector,          # Extended: [state_channel_1, ..., state_channel_n]
    
    # === PHYSICS-INSPIRED FIELDS ===
    :bias,                  # ℝ - External field / policy pressure
    :coupling,              # Local energy function (neighbor weights)
    :temperature,           # Noise/randomness parameter
    
    # === CRITICALITY METRICS ===
    :phi_phase,             # Phase for synchrony (PLV monitoring)
    :sigma_flow,            # Propagatability / connectivity
    :lambda_sensitivity,    # Local FTLE (chaos/stability indicator)
    
    # === MEMORY (MIRAS) ===
    :surprise_metric,       # |predicted - observed| gradient magnitude
    :retention_gate,        # Memory decay control [0, 1]
    :momentum_surprise,     # β-EMA smoothed surprise
    
    # === NETWORK ===
    :neighbors,             # Precomputed neighbor coords (6 in-plane + temporal)
    :presence,              # :vacant | :occupied | :forwarding
    :trust_score,           # Trust level for routing
    :relay_weight,          # Load balancing weight
    
    # === CRYPTO/SECURITY ===
    :key_fragment,          # Encrypted key shard
    :route_tags,            # Bloom filter of destination IDs
    
    # === CHANNEL ===
    :channel_id,            # Active channel ID (nil if idle)
    
    # === METADATA ===
    :policy_anchors,        # Crown policy references
    :timestamp,             # Last update time
    :rule_version           # Which CA rule version applies
  ]
  
  @type state :: :neg | :zero | :pos
  @type coord :: {integer(), integer(), integer()}
  
  @type t :: %__MODULE__{
    id: String.t(),
    coord: coord(),
    state: state(),
    # ... full type spec
  }
end
```

### State Semantics

| State | Symbol | Meaning | Domain Examples |
|-------|--------|---------|-----------------|
| **Negative** | -1 / `:neg` | Inhibitory, off, decayed, negative evidence | Denied request, failed check, expired |
| **Zero** | 0 / `:zero` | Neutral, no signal, resting, unknown | Idle, awaiting, unassigned |
| **Positive** | +1 / `:pos` | Excitatory, on, active, positive evidence | Approved, active, confirmed |

### Multi-Channel State Vector

For richer state representation (like NCA's 16+ channels):

```elixir
@type state_vector :: %{
  visible: [float()],      # Channels 0-3: RGBA visible state
  hidden: [float()],       # Channels 4-11: Hidden computation state
  memory: [float()],       # Channels 12-15: Persistent memory
  domain: [float()]        # Channels 16+: Domain-specific extensions
}
```

### Reversible Transition Function

```elixir
@spec reversible_update(Thunderbit.t(), [Thunderbit.t()]) :: Thunderbit.t()
def reversible_update(center, neighbors) do
  # Compute local energy
  energy = compute_local_energy(center, neighbors)
  
  # Apply Toffoli-style reversible gate
  new_state = apply_reversible_rule(center.state, neighbors, center.rule_version)
  
  # Ensure bijective mapping
  assert reversible?(center.state, new_state, neighbors)
  
  %{center | state: new_state, timestamp: now()}
end

@spec compute_local_energy(Thunderbit.t(), [Thunderbit.t()]) :: float()
def compute_local_energy(center, neighbors) do
  # Ising-style energy: E = -Σ J_ij * s_i * s_j - h * s_i
  coupling_energy = Enum.reduce(neighbors, 0.0, fn neighbor, acc ->
    acc - center.coupling * state_to_float(center.state) * state_to_float(neighbor.state)
  end)
  
  field_energy = -center.bias * state_to_float(center.state)
  
  coupling_energy + field_energy
end
```

---

## 4-Phase Thunderclock Protocol

### Origin: QCA Clocking

QCA circuits use four clock phases:
1. **Switch** - Barriers rising, electrons freeze into polarization
2. **Hold** - Barriers max, state stable
3. **Release** - Barriers fall, state starts to unlock
4. **Relax** - Barriers low, cell unpolarized/rest

### Thunderline Mapping

```
┌─────────────────────────────────────────────────────────────────────┐
│                    4-PHASE THUNDERCLOCK                             │
│                                                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   │   SWITCH    │ ──►│    HOLD     │ ──►│   RELEASE   │ ──►│    RELAX    │
│   │  (Sense)    │    │  (Compute)  │    │   (Emit)    │    │  (Decay)    │
│   └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
│         │                  │                  │                  │
│         ▼                  ▼                  ▼                  ▼
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   │ Read inputs │    │ Apply CA    │    │ Commit      │    │ Apply decay │
│   │ Integrate   │    │ rules       │    │ changes     │    │ Forgetting  │
│   │ neighbors   │    │ Cerebros    │    │ Emit events │    │ GC cleanup  │
│   │ Parse       │    │ ONNX calls  │    │ Update UI   │    │ Rollback    │
│   │ signals     │    │ No I/O      │    │ Respond     │    │ reversible  │
│   └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
│                                                                     │
│   Domain Activity:                                                  │
│   SWITCH:  Flow(events), Link(messages), Grid(API), Prism(UI)      │
│   HOLD:    Bolt(CA rules), Crown(policy), Cerebros(ML)             │
│   RELEASE: Flow(emit), Block(persist), Grid(respond), Link(send)   │
│   RELAX:   Wall(decay), Gate(cleanup), Core(reset)                 │
└─────────────────────────────────────────────────────────────────────┘
```

### Implementation

```elixir
defmodule Thundercore.Clock do
  @moduledoc """
  4-Phase clock for Thunderline.
  Coordinates all domains through Switch→Hold→Release→Relax cycle.
  """
  
  use GenServer
  
  @phases [:switch, :hold, :release, :relax]
  @phase_duration_ms 500  # Configurable tick duration
  
  defstruct [
    :current_phase,
    :tick_count,
    :phase_index,
    :subscribers
  ]
  
  # === Phase Transition Events ===
  
  @spec current_phase() :: phase()
  def current_phase, do: GenServer.call(__MODULE__, :current_phase)
  
  @spec on_phase(phase(), callback()) :: :ok
  def on_phase(phase, callback) when phase in @phases do
    GenServer.cast(__MODULE__, {:subscribe, phase, callback})
  end
  
  # === Internal Implementation ===
  
  def handle_info(:tick, state) do
    # Advance phase
    next_index = rem(state.phase_index + 1, 4)
    next_phase = Enum.at(@phases, next_index)
    
    # Emit phase transition event
    Thunderflow.EventBus.publish_event!(%{
      name: "core.clock.phase",
      source: :core,
      payload: %{
        phase: next_phase,
        tick: state.tick_count,
        timestamp: DateTime.utc_now()
      }
    })
    
    # Notify subscribers
    notify_phase_subscribers(next_phase, state.subscribers)
    
    # Schedule next tick
    Process.send_after(self(), :tick, @phase_duration_ms)
    
    {:noreply, %{state | 
      phase_index: next_index, 
      current_phase: next_phase,
      tick_count: state.tick_count + (if next_index == 0, do: 1, else: 0)
    }}
  end
end
```

### Phase Responsibilities

| Phase | Duration | Primary Domains | Activities |
|-------|----------|-----------------|------------|
| **SWITCH** | 25% | Flow, Link, Grid, Prism | Read world: events, messages, API requests, UI input |
| **HOLD** | 25% | Bolt, Crown, Cerebros | Compute: CA rules, policies, ML inference. No I/O. |
| **RELEASE** | 25% | Flow, Block, Grid, Link | Write world: emit events, persist, respond, send |
| **RELAX** | 25% | Wall, Gate, Core | Cleanup: decay, forgetting, GC, reversible rollback |

---

## Reversible Logic Substrate

### Landauer's Principle

Classical irreversible logic erases information → heat dissipation (kT ln 2 per bit).

Reversible gates provide **bijective mapping** between inputs and outputs:
- No information destroyed
- Theoretically zero heat generation
- Can "uncompute" to recover previous state

### Thunderline Application: Logical Entropy Discipline

We treat "reversible" as **logical entropy discipline**, not just thermodynamics:

#### 1. Reversible Thunderbit Rule Design

```elixir
defmodule Thunderbolt.ReversibleRules do
  @moduledoc """
  Reversible CA rules based on Toffoli/Feynman gate compositions.
  """
  
  @doc """
  Ternary Feynman gate: controlled "copy/transform" operation.
  XOR-like for ternary: output = (input + control) mod 3
  """
  @spec feynman_ternary(state(), state()) :: state()
  def feynman_ternary(control, target) do
    Integer.mod(state_to_int(control) + state_to_int(target), 3)
    |> int_to_state()
  end
  
  @doc """
  Ternary Toffoli gate: controlled-controlled "flip/transform".
  Only flips target if BOTH controls are non-zero.
  """
  @spec toffoli_ternary(state(), state(), state()) :: state()
  def toffoli_ternary(control_a, control_b, target) do
    if control_a != :zero and control_b != :zero do
      Integer.mod(state_to_int(target) + 1, 3) |> int_to_state()
    else
      target
    end
  end
  
  @doc """
  Verify that a rule is reversible (bijective).
  """
  @spec reversible?(rule_fn()) :: boolean()
  def reversible?(rule_fn) do
    # Generate all possible input combinations
    inputs = for a <- [:neg, :zero, :pos],
                 b <- [:neg, :zero, :pos],
                 c <- [:neg, :zero, :pos], do: {a, b, c}
    
    outputs = Enum.map(inputs, &rule_fn.(&1))
    
    # Check bijection: unique outputs = unique inputs
    length(Enum.uniq(outputs)) == length(inputs)
  end
end
```

#### 2. Undo/Rollback for PACs

```elixir
defmodule Thunderpac.ReversibleFlow do
  @moduledoc """
  Mark PAC transformations as reversible for cheap rollback.
  """
  
  @doc """
  Execute a reversible transformation with automatic inverse recording.
  """
  @spec with_reversible(PAC.t(), (PAC.t() -> PAC.t())) :: {:ok, PAC.t(), inverse_fn()}
  def with_reversible(pac, transform_fn) do
    # Capture initial state
    initial = capture_state(pac)
    
    # Apply transform
    updated = transform_fn.(pac)
    
    # Generate inverse function
    inverse = fn _pac -> restore_state(initial) end
    
    {:ok, updated, inverse}
  end
  
  @doc """
  Execute reversible flow - cheap to undo without full snapshots.
  """
  @spec execute_reversible_flow(PAC.t(), [transform_fn()]) :: {:ok, PAC.t(), [inverse_fn()]}
  def execute_reversible_flow(pac, transforms) do
    {final_pac, inverses} = Enum.reduce(transforms, {pac, []}, fn transform, {p, invs} ->
      {:ok, new_p, inv} = with_reversible(p, transform)
      {new_p, [inv | invs]}
    end)
    
    {:ok, final_pac, Enum.reverse(inverses)}
  end
  
  @doc """
  Rollback using recorded inverse operations.
  """
  @spec rollback(PAC.t(), [inverse_fn()]) :: PAC.t()
  def rollback(pac, inverses) do
    Enum.reduce(Enum.reverse(inverses), pac, fn inv, p -> inv.(p) end)
  end
end
```

#### 3. Entropy-Aware Thunderflow Processors

```elixir
defmodule Thunderflow.EntropyAnnotation do
  @moduledoc """
  Annotate event processors as reversible or irreversible.
  """
  
  @type entropy_type :: :reversible | :irreversible | :compressive | :destructive
  
  @doc """
  Declare processor entropy characteristics.
  """
  defmacro entropy(type) when type in [:reversible, :irreversible, :compressive, :destructive] do
    quote do
      @entropy_type unquote(type)
      
      def entropy_type, do: unquote(type)
    end
  end
  
  @doc """
  Decide where to pay cost of compression/forgetting vs full invertibility.
  """
  @spec should_preserve_inverse?(processor_module()) :: boolean()
  def should_preserve_inverse?(processor) do
    processor.entropy_type() == :reversible
  end
end
```

---

## Ternary State Model

### Why Ternary?

From TQCA research:
- More information per "wire" (log₂(3) ≈ 1.58 bits vs 1 bit)
- Fewer interconnects needed
- Lower complexity + power vs binary for some circuits
- Natural mapping to: positive/neutral/negative, yes/no/unknown, allow/deny/defer

### Thunderbit Ternary Channels

```elixir
defmodule Thunderbolt.TernaryState do
  @moduledoc """
  Ternary state model for Thunderbits.
  """
  
  @type ternary :: :neg | :zero | :pos
  @type balanced_ternary :: -1 | 0 | 1
  
  # === Conversion ===
  
  @spec to_balanced(ternary()) :: balanced_ternary()
  def to_balanced(:neg), do: -1
  def to_balanced(:zero), do: 0
  def to_balanced(:pos), do: 1
  
  @spec from_balanced(balanced_ternary()) :: ternary()
  def from_balanced(-1), do: :neg
  def from_balanced(0), do: :zero
  def from_balanced(1), do: :pos
  
  # === Ternary Arithmetic ===
  
  @spec add(ternary(), ternary()) :: ternary()
  def add(a, b) do
    Integer.mod(to_balanced(a) + to_balanced(b) + 1, 3) - 1
    |> from_balanced()
  end
  
  @spec multiply(ternary(), ternary()) :: ternary()
  def multiply(a, b) do
    (to_balanced(a) * to_balanced(b))
    |> clamp(-1, 1)
    |> from_balanced()
  end
  
  # === Ternary Logic ===
  
  @spec ternary_not(ternary()) :: ternary()
  def ternary_not(:neg), do: :pos
  def ternary_not(:zero), do: :zero
  def ternary_not(:pos), do: :neg
  
  @spec ternary_and(ternary(), ternary()) :: ternary()
  def ternary_and(a, b), do: min_ternary(a, b)
  
  @spec ternary_or(ternary(), ternary()) :: ternary()
  def ternary_or(a, b), do: max_ternary(a, b)
end
```

### Domain Status Applications

| Domain | Ternary Usage |
|--------|---------------|
| **Thundercrown** | ALLOW / DENY / DEFER policies |
| **Thundergate** | TRUSTED / UNKNOWN / UNTRUSTED |
| **Thunderpac** | ACTIVE / IDLE / DEGRADED |
| **Thunderflow** | SUCCESS / PENDING / FAILED events |
| **Thundervine** | CONNECTED / ORPHAN / BLOCKED DAG edges |

### Ternary Policy Predicates

```elixir
defmodule Thundercrown.TernaryPolicy do
  @moduledoc """
  Express policies over ternary predicates.
  """
  
  @doc """
  Evaluate policy: allow if trust ≥ 0 and risk ≤ 0
  """
  @spec evaluate_access(trust :: ternary(), risk :: ternary()) :: :allow | :deny | :defer
  def evaluate_access(trust, risk) do
    trust_ok = trust in [:zero, :pos]
    risk_ok = risk in [:neg, :zero]
    
    cond do
      trust_ok and risk_ok -> :allow
      not trust_ok -> :deny
      not risk_ok -> :defer  # Need more information
    end
  end
end
```

---

## MIRAS Deep Memory Integration

### The 4-Choice Framework

From Titans/MIRAS research:

| Component | Description | Thunderline Mapping |
|-----------|-------------|---------------------|
| **Memory** | Deep MLP state container | `Thunderpac.MemoryModule` GenServer |
| **Attention** | Cross-attention via context | Query against memory bank |
| **Retention** | Weight decay gate | Forgetting schedule |
| **Update** | Surprise-triggered writes | Gradient magnitude threshold |

### Thunderpac MemoryModule

```elixir
defmodule Thunderpac.MemoryModule do
  @moduledoc """
  Titans-style deep MLP memory with surprise-gated updates.
  
  Write only when surprise (‖∇ℓ‖) > threshold.
  Momentum-based surprise smoothing (β-EMA).
  Weight decay as forgetting.
  """
  
  use GenServer
  
  defstruct [
    :pac_id,
    :memory_state,        # Deep MLP weights (Nx tensor)
    :surprise_threshold,  # θ for write gate
    :momentum_beta,       # β for EMA smoothing
    :weight_decay,        # Forgetting rate
    :current_surprise,    # Current surprise metric
    :smoothed_surprise    # β-EMA smoothed
  ]
  
  # === Public API ===
  
  @doc """
  Query memory with input pattern.
  """
  @spec read(pac_id(), query :: Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()}
  def read(pac_id, query) do
    GenServer.call(via(pac_id), {:read, query})
  end
  
  @doc """
  Attempt memory write (only succeeds if surprise > threshold).
  """
  @spec write(pac_id(), input :: Nx.Tensor.t(), target :: Nx.Tensor.t()) :: :written | :skipped
  def write(pac_id, input, target) do
    GenServer.call(via(pac_id), {:write, input, target})
  end
  
  @doc """
  Force decay pass (called during RELAX phase).
  """
  @spec decay(pac_id()) :: :ok
  def decay(pac_id) do
    GenServer.cast(via(pac_id), :decay)
  end
  
  # === Callbacks ===
  
  def handle_call({:write, input, target}, _from, state) do
    # Compute surprise metric (gradient magnitude)
    {output, gradient} = forward_backward(state.memory_state, input, target)
    surprise = Nx.sum(Nx.abs(gradient)) |> Nx.to_number()
    
    # Update smoothed surprise with momentum
    smoothed = state.momentum_beta * state.smoothed_surprise + 
               (1 - state.momentum_beta) * surprise
    
    # Check write gate
    if smoothed > state.surprise_threshold do
      # Apply gradient update to memory
      new_memory = apply_gradient_update(state.memory_state, gradient)
      
      # Emit event
      emit_memory_event(:write, state.pac_id, %{
        surprise: surprise,
        smoothed: smoothed
      })
      
      {:reply, :written, %{state | 
        memory_state: new_memory,
        current_surprise: surprise,
        smoothed_surprise: smoothed
      }}
    else
      {:reply, :skipped, %{state | 
        current_surprise: surprise,
        smoothed_surprise: smoothed
      }}
    end
  end
  
  def handle_cast(:decay, state) do
    # Apply weight decay (forgetting)
    decayed_memory = Nx.multiply(state.memory_state, state.weight_decay)
    
    emit_memory_event(:decay, state.pac_id, %{
      decay_rate: state.weight_decay
    })
    
    {:noreply, %{state | memory_state: decayed_memory}}
  end
  
  # === Private ===
  
  defp forward_backward(memory, input, target) do
    # Forward pass through deep MLP
    output = deep_mlp_forward(memory, input)
    
    # Compute loss gradient
    loss = Nx.mean(Nx.power(Nx.subtract(output, target), 2))
    gradient = Nx.Defn.grad(loss, memory)
    
    {output, gradient}
  end
  
  defp emit_memory_event(type, pac_id, payload) do
    Thunderflow.EventBus.publish_event!(%{
      name: "pac.memory.#{type}",
      source: :pac,
      payload: Map.merge(payload, %{pac_id: pac_id})
    })
  end
end
```

### Surprise-Driven Updates

```elixir
defmodule Thunderbolt.SurpriseMetric do
  @moduledoc """
  Compute surprise metrics for MIRAS integration.
  """
  
  @doc """
  Compute surprise as gradient magnitude.
  ‖∇ℓ‖ measures how unexpected the observation is.
  """
  @spec compute_surprise(predicted :: Nx.Tensor.t(), observed :: Nx.Tensor.t()) :: float()
  def compute_surprise(predicted, observed) do
    diff = Nx.subtract(observed, predicted)
    Nx.sum(Nx.abs(diff)) |> Nx.to_number()
  end
  
  @doc """
  Momentum-smoothed surprise (β-EMA).
  s_t = β·s_{t-1} + (1-β)·‖∇ℓ_t‖
  """
  @spec momentum_surprise(previous :: float(), current :: float(), beta :: float()) :: float()
  def momentum_surprise(previous, current, beta \\ 0.9) do
    beta * previous + (1 - beta) * current
  end
  
  @doc """
  Check if surprise exceeds write threshold.
  """
  @spec should_write?(smoothed_surprise :: float(), threshold :: float()) :: boolean()
  def should_write?(smoothed_surprise, threshold) do
    smoothed_surprise > threshold
  end
end
```

---

## Topological Stability (Braids)

### From Anyonic Physics to Software

The Kitaev/Sen paper discusses:
- **Qutrits**: Ternary quantum states
- **Fusion rules**: How states combine
- **Braid invariants**: Topological properties preserved under deformation
- **Stabilizers**: Cannot be corrupted without destroying the structure

### Thunderline Application

**Stable composite structures** that behave like agents, tasks, goals, memories:

```elixir
defmodule Thunderpac.TopologicalBraid do
  @moduledoc """
  Represent stable composite structures as topological braids.
  
  A braid is a configuration of PAC state that is stable under
  local perturbations - you cannot corrupt it without destroying
  the entire structure.
  """
  
  defstruct [
    :id,
    :strands,           # List of strand states
    :crossings,         # Crossing sequence
    :invariant,         # Computed topological invariant
    :pac_id
  ]
  
  @doc """
  Create a new braid from PAC state.
  """
  @spec from_pac_state(PAC.t()) :: t()
  def from_pac_state(pac) do
    strands = extract_strands(pac)
    crossings = compute_crossings(strands)
    invariant = jones_polynomial(crossings)  # Topological invariant
    
    %__MODULE__{
      id: Thunderline.UUID.v7(),
      strands: strands,
      crossings: crossings,
      invariant: invariant,
      pac_id: pac.id
    }
  end
  
  @doc """
  Verify braid integrity.
  Returns true if the invariant is preserved.
  """
  @spec valid?(t()) :: boolean()
  def valid?(braid) do
    current_invariant = jones_polynomial(braid.crossings)
    current_invariant == braid.invariant
  end
  
  @doc """
  Detect corruption - invariant change indicates tampering.
  """
  @spec corrupted?(t()) :: boolean()
  def corrupted?(braid), do: not valid?(braid)
end
```

### Applications

| Structure | Braid Representation | Corruption Detection |
|-----------|---------------------|----------------------|
| **Agent Identity** | PAC personality/memory strands | Identity theft detection |
| **Task State** | Workflow step sequence | Unexpected state changes |
| **Goal Tree** | Plan node dependencies | Broken plan structure |
| **Long-term Memory** | Memory strand persistence | Memory corruption |

---

## Fault Tolerance Model

### From TQCA Research

The paper explicitly models faults:
- **Cell omission defects**: Missing cells (77-92% tolerance)
- **Misalignment defects**: Offset positioning

### Software Mapping

```elixir
defmodule Thunderbolt.FaultTolerance do
  @moduledoc """
  Fault tolerance patterns from TQCA research.
  """
  
  @doc """
  Test system behavior with simulated node dropouts.
  """
  @spec simulate_dropout(lattice :: [Thunderbit.t()], dropout_rate :: float()) :: [Thunderbit.t()]
  def simulate_dropout(lattice, dropout_rate) do
    Enum.filter(lattice, fn _bit -> :rand.uniform() > dropout_rate end)
  end
  
  @doc """
  Verify that CA converges despite missing cells.
  """
  @spec verify_convergence_with_faults(lattice, target_pattern, max_steps, dropout_rate) :: boolean()
  def verify_convergence_with_faults(lattice, target, max_steps, dropout_rate) do
    faulty_lattice = simulate_dropout(lattice, dropout_rate)
    
    final_state = Enum.reduce(1..max_steps, faulty_lattice, fn _, lat ->
      Thunderbolt.CA.Stepper.step(lat)
    end)
    
    pattern_matches?(final_state, target)
  end
  
  @doc """
  Design rule patterns that tolerate fraction of dead Thunderbits.
  """
  @spec fault_tolerant_rule?(rule_fn, tolerance :: float()) :: boolean()
  def fault_tolerant_rule?(rule_fn, tolerance) do
    # Test multiple random dropout configurations
    results = for _ <- 1..100 do
      verify_convergence_with_faults(test_lattice(), test_target(), 100, tolerance)
    end
    
    success_rate = Enum.count(results, & &1) / 100
    success_rate >= 0.95  # 95% success threshold
  end
end
```

### Thundervine DAG Fault Simulation

```elixir
defmodule Thundervine.FaultSimulation do
  @moduledoc """
  Inject faults into DAG workflows and verify resilience.
  """
  
  @doc """
  Inject "missing node" faults and verify invariants.
  """
  @spec inject_node_faults(workflow_id, fault_rate) :: {:ok | :degraded | :failed, metrics}
  def inject_node_faults(workflow_id, fault_rate) do
    workflow = Thundervine.Workflow.get!(workflow_id)
    
    # Mark random nodes as failed
    nodes_to_fail = workflow.nodes
    |> Enum.filter(fn _ -> :rand.uniform() < fault_rate end)
    |> Enum.map(& &1.id)
    
    # Attempt workflow execution
    result = Thundervine.Executor.run_with_faults(workflow, nodes_to_fail)
    
    {result.status, %{
      total_nodes: length(workflow.nodes),
      failed_nodes: length(nodes_to_fail),
      completed: result.completed_nodes,
      skipped: result.skipped_nodes
    }}
  end
end
```

---

## Domain Module Mapping

### New HC Items for Implementation

| HC ID | Module | Description | Priority | Status |
|-------|--------|-------------|----------|--------|
| **HC-86** | `Thunderbolt.TernaryState` | Ternary arithmetic/logic primitives | P0 | ✅ Done |
| **HC-87** | `Thunderbolt.Thunderbit` v2 | Full ternary state model, MIRAS fields | P0 | ✅ Done |
| **HC-88** | `Thundercore.Clock` | 4-phase Switch/Hold/Release/Relax | P0 | ✅ Done |
| **HC-89** | `Thunderbolt.ReversibleRules` | Toffoli/Feynman gate implementations | P0 | ✅ Done |
| **HC-90** | `Thunderpac.MemoryModule` | MIRAS deep MLP memory | P0 | ✅ Done |
| **HC-91** | `Thunderbolt.SurpriseMetric` | Gradient-based novelty computation | P1 | Not Started |
| **HC-92** | `Thunderpac.TopologicalBraid` | Stable composite structures | P1 | Not Started |
| **HC-93** | `Thunderbolt.FaultTolerance` | TQCA-inspired fault modeling | P1 | Not Started |
| **HC-94** | `Thundercrown.TernaryPolicy` | Ternary policy predicates | P1 | Not Started |
| **HC-95** | `CA.Stepper` + `CA.Runner` v2 | Wire v2 tick to CA engine | P0 | ✅ Done |

### Module Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MODULE DEPENDENCIES                              │
│                                                                     │
│   Thundercore.Clock ────────────────────────────────────────────┐  │
│         │                                                        │  │
│         ▼                                                        │  │
│   ┌─────────────────┐                                           │  │
│   │ Thunderbolt     │                                           │  │
│   │ ├── Thunderbit  │◄──────────────────────────────────────┐  │  │
│   │ ├── TernaryState│                                       │  │  │
│   │ ├── ReversibleRules│◄───┐                               │  │  │
│   │ ├── SurpriseMetric│    │                               │  │  │
│   │ └── FaultTolerance│    │                               │  │  │
│   └─────────────────┘      │                               │  │  │
│         │                   │                               │  │  │
│         ▼                   │                               │  │  │
│   ┌─────────────────┐      │                               │  │  │
│   │ Thunderpac      │      │                               │  │  │
│   │ ├── MemoryModule│◄─────┼───────────────────────────┐  │  │  │
│   │ ├── ReversibleFlow│────┘                           │  │  │  │
│   │ └── TopologicalBraid│                              │  │  │  │
│   └─────────────────┘                                  │  │  │  │
│         │                                              │  │  │  │
│         ▼                                              │  │  │  │
│   ┌─────────────────┐                                  │  │  │  │
│   │ Thundercrown    │                                  │  │  │  │
│   │ └── TernaryPolicy│◄────────────────────────────────┤  │  │  │
│   └─────────────────┘                                  │  │  │  │
│         │                                              │  │  │  │
│         ▼                                              │  │  │  │
│   ┌─────────────────┐                                  │  │  │  │
│   │ Thunderflow     │                                  │  │  │  │
│   │ └── EntropyAnnotation│◄────────────────────────────┘  │  │  │
│   └─────────────────┘                                     │  │  │
│         │                                                 │  │  │
│         ▼                                                 │  │  │
│   ┌─────────────────┐                                     │  │  │
│   │ Thunderwall     │◄────────────────────────────────────┘  │  │
│   │ └── EntropyBoundary│                                     │  │
│   └─────────────────┘                                        │  │
│                                                              │  │
└──────────────────────────────────────────────────────────────┴──┘
```

---

## Implementation Roadmap

### Phase 1: Core Substrate (Week 1-2) ✅ COMPLETE

| Task | Module | Description | Status |
|------|--------|-------------|--------|
| 1.1 | `Thunderbolt.TernaryState` | Ternary arithmetic/logic primitives | ✅ Done |
| 1.2 | `Thunderbolt.Thunderbit` v2 | Full struct with all fields + `ternary_tick/2` | ✅ Done |
| 1.3 | `Thundercore.Clock` | 4-phase GenServer + events + 19 tests | ✅ Done |
| 1.4 | `Thunderbolt.ReversibleRules` | Feynman/Toffoli implementations | ✅ Done |
| 1.5 | `Thunderpac.MemoryModule` | MIRAS deep MLP memory | ✅ Done |
| 1.6 | `CA.Stepper` v2 | `step_ternary_grid/2` + rule_version dispatch + 34 tests | ✅ Done |
| 1.7 | `CA.Runner` v2 | Clock-driven mode via `:hold` phase subscription | ✅ Done |

**Completed**: December 5, 2025

### Phase 2: Memory System (Week 2-3)

| Task | Module | Description | Est. Hours |
|------|--------|-------------|------------|
| 2.1 | `Thunderbolt.SurpriseMetric` | Gradient magnitude computation | 4h |
| 2.2 | `Thunderpac.MemoryModule` | MIRAS deep MLP memory | 12h |
| 2.3 | `Thunderpac.ReversibleFlow` | Undo/rollback infrastructure | 6h |
| 2.4 | Event taxonomy updates | `pac.memory.*` events | 2h |

### Phase 3: Fault Tolerance (Week 3-4)

| Task | Module | Description | Est. Hours |
|------|--------|-------------|------------|
| 3.1 | `Thunderbolt.FaultTolerance` | Dropout simulation | 4h |
| 3.2 | `Thundervine.FaultSimulation` | DAG fault injection | 4h |
| 3.3 | `Thunderpac.TopologicalBraid` | Braid invariants | 8h |
| 3.4 | Test harness | Automated fault testing | 6h |

### Phase 4: Policy Integration (Week 4-5)

| Task | Module | Description | Est. Hours |
|------|--------|-------------|------------|
| 4.1 | `Thundercrown.TernaryPolicy` | Ternary policy predicates | 4h |
| 4.2 | `Thunderflow.EntropyAnnotation` | Processor entropy tags | 4h |
| 4.3 | `Thunderwall.EntropyBoundary` | Decay/archive integration | 6h |
| 4.4 | Integration tests | End-to-end validation | 8h |

### Phase 5: Cerebros Integration (Week 5-6)

| Task | Module | Description | Est. Hours |
|------|--------|-------------|------------|
| 5.1 | TPE search space extension | Ternary/reversible hyperparams | 4h |
| 5.2 | DiffLogic rule updates | Gradient-based CA learning | 8h |
| 5.3 | LoopMonitor integration | Surprise + criticality metrics | 6h |
| 5.4 | End-to-end optimization | Full pipeline validation | 8h |

**Total Estimated Effort**: ~120 hours (3 developer-weeks)

---

## Research Citations

1. **Ternary QCA**: "Ternary Reversible Feynman and Toffoli Gates in TQCA" - TQCA reversible logic
2. **Phase Transitions**: Akin's Phase Transitions research - Ising models and emergent order
3. **Topological Memory**: Kitaev/Sen 0612426v1 - Anyonic stability and braid invariants
4. **DiffLogic CA**: Google Research "Growing Self-Organizing Systems with DiffLogic CA"
5. **Titans Memory**: Google "Titans: Learning to Memorize at Test Time" (2025)
6. **MIRAS**: "MIRAS: Unlocking Expressivity in Deep MLP Memory" (2025)
7. **GNCA**: Mordvintsev et al. "Growing Neural Cellular Automata" (Distill, 2020)
8. **Universal NCA**: Universal Neural Cellular Automata research

---

## Glossary

| Term | Definition |
|------|------------|
| **Thunderbit** | Single voxel cell in 3D CA lattice with ternary state |
| **Ternary State** | Three-valued logic: -1/0/+1 or neg/zero/pos |
| **Reversible Rule** | Bijective CA transition function (no info loss) |
| **MIRAS** | Memory, Attention, Retention, Update framework |
| **Surprise Metric** | Gradient magnitude measuring unexpectedness |
| **Topological Braid** | Stable composite structure with invariant |
| **4-Phase Clock** | Switch→Hold→Release→Relax cycle |
| **PLV** | Phase Locking Value (synchrony metric) |
| **λ̂** | Langton's lambda (chaos/stability indicator) |
| **FTLE** | Finite-Time Lyapunov Exponent |

---

**Document End**

*"The future belongs to those who believe in the beauty of their dreams." - Eleanor Roosevelt*

*But also to those who build virtual Ising machines in Elixir.* 🚀⚡
