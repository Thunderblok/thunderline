# Cerebros NAS Run Saga Implementation

## Overview
Refactored the Cerebros NAS run execution to use a **Reactor saga** for robust, fault-tolerant orchestration.

## Architecture

### RunSaga (Reactor-based)
**Location:** `lib/thunderline/thunderbolt/cerebros_bridge/run_saga.ex`

The saga implements a full lifecycle pipeline with proper compensation:

```
┌─────────────────────────────────────────────────────────┐
│                    RunSaga Pipeline                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. check_enabled                                        │
│     └─→ Verify bridge is enabled                        │
│                                                          │
│  2. ensure_run_id                                        │
│     └─→ Generate run ID if not provided                 │
│                                                          │
│  3. publish_start_event                                  │
│     └─→ Emit "cerebros.nas.run.started"                 │
│     └─→ Compensation: publish run.cancelled             │
│                                                          │
│  4. execute_nas_run (async)                              │
│     └─→ Call PythonXInvoker.call_nas_run()              │
│     └─→ Compensation: cleanup artifacts                 │
│                                                          │
│  5. process_results                                      │
│     └─→ Validate result structure                       │
│                                                          │
│  6. publish_complete_event                               │
│     └─→ Emit "cerebros.nas.run.completed"               │
│                                                          │
│  7. return result                                        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### RunWorker (Simplified)
**Location:** `lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex`

Now acts as a thin Oban wrapper that:
- Validates job arguments
- Delegates to RunSaga
- Handles Reactor errors
- Integrates with Oban retry/backoff

**Before:** ~450 lines with complex inline logic  
**After:** ~90 lines, delegates to saga

## Benefits

### 1. **Separation of Concerns**
- Worker = Oban integration layer
- Saga = Business logic orchestration
- Each step is isolated and testable

### 2. **Error Handling**
- Automatic compensation on failures
- Cleanup of partial artifacts
- Event publishing for observability
- Structured error propagation

### 3. **Testability**
```elixir
# Can run saga synchronously in tests
{:ok, result} = RunSaga.run(spec, opts)

# Or enqueue async via Oban
{:ok, job} = RunSaga.enqueue(spec, opts)
```

### 4. **Compensation Logic**
Each step can define compensation:
```elixir
step :execute_nas_run do
  run fn args, _context ->
    # Execute NAS run
  end

  compensate fn _value, %{run_id: run_id}, _context ->
    # Clean up artifacts if later steps fail
    File.rm_rf("/tmp/cerebros/#{run_id}")
    :ok
  end
end
```

### 5. **Event-Driven Observability**
- `cerebros.nas.run.started` at saga start
- `cerebros.nas.run.completed` on success
- `cerebros.nas.run.cancelled` on compensation
- Full event trail for debugging

## Usage

### Enqueue a NAS Run
```elixir
spec = %{
  "dataset_id" => "mnist",
  "objective" => "accuracy",
  "search_space" => %{...}
}

# Via CerebrosBridge module
{:ok, job} = Thunderline.Thunderbolt.CerebrosBridge.enqueue_run(spec, 
  budget: %{"max_trials" => 10}
)

# Direct saga access
{:ok, result} = Thunderline.Thunderbolt.CerebrosBridge.RunSaga.run(spec, opts)
```

### Testing
```bash
# Test saga execution
mix run scripts/test_nas_saga.exs

# Monitor job status
SELECT * FROM oban_jobs WHERE queue = 'ml' ORDER BY inserted_at DESC LIMIT 5;
```

## Migration Notes

### Removed from RunWorker
- All trial processing logic (now in saga)
- Contract building and validation
- Telemetry emission (moved to saga steps)
- Complex argument normalization
- 300+ lines of helper functions

### Preserved Behavior
- Same Oban queue (`ml`)
- Same job argument structure
- Same error handling semantics
- Same event publishing pattern

## Future Enhancements

### 1. **Parallel Trial Execution**
```elixir
step :execute_trials, async?: true do
  # Run multiple trials concurrently
end
```

### 2. **Checkpointing**
Reactor supports halting and resuming:
```elixir
case RunSaga.run(spec, opts) do
  {:halted, state} -> 
    # Save state and resume later
    Reactor.run(state, %{}, %{})
end
```

### 3. **Sub-Sagas**
Compose complex workflows:
```elixir
step :hyperparameter_search do
  compose Thunderline.Thunderbolt.HyperparameterSaga
end
```

### 4. **Dynamic Step Generation**
```elixir
step :execute_nas_run do
  run fn args, _context ->
    # Can return new steps dynamically
    {:ok, result, [new_step1, new_step2]}
  end
end
```

## Files Modified

1. **Created:** `lib/thunderline/thunderbolt/cerebros_bridge/run_saga.ex`
   - Reactor saga with full lifecycle
   - Compensation logic
   - Event publishing

2. **Simplified:** `lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex`
   - Thin Oban wrapper
   - Delegates to RunSaga
   - ~80% code reduction

3. **Updated:** `lib/thunderline/thunderbolt/cerebros_bridge.ex`
   - Updated to use RunSaga
   - Simplified public API

4. **Created:** `scripts/test_nas_saga.exs`
   - Test script for saga execution

## Validation Checklist

- [x] Saga compiles without errors
- [x] Worker delegates to saga
- [x] Compensation logic defined
- [x] Event publishing integrated
- [ ] Integration tests pass
- [ ] Can enqueue jobs via Oban
- [ ] Can run saga synchronously
- [ ] Compensation triggers on failure
- [ ] Events appear in EventBus

## Next Steps

1. **Test the saga:**
   ```bash
   # Set bridge enabled
   export TL_ENABLE_CEREBROS_BRIDGE=true
   
   # Run test script
   mix run scripts/test_nas_saga.exs
   ```

2. **Monitor execution:**
   ```sql
   -- Watch Oban jobs
   SELECT id, state, queue, attempted_at, errors 
   FROM oban_jobs 
   WHERE queue = 'ml' 
   ORDER BY inserted_at DESC;
   ```

3. **Verify events:**
   ```elixir
   # In IEx
   iex> Thunderline.Thunderflow.EventBus.subscribe(self(), "cerebros.**")
   iex> flush()  # See events
   ```

## Resources

- [Reactor Documentation](https://hexdocs.pm/reactor)
- [Reactor Usage Rules](deps/reactor/usage-rules.md)
- Original Worker: `git show HEAD~1:lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex`
