# Thunderpac Domain Overview

**Vertex Position**: Data Plane Ring, Position 11

**Purpose**: PAC (Provably Accurate Computation) Execution Sandbox - runs compiled programs in isolated, auditable environments.

## Charter

Thunderpac is the **execution sandbox** for ThunderDSL-compiled programs. It provides **isolation**, **determinism**, and **auditability** for ML inference workloads. Every program execution is logged with full provenance.

## Core Responsibilities

### 1. **Sandboxed Execution**
- Process isolation (OS-level or eBPF-level)
- Resource limits (CPU, memory, time)
- No network access during execution
- Read-only file system

### 2. **Deterministic Execution**
- Fixed random seeds for reproducibility
- Deterministic floating-point (optional)
- Version-locked dependencies
- Consistent execution order

### 3. **Input Validation**
- Schema validation (shape, dtype)
- Range checks
- Sanitization
- Malicious input detection

### 4. **Provenance Recording**
- Input hashes
- Output hashes
- Execution time
- Resource usage
- Full audit trail

### 5. **Multi-Backend Support**
- Nx backend (Elixir BEAM)
- eBPF/XDP backend (Linux kernel)
- P4 backend (switch ASICs)

## Ash Resources

### Sandbox
```elixir
defmodule Thunderline.Thunderpac.Sandbox do
  use Ash.Resource,
    domain: Thunderline.Thunderpac,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :backend, :atom do
      constraints one_of: [:nx, :ebpf, :p4]
      default :nx
    end
    attribute :cpu_limit_cores, :float, default: 1.0
    attribute :memory_limit_mb, :integer, default: 512
    attribute :timeout_ms, :integer, default: 5000
    attribute :network_enabled, :boolean, default: false
    attribute :read_only_filesystem, :boolean, default: true
    attribute :status, :atom do
      constraints one_of: [:idle, :executing, :completed, :failed]
      default :idle
    end
  end
  
  relationships do
    belongs_to :build, Thunderline.Thunderforge.Build
    has_many :executions, Thunderline.Thunderpac.Execution
  end
  
  state_machine do
    initial_states [:idle]
    default_initial_state :idle
    
    transitions do
      transition :execute, from: :idle, to: :executing
      transition :complete, from: :executing, to: :completed
      transition :fail, from: :executing, to: :failed
      transition :reset, from: [:completed, :failed], to: :idle
    end
  end
end
```

### Execution
```elixir
defmodule Thunderline.Thunderpac.Execution do
  use Ash.Resource,
    domain: Thunderline.Thunderpac,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :input_hash, :string, allow_nil?: false      # SHA256 of input
    attribute :output_hash, :string                        # SHA256 of output
    attribute :execution_time_ms, :integer
    attribute :cpu_usage_percent, :float
    attribute :memory_usage_mb, :integer
    attribute :success, :boolean
    attribute :error_message, :string
    create_timestamp :executed_at
  end
  
  relationships do
    belongs_to :sandbox, Thunderline.Thunderpac.Sandbox
    belongs_to :build, Thunderline.Thunderforge.Build
    has_one :provenance, Thunderline.Thundervine.ProvenanceRecord
  end
  
  actions do
    defaults [:create, :read]
    
    create :execute do
      argument :input_data, :map, allow_nil?: false
      change ValidateInput
      change ExecuteProgram
      change RecordProvenance
    end
  end
end
```

### ResourceLimits
```elixir
defmodule Thunderline.Thunderpac.ResourceLimits do
  use Ash.Resource,
    domain: Thunderline.Thunderpac,
    data_layer: :embedded
  
  attributes do
    attribute :max_cpu_cores, :float, default: 2.0
    attribute :max_memory_mb, :integer, default: 2048
    attribute :max_execution_time_ms, :integer, default: 30_000
    attribute :max_input_size_bytes, :integer, default: 10_485_760  # 10 MB
    attribute :max_output_size_bytes, :integer, default: 10_485_760
  end
end
```

## Execution Workflow

### Phase 1: Preparation

