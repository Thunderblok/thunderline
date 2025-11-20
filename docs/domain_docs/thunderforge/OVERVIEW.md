# Thunderforge Domain Overview

**Vertex Position**: Control Plane Ring, Position 3

**Purpose**: Compiler & Toolchain domain - transforms ThunderDSL programs into deployable artifacts for multiple backends (Nx, eBPF, P4).

## Charter

Thunderforge is responsible for the **complete compilation pipeline** from human-written ThunderDSL source code to hardware-deployable machine learning inference programs. It embodies the vision of "write once, deploy everywhere" - from CPU to GPU to network dataplane.

## Core Responsibilities

### 1. **DSL Compilation**
- Parse ThunderDSL source code
- Expand pcube-style deterministic macros
- Lower to Pegasus primitives (Partition/Map/SumReduce)
- Type checking and validation

### 2. **IR Optimization**
- Primitive fusion pass (merge Maps, reorder operations)
- Dead code elimination
- Constant folding
- Resource requirement analysis

### 3. **Fuzzy Index Generation**
- Train decision trees for activation functions
- Greedy SSE minimization algorithm
- Compression ratio tuning
- Accuracy validation

### 4. **Multi-Backend Codegen**
- **Nx Backend**: Pure Elixir/Nx.defn functions
- **eBPF/XDP Backend**: C code → BPF bytecode
- **P4 Backend**: P4_16 match-action tables

### 5. **Artifact Management**
- Content-addressed storage (CAS)
- SBOM (Software Bill of Materials) generation
- Cryptographic signing with Ed25519
- Version tracking and provenance

### 6. **Build Orchestration**
- Parallel compilation for multiple targets
- Incremental builds (only recompile changed)
- Build caching
- Compilation telemetry

## Ash Resources

### Program
```elixir
defmodule Thunderline.Thunderforge.Program do
  use Ash.Resource,
    domain: Thunderline.Thunderforge,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :version, :string, allow_nil?: false
    attribute :source_dsl, :string, allow_nil?: false  # ThunderDSL code
    attribute :target_matrix, {:array, :string}        # ["nx", "ebpf", "p4"]
    attribute :author, :string
    attribute :description, :string
    create_timestamp :created_at
  end
  
  relationships do
    has_many :builds, Thunderline.Thunderforge.Build
    belongs_to :topology, Thunderline.Thundergrid.Topology
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    create :compile do
      argument :targets, {:array, :string}, allow_nil?: false
      change CompileProgram
    end
  end
end
```

### Build
```elixir
defmodule Thunderline.Thunderforge.Build do
  use Ash.Resource,
    domain: Thunderline.Thunderforge,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :ir_hash, :string, allow_nil?: false      # SHA256 of IR
    attribute :artifacts, :map                          # {target: cas_path}
    attribute :sbom, :map                               # Dependencies
    attribute :signature, :string                       # Ed25519 signature
    attribute :compilation_time_ms, :integer
    attribute :primitive_count, :integer                # Pre-fusion
    attribute :fused_primitive_count, :integer          # Post-fusion
    attribute :status, :atom do
      constraints one_of: [:pending, :compiling, :success, :failed]
      default :pending
    end
    create_timestamp :compiled_at
  end
  
  relationships do
    belongs_to :program, Thunderline.Thunderforge.Program
    has_many :deployments, Thunderline.Thunderforge.Deployment
    has_many :tables, Thunderline.Thunderforge.Table
  end
end
```

### Table
```elixir
defmodule Thunderline.Thunderforge.Table do
  use Ash.Resource,
    domain: Thunderline.Thunderforge,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false         # e.g., "relu_table"
    attribute :function_type, :atom                     # :relu, :sigmoid, etc.
    attribute :fuzzy_tree, :map                         # Tree structure
    attribute :centroids, {:array, :map}                # {range, value}
    attribute :compression_ratio, :float                # Original/compressed
    attribute :accuracy_mae, :float                     # Mean absolute error
    attribute :sample_count, :integer                   # Training samples
  end
  
  relationships do
    belongs_to :build, Thunderline.Thunderforge.Build
  end
end
```

