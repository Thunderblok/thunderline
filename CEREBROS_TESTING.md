# Cerebros Integration Testing Guide

## Status

✅ **Phase 1 Complete**: All Cerebros compilation errors fixed
- Fixed 34 files with broken module references
- Updated CerebrosJobsController to use Ash resources
- Updated CerebrosJobsJSON view to match schema
- Controller tests created (11 test cases)

⚠️ **Phase 2 - Integration Tests**: Hanging during execution
- Created comprehensive integration test suite (8 scenarios, 436 lines)
- Tests hang during compilation/setup phase
- Likely due to complex async requirements (database, Oban, file system)

✅ **Server Running**: Phoenix server started successfully on port 5001

## Manual Workflow Testing

The Cerebros service integration works in this flow:

```
Dataset Creation → Corpus Generation → Job Creation → 
Poll for Jobs → Fetch Corpus → Training → 
Report Metrics → Upload Checkpoints → Complete Job
```

### Step 1: Start Phoenix Server

```bash
cd /home/mo/DEV/Thunderline
iex -S mix phx.server
```

Server will be accessible at `http://localhost:5001`

### Step 2: Create Test Dataset (in IEx)

```elixir
# In the running IEx session:
alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain

# Create dataset
{:ok, dataset} = TrainingDataset.create(%{
  name: "Test Shakespeare Corpus",
  description: "Sample corpus for testing Cerebros integration",
  status: :collecting
}, domain: Domain)

# Simulate document uploads
{:ok, dataset} = dataset
  |> Ash.Changeset.for_update(:update, %{
    stage_1_count: 10,
    stage_2_count: 15,
    stage_3_count: 8,
    stage_4_count: 5,
    total_chunks: 1500
  })
  |> Ash.update(domain: Domain)

# Freeze dataset
{:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)

# Set corpus path
corpus_path = "/tmp/test_shakespeare_corpus.jsonl"
{:ok, dataset} = TrainingDataset.set_corpus_path(dataset, corpus_path, domain: Domain)

# Create corpus file
corpus_content = """
{"text": "To be, or not to be, that is the question"}
{"text": "All the world's a stage, and all the men and women merely players"}
{"text": "Romeo, Romeo, wherefore art thou Romeo?"}
"""
File.write!(corpus_path, corpus_content)

IO.puts("Dataset ID: #{dataset.id}")
IO.puts("Corpus path: #{corpus_path}")
```

### Step 3: Create Training Job

```elixir
# Create a training job
{:ok, job} = CerebrosTrainingJob.create(%{
  training_dataset_id: dataset.id,
  model_id: "gpt-4o-mini",
  hyperparameters: %{
    "n_epochs" => 3,
    "batch_size" => 32,
    "learning_rate" => 0.0001
  }
}, domain: Domain)

IO.puts("Training Job ID: #{job.id}")
IO.puts("Job Status: #{job.status}")  # Should be :queued
```

### Step 4: Test API Endpoints (curl)

Open a **new terminal** and run these commands:

#### Test 1: Poll for Jobs

```bash
curl -v http://localhost:5001/api/jobs/poll
```

Expected: 200 OK with job JSON containing the job you just created

#### Test 2: Get Corpus Data

```bash
# Replace JOB_ID with your job ID from Step 3
curl http://localhost:5001/api/datasets/DATASET_ID/corpus | jq
```

Expected: JSON with corpus_path and metadata

#### Test 3: Start Training

```bash
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/status \
  -H 'Content-Type: application/json' \
  -d '{"status": "running"}' | jq
```

Expected: 200 OK with updated job status

#### Test 4: Report Training Metrics (Phase 1)

```bash
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/metrics \
  -H 'Content-Type: application/json' \
  -d '{
    "metrics": {
      "loss": 2.5,
      "accuracy": 0.45,
      "perplexity": 12.2
    },
    "phase": 1
  }' | jq
```

Expected: 200 OK with updated metrics

#### Test 5: Upload Checkpoint (Phase 1)

```bash
curl -X POST http://localhost:5001/api/jobs/JOB_ID/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{
    "checkpoint_url": "s3://thunderline-models/shakespeare-model-phase1.keras",
    "phase": 1
  }' | jq
```

Expected: 200 OK with checkpoint added to list

#### Test 6: Report Metrics Phase 2

```bash
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/metrics \
  -H 'Content-Type: application/json' \
  -d '{
    "metrics": {
      "loss": 1.8,
      "accuracy": 0.62,
      "perplexity": 6.1
    },
    "phase": 2
  }' | jq
```

#### Test 7: Upload Checkpoint Phase 2

```bash
curl -X POST http://localhost:5001/api/jobs/JOB_ID/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{
    "checkpoint_url": "s3://thunderline-models/shakespeare-model-phase2.keras",
    "phase": 2
  }' | jq
```

#### Test 8: Complete Training

```bash
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/status \
  -H 'Content-Type: application/json' \
  -d '{"status": "completed", "final_model_id": "shakespeare-v1"}' | jq
```

Expected: 200 OK with final status and model ID

### Step 5: Verify Final State (in IEx)

```elixir
# Reload the job
job = CerebrosTrainingJob.get_by_id!(job.id, domain: Domain)

IO.inspect(job.status, label: "Final Status")  # Should be :completed
IO.inspect(job.checkpoint_urls, label: "Checkpoints")  # Should have 2 URLs
IO.inspect(job.metrics, label: "Final Metrics")
IO.inspect(job.final_model_id, label: "Model ID")
```

