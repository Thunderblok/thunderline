# ThunderDSL Language Specification

## Overview

ThunderDSL is a domain-specific language for expressing dataplane-deployable machine learning computations. It combines:

- **pcube-style deterministic macro expansion** for safety and predictability
- **Pegasus-style execution primitives** (Partition/Map/SumReduce) for hardware constraints
- **Fuzzy-index tree compression** for table size reduction
- **Multi-backend code generation** (Elixir/Nx, eBPF/XDP, P4)

## Design Principles

1. **Deterministic Execution**: No runtime surprises, all behavior known at compile-time
2. **Hardware-Aware**: Maps naturally to match-action tables (MAT) in dataplanes
3. **Provenance**: Every compilation tracked, every artifact signed
4. **Performance**: Targets microsecond latency for inference

## Language Constructs

### 1. Program Declaration

```elixir
defthunder MyMLModel do
  @version "1.0.0"
  @target [:nx, :ebpf, :p4]
  @author "team@thunderline.dev"
  
  # Program body
end
```

**Attributes**:
- `@version` - Semantic version string (required)
- `@target` - List of compilation targets (required)
- `@author` - Attribution (optional)
- `@description` - Human-readable purpose (optional)

---

### 2. Input/Output Declarations

```elixir
input :features, shape: {32}, dtype: :f32
input :weights, shape: {32, 10}, dtype: :f32

output :predictions, shape: {10}, dtype: :f32
```

**Supported Types**:
- `:f32`, `:f64` - Floating point
- `:s8`, `:s16`, `:s32`, `:s64` - Signed integers
- `:u8`, `:u16`, `:u32`, `:u64` - Unsigned integers

**Shape**:
- Tuple of integers `{d1, d2, ...}`
- Variable dimensions not supported in v1.0

---

### 3. @thunder_for - Sequential Iteration

```elixir
@thunder_for i <- 0..31 do
  # Sequential computation
  # i is compile-time constant (unrolled)
end
```

**Semantics**:
- Macro that unrolls to sequential operations
- Loop variable `i` is compile-time constant
- No dynamic loops (hardware constraint)

**Lowering**:
```
@thunder_for i <- 0..3 do
  x[i] = x[i] + 1
end

# Expands to:
x[0] = x[0] + 1
x[1] = x[1] + 1
x[2] = x[2] + 1
x[3] = x[3] + 1

# Lowers to Pegasus primitives:
Partition(x, stride: 1)
Map(lambda elem: elem + 1)
```

---

### 4. @thunder_sum - Element-wise Sum

```elixir
@thunder_sum [tensor_a, tensor_b, tensor_c] do
  # Element-wise sum of all tensors
end
```

**Semantics**:
- Reduces list of tensors to single tensor
- Element-wise addition (broadcasting not supported in v1.0)

**Lowering**:
```
@thunder_sum [a, b, c]

# Lowers to:
SumReduce([a, b, c], axis: :all)
```

---

### 5. @thunder_sync - Synchronization Barrier

```elixir
@thunder_sync do
  # All prior operations must complete before continuing
end
```

**Semantics**:
- Ensures all prior operations complete
- Memory fence / barrier
- Required between pipeline stages in hardware

**Lowering**:
```
@thunder_sync

# Lowers to:
Barrier(scope: :global)
```

---

### 6. @thunder_matmul - Matrix Multiplication

```elixir
@thunder_matmul features, weights do
  # Result = features @ weights
end
```

**Semantics**:
- Matrix multiplication (2D only in v1.0)
- Shape checking at compile-time

**Lowering**:
```
@thunder_matmul features, weights

# Lowers to:
Partition(features, by: :row)
Partition(weights, by: :column)
Map(dot_product_via_fuzzy_index)
SumReduce(axis: :inner)
```

---

### 7. @thunder_activate - Activation Function

```elixir
@thunder_activate :relu, logits do
  # ReLU activation
end
```

**Supported Activations**:
- `:relu` - max(0, x)
- `:sigmoid` - 1 / (1 + exp(-x))
- `:tanh` - tanh(x)
- `:softmax` - exp(x) / sum(exp(x))

**Lowering**:
```
@thunder_activate :relu, x

# Lowers to:
Map(fuzzy_index_lookup(:relu_table, x))
```

Activation functions use pre-computed lookup tables with fuzzy-index compression for speed.

---

## Compilation Pipeline

### Stage 1: Parse (Source → AST)

```elixir
"@thunder_for i <- 0..3 do ... end"
  |
  v
%AST.For{
  var: :i,
  range: %Range{first: 0, last: 3},
  body: [...]
}
```

**Parser**: NimbleParsec-based.

---

### Stage 2: Expand (AST → Expanded AST)

```elixir
%AST.For{var: :i, range: 0..3, body: [...]}
  |
  v (pcube-style macro expansion)
  v
[
  %AST.Assign{target: "x[0]", value: ...},
  %AST.Assign{target: "x[1]", value: ...},
  %AST.Assign{target: "x[2]", value: ...},
  %AST.Assign{target: "x[3]", value: ...}
]
```

