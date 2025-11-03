# Horizontal Rings: Control & Data Plane Protocols

## Overview

Horizontal edges connect vertices **within the same ring** (control or data plane), enabling feedback loops, pipeline stages, and coordination. These edges have fundamentally different characteristics from vertical edges.

## Ring Characteristics Comparison

| Characteristic | Control Ring (Top) | Data Ring (Bottom) |
|---------------|-------------------|-------------------|
| **Latency** | Medium (10-100ms) | Low (1-10ms) |
| **Consistency** | Strong | Eventual |
| **Protocol** | Ash actions + events | Broadway + direct calls |
| **Failure Mode** | Degrade gracefully | Fast fail + retry |
| **Observability** | Full audit trail | Sampled telemetry |

---

## Control Plane Ring (Strategy/Compilation/Policy)

### Crown → Bolt (Policy to Orchestration)

**Purpose**: Policies define orchestration constraints.

**Use Cases**:
- Maximum retry attempts
- Allowed resource types
- Compliance requirements for workflows

**Protocol**:
```elixir
# Crown publishes policy change event
Thunderflow.EventBus.publish_event!(%{
  name: "policy.workflow.updated",
  domain: "crown",
  source: :crown,
  payload: %{policy_id: id, constraints: constraints}
})

# Bolt subscribes and updates constraints
def handle_info({:event, %{name: "policy.workflow.updated"}}, state) do
  # Update workflow constraints
  {:noreply, update_constraints(state)}
end
```

**Latency**: 10-50ms (asynchronous event delivery).

---

### Bolt → Forge (HPO to Compilation)

**Purpose**: HPO triggers recompilation with new hyperparameters.

**Use Cases**:
- TPE samples new config → compile variant
- Performance feedback → optimization
- A/B testing program variants

**Protocol**:
```elixir
# Bolt HPO worker requests compilation
{:ok, build} = Thunderforge.compile_program(%{
  program_id: base_program.id,
  config_override: hpo_config,
  experiment_id: experiment.id
})

# Forge returns compiled artifact
%Thunderforge.Build{
  program_id: program.id,
  config: hpo_config,
  artifacts: %{nx: path_to_nx_binary}
}
```

**Latency**: 100-1000ms (synchronous compilation).

---

### Forge → Grid (Compilation to Placement)

**Purpose**: Compilation artifacts inform placement decisions.

**Use Cases**:
- Resource requirements (CPU, memory, GPU)
- Backend compatibility (Nx vs eBPF)
- Locality optimization

**Protocol**:
```elixir
# Forge provides resource requirements
requirements = Thunderforge.get_resource_requirements(build)

# Grid makes placement decision
{:ok, placement} = Thundergrid.select_zone(%{
  cpu_cores: requirements.cpu,
  memory_gb: requirements.memory,
  backend: requirements.backend
})
```

**Latency**: 10-50ms (lookup + decision).

---

### Grid → Sec (Topology to Security)

**Purpose**: Topology determines security zones and trust boundaries.

**Use Cases**:
- Cross-zone authentication requirements
- Network segmentation policies
- Key distribution strategies

**Protocol**:
```elixir
# Grid defines zone trust level
{:ok, zone} = Thundergrid.create_zone(%{
  name: "dmz",
  trust_level: :low
})

# Sec applies corresponding policies
{:ok, policy} = Thundersec.create_zone_policy(%{
  zone_id: zone.id,
  require_mTLS: true,
  key_rotation_days: 1
})
```

**Latency**: 20-100ms (policy application).

---

### Sec → Jam (Security to QoS)

**Purpose**: Authentication requirements influence rate limits.

**Use Cases**:
- Authenticated users get higher rate limits
- Anonymous users get throttled
- Service-level agreements (SLAs)

**Protocol**:
```elixir
# Sec provides authentication context
auth_context = Thundersec.authenticate(request)

# Jam applies rate limit based on context
limit = case auth_context.tier do
  :premium -> 10_000
  :standard -> 1_000
  :anonymous -> 100
end

Thunderjam.check_rate_limit(auth_context.actor_id, limit)
```

**Latency**: 5-20ms (hot path, cached).

---

### Jam → Crown (QoS to Policy)

**Purpose**: QoS violations trigger policy updates.

**Use Cases**:
- Automatic rate limit adjustment
- Policy feedback loop
- Abuse detection and response

**Protocol**:
```elixir
# Jam detects violations
violations = Thunderjam.get_rate_limit_violations(last: :hour)

if Enum.count(violations) > threshold do
  # Notify Crown to update policy
  Thunderflow.EventBus.publish_event!(%{
    name: "qos.violation.threshold_exceeded",
    domain: "jam",
    source: :jam,
    payload: %{violations: violations}
  })
end

# Crown adjusts policy (async)
def handle_info({:event, %{name: "qos.violation.threshold_exceeded"}}, state) do
  Thundercrown.tighten_rate_limits()
  {:noreply, state}
end
```

**Latency**: 50-200ms (asynchronous feedback).

---

## Data Plane Ring (Execution/IO/Storage)

### Clock → Block (Timers to Runtime)

**Purpose**: Periodic ticks trigger storage operations.

**Use Cases**:
- Scheduled backups
- Periodic compaction
- TTL-based cleanup

**Protocol**:
```elixir
# Clock emits tick event
Thunderflow.EventBus.publish_event!(%{
  name: "system.tick.5min",
  domain: "clock",
  source: :clock,
  payload: %{timestamp: DateTime.utc_now()}
})

# Block subscribes to tick
def handle_info({:event, %{name: "system.tick.5min"}}, state) do
  Thunderblock.compact_database()
  {:noreply, state}
end
```