### Deployment
```elixir
defmodule Thunderline.Thunderforge.Deployment do
  use Ash.Resource,
    domain: Thunderline.Thunderforge,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    attribute :target_backend, :atom                    # :nx, :ebpf, :p4
    attribute :target_zone, :string
    attribute :status, :atom do
      constraints one_of: [:initiated, :validated, :staged, :deployed, :verified, :failed]
      default :initiated
    end
    attribute :health_check_result, :map
    create_timestamp :deployed_at
  end
  
  relationships do
    belongs_to :build, Thunderline.Thunderforge.Build
  end
  
  state_machine do
    initial_states [:initiated]
    default_initial_state :initiated
    
    transitions do
      transition :validate, from: :initiated, to: :validated
      transition :stage, from: :validated, to: :staged
      transition :deploy, from: :staged, to: :deployed
      transition :verify, from: :deployed, to: :verified
      transition :fail, from: [:initiated, :validated, :staged, :deployed], to: :failed
    end
  end
end
```

## Compilation Pipeline Stages

### Stage 1: Parse
**Input**: ThunderDSL source string  
**Output**: AST (Abstract Syntax Tree)  
**Module**: `Thunderline.Thunderforge.Compiler.Parser`

```elixir
{:ok, ast} = Parser.parse(source_dsl)
# %AST.Program{
#   inputs: [...],
#   outputs: [...],
#   body: [%AST.For{...}, %AST.MatMul{...}, ...]
# }
```

### Stage 2: Expand
**Input**: AST with macros  
**Output**: Expanded AST (macros unrolled)  
**Module**: `Thunderline.Thunderforge.Compiler.Expander`

```elixir
expanded_ast = Expander.expand(ast)
# Macros like @thunder_for unrolled to explicit operations
```

### Stage 3: Lower
**Input**: Expanded AST  
**Output**: Pegasus Primitives IR  
**Module**: `Thunderline.Thunderforge.Compiler.Lowerer`

```elixir
ir = Lowerer.lower(expanded_ast)
# [%IR.Partition{...}, %IR.Map{...}, %IR.SumReduce{...}]
```

### Stage 4: Generate Tables
**Input**: IR + Sample Data  
**Output**: Fuzzy Index Trees  
**Module**: `Thunderline.Thunderforge.Compiler.FuzzyIndex`

```elixir
tables = FuzzyIndex.generate_tables(ir, sample_data)
# %Table{name: "relu", fuzzy_tree: ..., centroids: [...]}
```

### Stage 5: Fuse Primitives
**Input**: IR  
**Output**: Optimized IR  
**Module**: `Thunderline.Thunderforge.Compiler.Fusion`

```elixir
fused_ir = Fusion.optimize(ir)
# Merged consecutive Maps, reordered operations
```

### Stage 6: Codegen
**Input**: Optimized IR + Tables  
**Output**: Target code (Nx, eBPF, P4)  
**Modules**: `Thunderline.Thunderforge.Backends.*`

```elixir
artifacts = %{
  nx: NxBackend.generate(fused_ir, tables),
  ebpf: EbpfBackend.generate(fused_ir, tables),
  p4: P4Backend.generate(fused_ir, tables)
}
```

### Stage 7: Package
**Input**: Artifacts + Metadata  
**Output**: Build resource with signatures  
**Module**: `Thunderline.Thunderforge.Packager`

```elixir
{:ok, build} = Packager.package(%{
  artifacts: artifacts,
  program: program,
  sbom: generate_sbom(),
  signature: sign_with_ed25519(artifacts)
})
```

## Integration Points

### Vertical Edge: Bolt → Forge (HPO Compilation)

```elixir
# Thunderbolt HPO samples configuration
config = Thunderbolt.HPO.sample_config(experiment_id)

# Forge compiles variant
{:ok, build} = Thunderforge.compile_program(%{
  program_id: base_program.id,
  config_override: config,
  targets: [:nx]
})

# Bolt deploys and evaluates
result = execute_and_measure(build)
Thunderbolt.HPO.record_trial(experiment_id, config, result)
```

### Vertical Edge: Forge → Link (Deploy to Dataplane)