**Expander**: Pattern match + rewrite rules.

---

### Stage 3: Lower (Expanded AST → Pegasus Primitives IR)

```elixir
[%AST.Assign{...}, %AST.Assign{...}, ...]
  |
  v
[
  %IR.Partition{input: :x, stride: 1},
  %IR.Map{fn: :increment, table: nil},
  %IR.SumReduce{axis: :all}
]
```

**Lowerer**: Maps AST nodes to Partition/Map/SumReduce.

---

### Stage 4: Generate Fuzzy Index Trees

```elixir
%IR.Map{fn: :relu, table: nil}
  |
  v (train on sample data)
  v
%FuzzyTree{
  splits: [
    {threshold: 0.0, left: :negative_branch, right: :positive_branch}
  ],
  centroids: [
    {range: :negative_branch, value: 0.0},
    {range: :positive_branch, value: :identity}
  ]
}
```

**Algorithm**: Greedy SSE minimization (decision tree for continuous functions).

---

### Stage 5: Primitive Fusion (IR Optimization)

```elixir
[
  %IR.Map{fn: :normalize},
  %IR.Map{fn: :scale},
  %IR.SumReduce{axis: :all}
]
  |
  v (merge consecutive Maps)
  v
[
  %IR.Map{fn: :normalize_and_scale},  # Fused!
  %IR.SumReduce{axis: :all}
]
```

**Fusion Rules**:
- Consecutive Maps → Single Map (if no dependency)
- SumReduce can move past linear Maps
- Partition cannot be fused (structural operation)

---

### Stage 6: Codegen (IR → Target Code)

#### Target: Elixir/Nx

```elixir
%IR.Map{fn: :relu, table: fuzzy_tree}
  |
  v
defn relu(x) do
  Nx.max(0, x)
end
```

**Backend**: Pure Nx.defn functions.

---

#### Target: eBPF/XDP

```elixir
%IR.Map{fn: :relu, table: fuzzy_tree}
  |
  v
BPF_MAP_DEF(relu_table, BPF_MAP_TYPE_HASH, key_t, val_t, 1024);

static __always_inline u32 fuzzy_lookup(u32 input) {
  // Binary search through fuzzy index tree
  if (input < 0) return 0;
  return bpf_map_lookup_elem(&relu_table, &input);
}
```

**Backend**: C code compiled with clang to BPF bytecode.

---

#### Target: P4

```elixir
%IR.Map{fn: :relu, table: fuzzy_tree}
  |
  v
table relu_table {
  key = {
    meta.input: range;
  }
  actions = {
    set_output;
  }
  size = 1024;
}

action set_output(bit<32> value) {
  meta.output = value;
}
```

**Backend**: P4_16 source compiled with p4c.

---

### Stage 7: Package (Artifacts + SBOM + Signature)

```elixir
%Build{
  program_id: "uuid",
  ir_hash: "sha256:...",
  artifacts: %{
    nx: "/cas/abc123.nx",
    ebpf: "/cas/def456.o",
    p4: "/cas/ghi789.p4"
  },
  sbom: %{
    dependencies: ["nx", "libbpf", "p4c"],
    licenses: ["MIT", "GPL-2.0", "Apache-2.0"]
  },
  signature: "ed25519:..."
}
```

**Storage**: Content-addressed storage (CAS) for immutability.

---

## Example Program

```elixir
defthunder ImageClassifier do
  @version "1.0.0"
  @target [:nx, :ebpf]
  @description "Classify 28x28 grayscale images"
  
  input :image, shape: {784}, dtype: :u8
  input :weights_l1, shape: {784, 128}, dtype: :f32
  input :weights_l2, shape: {128, 10}, dtype: :f32
  
  output :probabilities, shape: {10}, dtype: :f32
  
  def forward do
    # Normalize input to [0, 1]
    normalized = @thunder_for i <- 0..783 do
      image[i] / 255.0
    end
    
    # Layer 1: FC + ReLU
    @thunder_sync
    hidden = @thunder_matmul normalized, weights_l1
    activated = @thunder_activate :relu, hidden
    
    # Layer 2: FC + Softmax
    @thunder_sync
    logits = @thunder_matmul activated, weights_l2
    output = @thunder_activate :softmax, logits
    
    output
  end
end
```

**Compilation**:
```bash
$ thunderforge compile image_classifier.td --target nx,ebpf
✓ Parsed (12 nodes)
✓ Expanded (784 unrolled loops + 6 operations)
✓ Lowered (18 primitives: 8 Partition, 6 Map, 4 SumReduce)
✓ Generated fuzzy trees (2 tables, compression: 95%)
✓ Fused primitives (18 → 12 primitives, 33% reduction)
✓ Codegen: nx (784 lines), ebpf (1204 lines)
✓ Packaged: build_abc123

Build ID: abc123
Artifacts:
  - nx: /cas/abc123.nx (12 KB)
  - ebpf: /cas/abc123.o (48 KB)
```

