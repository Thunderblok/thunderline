# Training Prompt Interface - UPM Integration Guide

**Status**: ✅ Implemented  
**Route**: `/training/prompt`  
**Last Updated**: 2024-11-24

---

## 🎯 Overview

The Training Prompt Interface provides a streamlined way to submit text-based training jobs directly from the dashboard. It integrates with:

- **UPM (Unified Persistent Model)**: Continuous learning pipeline
- **Cerebros NAS**: Neural Architecture Search for training
- **MLflow**: Experiment tracking and metrics
- **Oban**: Background job processing

## 🏗️ Architecture

```
User Input (Dashboard)
       ↓
TrainingPromptLive
       ↓
TrainingDataset.create → CSV generation
       ↓
CerebrosTrainer.enqueue_training (Oban)
       ↓
    [If UPM enabled]
       ├─→ UPM.TrainerWorker (online learning)
       ├─→ UPM.SnapshotManager (versioned snapshots)
       └─→ UPM.AdapterSync (distribute to agents)
       ↓
Cerebros Service (HTTP POST)
       ↓
MLflow Tracking (experiment metrics)
       ↓
Real-time Updates (PubSub)
       ↓
Dashboard Refresh
```

## 📋 Features

### 1. Text Input Interface
- **Multi-line text area** for training prompts
- **Character counter** for validation
- **Debounced input** for performance
- **Auto-save** draft prompts (future)

### 2. Training Configuration
- **Model Type Selection**:
  - Text Classification
  - Sentiment Analysis
  - Instruction Following
  - General Chat
- **Priority Levels**: Low, Normal, High
- **UPM Toggle**: Enable/disable UPM pipeline
- **MLflow Tracking**: Optional experiment tracking

### 3. Real-Time Job Monitoring
- **Live status updates** via PubSub
- **Progress tracking** (Phase 1-4)
- **Metric visualization** (loss, accuracy, etc.)
- **MLflow integration** with direct links

### 4. UPM Pipeline Status
- **Active Trainers** count
- **Snapshot History** (last 24h)
- **Drift Score** (p95)
- **Adapter Sync Status** (agents updated)

## 🚀 Usage

### Basic Training Job Submission

1. Navigate to `/training/prompt`
2. Enter training text in the text area
3. Select model type and priority
4. Enable UPM if desired
5. Click "Submit Training Job"

### Example Prompts

```text
Classify customer sentiment:

1. "I love this product!" -> positive
2. "Not what I expected" -> negative
3. "It works fine" -> neutral
```

```text
Instruction following:

Task: Summarize the following text
Input: [long text here]
Expected: [short summary]
```

### With UPM Integration

When UPM is enabled:
- Training creates a **feature window** event
- UPM **TrainerWorker** ingests the window
- Model updates are **incrementally applied**
- **Snapshots** are created at intervals
- **Adapters** sync to all connected agents
- **Drift monitoring** tracks model quality

## 🔧 Configuration

### Enable UPM

```elixir
# config/dev.exs or config/runtime.exs
config :thunderline, :features,
  unified_model: true
```

### Enable Oban

```elixir
# config/dev.exs
config :thunderline, Oban,
  repo: Thunderline.Repo,
  queues: [cerebros_training: 10],
  plugins: []
```

### Configure MLflow

```elixir
# config/config.exs
config :thunderline,
  mlflow_tracking_uri: System.get_env("MLFLOW_TRACKING_URI", "http://localhost:5000")
```

### Cerebros Service URL

```elixir
# config/config.exs
config :thunderline,
  cerebros_url: System.get_env("CEREBROS_URL", "http://localhost:8000")
```

## 📊 Data Flow

### 1. Dataset Creation

When you submit a prompt:

```elixir
# Creates TrainingDataset
dataset = TrainingDataset.create(%{
  name: "prompt_12345_text_classification",
  description: "Training dataset from prompt submission",
  metadata: %{
    "source" => "prompt_interface",
    "model_type" => "text_classification",
    "created_by" => "user@example.com"
  }
})

# Writes CSV file
# /tmp/thunderline/training/{dataset_id}/prompt_data.csv
```

### 2. Job Enqueueing

```elixir
# Enqueues Oban job
CerebrosTrainer.enqueue_training(dataset.id, [
  metadata: %{
    "prompt_preview" => "First 100 chars...",
    "model_type" => "text_classification",
    "use_upm" => true,
    "track_mlflow" => true
  }
])
```

### 3. Training Execution

```elixir
# Oban worker processes job
CerebrosTrainer.perform(%{
  "training_dataset_id" => dataset_id,
  "job_id" => job_id
})

# If UPM enabled:
# - Creates feature window
# - UPM.TrainerWorker processes window
# - Snapshot created after N windows
# - Adapters sync to agents
```

