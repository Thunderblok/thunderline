# Spectral Norm Integration - Architecture Overview

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         CEREBROS (Python)                        │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Optuna Study                                               │ │
│  │  • spectral_norm: [True, False]                           │ │
│  │  • learning_rate, n_layers, etc.                          │ │
│  └───────────────┬────────────────────────────────────────────┘ │
│                  │                                               │
│  ┌───────────────▼────────────────────────────────────────────┐ │
│  │ Model Builder                                              │ │
│  │  if spectral_norm:                                        │ │
│  │      layer = torch.nn.utils.spectral_norm(layer)          │ │
│  └───────────────┬────────────────────────────────────────────┘ │
│                  │                                               │
│  ┌───────────────▼────────────────────────────────────────────┐ │
│  │ Training Loop                                              │ │
│  │  • Emit events → Thunderline                              │ │
│  │  • Log to MLflow (params, metrics, artifacts)             │ │
│  └───────────────┬────────────────────────────────────────────┘ │
└──────────────────┼────────────────────────────────────────────────┘
                   │
                   │ HTTP POST /api/events/ml
                   │
┌──────────────────▼────────────────────────────────────────────────┐
│                    THUNDERLINE (Elixir)                           │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ThunderGate (External Integration)                         │  │
│  │  POST /api/events/ml                                       │  │
│  │  • Validate event payload                                  │  │
│  │  • Inject into ThunderFlow                                 │  │
│  └───────────────┬────────────────────────────────────────────┘  │
│                  │                                                │
│  ┌───────────────▼────────────────────────────────────────────┐  │
│  │ ThunderFlow (Event Pipeline)                               │  │
│  │  Events: [:thunderline, :ml, :run, :start|:stop|:metric]  │  │
│  │  • Route to subscribers (Broadway)                         │  │
│  │  • Log for observability                                   │  │
│  └───────────────┬────────────────────────────────────────────┘  │
│                  │                                                │
│  ┌───────────────▼────────────────────────────────────────────┐  │
│  │ ThunderBolt (ML Orchestration)                             │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ CerebrosBridge (Anti-Corruption Layer)               │  │  │
│  │  │  • Translator: Cerebros → Ash Resources              │  │  │
│  │  │  • Invoker: Call external training                   │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ Ash Resources                                        │  │  │
│  │  │  • ModelRun (experiment)                             │  │  │
│  │  │  • Trial (spectral_norm: bool, hyperparams, metrics)│  │  │
│  │  │  • Artifact (model checkpoint reference)            │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └───────────────┬────────────────────────────────────────────┘  │
│                  │                                                │
│  ┌───────────────▼────────────────────────────────────────────┐  │
│  │ ThunderBlock (Persistence)                                 │  │
│  │  • PostgreSQL (Trial records)                              │  │
│  │  • Vault/S3 (Model artifacts)                              │  │
│  │  • MLflow artifact storage backend                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ThunderLink (UI/LiveView)                                  │  │
│  │  • Real-time training monitor                              │  │
│  │  • Experiment comparison dashboard                         │  │
│  │  • Subscribe to ThunderFlow events via PubSub              │  │
│  └────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘

                           │
                           │ Parallel Logging
                           │
                   ┌───────▼────────┐
                   │     MLflow     │
                   │  • Parameters  │
                   │  • Metrics     │
                   │  • Artifacts   │
                   │  • Tags        │
                   └────────────────┘
```

---

## Data Flow: Training Trial Lifecycle

### 1. **Trial Initiation** (ThunderBolt → Cerebros)

```elixir
# Thunderline creates Trial record
trial = %Trial{
  id: "abc-123",
  model_run_id: "run-456",
  spectral_norm: true,  # <-- NEW FIELD
  hyperparams: %{learning_rate: 0.001, n_layers: 4},
  status: :running
}

# CerebrosBridge.Client invokes external training
CerebrosBridge.Client.start_trial(%{
  trial_id: trial.id,
  spectral_norm: trial.spectral_norm,
  hyperparams: trial.hyperparams
})
```

### 2. **Training Start** (Cerebros → Thunderline)

```python
# Cerebros Python code
import requests