---

## Fuzzy Index Tree Algorithm

### Problem

**Input**: Continuous function `f(x)`, sample points `X`

**Output**: Tree that approximates `f` with minimal table size

### Algorithm (Greedy SSE Minimization)

```
1. Start with root node containing all sample points
2. For each node:
   a. Find threshold `t` that minimizes SSE:
      SSE(t) = Σ(x < t) (f(x) - μ_left)² + Σ(x ≥ t) (f(x) - μ_right)²
   b. Split node at threshold t
   c. Store centroids (μ_left, μ_right)
3. Repeat until:
   - Max depth reached, OR
   - SSE improvement < threshold, OR
   - Node has < min_samples
4. Prune tree (remove redundant splits)
```

### Example: ReLU(x) = max(0, x)

```
Sample points: [-2, -1, 0, 1, 2]
Function values: [0, 0, 0, 1, 2]

Tree:
         [threshold: 0.0]
        /                \
  [centroid: 0.0]    [threshold: 1.5]
                    /              \
              [centroid: 1.0]  [centroid: 2.0]

Compression: 5 points → 3 centroids (40% reduction)
Accuracy: MAE = 0.0 (exact for ReLU)
```

For complex functions (sigmoid, tanh), accuracy ≈ 98-99% with 10-20 centroids.

---

## Primitive Fusion Rules

### Rule 1: Consecutive Maps Fusion

```
Map(f) → Map(g) → Map(h)
  ===becomes===>
Map(h ∘ g ∘ f)  # Function composition
```

**Benefit**: Reduces pipeline stages.

---

### Rule 2: SumReduce Reordering

```
Map(f) → SumReduce(axis)
  ===becomes===> (if f is linear)
SumReduce(axis) → Map(f)
```

**Benefit**: May enable further Map fusion.

---

### Rule 3: Partition Hoisting

```
Partition(A) → Map(f) → Partition(B)
  ===becomes===
Partition(A ∪ B) → Map(f)
```

**Benefit**: Single partitioning pass.

---

## Type System

### Tensor Types

```
Tensor(shape, dtype)
  where shape = {d1, d2, ...}  # Compile-time known
        dtype ∈ {:f32, :f64, :s8, :u8, ...}
```

**Typing Rules**:

1. **Addition**: `Tensor(S, T) + Tensor(S, T) → Tensor(S, T)`
2. **Matmul**: `Tensor({M, K}, T) @ Tensor({K, N}, T) → Tensor({M, N}, T)`
3. **Map**: `Map(Tensor(S, T), f: T → T) → Tensor(S, T)`
4. **SumReduce**: `SumReduce(Tensor({D1, D2, ...}), axis: i) → Tensor({D1, ..., D_{i-1}, D_{i+1}, ...})`

---

## Runtime Execution Model

### Elixir/Nx Runtime

```elixir
# Compiled program module
defmodule ImageClassifier.NxRuntime do
  import Nx.Defn
  
  defn forward(image, weights_l1, weights_l2) do
    # Generated Nx.defn code
  end
end

# Execution
result = ImageClassifier.NxRuntime.forward(
  Nx.tensor(image),
  Nx.tensor(weights_l1),
  Nx.tensor(weights_l2)
)
```

**Performance**: 1-10ms on CPU, 100-1000μs on GPU.

---

### eBPF/XDP Runtime

```c
// Compiled BPF program
SEC("xdp")
int classify_packet(struct xdp_md *ctx) {
  // Extract features from packet
  u8 features[784];
  extract_features(ctx, features);
  
  // Lookup via fuzzy index
  u32 class = classify(features);
  
  // Set packet mark
  ctx->mark = class;
  return XDP_PASS;
}
```

**Performance**: 10-100μs per packet.

---

## Security Considerations

1. **Deterministic Execution**: No dynamic dispatch, all code paths known
2. **Bounded Resources**: Fixed memory, no dynamic allocation
3. **Signed Artifacts**: All builds cryptographically signed
4. **Audit Trail**: Full provenance in Thundervine
5. **Sandbox Execution**: eBPF verifier, P4 compiler checks

---

## Future Extensions (v2.0+)

- [ ] Dynamic shapes (runtime-determined dimensions)
- [ ] Control flow (if/else within loops)
- [ ] Custom operator definitions
- [ ] Multi-device heterogeneous execution
- [ ] Automatic differentiation (training support)
- [ ] Quantization (INT8, INT4)

---

## References

- [Pegasus Paper](https://www.usenix.org/conference/nsdi20/presentation/zhang-yi) - Match-action table ML
- [pcube Paper](https://dl.acm.org/doi/10.1145/3341301.3359646) - Deterministic probabilistic programming
- [Prism Topology](architecture/PRISM_TOPOLOGY.md)
- [Thunderforge Domain](domains/thunderforge/OVERVIEW.md)