```elixir
# Forge provides compiled eBPF program
{:ok, build} = Thunderforge.get_build(build_id)
ebpf_path = build.artifacts[:ebpf]

# Link deploys to network interface
{:ok, deployment} = Thunderlink.deploy_ebpf(%{
  build_id: build.id,
  ebpf_program_path: ebpf_path,
  interface: "eth0",
  attach_mode: :xdp_generic
})
```

### Horizontal Edge: Forge → Grid (Resource Requirements)

```elixir
# Forge analyzes compiled program
requirements = Thunderforge.analyze_requirements(build)
# %{cpu_cores: 2, memory_mb: 512, backend: :nx, gpu?: false}

# Grid makes placement decision
{:ok, zone} = Thundergrid.select_zone(requirements)
```

## Performance Targets

| Stage | Latency (P50) | Latency (P99) |
|-------|--------------|--------------|
| Parse | 10ms | 50ms |
| Expand | 50ms | 200ms |
| Lower | 20ms | 100ms |
| Generate Tables | 500ms | 2000ms |
| Fuse | 30ms | 150ms |
| Codegen (Nx) | 100ms | 500ms |
| Codegen (eBPF) | 200ms | 1000ms |
| Codegen (P4) | 300ms | 1500ms |
| **Total (Nx only)** | **750ms** | **3s** |
| **Total (All targets)** | **1.5s** | **5s** |

## Telemetry Events

```elixir
[:thunderline, :forge, :compile, :start]
[:thunderline, :forge, :compile, :stop]
[:thunderline, :forge, :compile, :exception]

[:thunderline, :forge, :stage, :parse]
[:thunderline, :forge, :stage, :expand]
[:thunderline, :forge, :stage, :lower]
[:thunderline, :forge, :stage, :tables]
[:thunderline, :forge, :stage, :fusion]
[:thunderline, :forge, :stage, :codegen]
[:thunderline, :forge, :stage, :package]
```

## Security Model

### Input Validation
- DSL syntax checked before execution
- Type system prevents invalid operations
- Resource bounds enforced (max program size, max loop iterations)

### Artifact Integrity
- All builds signed with Ed25519
- Content-addressed storage prevents tampering
- SBOM tracks all dependencies

### Sandbox Execution
- Compilation runs in isolated process
- Resource limits (CPU, memory, time)
- No network access during compilation

## Testing Strategy

### Unit Tests
- Parser: Valid/invalid DSL syntax
- Expander: Macro expansion correctness
- Lowerer: AST → IR mapping
- Fusion: Optimization correctness proofs
- Backends: Code generation accuracy

### Integration Tests
- End-to-end: DSL → Nx execution
- Multi-target: Same program on all backends
- HPO integration: Bolt triggers compilation

### Property Tests
- Fuzzy index accuracy (StreamData)
- Fusion preserves semantics
- Type system soundness

## Development Phases

### Phase 1: Foundation (Sprint after Sprint 4)
- [ ] Create domain module structure
- [ ] Define Ash resources (Program, Build, Deployment, Table)
- [ ] Implement basic parser (NimbleParsec)
- [ ] Stub backends (return dummy code)

### Phase 2: PoC (Next 4-6 weeks)
- [ ] Working Nx backend
- [ ] Basic primitives (Partition/Map/SumReduce)
- [ ] Simple macro expansion (@thunder_for only)
- [ ] Integration with Thunderbolt HPO
- [ ] End-to-end test: DSL → execution

### Phase 3: Production (6-8 weeks)
- [ ] Fuzzy index tree generation
- [ ] Primitive fusion pass
- [ ] Complete macro set
- [ ] Performance optimization
- [ ] Production deployment

### Phase 4: Exotic Backends (3-6 months)
- [ ] eBPF/XDP backend
- [ ] P4 backend
- [ ] Hardware validation
- [ ] Customer trials

## References

- [ThunderDSL Specification](../THUNDERDSL_SPECIFICATION.md)
- [Compiler Pipeline](COMPILER_PIPELINE.md)
- [Pegasus Primitives](../PEGASUS_PRIMITIVES.md)
- [Fuzzy Index Algorithm](FUZZY_INDEX_ALGORITHM.md)