**Latency**: 1-10ms (fast event).

---

### Block → Link (Storage to I/O)

**Purpose**: Persisted data flows to I/O layer.

**Use Cases**:
- Replicate database writes to network
- Stream query results to clients
- Export data to external systems

**Protocol**:
```elixir
# Block streams changes
Thunderblock.stream_changes()
|> Stream.each(fn change ->
  Thunderlink.send_to_replica(change)
end)
|> Stream.run()
```

**Latency**: 5-50ms (streaming pipeline).

---

### Link → Flow (I/O to Events)

**Purpose**: Network packets generate events.

**Use Cases**:
- HTTP request → event
- WebSocket message → event
- eBPF packet capture → event

**Protocol**:
```elixir
# Link receives network packet
def handle_packet(packet) do
  # Convert to event
  event = %{
    name: "network.packet.received",
    domain: "link",
    source: :link,
    payload: packet
  }
  
  # Publish to Flow (fast path, no waiting)
  Thunderflow.EventBus.publish_event!(event)
end
```

**Latency**: 1-5ms (critical hot path).

---

### Flow → Pac (Events to Execution)

**Purpose**: Events trigger sandboxed execution.

**Use Cases**:
- Event-driven functions
- Stream processing
- Reactive workflows

**Protocol**:
```elixir
# Flow routes event to Pac
Broadway.Message.put_data(message, event)

# Pac processes in sandbox
def handle_batch(_batch, messages, _context) do
  Enum.map(messages, fn msg ->
    event = Broadway.Message.get_data(msg)
    result = Thunderpac.execute_in_sandbox(event.payload)
    Broadway.Message.put_data(msg, result)
  end)
end
```

**Latency**: 10-100ms (sandbox overhead).

---

### Pac → Vine (Execution to Provenance)

**Purpose**: Execution results recorded in DAG.

**Use Cases**:
- Audit trail of computations
- Reproducibility tracking
- Causality analysis

**Protocol**:
```elixir
# Pac records execution in Vine
{:ok, node} = Thundervine.record_execution(%{
  sandbox_id: sandbox.id,
  input_event_id: event.id,
  output: result,
  duration_us: duration
})
```

**Latency**: 5-20ms (async write, buffered).

---

### Vine → Clock (Provenance to Scheduling)

**Purpose**: Provenance queries inform scheduling decisions.

**Use Cases**:
- Replay past executions
- Schedule based on historical patterns
- Optimize task ordering

**Protocol**:
```elixir
# Vine provides execution history
history = Thundervine.get_execution_history(%{
  task: :data_processing,
  last: {:days, 7}
})

# Clock optimizes schedule
optimal_time = Thunderclock.optimize_schedule(%{
  history: history,
  constraints: constraints
})
```

**Latency**: 20-100ms (query + optimization).

---

## Protocol Selection Guidelines

### When to Use Synchronous (Ash Actions)

- Strong consistency required
- Transactional semantics needed
- Immediate response expected
- Low throughput (<100/s)

**Example**: Forge → Grid placement decision.

### When to Use Asynchronous (Events via Flow)

- Eventual consistency acceptable
- Fire-and-forget semantics
- High throughput (>1000/s)
- Decoupled components

**Example**: Link → Flow packet events.

### When to Use Direct Function Calls

- Same BEAM node
- Nanosecond latency critical
- Tight coupling acceptable (rare)

**Example**: Hot path calculations within a vertex.

### When to Use Broadway Pipelines

- Stream processing
- Backpressure management
- Batch operations
- Message ordering

**Example**: Flow → Pac event processing.

---

## Performance Optimization

### Control Ring Optimizations

1. **Event batching**: Group related policy updates
2. **Caching**: Memoize expensive policy evaluations
3. **Async by default**: Use events unless sync required
4. **Debouncing**: Coalesce rapid updates

### Data Ring Optimizations

1. **Zero-copy**: Pass references, not data
2. **Hot path**: Inline critical operations
3. **Sampling**: Only emit 1% of telemetry events
4. **Buffering**: Batch provenance writes

---

## Failure Modes

### Control Ring Failures

**Symptom**: Policy updates stop propagating.

**Impact**: System continues with stale policies (safe default).

**Recovery**: Event replay from Thunderflow.

### Data Ring Failures

**Symptom**: Events stop flowing.

**Impact**: Processing halts (fail-fast).

**Recovery**: Broadway automatic retry with backoff.

---

## Testing Strategy

### Control Ring Tests

- Async event delivery timing
- Policy propagation correctness
- Feedback loop convergence

### Data Ring Tests

- Broadway backpressure handling
- Event throughput under load
- Provenance write batching

---

## Monitoring

### Key Metrics

**Control Ring:**
- Policy propagation latency (P50, P99)
- Event queue depth
- Feedback loop cycles

**Data Ring:**
- Event throughput (events/sec)
- Pipeline batch sizes
- Provenance write lag

### Alerts

- Control ring event queue > 10,000
- Data ring throughput < 1,000 events/sec
- Provenance write lag > 10 seconds

---

## References

- [Prism Topology](PRISM_TOPOLOGY.md)
- [Vertical Edges](VERTICAL_EDGES.md)
- [Event Bus Specification](../EVENT_BUS_SPECIFICATION.md)
- [Broadway Documentation](https://hexdocs.pm/broadway/)