def start_training(trial_config):
    # Build model with spectral norm if enabled
    model = build_model(spectral_norm=trial_config['spectral_norm'])
    
    # Emit start event to Thunderline
    requests.post('http://thunderline:4000/api/events/ml', json={
        'event': 'ml.run.start',
        'trial_id': trial_config['trial_id'],
        'metadata': {
            'spectral_norm': trial_config['spectral_norm'],
            'hyperparams': trial_config['hyperparams']
        }
    })
    
    # Log to MLflow
    mlflow.log_param('spectral_norm', trial_config['spectral_norm'])
    mlflow.set_tag('trial_id', trial_config['trial_id'])
```

### 3. **Training Progress** (Cerebros → Thunderline)

```python
# During training loop
for epoch in range(num_epochs):
    train_loss = train_one_epoch(model, dataloader)
    val_acc = validate(model, val_dataloader)
    
    # Emit metric event
    requests.post('http://thunderline:4000/api/events/ml', json={
        'event': 'ml.run.metric',
        'trial_id': trial_id,
        'metadata': {'epoch': epoch},
        'measurements': {
            'train_loss': train_loss,
            'val_accuracy': val_acc
        }
    })
    
    # Log to MLflow
    mlflow.log_metric('train_loss', train_loss, step=epoch)
    mlflow.log_metric('val_accuracy', val_acc, step=epoch)
```

### 4. **Training Completion** (Cerebros → Thunderline)

```python
# Save model and emit completion event
torch.save(model.state_dict(), 'model.pth')
mlflow.log_artifact('model.pth')

requests.post('http://thunderline:4000/api/events/ml', json={
    'event': 'ml.run.stop',
    'trial_id': trial_id,
    'metadata': {
        'success': True,
        'epochs': num_epochs,
        'mlflow_run_id': mlflow.active_run().info.run_id
    },
    'measurements': {
        'duration_ms': training_duration_ms,
        'final_val_accuracy': final_acc
    }
})
```

### 5. **Result Processing** (Thunderline)

```elixir
# ThunderFlow event handler
def handle_training_stop(event) do
  trial_id = event.metadata.trial_id
  
  # Update Trial resource via Ash action
  Trial
  |> Ash.get!(trial_id)
  |> Ash.Changeset.for_update(:complete, %{
    status: :completed,
    metrics: event.measurements,
    mlflow_run_id: event.metadata.mlflow_run_id
  })
  |> Ash.update!()
  
  # Create Artifact record for model checkpoint
  Artifact.create!(%{
    trial_id: trial_id,
    type: :model_checkpoint,
    storage_path: "s3://thunderblock/models/#{trial_id}/model.pth",
    metadata: %{spectral_norm: event.metadata.spectral_norm}
  })
end
```

---

## Anti-Corruption Layer Pattern

The **CerebrosBridge** acts as a protective boundary:

### What Crosses the Boundary ✅

- **Inputs to Cerebros**: Trial configuration (spectral_norm flag, hyperparams)
- **Outputs from Cerebros**: Results (metrics, artifact URIs)
- **Events**: Canonical ThunderFlow event format

### What Does NOT Cross ❌

- PyTorch model internals
- Training loop implementation details
- Cerebros-specific data structures
- Direct database writes from Python

### Translation Example

```elixir
# CerebrosBridge.Translator
defmodule Thunderline.ThunderBolt.CerebrosBridge.Translator do
  @doc "Translate Cerebros trial result to Ash Trial resource"
  def translate_result(cerebros_result) do
    %{
      metrics: %{
        val_accuracy: cerebros_result["accuracy"],
        val_loss: cerebros_result["loss"],
        training_time: cerebros_result["duration_seconds"]
      },
      spectral_norm: cerebros_result["config"]["spectral_norm"],
      status: translate_status(cerebros_result["status"])
    }
  end
  
  defp translate_status("success"), do: :completed
  defp translate_status("failed"), do: :failed
  defp translate_status(_), do: :unknown
