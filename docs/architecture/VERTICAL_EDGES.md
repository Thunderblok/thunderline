# Vertical Edges: Control → Data Deployments

## Overview

Vertical edges in the prism topology represent **deployment flows** from control plane domains to their corresponding data plane domains. These are the primary mechanism for translating policy, compilation, and orchestration decisions into running systems.

## Edge Characteristics

- **Directionality**: Strictly control → data (top → bottom)
- **Latency**: Medium (10-1000ms typical)
- **Reliability**: High (transactional, with rollback)
- **Protocol**: Ash actions with optional Reactor workflows
- **Observability**: Full audit trail in Thundervine

## The Six Vertical Edges

### 1. Crown → Clock (Policy to Timers)

**Purpose**: Enforce timing policies on scheduled operations.

**Use Cases**:
- Maximum execution time limits
- Rate limiting based on policy
- Compliance-mandated retention schedules

**Protocol**:
```elixir
# Crown defines policy
{:ok, policy} = Thundercrown.create_timing_policy(%{
  max_execution_ms: 5000,
  retry_policy: :exponential_backoff
})

# Block.Timing registers policy enforcement
{:ok, timer} = Thunderblock.Timing.create_timer(%{
  policy_id: policy.id,
  schedule: "*/5 * * * *"
})
```

**Rollback**: Timer disabled if policy validation fails.

**Note**: Timer functionality consolidated into ThunderBlock.Timing subdomain.

---

### 2. Bolt → Block (Orchestration to Runtime)

**Purpose**: Deploy orchestrated workflows to execution runtime.

**Use Cases**:
- Reactor workflow deployment
- HPO experiment execution
- Batch job submission

**Protocol**:
```elixir
# Bolt orchestrates deployment
{:ok, deployment} = Thunderbolt.deploy_workflow(%{
  workflow_id: workflow.id,
  target_zone: "us-west-2a"
})

# Block provisions runtime resources
{:ok, instance} = Thunderblock.create_runtime(%{
  deployment_id: deployment.id,
  resources: %{cpu: 4, memory_gb: 16}
})
```

**Rollback**: Runtime resources released if deployment fails.

---

### 3. Forge → Link (Compilation to I/O)

**Purpose**: Deploy compiled ThunderDSL programs to I/O layer (eBPF/XDP/P4).

**Use Cases**:
- eBPF program injection to network interface
- P4 pipeline reconfiguration
- Dataplane model deployment

**Protocol**:
```elixir
# Forge compiles ThunderDSL program
{:ok, build} = Thunderforge.compile_program(%{
  program_id: program.id,
  target: :ebpf_xdp
})

# Link deploys to network interface
{:ok, deployment} = Thunderlink.deploy_ebpf(%{
  build_id: build.id,
  interface: "eth0",
  attach_mode: :xdp_generic
})
```

**Rollback**: Previous eBPF program restored if deployment fails.

---

### 4. Grid → Flow (Topology to Events)

**Purpose**: Configure zone-aware event routing.

**Use Cases**:
- Region-specific event filtering
- Cross-zone replication policies
- Locality-optimized delivery

**Protocol**:
```elixir
# Grid defines topology
{:ok, zone} = Thundergrid.create_zone(%{
  name: "us-west-2a",
  tier: :production
})

# Flow configures routing
{:ok, route} = Thunderflow.create_route(%{
  zone_id: zone.id,
  filter: "domain == :bolt",
  priority: :high
})
```

**Rollback**: Previous routing configuration restored.

---

### 5. Sec → Pac (Security to Execution)

**Purpose**: Apply security constraints to execution sandbox.

**Use Cases**:
- Resource limits (CPU, memory, network)
- Allowed syscalls/operations
- Cryptographic key provisioning

**Protocol**:
```elixir
# Sec defines security policy
{:ok, policy} = Thundersec.create_sandbox_policy(%{
  max_memory_mb: 512,
  allowed_syscalls: [:read, :write, :mmap],
  network_access: false
})

# Pac enforces policy
{:ok, sandbox} = Thunderpac.create_sandbox(%{
  policy_id: policy.id,
  isolation: :seccomp_bpf
})
```

**Rollback**: Sandbox terminated if policy violation detected.

---

### 6. Jam → Vine (QoS to Provenance)

**Purpose**: Apply rate limits to provenance writes.

