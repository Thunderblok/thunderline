# Spectral Normalization - Quick Reference Card

## What Is Spectral Normalization?

**In Plain English**: A technique to keep neural network weights "well-behaved" during training by constraining how much they can amplify signals.

**Technical**: Limits the spectral norm (largest singular value) of weight matrices to 1, preventing gradient explosion and improving training stability.

**PyTorch One-Liner**:
```python
layer = torch.nn.utils.spectral_norm(nn.Linear(in_feat, out_feat))
```

---

## Why High Command Wants This

✅ **Stability**: Prevents training from exploding or collapsing  
✅ **Generalization**: Often improves model performance on unseen data  
✅ **Research**: Compare constrained vs unconstrained models scientifically  
✅ **Toggleable**: Easy A/B testing via Optuna hyperparameter

---

## The Integration in 5 Bullets

1. **Optuna adds toggle**: `spectral_norm: [True, False]` in search space
2. **Cerebros applies it**: Wraps linear layers when flag is True
3. **Thunderline tracks it**: New `spectral_norm` boolean in Trial resource
4. **Events flow**: Training lifecycle events via ThunderFlow
5. **MLflow logs it**: Parameters, metrics, artifacts all recorded

---

## Key Architecture Principle: Anti-Corruption Layer

```
┌─────────────────┐         ┌──────────────────┐
│   Cerebros      │         │   Thunderline    │
│   (Python)      │◄────────┤   (Elixir)       │
│                 │  Bridge │                  │
│ • PyTorch       │         │ • Ash Resources  │
│ • ML internals  │         │ • Events         │
└─────────────────┘         └──────────────────┘
        │                            │
        │   NO LEAKAGE              │
        │   ACROSS BOUNDARY         │
        └───────────────────────────┘
```

**What crosses**: Clean data (configs, results, events)  
**What doesn't**: PyTorch tensors, training loops, model internals

---

## Domain Responsibilities

| Domain | Responsibility | Spectral Norm Role |
|--------|---------------|-------------------|
| **ThunderBolt** | ML orchestration | Stores Trial.spectral_norm, invokes Cerebros |
| **ThunderFlow** | Event pipeline | Routes ml.run.* events |
| **ThunderBlock** | Persistence | Stores model artifacts |
| **ThunderGate** | External integration | Accepts events from Cerebros |
| **ThunderLink** | UI/LiveView | Displays trials grouped by constraint |

---

## Event Quick Reference

### ml.run.start
```elixir
%Event{
  name: [:thunderline, :ml, :run, :start],
  metadata: %{
    trial_id: "abc-123",
    model_run_id: "run-456",
    spectral_norm: true,  # ← THE KEY FLAG
    hyperparams: %{...}
  }
}
```

### ml.run.stop
```elixir
%Event{
  name: [:thunderline, :ml, :run, :stop],
  metadata: %{trial_id: "abc-123", success: true},
  measurements: %{
    duration_ms: 45000,
    final_val_accuracy: 0.91
  }
}
```

### ml.run.metric (optional, periodic)
```elixir
%Event{
  name: [:thunderline, :ml, :run, :metric],
  metadata: %{trial_id: "abc-123", epoch: 10},
  measurements: %{
    train_loss: 0.123,
    val_accuracy: 0.87
  }
}
```

---

## Trial Resource Schema

```elixir
defmodule Thunderline.ThunderBolt.Trial do
  use Ash.Resource
  
  attributes do
    uuid_primary_key :id
    
    # ⭐ NEW FIELD ⭐
    attribute :spectral_norm, :boolean, default: false
    
    # NEW FIELD for MLflow cross-reference
    attribute :mlflow_run_id, :string
    
    # Existing fields
    attribute :hyperparams, :map
    attribute :metrics, :map
    attribute :status, :atom  # :running, :completed, :failed
  end
  
  relationships do
    belongs_to :model_run, ModelRun
    has_one :artifact, Artifact
  end
end
```

---

## MLflow Integration Points

### Logging from Cerebros
```python
# Parameters (static config)
mlflow.log_param('spectral_norm', True)
mlflow.log_param('learning_rate', 0.001)

# Metrics (performance)
mlflow.log_metric('val_accuracy', 0.91)

# Tags (cross-reference)
mlflow.set_tag('trial_id', 'abc-123')
mlflow.set_tag('model_run_id', 'run-456')

# Artifacts (model files)
mlflow.log_artifact('model.pth')
```

### Querying from Thunderline
```elixir
# Option 1: Direct Ash query
Trial
|> Ash.Query.filter(spectral_norm == true)
|> Ash.Query.filter(status == :completed)
|> Ash.read!()

# Option 2: Via MLflow run ID
trial = Trial |> Ash.get!(trial_id)
# Use trial.mlflow_run_id to fetch from MLflow API
```

---

## Dashboard Queries You'll Need