### 4. Progress Updates

```elixir
# PubSub broadcasts
PubSub.broadcast(Thunderline.PubSub, "training:jobs", {
  :job_update, %{
    job_id: job_id,
    status: :running,
    phase: 2,
    metrics: %{loss: 0.45, accuracy: 0.82}
  }
})
```

## 🧪 Testing

### Manual Testing

```bash
# 1. Start dependencies
mix deps.get
mix ecto.migrate

# 2. Start Phoenix server
DATABASE_URL="ecto://postgres:postgres@localhost:5432/thunderline" mix phx.server

# 3. Navigate to http://localhost:5001/training/prompt

# 4. Submit test prompt
# Text: "Test training prompt"
# Model: Text Classification
# UPM: Enabled
```

### Integration Testing

```elixir
# test/thunderline_web/live/training_prompt_live_test.exs
test "submits training job successfully", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/training/prompt")
  
  form_data = %{
    "prompt_text" => "Test training data",
    "model_type" => "text_classification",
    "priority" => "normal",
    "use_upm" => "true"
  }
  
  view
  |> form("#training-prompt-form", training: form_data)
  |> render_submit()
  
  assert_redirect(view, "/training/prompt")
  assert has_element?(view, "#recent-jobs")
end
```

## 📈 Metrics & Monitoring

### Training Job Metrics

The interface displays:
- **Job Status**: queued, running, completed, failed
- **Phase Progress**: 1-4 (Cerebros training phases)
- **Training Metrics**: Loss, accuracy, F1 score
- **Execution Time**: Started, duration
- **MLflow Link**: Direct link to experiment

### UPM Pipeline Metrics

When UPM is enabled:
- **Active Trainers**: Count of running UPM workers
- **Snapshots**: Count of snapshots created (24h)
- **Drift Score**: p95 drift metric
- **Adapters Synced**: Count of agents updated

## 🔗 Related Documentation

- [UPM Implementation](./docs/unified_persistent_model_implementation.md)
- [UPM Runbook](./docs/unified_persistent_model.md)
- [Cerebros Training Worker](./lib/thunderline/workers/cerebros_trainer.ex)
- [Training Dataset Resource](./lib/thunderline/thunderbolt/resources/training_dataset.ex)
- [Cerebros Training Job Resource](./lib/thunderline/thunderbolt/resources/cerebros_training_job.ex)

## 🛠️ Troubleshooting

### "UPM Disabled" Badge

**Cause**: Feature flag not enabled  
**Fix**:
```elixir
# config/dev.exs
config :thunderline, :features, unified_model: true
```

### Job Stuck in "Queued"

**Cause**: Oban not running or queue misconfigured  
**Fix**:
```elixir
# Verify Oban config
config :thunderline, Oban,
  repo: Thunderline.Repo,
  queues: [cerebros_training: 10]

# Check Oban is running
iex> Oban.check_queue(queue: :cerebros_training)
```

### MLflow Link Not Working

**Cause**: MLflow service not running  
**Fix**:
```bash
# Start MLflow
cd thunderhelm
mlflow server --host 0.0.0.0 --port 5000

# Or via Docker Compose
docker-compose up mlflow
```

### Cerebros Connection Failed

**Cause**: Cerebros service not available  
**Fix**:
```bash
# Start Cerebros service
cd thunderhelm/cerebros_service
python cerebros_service.py
```

## 🚧 Future Enhancements

- [ ] **Batch Prompt Submission**: Upload CSV of training prompts
- [ ] **Template Library**: Pre-built prompt templates
- [ ] **Prompt Versioning**: Track prompt iterations
- [ ] **A/B Testing**: Compare model versions
- [ ] **Auto-Labeling**: Use Ash_AI to suggest labels
- [ ] **Prompt Suggestions**: AI-powered prompt refinement
- [ ] **Export Results**: Download training results
- [ ] **Real-time Logs**: Stream training logs to dashboard
- [ ] **Model Comparison**: Side-by-side metric visualization
- [ ] **Scheduled Training**: Cron-based training runs

## 📞 Support

For issues or questions:
- Check [THUNDERLINE_MASTER_PLAYBOOK.md](./THUNDERLINE_MASTER_PLAYBOOK.md)
- Review [UPM Implementation Docs](./docs/unified_persistent_model_implementation.md)
- Check Oban dashboard at `/admin/oban`
- View MLflow UI at `http://localhost:5000`

---

**Quick Start Checklist**:
- [x] Oban enabled in `config/dev.exs`
- [x] LiveDebugger re-enabled
- [x] Router configured with `/training/prompt` route
- [x] TrainingPromptLive component created
- [ ] UPM feature flag enabled (optional)
- [ ] MLflow service running
- [ ] Cerebros service running
- [ ] PostgreSQL database migrated
