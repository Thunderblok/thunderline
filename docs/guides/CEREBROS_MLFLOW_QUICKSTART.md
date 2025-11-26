# Cerebros + MLflow 3 Integration Quickstart

## Overview

This guide shows how to manually submit a training job to Cerebros with full MLflow 3 tracking integration.

**Architecture**:
- **Thunderline** (Phoenix + Ash) - REST API on port 5001
- **MLflow Server** - Experiment tracking on port 5000  
- **Cerebros Service** (Python) - Training worker that polls Thunderline and logs to MLflow

---

## Prerequisites Checklist

- [ ] Thunderline server running on `http://localhost:5001`
- [ ] MLflow 3.x server running on `http://localhost:5000`
- [ ] Python 3.13 environment with MLflow installed
- [ ] Cerebros service dependencies installed

---

## Step 1: Start MLflow Server

### Option A: Using the provided script

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/mlflow
chmod +x start_mlflow.sh
./start_mlflow.sh
```

**What it does**:
- Installs MLflow 3.x if not present
- Creates SQLite backend (`mlflow.db`)
- Creates artifact directory (`./mlruns`)
- Starts server on `http://0.0.0.0:5000`

### Option B: Manual start

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/mlflow

# Install MLflow 3.x
pip install "mlflow>=3.0.0"

# Create directories
mkdir -p mlruns

# Start server
mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri sqlite:///mlflow.db \
    --default-artifact-root ./mlruns
```

### Verify MLflow is Running

```bash
# Check health endpoint
curl http://localhost:5000/health

# List experiments (should return empty array initially)
curl http://localhost:5000/api/2.0/mlflow/experiments/list | jq
```

Expected response:
```json
{
  "experiments": []
}
```

---

## Step 2: Start Thunderline Server

```bash
cd /home/mo/DEV/Thunderline

# Set MLflow environment variable
export MLFLOW_TRACKING_URI=http://localhost:5000

# Start Phoenix
mix phx.server
```

**Wait for startup** (~30 seconds due to Oban initialization). Look for:
```
[info] Running ThunderlineWeb.Endpoint with Bandit 1.x.x at 127.0.0.1:5001 (http)
```

### Verify Thunderline is Running

```bash
curl http://localhost:5001/api/jobs/poll
```

Expected: `204 No Content` (no jobs queued yet)

---

## Step 3: Create Training Dataset and Job

### Option A: Using IEx (Recommended)

Open a new terminal and connect to the running Phoenix server:

```bash
cd /home/mo/DEV/Thunderline
iex --sname test --remsh thunderline@$(hostname -s)
```

Then execute:

```elixir
# Import modules
alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain

# 1. Create dataset
{:ok, dataset} = TrainingDataset.create(%{
  name: "Shakespeare Corpus - MLflow Test",
  description: "Testing Cerebros with MLflow integration",
  status: :collecting
}, domain: Domain)

IO.puts("✓ Dataset created: #{dataset.id}")

# 2. Simulate document collection
{:ok, dataset} = dataset
  |> Ash.Changeset.for_update(:update, %{
    stage_1_count: 15,
    stage_2_count: 12,
    stage_3_count: 10,
    stage_4_count: 8,
    total_chunks: 2000
  })
  |> Ash.update(domain: Domain)

IO.puts("✓ Updated document counts")

# 3. Freeze dataset
{:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)
IO.puts("✓ Dataset frozen: #{dataset.status}")

# 4. Create corpus file (JSONL format)
corpus_path = "/tmp/shakespeare_corpus_#{System.system_time(:second)}.jsonl"
corpus_content = """
{"text": "To be, or not to be, that is the question"}
{"text": "Whether 'tis nobler in the mind to suffer"}
{"text": "The slings and arrows of outrageous fortune"}
{"text": "Or to take arms against a sea of troubles"}
{"text": "And by opposing end them. To die—to sleep"}
{"text": "No more; and by a sleep to say we end"}
{"text": "The heart-ache and the thousand natural shocks"}
{"text": "That flesh is heir to: 'tis a consummation"}
{"text": "Devoutly to be wish'd. To die, to sleep"}
{"text": "To sleep, perchance to dream—ay, there's the rub"}
"""

File.write!(corpus_path, corpus_content)
IO.puts("✓ Corpus file created: #{corpus_path}")