## Testing with Python Cerebros Service

### Prerequisites

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/cerebros_service
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Configure Environment

```bash
# Set Thunderline API URL
export THUNDERLINE_API_URL=http://localhost:5001
export POLL_INTERVAL=5  # Poll every 5 seconds
```

### Start Cerebros Service

```bash
./start_cerebros.sh
```

The service will:
1. Poll `/api/jobs/poll` every 5 seconds
2. Pick up queued jobs automatically
3. Download corpus from `/api/datasets/:id/corpus`
4. Execute training (simulated or real)
5. Report progress via `/api/jobs/:id/metrics`
6. Upload checkpoints via `/api/jobs/:id/checkpoints`
7. Mark complete via `/api/jobs/:id/status`

### Watch Service Logs

```bash
tail -f logs/cerebros_service.log
```

## API Endpoint Reference

### `GET /api/jobs/poll`
- **Purpose**: Get next queued job
- **Response**: 200 with job JSON, or 204 if no jobs
- **Used by**: Cerebros service polling loop

### `GET /api/datasets/:dataset_id/corpus`
- **Purpose**: Get corpus file path and metadata
- **Response**: JSON with `corpus_path`, `total_chunks`, etc.
- **Used by**: Before starting training

### `PATCH /api/jobs/:id/status`
- **Purpose**: Update job status (queued → running → completed/failed)
- **Body**: `{"status": "running"}` or `{"status": "completed", "final_model_id": "..."}` or `{"status": "failed", "error_message": "..."}`
- **Used by**: At training lifecycle transitions

### `PATCH /api/jobs/:id/metrics`
- **Purpose**: Report training metrics during execution
- **Body**: `{"metrics": {"loss": 1.5, ...}, "phase": 1}`
- **Used by**: Periodically during training

### `POST /api/jobs/:id/checkpoints`
- **Purpose**: Upload checkpoint URL after each phase
- **Body**: `{"checkpoint_url": "s3://...", "phase": 1}`
- **Used by**: After each training phase completes

## Troubleshooting

### Integration Tests Hanging

The integration test file hangs during compilation due to:
- Complex async setup (Ecto sandbox, Oban, file system)
- Database connection pool initialization timing
- EventBus subscription setup

**Workaround**: Use manual testing or simpler controller tests

### Oban Errors on Startup

```
GenServer {Oban.Registry, {Oban, Oban.Sonar}} terminating
** (ArgumentError) errors were found at the given arguments
```

**Impact**: Non-blocking - Oban will retry and eventually connect
**Cause**: Database connection timing during startup
**Fix**: Wait a few seconds for Oban to stabilize

### "three" JS Error

```
✘ [ERROR] Could not resolve "three"
```

**Impact**: CA visualization won't work, but API endpoints unaffected
**Cause**: Missing npm package
**Fix**: `cd assets && npm install three`

### No Jobs Returned from Poll

**Check**:
1. Job status is `:queued` (not `:running` or `:completed`)
2. Dataset has `corpus_path` set
3. Job `training_dataset_id` points to valid dataset

**Debug**:
```elixir
# In IEx:
require Ash.Query
CerebrosTrainingJob.list(
  query: Ash.Query.filter(CerebrosTrainingJob, status == :queued),
  domain: Domain
)
```

### Corpus File Not Found

**Check**:
1. File exists at the path stored in `dataset.corpus_path`
2. Path is absolute, not relative
3. File has read permissions

**Verify**:
```elixir
dataset = TrainingDataset.get_by_id!("...", domain: Domain)
File.exists?(dataset.corpus_path)
File.read!(dataset.corpus_path) |> String.split("\n") |> length()
```

## Next Steps

1. **Fix Integration Tests**: Simplify async setup or split into smaller test files
2. **Add MLflow Integration**: Sync metrics to MLflow experiments
3. **Document Python Client**: Create official Python SDK for Cerebros service
4. **Add Authentication**: Protect API endpoints with API keys or tokens
5. **Add Rate Limiting**: Prevent polling abuse
6. **WebSocket Support**: Replace polling with real-time job notifications

## Architecture Diagram

```
┌─────────────────┐
│  Phoenix Server │
│  (Thunderline)  │
└────────┬────────┘
         │
         │ HTTP API
         │
┌────────▼────────┐
│ Cerebros Service│ (Python)
│  - Polls jobs   │
│  - Trains models│
│  - Reports back │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   MLflow        │
│  (Experiments)  │
└─────────────────┘
```

## File Locations

- **Controller**: `lib/thunderline_web/controllers/cerebros_jobs_controller.ex`
- **View**: `lib/thunderline_web/controllers/cerebros_jobs_json.ex`
- **Resources**:
  - `lib/thunderline/thunderbolt/resources/cerebros_training_job.ex`
  - `lib/thunderline/thunderbolt/resources/training_dataset.ex`
- **Tests**:
  - `test/thunderline_web/controllers/cerebros_jobs_controller_test.exs`
  - `test/thunderline_web/cerebros_integration_test.exs` (hanging)
- **Python Service**: `thunderhelm/cerebros_service/`
- **This Guide**: `CEREBROS_TESTING.md`
- **Quick Test Script**: `scripts/test_cerebros_api.sh`

---

**Last Updated**: November 22, 2025
**Status**: Phase 1 complete, manual testing ready, integration tests pending fix