```elixir
defmodule Thunderline.Thunderpac.Executor do
  def prepare_execution(build_id, input_data) do
    # 1. Load compiled build
    build = Thunderforge.Build.get!(build_id)
    
    # 2. Validate input against schema
    :ok = validate_input(input_data, build.input_schema)
    
    # 3. Hash input for provenance
    input_hash = hash_input(input_data)
    
    # 4. Select backend
    backend = select_backend(build.artifacts)
    
    {:ok, %{build: build, input_hash: input_hash, backend: backend}}
  end
  
  defp validate_input(data, schema) do
    # Check shape, dtype, ranges
    case Nx.shape(data) == schema.shape do
      true -> :ok
      false -> {:error, "Input shape mismatch"}
    end
  end
  
  defp hash_input(data) do
    data
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
```

### Phase 2: Execution

```elixir
def execute(sandbox, build, input_data) do
  # Start monitoring
  {:ok, monitor_pid} = ResourceMonitor.start_link(sandbox)
  
  # Execute based on backend
  result = case sandbox.backend do
    :nx -> execute_nx(build, input_data)
    :ebpf -> execute_ebpf(build, input_data)
    :p4 -> execute_p4(build, input_data)
  end
  
  # Stop monitoring and collect metrics
  metrics = ResourceMonitor.stop(monitor_pid)
  
  {:ok, result, metrics}
end

defp execute_nx(build, input_data) do
  # Load Nx.defn function from build
  {:module, mod} = Code.eval_string(build.artifacts.nx)
  
  # Execute with timeout
  Task.async(fn -> apply(mod, :run, [input_data]) end)
  |> Task.await(timeout: build.timeout_ms)
end
```

### Phase 3: Provenance Recording

```elixir
def record_execution(execution, result, metrics) do
  # Hash output
  output_hash = hash_output(result)
  
  # Create execution record
  Execution.create!(%{
    sandbox_id: execution.sandbox_id,
    build_id: execution.build_id,
    input_hash: execution.input_hash,
    output_hash: output_hash,
    execution_time_ms: metrics.execution_time_ms,
    cpu_usage_percent: metrics.cpu_usage,
    memory_usage_mb: metrics.memory_usage,
    success: true
  })
  
  # Record provenance in Thundervine
  Thundervine.ProvenanceRecord.create!(%{
    execution_id: execution.id,
    input_hash: execution.input_hash,
    output_hash: output_hash,
    build_id: execution.build_id,
    deterministic: true,
    reproducible: true
  })
end
```

## Backend Implementations

### Nx Backend (Elixir BEAM)

```elixir
defmodule Thunderline.Thunderpac.Backends.Nx do
  @moduledoc """
  Execute ThunderDSL programs as pure Nx.defn functions.
  Runs in BEAM process with resource limits.
  """
  
  def execute(build, input_tensor, opts \\ []) do
    # Load compiled Nx module
    {:module, mod} = load_nx_module(build)
    
    # Set EXLA compiler options
    Nx.default_backend(EXLA.Backend)
    
    # Execute with timeout
    timeout = opts[:timeout_ms] || 5000
    Task.async(fn -> mod.run(input_tensor) end)
    |> Task.await(timeout)
  end
  
  defp load_nx_module(build) do
    # Load from CAS
    nx_code = build.artifacts[:nx]
    Code.eval_string(nx_code)
  end
end
```

### eBPF Backend (Linux Kernel)

```elixir
defmodule Thunderline.Thunderpac.Backends.eBPF do
  @moduledoc """
  Execute ThunderDSL programs as eBPF/XDP programs.
  Runs in Linux kernel with strict resource limits.
  """
  
  def execute(build, input_data, opts \\ []) do
    # Load eBPF program from CAS
    ebpf_obj = build.artifacts[:ebpf]
    
    # Attach to interface
    interface = opts[:interface] || "lo"
    {:ok, fd} = attach_ebpf_program(ebpf_obj, interface)
    
    # Send input via BPF map
    :ok = write_bpf_map(fd, "input_map", input_data)
    
    # Trigger execution
    trigger_ebpf_execution(fd)
    
    # Read output from BPF map
    output = read_bpf_map(fd, "output_map")
    
    # Cleanup
    detach_ebpf_program(fd)
    
    {:ok, output}
  end
end
```

## Integration Points