# 5. Set corpus path
{:ok, dataset} = TrainingDataset.set_corpus_path(dataset, corpus_path, domain: Domain)
IO.puts("✓ Corpus path set")

# 6. Create training job with hyperparameters
{:ok, job} = CerebrosTrainingJob.create(%{
  training_dataset_id: dataset.id,
  model_id: "gpt-4o-mini",
  hyperparameters: %{
    "n_epochs" => 5,
    "batch_size" => 64,
    "learning_rate" => 0.001,
    "seq_length" => 128,
    "embedding_dim" => 256,
    "rnn_units" => 512
  },
  metadata: %{
    "experiment_name" => "shakespeare-mlflow-test",
    "run_name" => "run-#{System.system_time(:second)}"
  }
}, domain: Domain)

IO.puts("\n========================================")
IO.puts("Training Job Created Successfully!")
IO.puts("========================================")
IO.puts("Dataset ID:    #{dataset.id}")
IO.puts("Job ID:        #{job.id}")
IO.puts("Job Status:    #{job.status}")
IO.puts("Corpus Path:   #{corpus_path}")
IO.puts("Model ID:      #{job.model_id}")
IO.puts("========================================\n")

# Save these for later
dataset_id = dataset.id
job_id = job.id
```

**Save the `dataset_id` and `job_id` values** - you'll need them for API testing.

---

## Step 4: Start Cerebros Service (with MLflow)

Open a **new terminal**:

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/cerebros_service

# Activate Python environment (or create one)
python3.13 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export THUNDERLINE_API_URL=http://localhost:5001
export MLFLOW_TRACKING_URI=http://localhost:5000
export POLL_INTERVAL=5
export SERVICE_ID=cerebros-worker-1

# Start service
python cerebros_service.py
```

