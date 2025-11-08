# Cerebros RunWorker Saga Implementation

## Overview

Converted the Cerebros `RunWorker` from a traditional Oban worker to use **Reactor saga orchestration** for better transaction management, compensation, and observability.

## Architecture

### Before (Traditional Oban Worker)
```
RunWorker.perform/1
  ├─ Validate inputs
  ├─ Prepare run
  ├─ Execute training
  ├─ Monitor progress
  ├─ Collect results
  └─ Cleanup
```

**Problems:**
- Manual error handling at each step
- No automatic compensation/rollback
- Hard to test individual steps
- Limited observability of step boundaries

### After (Reactor Saga)
```
RunSaga (Reactor)
  ├─ Step: validate_inputs (sync)
  ├─ Step: prepare_run (sync)
  ├─ Step: execute_training (async) ← with compensate/undo
  ├─ Step: monitor_progress (async)
  ├─ Step: collect_results (sync)
  └─ Step: cleanup (sync)

RunWorker.perform/1
  └─ Reactor.run(RunSaga, params, context)
```

**Benefits:**
✅ Automatic compensation on failure
✅ Built-in retry logic with exponential backoff
✅ Clear step boundaries with telemetry
✅ Testable steps in isolation
✅ Visual DAG of dependencies
✅ Rollback support via `undo/4`

## Key Components

### 1. RunSaga (`lib/thunderline/thunderbolt/cerebros/run_saga.ex`)

**Reactor DSL-based saga** with 6 steps:

| Step | Type | Purpose | Compensation |
|------|------|---------|--------------|
| `validate_inputs` | sync | Validate worker params | N/A |
| `prepare_run` | sync | Setup environment | N/A |
| `execute_training` | async | Start training job | Compensate on connection errors |
| `monitor_progress` | async | Poll training status | N/A |
| `collect_results` | sync | Gather metrics/artifacts | N/A |
| `cleanup` | sync | Remove temp files | N/A |

**Key Features:**
- **Async training execution** for long-running operations
- **Compensate callback** to retry on transient errors (DB connection failures)
- **Undo callback** to rollback training job if later steps fail
- **Step modules** for clean separation of concerns
- **Telemetry integration** at each step boundary

### 2. RunWorker (`lib/thunderline/thunderbolt/cerebros/run_worker.ex`)

**Simplified Oban worker** that delegates to saga:

```elixir
@impl Oban.Worker
def perform(%Job{args: args}) do
  context = build_context(args)
  
  case Reactor.run(RunSaga, args, context) do
    {:ok, result} -> {:ok, result}
    {:error, error} -> {:error, error}
    {:halted, state} -> {:error, "Training halted: #{inspect(state)}"}
  end
end
```

**Enqueue helper:**
```elixir
RunWorker.enqueue_saga(inputs, opts \\ [])
```

### 3. Step Modules (to be created)

```
lib/thunderline/thunderbolt/cerebros/steps/
  ├─ validate_inputs.ex       # Input validation
  ├─ prepare_run.ex           # Environment setup
  ├─ execute_training.ex      # Training execution + compensation
  ├─ monitor_progress.ex      # Progress polling
  ├─ collect_results.ex       # Results gathering
  └─ cleanup.ex               # Cleanup operations
```

Each step implements `Reactor.Step` behavior:
```elixir
defmodule Thunderline.Thunderbolt.Cerebros.Steps.ExecuteTraining do
  use Reactor.Step

  @impl true
  def run(arguments, context, options) do
    # Execute training logic
  end

  @impl true
  def compensate(reason, arguments, context, options) do
    case reason do
      %DBConnection.ConnectionError{} -> :retry
      _other -> :ok
    end
  end

  @impl true
  def undo(training_job, arguments, context, options) do
    # Rollback: cancel training job
    :ok
  end
end
```

## Usage Examples

### Enqueue Training Run
```elixir
# Via saga helper
{:ok, job} = RunWorker.enqueue_saga(%{
  worker_id: UUID.v7(),
  model_name: "resnet50",
  dataset_name: "imagenet",
  config_path: "/configs/train.yaml",
  checkpoint_interval: 100
})

# Traditional Oban enqueue still works
{:ok, job} = RunWorker.enqueue(%{...}, scheduled_at: ~U[2025-01-01 00:00:00Z])
```

### Test Individual Steps
```elixir
# Test just validation step
{:ok, validated} = ValidateInputs.run(%{
  model_name: "test_model",
  dataset_name: "test_data",
  config_path: "/tmp/config.yaml"
}, %{}, [])

# Test full saga
{:ok, result} = Reactor.run(RunSaga, inputs, context)
```

### Monitor Saga Progress
```elixir
# Reactor emits telemetry at step boundaries
:telemetry.attach_many(
  "saga-monitor",
  [
    [:reactor, :step, :start],
    [:reactor, :step, :complete],
    [:reactor, :step, :compensate]
  ],
  &handle_saga_event/4,
  nil
)
```

## Migration Checklist

- [x] Create RunSaga with Reactor DSL
- [x] Update RunWorker to delegate to saga
- [x] Add enqueue_saga helper to CerebrosBridge
- [x] Create test script
- [ ] Implement individual step modules:
  - [ ] ValidateInputs
  - [ ] PrepareRun
  - [ ] ExecuteTraining (with compensate/undo)
  - [ ] MonitorProgress
  - [ ] CollectResults
  - [ ] Cleanup
- [ ] Add comprehensive tests
- [ ] Update Cerebros documentation
- [ ] Add telemetry handlers for observability

## Benefits Realized

1. **Better Error Handling**
   - Automatic compensation on transient failures
   - Clean rollback via undo callbacks
   - Retry logic built into Reactor

2. **Improved Testability**
   - Test steps in isolation
   - Mock dependencies easily
   - Clear test boundaries

3. **Enhanced Observability**
   - Telemetry at each step
   - Visual DAG of workflow
   - Step timing metrics

4. **Maintainability**
   - Clean separation of concerns
   - Declarative step dependencies
   - Self-documenting workflow

## Next Steps

1. **Implement step modules** with full business logic
2. **Add comprehensive tests** for each step + saga
3. **Setup telemetry handlers** for monitoring
4. **Document compensation strategies** for each step
5. **Benchmark performance** vs traditional worker
6. **Consider other workers** for saga conversion (if beneficial)

## References

- Reactor Usage Rules: `deps/reactor/usage-rules.md`
- Thunderline Reactor Examples: `lib/thunderline/*/reactors/`
- Oban Worker Docs: `deps/ash_oban/usage-rules.md`