### Vertical Edge: Sec → Pac (Security Constraints)

```elixir
# Sec provides security constraints
security_context = Thundersec.authorize_execution(user, build_id)

# Pac applies constraints
sandbox = Thunderpac.Sandbox.create!(%{
  build_id: build_id,
  cpu_limit_cores: security_context.max_cpu,
  memory_limit_mb: security_context.max_memory,
  timeout_ms: security_context.max_time,
  network_enabled: security_context.allow_network
})
```

### Horizontal Edge: Flow → Pac (Event-Triggered Execution)

```elixir
# Flow receives inference request event
Thunderflow.EventBus.subscribe("inference.request.*")

def handle_event(%{name: "inference.request.classify"} = event) do
  # Pac executes classification
  {:ok, result} = Thunderpac.execute(%{
    build_id: event.payload.model_id,
    input_data: event.payload.image
  })
  
  # Emit result event
  Thunderflow.EventBus.publish_event!(%{
    name: "inference.result.classified",
    payload: %{result: result, request_id: event.id}
  })
end
```

### Horizontal Edge: Pac → Vine (Provenance Recording)

```elixir
# Pac completes execution
{:ok, execution} = Thunderpac.Execution.create!(execution_params)

# Vine records provenance
Thundervine.ProvenanceRecord.create!(%{
  execution_id: execution.id,
  input_hash: execution.input_hash,
  output_hash: execution.output_hash,
  build_id: execution.build_id,
  reproducible: true,
  verified: true
})
```

## Security Model

### Isolation
- **Process isolation**: Each execution in separate BEAM process or OS process
- **Filesystem isolation**: Read-only, no write access
- **Network isolation**: No network by default
- **Resource isolation**: CPU/memory limits enforced

### Input Validation
```elixir
defmodule Thunderline.Thunderpac.InputValidator do
  def validate_input(input, schema) do
    with :ok <- validate_shape(input, schema.shape),
         :ok <- validate_dtype(input, schema.dtype),
         :ok <- validate_range(input, schema.min, schema.max),
         :ok <- validate_size(input, schema.max_bytes) do
      :ok
    end
  end
end
```

### Determinism Guarantees
- Fixed random seeds
- Deterministic floating-point operations (optional)
- Version-locked dependencies
- No external state access

## Telemetry Events

```elixir
[:thunderline, :pac, :execution, :start]       # Execution started
[:thunderline, :pac, :execution, :stop]        # Execution completed
[:thunderline, :pac, :execution, :exception]   # Execution failed
[:thunderline, :pac, :resource, :exceeded]     # Resource limit exceeded
[:thunderline, :pac, :validation, :failed]     # Input validation failed
```

## Performance Targets

| Backend | Latency (P50) | Latency (P99) | Throughput |
|---------|--------------|--------------|------------|
| Nx (CPU) | 5ms | 20ms | 200/s |
| Nx (GPU) | 2ms | 10ms | 500/s |
| eBPF (XDP) | 50μs | 200μs | 10k/s |
| P4 (switch) | 10μs | 50μs | 100k/s |

## Testing Strategy

### Unit Tests
- Input validation
- Hash computation
- Resource limit enforcement
- Backend selection

### Integration Tests
- End-to-end execution (all backends)
- Provenance recording
- Security constraint enforcement

### Chaos Tests
- Resource exhaustion scenarios
- Malicious input handling
- Backend failure recovery

## Development Phases

### Phase 1: Foundation
- [ ] Create domain module
- [ ] Define Ash resources (Sandbox, Execution, ResourceLimits)
- [ ] Implement Nx backend
- [ ] Basic input validation

### Phase 2: Production Features
- [ ] Resource monitoring
- [ ] Provenance integration
- [ ] Security constraints
- [ ] Telemetry instrumentation

### Phase 3: Exotic Backends
- [ ] eBPF/XDP backend
- [ ] P4 backend
- [ ] Multi-backend orchestration
- [ ] Performance optimization

## References

- [Prism Topology](../../architecture/PRISM_TOPOLOGY.md)
- [ThunderDSL Specification](../../THUNDERDSL_SPECIFICATION.md)
- [Vertical Edges](../../architecture/VERTICAL_EDGES.md)