**What happens**:
1. Service registers with Thunderline
2. Starts polling every 5 seconds
3. Picks up queued job automatically
4. Creates MLflow experiment (if doesn't exist)
5. Starts MLflow run with hyperparameters
6. Executes training phases
7. Logs metrics to MLflow during training
8. Uploads checkpoints after each phase
9. Marks job complete in Thunderline

### Expected Output

```
2025-11-22 10:30:15 - cerebros - INFO - Starting Cerebros service: cerebros-worker-1
2025-11-22 10:30:15 - cerebros - INFO - MLflow tracking URI set to: http://localhost:5000
2025-11-22 10:30:15 - cerebros - INFO - Service registered successfully
2025-11-22 10:30:15 - cerebros - INFO - Polling for jobs...
2025-11-22 10:30:15 - cerebros - INFO - Found job: <job_id>
2025-11-22 10:30:15 - cerebros - INFO - Starting MLflow run for experiment: shakespeare-mlflow-test
2025-11-22 10:30:16 - cerebros - INFO - Training started with hyperparameters: {...}
2025-11-22 10:30:20 - cerebros - INFO - Phase 1/4 - Loss: 2.854, Accuracy: 0.423
2025-11-22 10:30:25 - cerebros - INFO - Phase 2/4 - Loss: 2.156, Accuracy: 0.512
2025-11-22 10:30:30 - cerebros - INFO - Phase 3/4 - Loss: 1.832, Accuracy: 0.589
2025-11-22 10:30:35 - cerebros - INFO - Phase 4/4 - Loss: 1.645, Accuracy: 0.634
2025-11-22 10:30:36 - cerebros - INFO - Training completed successfully
2025-11-22 10:30:36 - cerebros - INFO - MLflow run completed: <run_id>
```

---

## Step 5: Monitor Training in MLflow UI

### Access MLflow Web UI

Open browser: **http://localhost:5000**

### What You'll See

1. **Experiments List**:
   - Experiment: `shakespeare-mlflow-test` (or default name)

2. **Click on the experiment** to see runs:
   - Run name: `run-<timestamp>` or auto-generated
   - Status: RUNNING → FINISHED
   - Duration: ~30-60 seconds

3. **Click on the run** to see details:

   **Parameters** (logged from hyperparameters):
   - `n_epochs`: 5
   - `batch_size`: 64
   - `learning_rate`: 0.001
   - `seq_length`: 128
   - `embedding_dim`: 256
   - `rnn_units`: 512

   **Metrics** (logged during training):
   - `loss`: [2.854, 2.156, 1.832, 1.645] (decreasing)
   - `accuracy`: [0.423, 0.512, 0.589, 0.634] (increasing)
   - `perplexity`: [computed from loss]

   **Tags**:
   - `job_id`: <Thunderline job ID>
   - `dataset_id`: <Thunderline dataset ID>
   - `model_id`: gpt-4o-mini
   - `source`: cerebros-service

   **Artifacts**:
   - `checkpoints/phase_1.keras`
   - `checkpoints/phase_2.keras`
   - `checkpoints/phase_3.keras`
   - `checkpoints/phase_4.keras`
   - `model/final_model.keras`

---

## Step 6: Verify in Thunderline

### Check Job Status via API

```bash
# Get job status
curl http://localhost:5001/api/jobs/poll | jq

# Should show empty or next job (if multiple queued)
```

### Check Job Details in IEx

```elixir
# Reconnect to IEx if needed
alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
alias Thunderline.Thunderbolt.Domain
require Ash.Query

# Reload job (use your job_id from Step 3)
{:ok, job} = CerebrosTrainingJob
  |> Ash.Query.filter(id == ^"<your-job-id>")
  |> Ash.read_one(domain: Domain)

IO.inspect(job.status, label: "Status")                    # :completed
IO.inspect(job.phase, label: "Final Phase")               # 4
IO.inspect(job.metrics, label: "Final Metrics")           # %{loss: 1.645, accuracy: 0.634, ...}
IO.inspect(job.checkpoint_urls, label: "Checkpoints")     # List of S3/file URLs
IO.inspect(job.final_model_id, label: "Model ID")         # "shakespeare-v1" or similar
IO.inspect(job.completed_at, label: "Completed At")       # DateTime
```

### Check MLflow Integration in Database

```elixir
alias Thunderline.Thunderbolt.MLflow.{Experiment, Run}
require Ash.Query

# Find MLflow runs linked to this trial
{:ok, runs} = Run
  |> Ash.Query.filter(model_trial_id == ^job.id)
  |> Ash.read(domain: Domain)

IO.inspect(Enum.count(runs), label: "MLflow runs found")

# Get run details
run = List.first(runs)
IO.inspect(run.mlflow_run_id, label: "MLflow Run ID")
IO.inspect(run.status, label: "Run Status")
IO.inspect(run.params, label: "Parameters")
IO.inspect(run.metrics, label: "Metrics")
```

---

## Manual Testing (Without Cerebros Service)

If you want to test the API manually without running the Python service:

### 1. Poll for Job

```bash
curl http://localhost:5001/api/jobs/poll | jq
```

**Response**:
```json
{
  "id": "<job-id>",
  "status": "queued",
  "model_id": "gpt-4o-mini",
  "hyperparameters": {
    "n_epochs": 5,
    "batch_size": 64,
    "learning_rate": 0.001
  },
  "training_dataset_id": "<dataset-id>"
}
```

### 2. Get Corpus Path

```bash
curl http://localhost:5001/api/datasets/<dataset-id>/corpus | jq
```

**Response**:
```json
{
  "corpus_path": "/tmp/shakespeare_corpus_1234567890.jsonl",
  "dataset_name": "Shakespeare Corpus - MLflow Test",
  "total_chunks": 2000,
  "stage_counts": {
    "stage_1": 15,
    "stage_2": 12,
    "stage_3": 10,
    "stage_4": 8
  }
}
```

### 3. Start Training

```bash
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/status \
  -H 'Content-Type: application/json' \
  -d '{"status": "running"}' | jq
```

### 4. Report Metrics (Phase 1)

```bash
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/metrics \
  -H 'Content-Type: application/json' \
  -d '{
    "metrics": {
      "loss": 2.854,
      "accuracy": 0.423,
      "perplexity": 17.35
    },
    "phase": 1
  }' | jq
```

### 5. Upload Checkpoint (Phase 1)

```bash
curl -X POST http://localhost:5001/api/jobs/<job-id>/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{
    "checkpoint_url": "file:///tmp/models/shakespeare-phase1.keras",
    "phase": 1
  }' | jq
```

### 6. Repeat for Phases 2-4

Update phase number and adjust metrics (loss decreasing, accuracy increasing):

```bash
# Phase 2
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/metrics \
  -H 'Content-Type: application/json' \
  -d '{"metrics": {"loss": 2.156, "accuracy": 0.512}, "phase": 2}' | jq

curl -X POST http://localhost:5001/api/jobs/<job-id>/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{"checkpoint_url": "file:///tmp/models/shakespeare-phase2.keras", "phase": 2}' | jq

# Phase 3
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/metrics \
  -H 'Content-Type: application/json' \
  -d '{"metrics": {"loss": 1.832, "accuracy": 0.589}, "phase": 3}' | jq

curl -X POST http://localhost:5001/api/jobs/<job-id>/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{"checkpoint_url": "file:///tmp/models/shakespeare-phase3.keras", "phase": 3}' | jq

# Phase 4
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/metrics \
  -H 'Content-Type: application/json' \
  -d '{"metrics": {"loss": 1.645, "accuracy": 0.634}, "phase": 4}' | jq

curl -X POST http://localhost:5001/api/jobs/<job-id>/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{"checkpoint_url": "file:///tmp/models/shakespeare-phase4.keras", "phase": 4}' | jq
```

### 7. Complete Training

```bash
curl -X PATCH http://localhost:5001/api/jobs/<job-id>/status \
  -H 'Content-Type: application/json' \
  -d '{
    "status": "completed",
    "final_model_id": "shakespeare-v1-mlflow"
  }' | jq
```

---

## MLflow API Integration (Advanced)

If you want to log to MLflow directly from your testing:

### Create Experiment

```bash
curl -X POST http://localhost:5000/api/2.0/mlflow/experiments/create \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "manual-test-experiment",
    "artifact_location": "/tmp/mlflow-artifacts"
  }' | jq
```

**Response**: `{"experiment_id": "0"}`

### Create Run

```bash
curl -X POST http://localhost:5000/api/2.0/mlflow/runs/create \
  -H 'Content-Type: application/json' \
  -d '{
    "experiment_id": "0",
    "start_time": '$(date +%s%3N)',
    "tags": [
      {"key": "job_id", "value": "<your-job-id>"},
      {"key": "source", "value": "manual-test"}
    ]
  }' | jq
```

**Response**: `{"run": {"info": {"run_id": "abc123..."}}}`

### Log Parameters

```bash
curl -X POST http://localhost:5000/api/2.0/mlflow/runs/log-parameter \
  -H 'Content-Type: application/json' \
  -d '{
    "run_id": "<run-id>",
    "key": "learning_rate",
    "value": "0.001"
  }'
```

### Log Metrics

```bash
curl -X POST http://localhost:5000/api/2.0/mlflow/runs/log-metric \
  -H 'Content-Type: application/json' \
  -d '{
    "run_id": "<run-id>",
    "key": "loss",
    "value": 2.5,
    "timestamp": '$(date +%s%3N)',
    "step": 1
  }'
```

### Update Run Status

```bash
curl -X POST http://localhost:5000/api/2.0/mlflow/runs/update \
  -H 'Content-Type: application/json' \
  -d '{
    "run_id": "<run-id>",
    "status": "FINISHED",
    "end_time": '$(date +%s%3N)'
  }'
```

---

## Troubleshooting

### MLflow Server Not Starting

**Error**: `ModuleNotFoundError: No module named 'mlflow'`

**Solution**:
```bash
pip install "mlflow>=3.0.0"
```

**Error**: `Address already in use` (port 5000)

**Solution**:
```bash
# Find process using port 5000
lsof -i :5000

# Kill it
kill -9 <PID>

# Or use different port
mlflow server --port 5001 ...
```

### Cerebros Service Can't Connect

**Error**: `Connection refused to http://localhost:5001`

**Solution**: Verify Thunderline is running:
```bash
curl http://localhost:5001/api/jobs/poll
```

**Error**: `Failed to create MLflow experiment`

**Solution**: Check MLflow server logs and verify connectivity:
```bash
curl http://localhost:5000/health
```

### Job Not Being Picked Up

**Check job status in IEx**:
```elixir
alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
require Ash.Query

{:ok, jobs} = CerebrosTrainingJob
  |> Ash.Query.filter(status == :queued)
  |> Ash.read(domain: Thunderline.Thunderbolt.Domain)

IO.inspect(Enum.count(jobs), label: "Queued jobs")
```

**Verify polling works**:
```bash
curl http://localhost:5001/api/jobs/poll | jq
```

### Metrics Not Showing in MLflow

1. **Check MLflow run ID is set**:
   ```elixir
   IO.inspect(job.mlflow_run_id, label: "MLflow Run ID")
   ```

2. **Verify metrics in database**:
   ```elixir
   IO.inspect(job.metrics, label: "Job Metrics")
   ```

3. **Check MLflow UI** - refresh page, metrics update in real-time

---

## Environment Variables Reference

### Thunderline (Elixir)

```bash
export MLFLOW_TRACKING_URI=http://localhost:5000
export MLFLOW_DEFAULT_EXPERIMENT=thunderline-trials
export MLFLOW_ARTIFACT_LOCATION=./mlruns
export MLFLOW_ENABLED=true
```

### Cerebros Service (Python)

```bash
export THUNDERLINE_API_URL=http://localhost:5001
export MLFLOW_TRACKING_URI=http://localhost:5000
export POLL_INTERVAL=5
export SERVICE_ID=cerebros-worker-1
export HEARTBEAT_INTERVAL=30
```

### MLflow Server

```bash
export MLFLOW_HOST=0.0.0.0
export MLFLOW_PORT=5000
export MLFLOW_BACKEND_STORE=sqlite:///mlflow.db
export MLFLOW_ARTIFACT_ROOT=./mlruns
```

---

## Quick Reference Commands

### Start All Services

```bash
# Terminal 1: MLflow
cd thunderhelm/mlflow && ./start_mlflow.sh

# Terminal 2: Thunderline
export MLFLOW_TRACKING_URI=http://localhost:5000
mix phx.server

# Terminal 3: Cerebros
cd thunderhelm/cerebros_service
export THUNDERLINE_API_URL=http://localhost:5001
export MLFLOW_TRACKING_URI=http://localhost:5000
python cerebros_service.py
```

### Create Job (IEx one-liner)

```elixir
{:ok, ds} = Thunderline.Thunderbolt.Resources.TrainingDataset.create(%{name: "Test", status: :collecting}, domain: Thunderline.Thunderbolt.Domain); {:ok, ds} = Thunderline.Thunderbolt.Resources.TrainingDataset.freeze(ds, domain: Thunderline.Thunderbolt.Domain); File.write!("/tmp/corpus.jsonl", "{\"text\": \"test\"}"); {:ok, ds} = Thunderline.Thunderbolt.Resources.TrainingDataset.set_corpus_path(ds, "/tmp/corpus.jsonl", domain: Thunderline.Thunderbolt.Domain); Thunderline.Thunderbolt.Resources.CerebrosTrainingJob.create(%{training_dataset_id: ds.id, model_id: "test"}, domain: Thunderline.Thunderbolt.Domain)
```

### Check Status

```bash
# Thunderline jobs
curl http://localhost:5001/api/jobs/poll | jq

# MLflow experiments
curl http://localhost:5000/api/2.0/mlflow/experiments/list | jq

# MLflow runs
curl http://localhost:5000/api/2.0/mlflow/runs/search \
  -H 'Content-Type: application/json' \
  -d '{"experiment_ids": ["0"]}' | jq
```

---

## Next Steps

1. **Create real training corpus** with meaningful text data
2. **Tune hyperparameters** for better convergence
3. **Set up S3/artifact storage** instead of local filesystem
4. **Configure MLflow backend** with PostgreSQL for production
5. **Add custom metrics** (perplexity, BLEU score, etc.)
6. **Implement model serving** from checkpoints
7. **Set up monitoring** and alerts for failed jobs

---

## Resources

- **MLflow Documentation**: https://mlflow.org/docs/latest/
- **Cerebros Service Code**: `thunderhelm/cerebros_service/`
- **Thunderline MLflow Client**: `lib/thunderline/thunderbolt/mlflow/client.ex`
- **API Reference**: `CEREBROS_TESTING.md`
- **Full Testing Guide**: `CEREBROS_MANUAL_TEST_GUIDE.md`

---

**Last Updated**: November 22, 2025  
**Status**: Production-ready for local development and testing