**Use Cases**:
- Prevent provenance spam
- Priority-based write scheduling
- Quota enforcement

**Protocol**:
```elixir
# Gate.RateLimiting defines rate limit
{:ok, limit} = Thundergate.RateLimiting.create_rate_limit(%{
  resource: :provenance_writes,
  max_per_second: 1000,
  burst: 5000
})

# Vine respects limit
{:ok, node} = Thundervine.record_provenance(%{
  event_id: event.id,
  rate_limit_id: limit.id
})
```

**Rollback**: Write queued if rate limit exceeded.

**Note**: Rate limiting consolidated into ThunderGate.RateLimiting subdomain.

---

## Deployment State Machine

Every vertical edge deployment follows this state machine:

```
[Initiated] → [Validated] → [Staged] → [Deployed] → [Verified]
      ↓            ↓           ↓            ↓
   [Failed]  → [Rollback] → [Rolled Back]
```

### States

1. **Initiated**: Control plane action called
2. **Validated**: Pre-deployment checks pass
3. **Staged**: Resources allocated, not yet active
4. **Deployed**: Active in data plane
5. **Verified**: Health checks pass post-deployment
6. **Failed**: Deployment error occurred
7. **Rollback**: Previous state restoration in progress
8. **Rolled Back**: Successfully reverted to previous state

### Transitions

Managed by Ash state machine extension:

```elixir
state_machine do
  initial_states [:initiated]
  default_initial_state :initiated

  transitions do
    transition :validate, from: :initiated, to: :validated
    transition :stage, from: :validated, to: :staged
    transition :deploy, from: :staged, to: :deployed
    transition :verify, from: :deployed, to: :verified
    
    # Failure handling
    transition :fail, from: [:initiated, :validated, :staged, :deployed], to: :failed
    transition :rollback, from: :failed, to: :rollback
    transition :complete_rollback, from: :rollback, to: :rolled_back
  end
end
```

## Telemetry

All vertical edge operations emit telemetry:

```elixir
:telemetry.execute(
  [:thunderline, :vertical_edge, :deploy],
  %{duration_ms: duration},
  %{
    from_domain: :crown,
    to_domain: :clock,
    deployment_id: id,
    state: :verified
  }
)
```

## Error Handling

### Transient Errors
- Network timeouts
- Temporary resource unavailability
- Rate limiting

**Strategy**: Retry with exponential backoff (managed by Oban).

### Permanent Errors
- Policy violation
- Resource quota exceeded
- Invalid configuration

**Strategy**: Fail fast, rollback, alert.

### Rollback Guarantees

All vertical edges MUST implement rollback:

```elixir
defmodule Thunderline.Thunderforge.Deploy do
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_transaction(fn changeset ->
      # Snapshot current state for rollback
      snapshot_current_deployment(changeset)
      changeset
    end)
    |> Ash.Changeset.after_transaction(fn changeset, {:error, error} ->
      # Rollback on failure
      restore_previous_deployment(changeset)
      {:error, error}
      
      changeset, {:ok, result} ->
        {:ok, result}
    end)
  end
end
```

## Performance Targets

| Edge | P50 Latency | P99 Latency | Throughput |
|------|------------|------------|------------|
| Crown → Clock | 50ms | 200ms | 100/s |
| Bolt → Block | 100ms | 500ms | 50/s |
| Forge → Link | 200ms | 1000ms | 10/s |
| Grid → Flow | 20ms | 100ms | 500/s |
| Sec → Pac | 30ms | 150ms | 200/s |
| Jam → Vine | 10ms | 50ms | 1000/s |

## Testing Strategy

### Unit Tests
- State machine transitions
- Rollback logic
- Error handling

### Integration Tests
- End-to-end deployment flow
- Cross-domain communication
- Telemetry emission

### Chaos Tests
- Random deployment failures
- Network partitions during deployment
- Resource exhaustion scenarios

## Future Enhancements

- [ ] Canary deployments (gradual rollout)
- [ ] Blue-green deployments (zero-downtime)
- [ ] Multi-region coordination
- [ ] Automatic remediation on failure
- [ ] Predictive rollback (detect issues before full deployment)

## References

- [Prism Topology](PRISM_TOPOLOGY.md)
- [Horizontal Rings](HORIZONTAL_RINGS.md)
- [Ash State Machine](https://hexdocs.pm/ash_state_machine/)