### Comparison: Spectral Norm ON vs OFF
```elixir
# Average accuracy by constraint type
Trial
|> Ash.Query.filter(status == :completed)
|> Ash.Query.aggregate(:avg, field(:metrics, ["val_accuracy"]))
|> Ash.Query.group_by(:spectral_norm)
|> Ash.read!()

# Expected result:
# [
#   %{spectral_norm: true, avg_val_accuracy: 0.89},
#   %{spectral_norm: false, avg_val_accuracy: 0.85}
# ]
```

### Recent Trials
```elixir
Trial
|> Ash.Query.filter(inserted_at > ago(1, :day))
|> Ash.Query.sort(inserted_at: :desc)
|> Ash.Query.limit(20)
|> Ash.read!()
```

---

## Common Pitfalls & Solutions

### ❌ Pitfall: MLflow and Thunderline records diverge
**Solution**: Use same trial_id in both systems, sync immediately after training

### ❌ Pitfall: Event flood crashes LiveView
**Solution**: Use debouncing, sampling, or aggregation for high-frequency events

### ❌ Pitfall: Cerebros changes break Thunderline
**Solution**: Version the API contract, validate payloads at ThunderGate

### ❌ Pitfall: Tight coupling between Python and Elixir
**Solution**: CerebrosBridge enforces clean boundary, only pass simple data structures

---

## Testing Strategy

### Unit Tests (Elixir)
```bash
# Test Trial resource
mix test test/thunderline/thunderbolt/trial_test.exs

# Test event emission
mix test test/thunderline/thunderflow/ml_events_test.exs

# Test bridge translation
mix test test/thunderline/thunderbolt/cerebros_bridge_test.exs
```

### Integration Tests (Elixir + Mocked Cerebros)
```bash
# Test full event flow
mix test test/thunderline_web/integration/ml_events_test.exs
```

### End-to-End Tests (Elixir + Real Cerebros)
```bash
# Dry-run experiment with 5-10 trials
mix run scripts/run_spectral_norm_experiment.exs
```

---

## Debugging Checklist

When things break:

1. **Check event logs**: Are events arriving at ThunderGate?
   ```bash
   grep "ml.run" logs/dev.log | tail -20
   ```

2. **Verify database**: Is spectral_norm being saved?
   ```bash
   psql -d thunderline_dev -c "SELECT id, spectral_norm, status FROM trials LIMIT 5;"
   ```

3. **Check MLflow**: Are runs being logged?
   ```bash
   curl http://localhost:5000/api/2.0/mlflow/experiments/list
   ```

4. **Inspect bridge telemetry**: Any errors in CerebrosBridge?
   ```elixir
   :telemetry.list_handlers([:cerebros, :bridge])
   ```

5. **Review Cerebros logs**: Is Python code executing correctly?
   ```bash
   tail -f /path/to/cerebros/logs/training.log
   ```

---

## Performance Targets

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Event ingestion latency | <100ms (p95) | ThunderGate telemetry |
| Database query time | <50ms | Ash query instrumentation |
| LiveView update lag | <200ms | Phoenix LiveView telemetry |
| MLflow sync time | <500ms | CerebrosBridge timing |

---

## Useful Commands

### Development
```bash
# Generate migration
mix ash_postgres.generate_migrations

# Run migrations
mix ecto.migrate

# Run tests
mix test

# Start server
iex -S mix phx.server

# Check event handlers
:telemetry.list_handlers([])
```

### Debugging
```bash
# Inspect Trial records
iex> Thunderline.ThunderBolt.Trial |> Ash.read!() |> Enum.take(5)

# Manually emit test event
iex> Thunderline.ThunderFlow.MLEvents.emit_training_start("test-id", "run-id", %{})

# Check MLflow connection
curl http://localhost:5000/health
```

### Deployment
```bash
# Build release
MIX_ENV=prod mix release

# Run migrations in production
bin/thunderline eval "Thunderline.Release.migrate()"

# Check logs
kubectl logs -n thunderline -l app=thunderline --tail=100
```

---

## Resources

- **Spectral Norm Paper**: [arxiv.org/abs/1802.05957](https://arxiv.org/abs/1802.05957)
- **PyTorch Docs**: [pytorch.org/docs/stable/generated/torch.nn.utils.spectral_norm.html](https://pytorch.org/docs/stable/generated/torch.nn.utils.spectral_norm.html)
- **MLflow Docs**: [mlflow.org/docs/latest/index.html](https://mlflow.org/docs/latest/index.html)
- **Ash Framework**: [ash-hq.org](https://ash-hq.org)

---

## Questions for High Command

Before starting implementation:

1. **Priority**: Is this urgent or can it be incremental over 6 weeks?
2. **Cerebros Access**: Do we have write access to the Python codebase?
3. **MLflow Setup**: Is infrastructure provisioned? (tracking server, artifact storage)
4. **Team Coordination**: Who owns the Python changes vs Elixir changes?
5. **Rollout Strategy**: Prototype first or full implementation?

---

**Keep This Handy**: Bookmark this file for quick lookups during implementation!

*Per aspera ad astra* - Through hardships to the stars! ⭐
