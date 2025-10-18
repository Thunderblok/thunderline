# Reactor Sagas in Thunderline

This document describes the Reactor saga patterns used in Thunderline for orchestrating complex, multi-step workflows across domain boundaries.

## What are Reactor Sagas?

**Reactor** is Elixir's declarative saga orchestration library. A saga is a long-running workflow composed of multiple steps that can:

- Execute sequentially or in parallel
- Maintain transactional consistency across multiple domains
- Automatically compensate (rollback) on failure
- Emit telemetry for observability
- Handle retries and timeouts

## When to Use Sagas

Use Reactor sagas when:

- **Multi-Domain Coordination**: Workflow spans multiple Ash domains (e.g., ThunderGate → ThunderBlock → ThunderLink)
- **Compensatable Operations**: Each step can be undone if later steps fail
- **Long-Running Workflows**: Process takes seconds/minutes (not milliseconds)
- **External Dependencies**: Workflow involves external services (email, ML APIs, payment gateways)
- **Complex State Transitions**: Multiple conditional branches and error paths

**Do NOT use sagas for:**

- Simple CRUD operations (use Ash actions directly)
- Fast in-memory computations
- Workflows entirely within a single resource
- Fire-and-forget background jobs (use Oban instead)

## Available Sagas

### 1. UserProvisioningSaga

**Purpose**: Complete user onboarding from magic link to vault provisioning

**Steps**:
1. Validate email format
2. Generate secure magic link token
3. Send email via ThunderGate.MagicLinkSender
4. Create user record (ThunderGate)
5. Provision vault space (ThunderBlock)
6. Create default community membership (ThunderLink)
7. Emit onboarding complete event

**Compensation**: If vault provisioning fails, deletes created user and removes any partial memberships.

**Example**:
```elixir
alias Thunderline.Thunderbolt.Sagas.UserProvisioningSaga

inputs = %{
  email: "user@example.com",
  correlation_id: Thunderline.UUID.v7(),
  magic_link_redirect: "/communities"
}

case Reactor.run(UserProvisioningSaga, inputs) do
  {:ok, %{user: user, vault: vault}} ->
    {:ok, user}
    
  {:error, reason} ->
    Logger.error("Provisioning failed: #{inspect(reason)}")
    {:error, :provisioning_failed}
end
```

### 2. UPMActivationSaga

**Purpose**: Promote shadow-trained UPM snapshot to active production status

**Steps**:
1. Load shadow snapshot from ThunderBlock
2. Validate drift metrics against threshold
3. Check ThunderCrown policy gates
4. Deactivate previous active snapshot
5. Activate new snapshot
6. Sync all UpmAdapters to new snapshot
7. Emit activation event

**Compensation**: Reverts snapshot to shadow status and restores previous active snapshot if adapter sync fails.

**Example**:
```elixir
alias Thunderline.Thunderbolt.Sagas.UPMActivationSaga

inputs = %{
  snapshot_id: "snap_abc123",
  correlation_id: Thunderline.UUID.v7(),
  max_drift_score: 0.15
}

case Reactor.run(UPMActivationSaga, inputs) do
  {:ok, %{snapshot: snapshot, adapters: adapters}} ->
    Logger.info("Activated snapshot #{snapshot.id} with #{adapters.count} adapters")
    {:ok, snapshot}
    
  {:error, {:drift_threshold_exceeded, score}} ->
    Logger.warning("Drift too high: #{score}")
    {:error, :drift_rejected}
end
```

### 3. CerebrosNASSaga

**Purpose**: Execute Neural Architecture Search via Cerebros bridge

**Steps**:
1. Load training dataset from ThunderBolt
2. Create ModelRun record
3. Generate architecture proposals (Cerebros bridge)
4. Dispatch training jobs
5. Await completion (poll with timeout)
6. Collect artifacts
7. Compute Pareto frontier
8. Persist best model as ModelVersion
9. Emit completion event

**Compensation**: Marks ModelRun as failed and cancels in-flight training jobs.

**Example**:
```elixir
alias Thunderline.Thunderbolt.Sagas.CerebrosNASSaga

inputs = %{
  dataset_id: "dataset_123",
  search_space: %{layers: [2, 4, 8], units: [64, 128, 256]},
  max_trials: 10,
  correlation_id: Thunderline.UUID.v7()
}

case Reactor.run(CerebrosNASSaga, inputs) do
  {:ok, %{run: run, best_model: model}} ->
    Logger.info("NAS complete: best model score #{model.score}")
    {:ok, model}
    
  {:error, reason} ->
    Logger.error("NAS failed: #{inspect(reason)}")
    {:error, :nas_failed}
end
```

## Running Sagas Under Supervision

For production use, run sagas under the saga supervisor for fault tolerance:

```elixir
alias Thunderline.Thunderbolt.Sagas.Supervisor

# Start saga asynchronously
{:ok, pid} = Supervisor.run_saga(
  UserProvisioningSaga,
  %{email: "user@example.com", correlation_id: correlation_id}
)

# List active sagas
active = Supervisor.list_active_sagas()

# Stop a saga by correlation ID
Supervisor.stop_saga(correlation_id)
```

## Telemetry Events

All sagas emit standardized telemetry events:

### Saga Lifecycle
- `[:reactor, :saga, :start]` - Saga begins execution
- `[:reactor, :saga, :complete]` - Saga completes successfully
- `[:reactor, :saga, :fail]` - Saga fails after compensation
- `[:reactor, :saga, :compensate]` - Compensation triggered

### Step Lifecycle
- `[:reactor, :saga, :step, :start]` - Individual step starts
- `[:reactor, :saga, :step, :stop]` - Step completes successfully
- `[:reactor, :saga, :step, :exception]` - Step raises exception

### Metadata
All events include:
```elixir
%{
  saga: "Elixir.Thunderline.Thunderbolt.Sagas.UserProvisioningSaga",
  correlation_id: "01JXXX...",
  step: "create_user"  # for step events
}
```

## Writing Custom Sagas

### 1. Create Module

```elixir
defmodule MyApp.Sagas.CustomWorkflow do
  use Reactor, extensions: [Reactor.Dsl]
  
  require Logger
  alias Thunderline.Thunderbolt.Sagas.Base
  
  input :my_param
  input :correlation_id
  
  around Base.telemetry_wrapper()
  
  # Define steps...
end
```

### 2. Define Steps with Compensation

```elixir
step :create_resource do
  argument :param, input(:my_param)
  
  run fn %{param: param}, _ ->
    case MyApp.create_resource(param) do
      {:ok, resource} -> {:ok, resource}
      {:error, reason} -> {:error, reason}
    end
  end
  
  compensate fn resource, _ ->
    Logger.warning("Compensating: deleting #{resource.id}")
    MyApp.delete_resource(resource)
    {:ok, :compensated}
  end
end
```

### 3. Return Final Result

```elixir
return :final_step
```

## Testing Sagas

### Unit Test Structure

```elixir
defmodule MyApp.Sagas.CustomWorkflowTest do
  use ExUnit.Case, async: false
  
  @moduletag :saga
  
  describe "CustomWorkflow" do
    test "executes happy path" do
      inputs = %{my_param: "value", correlation_id: Thunderline.UUID.v7()}
      
      result = Reactor.run(CustomWorkflow, inputs)
      
      assert {:ok, %{resource: resource}} = result
    end
    
    test "compensates on failure" do
      # Force a step to fail
      # Verify compensation executes
      # Verify no side effects remain
    end
    
    test "emits telemetry events" do
      # Attach telemetry handler
      # Verify expected events emitted
    end
  end
end
```

## Best Practices

1. **Idempotent Steps**: Ensure steps can be retried safely if they fail
2. **Minimal State**: Pass only necessary data between steps
3. **Clear Compensation**: Each compensate function should cleanly undo its step
4. **Telemetry**: Use `Base.telemetry_wrapper()` for automatic instrumentation
5. **Correlation IDs**: Always pass correlation_id for tracing across systems
6. **Timeouts**: Set realistic timeouts for long-running steps (e.g., ML training)
7. **Error Classification**: Distinguish transient vs. permanent errors
8. **Event Emission**: Publish canonical events at key lifecycle points

## Feature Flag

Reactor sagas are controlled by the `:reactor_sagas` feature flag (enabled by default):

```elixir
config :thunderline, :features, [:reactor_sagas, ...]
```

To disable sagas (e.g., for testing):

```elixir
config :thunderline, :features, []
```

## Interaction Matrix

Sagas intentionally cross domain boundaries. Document saga flows in the interaction matrix:

| Saga | Domains Touched | Reason |
|------|----------------|--------|
| UserProvisioningSaga | Gate → Block → Link | User onboarding requires auth (Gate), vault (Block), community (Link) |
| UPMActivationSaga | Bolt → Crown → Block | Model promotion requires training (Bolt), policy (Crown), persistence (Block) |
| CerebrosNASSaga | Bolt only | NAS workflow entirely within ML domain |

## Further Reading

- [Reactor Documentation](https://hexdocs.pm/reactor)
- [Saga Pattern (Martin Fowler)](https://martinfowler.com/articles/patterns-of-distributed-systems/saga.html)
- [Event Taxonomy](../THUNDERLINE_DOMAIN_CATALOG.md#event-taxonomy-canonical-event-shape)
- [Domain Interaction Matrix](../THUNDERLINE_DOMAIN_CATALOG.md#domain-interaction-matrix-allowed-directions)
