# ⚡ HIGH COMMAND ARCHITECTURE SYNTHESIS

> **The Rosetta Stone of Thunderline**
> 
> This document consolidates all High Command strategic directives into a unified technical reference.
> It synthesizes the 3D CA Lattice Communications, Neural CA (NCA) kernels, Latent CA (mesh-agnostic),
> Co-Lex Ordering, and CAT (Cellular Automata Transforms) into a coherent architecture for Thunderline
> and Cerebros integration.

**Document Status**: CANONICAL REFERENCE  
**Created**: November 28, 2025  
**Last Updated**: November 28, 2025  
**Related**: [HC_TODO_SWEEP.md](HC_TODO_SWEEP.md), [THUNDERLINE_MASTER_PLAYBOOK.md](../THUNDERLINE_MASTER_PLAYBOOK.md)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Core Architecture: The 3D CA Lattice](#1-core-architecture-the-3d-ca-lattice)
3. [Thunderbit Formal Definition](#2-thunderbit-formal-definition)
4. [Neural CA (NCA) Kernels](#3-neural-ca-nca-kernels)
5. [Latent CA: Mesh-Agnostic Rules](#4-latent-ca-mesh-agnostic-rules)
6. [Co-Lex Ordering Service](#5-co-lex-ordering-service)
7. [CAT: Cellular Automata Transforms](#6-cat-cellular-automata-transforms)
8. [Cerebros TPE Integration](#7-cerebros-tpe-integration)
9. [Domain Responsibility Matrix](#8-domain-responsibility-matrix)
10. [Implementation Roadmap](#9-implementation-roadmap)
11. [Glossary](#10-glossary)

---

## Executive Summary

### The Vision

Thunderline is building a **holographic, living, self-reconfiguring, spatial communication substrate**:

- **The CA lattice routes** (signaling, presence, topology)
- **WebRTC carries** (high-bandwidth payload)
- **Thunderflow coordinates** (event orchestration)
- **Thundergate secures** (crypto, keys, trust)
- **Thunderbolt/Cerebros optimizes** (ML-driven rule evolution)
- **Thundercore ticks it all** (temporal coherence)
- **Thunderpac personalizes** (PAC awareness)
- **Thunderwall prunes entropy** (decay, GC, archive)

### Key Insight

> **"The CA is the map, not the carrier."**

Instead of pushing bytes through the lattice, we:
1. Use CA for **routing paths**, **trust shapes**, **session-key diffusion**, **relay neighborhoods**, **load balance**
2. Use WebRTC/WebTransport for **actual transport**
3. The CA becomes a **self-adapting SDN (Software-Defined Network) map**

### Unification Moment

Four research threads converge into one architecture:

| Thread | Contribution | Integration Point |
|--------|--------------|-------------------|
| **3D CA Lattice** | Routing oracle, presence fields, secure mesh | Thunderbolt.Thunderbit grid |
| **Neural CA (NCA)** | Trainable local rules, universal compute | Thunderbolt.NCAKernel |
| **Latent CA (LCA)** | Mesh-agnostic, any topology | Thunderbolt.LCAKernel |
| **CAT Transforms** | Orthogonal basis, compression, crypto | Thunderbolt.CATTransform |
| **Co-Lex Ordering** | O(1) state comparison, BWT indexing | Thunderbolt.CoLex service |

---

## 1. Core Architecture: The 3D CA Lattice

### What the CA Lattice Does Well

| Capability | Description |
|------------|-------------|
| **Spatial indexing** | Local-first state propagation |
| **Resilience encoding** | Failure domains as topology |
| **Stability detection** | Stable, metastable, chaotic, oscillatory regions |
| **Route encoding** | Paths as emergent patterns |
| **Trust propagation** | Trust shape diffusion |
| **Session-key diffusion** | Crypto key fragments across voxels |
| **Load balancing** | Relay neighborhood selection |

### What the CA Lattice Does NOT Do

- ❌ Raw data transfer (too slow for bulk)
- ❌ Real-time audio/video (latency constraints)
- ❌ High throughput (update-step bounded)

**Solution**: CA handles signaling/routing, WebRTC handles payload.

### Thunderbit Voxel State Vector

Each Thunderbit (voxel cell) maintains:

```elixir
%Thunderbit{
  coord: {x, y, z},          # 3D position in lattice
  ϕ_phase: float,            # Phase for synchrony (PLV monitoring)
  σ_flow: float,             # Propagatability / connectivity
  λ̂_sensitivity: float,      # Local FTLE (chaos/stability indicator)
  trust_score: float,        # Trust level for routing
  presence_vector: map,      # Each user/PAC has a field they emit
  relay_weight: float,       # Load balancing weight
  key_fragment: binary,      # Crypto key shard
  channel_id: uuid | nil,    # Active channel
  route_tags: bloom_filter   # Destination ID bloom filter
}
```

### Local Decision Rules

Each voxel makes small local decisions:
- "I'm stable enough to relay" (σ_flow > threshold)
- "I have enough trust to bridge two users" (trust_score > threshold)
- "I can maintain ϕ-coherence for a WebRTC handshake" (PLV in band)
- "I should collapse this path due to high λ̂" (chaos detection)
- "I'm under attack → collapse presence field" (security response)

### Presence Field Diffusion

When a device/user/PAC appears:
1. Seeds a **presence wave** through the CA
2. Neighboring Thunderbits become **candidates**
3. Each candidate Thunderbit:
   - Emits event → Thunderflow
   - Thunderflow → picks viable WebRTC peers
   - Thunderlink → creates P2P/MeshRTC circuits
   - Thundergate → handles encryption handshake
   - Thunderbolt → optional ML coherence calculations
   - Thundercrown → ensures authorization

As the user moves/fades:
- CA field updates decay
- WebRTC routes prune automatically

---

## 2. Thunderbit Formal Definition

### Classical CAT Components

From CAT paper (translated to Thunderline):

| Component | Symbol | Description |
|-----------|--------|-------------|
| Lattice | L ⊂ Z^d | Grid dimension d |
| Alphabet | K = {0,1,...,k-1} | Finite states |
| Neighborhood | N ⊂ Z^d | e.g., radius r |
| Local rule | F_R: K^|N| → K | Rule indexed by R |
| Global update | G_R | Apply F_R to all sites |
| Evolution | x_t: L → K | State at time t |
| Basis functions | A(i,k) | CA evolution modes |
| Signal | f(i) = Σ c(k)·A(i,k) | Transform representation |

### Thunderbit Tuple Definition

```elixir
@type thunderbit :: %{
  id: uuid,                    # Unique identifier (PAC-scoped)
  p: {integer, integer, integer},  # 3D position (x,y,z)
  L: lattice,                  # Local lattice this bit governs
  K: alphabet,                 # Finite state alphabet
  N: neighborhood,             # Neighborhood structure (radius r)
  R: rule_id | [rule_id],      # CA rule identifier(s)
  B: boundary_condition,       # :periodic | :fixed | :reflective
  W: window_size,              # Block shape (e.g., 4×4×4)
  T: time_depth,               # CA steps in transform
  s_0_T: [state],              # Raw state evolution
  c: [coefficient]             # CAT transform coefficients
}
```

### Hierarchical Mapping

| Level | Entity | Description |
|-------|--------|-------------|
| **Thunderbit** | Local CA transform cell | Owns small 3D CA block |
| **Thunderbolt** | Bundle of Thunderbits | Union of CAT coefficients + coupling |
| **Thundergrid zone** | Windowed CAT view | Multi-resolution summaries |
| **ThunderDAG** | Compressed history | CAT coefficient snapshots + hashes |

**Conceptual Summary**:
> A Thunderbit is both a **compute cell** (evolving a CA) and a **transform cell** (encoding evolution as orthogonal CAT coefficients).

---

## 3. Neural CA (NCA) Kernels

### What Neural CA Provides

From the "Universal NCA" research:

1. **Local rule, global behavior**: Train update rule; emergence follows
2. **Continuous state**: Hooks directly into Nx/JAX/ONNX
3. **Training recipes**: Multi-step rollouts, multiple tasks, structural priors

### Thunderbolt.NCAKernel Resource

```elixir
defmodule Thunderbolt.NCAKernel do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :state_channels, :integer          # Hidden state dimensions
    attribute :neighborhood_radius, :integer     # Local neighborhood size
    attribute :step_fn_onnx, :binary             # ONNX model blob
    attribute :io_schema, :map                   # Input/output encoding
    attribute :training_program_id, :uuid        # Reference to curriculum
    attribute :stability_profile, :map           # PLV, λ̂ baseline
    timestamps()
  end
end
```

### NCAEngine Module

```elixir
defmodule Thunderbolt.NCAEngine do
  @moduledoc "Neural CA step execution"

  @spec step(NCAKernel.t(), lattice_state, steps :: integer) :: lattice_state
  def step(kernel, state, steps \\ 1) do
    Enum.reduce(1..steps, state, fn _, acc ->
      # Apply ONNX rule over grid via Ortex
      Thunderbolt.OrtexRunner.run(kernel.step_fn_onnx, acc)
    end)
  end

  @spec run_program(program, input_pattern) :: output_pattern
  def run_program(program, input) do
    # Execute multi-step NCA program
  end
end
```

### Training Curriculum (Minimal)

Start with practical subset of tasks:

| Task | Description | Validation |
|------|-------------|------------|
| **Signal propagation** | Pulse at A arrives at B after T steps | Path correctness |
| **Logic gates on wire** | AND, OR, XOR encoded in cells | Output correctness |
| **Read/Write memory** | Bitstring region + read/write heads | Update correctness |
| **Routing/multiplexing** | Two inputs, one output, control-based | Selection accuracy |

### LoopMonitor Integration

When training NCA kernels:
- Don't just optimize "task loss"
- Also regularize toward "good" dynamical regimes:
  - Penalize long PLV > threshold (frozen)
  - Penalize exploding λ̂ (chaos)
  - Reward edge-of-chaos band

---

## 4. Latent CA: Mesh-Agnostic Rules

### Key Innovation

From "Latent Cellular Automata: Learning Mesh-Agnostic Local Rules" (March 2025):

Instead of CA reading direct neighbors:
1. Read **latent embeddings** of nearby cells
2. Embeddings produced by MLP/graph attention/geometric transformer
3. Then compute next local update

**Result**: Works on ANY mesh, ANY topology, ANY geometry.

### Traditional vs Latent CA

```
Traditional CA:
new_state = f(center, neighbors)

Latent CA:
neighbors → encoder → latent descriptors (z)
new_state = f(center_state, z)
```

### Thunderbolt.LCAKernel Resource

```elixir
defmodule Thunderbolt.LCAKernel do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :embedding_model_onnx, :binary    # Neighborhood encoder
    attribute :rule_model_onnx, :binary         # Local rule network
    attribute :k_neighbors, :integer            # kNN graph parameter
    attribute :channels, :integer               # State channels
    attribute :state_shape, :map                # Expected shape
    attribute :compatible_tasks, {:array, :atom} # Task compatibility
    attribute :stability_profile, :map          # PLV, λ̂ baseline
    attribute :training_program_id, :uuid
    timestamps()
  end
end
```

### LCA Engine

```elixir
defmodule Thunderbolt.LCAEngine do
  @moduledoc "Latent CA execution with dynamic topology"

  def step(kernel, state) do
    # 1. Build kNN graph on-the-fly
    knn = build_knn(state, kernel.k_neighbors)
    
    # 2. Compute latent embeddings via encoder
    embeddings = run_embedding(kernel.embedding_model_onnx, state, knn)
    
    # 3. Apply rule network
    run_rule(kernel.rule_model_onnx, state, embeddings)
  end

  def build_knn(state, k) do
    # k-nearest neighbor graph computation
  end
end
```

### Why LCA Matters

This is the **missing piece** for Thunderbolt evolution from "2.5D grid" to **4D omni-layer automata**:

| Property | Benefit |
|----------|---------|
| Dynamic connectivity | Per-tick rewiring |
| Self-organizing networks | Thunderbit networks adapt |
| Shape growth | Thunderpac bodyplans |
| Self-healing | Distributed process recovery |
| Swarm logic | PAC multi-step reasoning |

---

## 5. Co-Lex Ordering Service

### Problem Statement

For large NFAs (automata), we need:
- **O(n) space** storage of state ordering
- **O(1) time** comparison: "is state u ≤ state v?"

### Solution: Maximum Co-Lex Partial Order

From SODA/ESA research on forward-stable NFAs:

1. **Co-lex order (≤)**: States ordered by co-lex order of reaching strings
2. **Co-lex extension (≤̄)**: Total order containing partial order
3. **Infimum/supremum walks**: Lex-smallest/largest paths to each state
4. **Conflict depths (φ, ψ)**: How far along walks to hit conflicts

### Thunderbolt.CoLex Module

```elixir
defmodule Thunderbolt.CoLex do
  @moduledoc """
  Co-lex ordering service for automata states.
  Provides O(1) comparison with O(n) storage.
  """

  @spec build_order(automaton) :: order_handle
  def build_order(automaton) do
    # 1. Forward-stable reduction (Paige-Tarjan)
    stable = forward_stable_reduce(automaton)
    
    # 2. Co-lex extension (Becker et al. Algorithm 1)
    extension = compute_extension(stable)
    
    # 3. Infimum/supremum graphs + Forward Visit
    {inf_graph, sup_graph} = build_inf_sup_graphs(stable, extension)
    
    # 4. Conflict depths
    {phi, psi} = compute_conflict_depths(stable, inf_graph, sup_graph)
    
    %OrderHandle{
      extension: extension,
      inf_graph: inf_graph,
      sup_graph: sup_graph,
      phi: phi,
      psi: psi
    }
  end

  @spec compare(order_handle, state_u, state_v) :: boolean
  def compare(handle, u, v) when u == v, do: true
  def compare(handle, u, v) do
    # Decision tree from paper (Fig. 1 / Section 4)
    # O(1) time using precomputed structures
  end

  @spec rank(order_handle, state) :: integer
  def rank(handle, state) do
    # Position in total order
  end
end
```

### Use Cases

| Domain | Application |
|--------|-------------|
| **Thunderbolt** | Canonical numbering for Thunderbit/CA state graphs |
| **Thundervine** | Graph-BWT index over world DAG |
| **Thunderblock** | Compressed storage for PAC histories |
| **Cerebros** | Search space as automaton, TPE stratification |

---

## 6. CAT: Cellular Automata Transforms

### What CAT Provides

From "Data Compression and Encryption Using Cellular Automata Transforms":

1. **Transform basis**: Like Fourier/DCT/Wavelet, but using CA evolution
2. **Orthogonal families**: Basis functions from rule evolution
3. **Compression**: Coefficients compress information
4. **Encryption**: Avalanche property (1-bit change → massive ciphertext change)

### Signal Representation

```
f(i) = Σ c(k) · A(i,k)

Where:
- f(i): Signal at site i
- A(i,k): Basis function at site i for mode k
- c(k): Transform coefficients
```

### CAT Basis Groups

| Group | Characteristics | Use Case |
|-------|-----------------|----------|
| **Group I** | Low-frequency, DC-like | Baseline, persistence |
| **Group II-IV** | Edge detection, high-freq | Activity, changes |
| **Sparse subset** | Selected coefficients | Compression |

### Thunderbolt.CATTransform Module

```elixir
defmodule Thunderbolt.CATTransform do
  @moduledoc """
  Cellular Automata Transform for signal representation,
  compression, and encryption.
  """

  defstruct [
    :rule_id,           # CA rule for basis generation
    :dims,              # 1D, 2D, or 3D
    :alphabet_size,     # k states
    :radius,            # Neighborhood radius r
    :window_shape,      # e.g., {4, 4, 4}
    :time_depth,        # T steps
    :basis_type,        # :orthogonal | :semi_orthogonal | :non_orthogonal
    :boundary_condition # :periodic | :fixed_zero | :reflective
  ]

  @spec forward(transform, signal) :: coefficients
  def forward(transform, signal) do
    # Generate basis functions from CA evolution
    basis = generate_basis(transform)
    # Project signal onto basis
    project(signal, basis)
  end

  @spec inverse(transform, coefficients) :: signal
  def inverse(transform, coefficients) do
    # Reconstruct signal from coefficients
    basis = generate_basis(transform)
    reconstruct(coefficients, basis)
  end

  @spec compress(transform, signal, opts) :: {coefficients, ratio}
  def compress(transform, signal, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.01)
    coeffs = forward(transform, signal)
    # Keep only significant coefficients
    sparse = sparsify(coeffs, threshold)
    {sparse, compute_ratio(coeffs, sparse)}
  end

  @spec encrypt(transform, plaintext, key) :: ciphertext
  def encrypt(transform, plaintext, key) do
    # CAT-based encryption with avalanche property
  end
end
```

### Integration Points

| Integration | Description |
|-------------|-------------|
| **Thunderbit state** | Encode as CAT coefficients, not raw values |
| **Thundergrid zones** | Windowed CAT for multi-resolution |
| **ThunderDAG** | CAT snapshots for compressed history |
| **Thundersec** | CAT encryption layer |
| **SNN mode** | CAT = discrete-event compatible |
| **Analog prep** | CAT basis → analog-friendly operations |

---

## 7. Cerebros TPE Integration

### Hyperparameter Vector

For a given PAC/Thunderbolt region:

```elixir
θ = {θ_CAT, θ_wiring, θ_model}
```

#### θ_CAT: CAT Basis Hyperparameters

| Parameter | Type | Range/Values |
|-----------|------|--------------|
| `rule_id` | integer/categorical | 0-255 (ECA) or catalog |
| `dims` | categorical | {1, 2, 3} |
| `alphabet_size` | categorical | {2, 3, 4, 8} |
| `radius` | categorical | {1, 2, 3} |
| `window_shape` | categorical | {(4,4,4), (8,8,8), ...} |
| `time_depth` | categorical | {4, 8, 16} |
| `basis_type` | categorical | {:orthogonal, :semi, :non} |
| `boundary_condition` | categorical | {:periodic, :fixed_zero, :reflective} |
| `group_selection` | categorical | {:low_freq, :edge, :sparse} |

#### θ_wiring: Thunderbit Wiring Hyperparameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `lattice_connectivity` | categorical | 6/18/26-neighbor in 3D |
| `coupling_strength` | continuous | Inter-Thunderbit influence |
| `update_schedule` | categorical | {:sync, :staggered, :random_scan} |
| `zone_overlap` | continuous | CAT window overlap % |

#### θ_model: Model Hyperparameters

Standard Cerebros/TPE knobs, but input layer now consumes CAT coefficients.

### TPE Trial Flow

```
1. Build CAT basis from θ_CAT
   - Construct rule R, window W, time depth T, boundary B
   - Precompute basis functions A(i,k)

2. Encode Thunderline data into CAT coefficients
   - For each Thunderbit region:
     - Collect raw state evolution s_0:T
     - Compute coefficients c_θ
   - Stream via Thunderflow → Thunderblock

3. Build model in Cerebros
   - Input layer accepts CAT feature vectors
   - Middle/output layers from θ_model
   - Lives in Python land

4. Train/evaluate
   - Task loss, accuracy, etc.
   - CAT-aware metrics (optional):
     - Compression ratio
     - Reconstruction error
     - PLV/λ̂ health
     - Analog-friendliness

5. Collapse to scalar objective y
   y = α·task_loss + β·reconstruction_error + γ·(1-compression_ratio) + δ·instability_penalty

6. Feed (θ, y) back to TPE
   - Update l(θ), g(θ) for good/bad regions
   - Propose new CAT parametrizations
```

### Event Protocol

```elixir
# Elixir → Python
%PACComputeRequest{
  task_id: uuid,
  agent_id: pac_id,
  world_state: %{grid_size: [32,32,32], features: %{...}},
  metrics: %{plv: 0.85, entropy: 3.2, lambda_hat: 0.47},
  cat_coefficients: binary,  # CAT-encoded state
  timestamp: unix_time,
  trace_context: %{trace_id: "...", span_id: "..."}
}

# Python → Elixir
%PACComputeResponse{
  task_id: uuid,
  status: :success,
  updated_params: %{rule_weights: [...], mutation_rate: 0.05},
  metrics: %{loss: 0.12, improvement: 0.05, tpe_trial_id: 42},
  timestamp: unix_time,
  trace_context: %{...}
}
```

---

## 8. Domain Responsibility Matrix

### Per-Domain Roles in Lattice Architecture

| Domain | Lattice Comms Role | CAT Role | NCA/LCA Role |
|--------|-------------------|----------|--------------|
| **Thundercore** | Universe clock, tick alignment | - | - |
| **Thunderpac** | PAC-owned channels, presence signatures | Per-PAC basis selection | PAC cognitive substrate |
| **Thundercrown** | Authorization per voxel, session policy | Governance of basis params | Policy on kernel selection |
| **Thunderbolt** | CA rules, Thunderbit structs, stepper | Transform execution | NCA/LCA kernel hosting |
| **Thundergate** | Crypto: key exchange, mTLS/DTLS | CAT encryption layer | - |
| **Thunderblock** | Persistent log, zone snapshots | CAT coefficient storage | Kernel persistence |
| **Thunderflow** | Events: ca.channel.*, ca.presence.* | Transform events | Training events |
| **Thundergrid** | API: send_message/2, GraphQL | Windowed CAT queries | Kernel queries |
| **Thundervine** | Channel graph (CARoute edges) | DAG of CAT transforms | NCA program DAGs |
| **Thunderprism** | 3D visualization, path painting | Basis visualization | Kernel studio |
| **Thunderlink** | WebRTC circuits, ICE negotiation | - | - |
| **Thunderwall** | Boundary damping, channel decay | Old CAT state decay | Kernel pruning |

### Cross-Domain Layers

| Layer | Domains | Responsibility |
|-------|---------|----------------|
| **Lattice Layer** | Bolt × Link × Gate | CA routing + WebRTC circuits + geometric crypto |
| **Compute Layer** | Bolt × Flow | PAC task routing, criticality optimization |
| **Transform Layer** | Bolt × Block | CAT encoding, coefficient storage |

---

## 9. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

**HC-60: Thunderbit Resource & Stepper**
- [ ] `Thunderbolt.Thunderbit` struct with state vector
- [ ] `Thunderbolt.CA.Stepper` basic CA step execution
- [ ] `Thunderbolt.CA.Neighborhood` 3D neighborhood computation
- [ ] Unit tests: state evolution, neighborhood

**HC-61: CAT Transform Primitives**
- [ ] `Thunderbolt.CATTransform` module
- [ ] Basis function generation
- [ ] Forward/inverse transform
- [ ] Unit tests: orthogonality, reconstruction

### Phase 2: NCA/LCA Kernels (Weeks 3-4)

**HC-62: NCA Kernel Infrastructure**
- [ ] `Thunderbolt.NCAKernel` Ash resource
- [ ] `Thunderbolt.NCAEngine.step/3`
- [ ] ONNX integration via Ortex
- [ ] Training curriculum (signal propagation task)
- [ ] Telemetry: `[:thunderline, :bolt, :nca, :*]`

**HC-63: LCA Kernel Infrastructure**
- [ ] `Thunderbolt.LCAKernel` Ash resource
- [ ] `Thunderbolt.LCAEngine.step/2`
- [ ] kNN graph construction
- [ ] Embedding network execution
- [ ] Unit tests: mesh-agnostic operation

### Phase 3: LoopMonitor Integration (Week 5)

**HC-40: Criticality Metrics** (existing)
- [ ] PLV aggregator
- [ ] Permutation entropy
- [ ] Langton's λ̂
- [ ] Lyapunov exponent estimation
- [ ] `bolt.ca.metrics.snapshot` events

### Phase 4: Cerebros TPE Bridge (Weeks 6-7)

**HC-64: TPE Search Space Extension**
- [ ] CAT hyperparameter definitions
- [ ] NCA/LCA hyperparameter definitions
- [ ] Cerebros bridge extensions
- [ ] Trial lifecycle events

**HC-65: Training Loop Integration**
- [ ] Multi-task curriculum
- [ ] LoopMonitor as auxiliary loss
- [ ] Kernel registration on success
- [ ] Telemetry dashboards

### Phase 5: Co-Lex Service (Weeks 8-9)

**HC-66: Co-Lex Ordering**
- [ ] Forward-stable reduction
- [ ] Co-lex extension computation
- [ ] Infimum/supremum graphs
- [ ] Conflict depth arrays
- [ ] O(1) comparator
- [ ] Integration with Thundervine DAG

### Phase 6: Production Hardening (Weeks 10-12)

**HC-67: WebRTC Circuit Integration**
- [ ] CA signaling → WebRTC establishment
- [ ] ICE over CA channel
- [ ] Circuit manager lifecycle
- [ ] Fallback/rerouting

**HC-68: Security Layer**
- [ ] CAT encryption
- [ ] Key fragment distribution
- [ ] Per-hop obfuscation
- [ ] Geometric secrecy validation

---

## 10. Glossary

| Term | Definition |
|------|------------|
| **CA** | Cellular Automaton - discrete computation on a lattice |
| **CAT** | Cellular Automata Transform - signal representation using CA basis |
| **NCA** | Neural CA - CA with learned neural network update rules |
| **LCA** | Latent CA - CA with latent embeddings for mesh-agnostic rules |
| **Thunderbit** | Single voxel cell in the 3D CA lattice |
| **Thunderbolt** | Bundle of Thunderbits forming functional cluster |
| **PLV** | Phase-Locking Value - measure of synchrony |
| **λ̂** | Langton's lambda - criticality indicator |
| **FTLE** | Finite-Time Lyapunov Exponent - chaos measure |
| **Co-lex order** | Co-lexicographic order on automaton states |
| **TPE** | Tree-structured Parzen Estimator - Bayesian optimization |
| **Presence field** | Diffused signal indicating user/PAC location |
| **Routing oracle** | CA as SDN map for path selection |

---

## References

### Research Papers

1. **Universal NCA**: "You can treat a continuous neural CA as a universal compute substrate"
2. **Latent CA (arXiv 2503.07061)**: "Mesh-agnostic local rules via latent embeddings"
3. **Co-Lex Ordering (SODA/ESA)**: "O(n) space, O(1) time state comparison for NFAs"
4. **CAT**: "Data Compression and Encryption Using Cellular Automata Transforms"
5. **DiffLogic CA**: "Differentiable logic for cellular automata" (Google Research)

### Internal Documents

- [THUNDERLINE_MASTER_PLAYBOOK.md](../THUNDERLINE_MASTER_PLAYBOOK.md) - Master architecture reference
- [HC_TODO_SWEEP.md](HC_TODO_SWEEP.md) - Technical debt tracker
- [EVENT_TAXONOMY.md](EVENT_TAXONOMY.md) - Event naming conventions
- [ERROR_CLASSES.md](reference/ERROR_CLASSES.md) - Error classification

---

## Appendix A: Thunderbit State Struct (Full)

```elixir
defmodule Thunderline.Thunderbolt.Thunderbit do
  @moduledoc """
  Single voxel cell in the 3D CA lattice.
  
  Combines:
  - Classical CA state
  - CAT transform coefficients
  - Routing/presence metadata
  - Security key fragments
  """

  @enforce_keys [:id, :coord]
  defstruct [
    # Identity
    :id,                    # UUID
    :coord,                 # {x, y, z}
    
    # CA State
    :state,                 # Current CA state (Nx tensor or bitfield)
    :rule_id,               # Active CA rule
    :neighborhood,          # Precomputed neighbors
    
    # Dynamics metrics
    :phi_phase,             # Phase for PLV
    :sigma_flow,            # Propagatability
    :lambda_sensitivity,    # Local FTLE
    
    # Routing
    :trust_score,           # Trust level
    :presence_vector,       # PAC presence fields
    :relay_weight,          # Load balancing
    :route_tags,            # Bloom filter of destinations
    
    # Channel
    :channel_id,            # Active channel (nil if idle)
    :key_id,                # Thundergate session key ref
    
    # CAT Transform
    :cat_config,            # CAT transform configuration
    :cat_coefficients,      # Latest transform coefficients
    
    # Timestamps
    :last_tick,             # Last update tick
    :created_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
    id: Ecto.UUID.t(),
    coord: {integer, integer, integer},
    state: term,
    rule_id: atom | integer,
    neighborhood: [{integer, integer, integer}],
    phi_phase: float,
    sigma_flow: float,
    lambda_sensitivity: float,
    trust_score: float,
    presence_vector: map,
    relay_weight: float,
    route_tags: term,
    channel_id: Ecto.UUID.t() | nil,
    key_id: String.t() | nil,
    cat_config: map,
    cat_coefficients: binary,
    last_tick: non_neg_integer,
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
end
```

---

## Appendix B: Event Taxonomy Additions

### CA/Lattice Events

```elixir
# Presence
"ca.presence.beacon"           # PAC presence broadcast
"ca.presence.wave.started"     # Presence wave initiated
"ca.presence.wave.converged"   # Stable presence field

# Channels
"ca.channel.requested"         # Channel establishment request
"ca.channel.established"       # Channel ready
"ca.channel.degraded"          # Path quality degraded
"ca.channel.rerouted"          # Path rerouted
"ca.channel.teardown"          # Channel closing

# Metrics
"ca.metrics.tick"              # Per-tick metrics
"ca.metrics.criticality"       # PLV/λ̂/entropy snapshot

# NCA/LCA
"nca.kernel.training.started"  # Kernel training begun
"nca.kernel.training.completed"# Kernel ready
"nca.kernel.deployed"          # Kernel in production
"lca.topology.rebuilt"         # kNN graph updated

# CAT
"cat.transform.computed"       # Transform completed
"cat.coefficients.stored"      # Coefficients persisted
"cat.encryption.applied"       # CAT encryption used
```

---

*This document is the canonical reference for Thunderline's CA/NCA/LCA/CAT architecture.*
*Last updated: November 28, 2025*