end
```

---

## Event Taxonomy

All ML training events follow this schema:

```elixir
%Thunderline.Event{
  # Event name (list-style for Telemetry)
  name: [:thunderline, :ml, :run, :start | :stop | :metric],
  
  # ISO8601 timestamp
  timestamp: ~U[2025-10-05 12:34:56.789Z],
  
  # Event source identifier
  source: "cerebros_training_job",
  
  # Contextual metadata (non-numeric)
  metadata: %{
    trial_id: "abc-123",
    model_run_id: "run-456",
    spectral_norm: true,
    hyperparams: %{...},
    epoch: 10  # for metric events
  },
  
  # Numeric measurements
  measurements: %{
    duration_ms: 45000,
    train_loss: 0.123,
    val_accuracy: 0.891
  }
}
```

---

## Database Schema Changes

### Trials Table Extension

```sql
-- Migration: Add spectral_norm column
ALTER TABLE trials
ADD COLUMN spectral_norm BOOLEAN DEFAULT false,
ADD COLUMN mlflow_run_id VARCHAR(255);

-- Index for filtering by constraint type
CREATE INDEX idx_trials_spectral_norm ON trials(spectral_norm);

-- Index for MLflow cross-reference
CREATE INDEX idx_trials_mlflow_run_id ON trials(mlflow_run_id);
```

### Sample Query

```elixir
# Query all trials with spectral norm enabled
Trial
|> Ash.Query.filter(spectral_norm == true)
|> Ash.Query.filter(status == :completed)
|> Ash.read!()

# Aggregate metrics by constraint type
Trial
|> Ash.Query.aggregate(:avg, :metrics["val_accuracy"], group_by: :spectral_norm)
|> Ash.read!()
```

---

## MLflow Integration Points

### Artifact Storage Configuration

```python
# Configure MLflow to use ThunderBlock S3 bucket
import mlflow
mlflow.set_tracking_uri("http://mlflow-server:5000")
mlflow.set_experiment("thunderline-spectral-norm-study")

# Artifacts stored in ThunderBlock-managed S3
os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://thunderblock-s3:9000'
os.environ['AWS_ACCESS_KEY_ID'] = 'thunderblock'
os.environ['AWS_SECRET_ACCESS_KEY'] = os.getenv('THUNDERBLOCK_SECRET')
```

### Cross-Referencing

```python
# Tag MLflow run with Thunderline IDs
with mlflow.start_run(run_name=f"trial-{trial_id}"):
    mlflow.set_tag("trial_id", trial_id)
    mlflow.set_tag("model_run_id", model_run_id)
    mlflow.set_tag("constraint_method", "spectral_norm" if use_spectral else "none")
    
    # ... training and logging ...
    
    # Return MLflow run ID to Thunderline
    return mlflow.active_run().info.run_id
```

---

## LiveView Dashboard Subscription

```elixir
defmodule ThunderlineWeb.MLTrainingMonitorLive do
  use ThunderlineWeb, :live_view
  
  def mount(_params, _session, socket) do
    # Subscribe to ML training events
    if connected?(socket) do
      :ok = ThunderFlow.EventBus.subscribe("ml.run.*")
    end
    
    {:ok, assign(socket, trials: load_running_trials())}
  end
  
  def handle_info({:event, %{name: "ml.run.start"} = event}, socket) do
    # Add new trial to UI
    trial = %{
      id: event.metadata.trial_id,
      spectral_norm: event.metadata.spectral_norm,
      status: :running,
      metrics: []
    }
    
    {:noreply, stream_insert(socket, :trials, trial)}
  end
  
  def handle_info({:event, %{name: "ml.run.metric"} = event}, socket) do
    # Update trial metrics in real-time
    # ... stream update logic ...
  end
end
```

---

## Key Takeaways

1. **Clean Boundaries**: Cerebros stays Python, Thunderline stays Elixir
2. **Event-Driven**: All communication via canonical ThunderFlow events
3. **Dual Logging**: MLflow for detailed history, Thunderline for real-time
4. **Anti-Corruption**: CerebrosBridge translates external data to Ash resources
5. **Observability-First**: Every action produces telemetry

---

**Status**: Architecture design complete ✅  
**Next**: Begin Phase 1 implementation (Ash resource extensions)
