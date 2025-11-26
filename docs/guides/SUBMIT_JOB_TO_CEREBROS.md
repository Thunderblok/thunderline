# Cerebros Manual Job Submission - Complete Workflow

## Quick Start (4 Terminals)

### Terminal 1: Start MLflow

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/mlflow

# First time only
pip install 'mlflow>=3.0.0'

# Start server
mlflow server \
  --host 0.0.0.0 \
  --port 5000 \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root ./mlruns
```

**Wait for**: `Listening at: http://0.0.0.0:5000`

---

### Terminal 2: Start Thunderline with IEx

```bash
cd /home/mo/DEV/Thunderline

# Set MLflow environment variable
export MLFLOW_TRACKING_URI=http://localhost:5000

# Start with interactive shell
iex -S mix phx.server
```

**Wait for**: 
- `[info] Running ThunderlineWeb.Endpoint...at 127.0.0.1:5001`
- IEx prompt: `iex(1)>`

**Note**: You'll see Oban errors for ~10 seconds - this is normal, they resolve automatically.

---

### In Terminal 2 (IEx prompt): Create Training Job

Paste these commands **one block at a time**:

```elixir
# Import modules
alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain
```

```elixir
# 1. Create dataset
dataset = Ash.create!(TrainingDataset, %{
  name: "Shakespeare Corpus - MLflow Test",
  description: "Testing Cerebros with MLflow 3 integration"
})

IO.puts("✓ Dataset created: #{dataset.id}")
```

```elixir
# 2. Simulate document collection
dataset = dataset
  |> Ash.Changeset.for_update(:update, %{
    stage_1_count: 15,
    stage_2_count: 12,
    stage_3_count: 10,
    stage_4_count: 8,
    total_chunks: 2000
  })
  |> Ash.update!()

IO.puts("✓ Document counts updated")
```

```elixir
# 3. Freeze dataset
dataset = dataset |> Ash.Changeset.for_update(:freeze) |> Ash.update!()
IO.puts("✓ Dataset frozen: #{dataset.status}")
```

```elixir
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
```

```elixir
# 5. Set corpus path
dataset = dataset |> Ash.Changeset.for_update(:set_corpus_path, %{corpus_path: corpus_path}) |> Ash.update!()
IO.puts("✓ Corpus path set")
```

```elixir
# 6. Create training job with hyperparameters
job = Ash.create!(CerebrosTrainingJob, %{
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
})

IO.puts("\n========================================")
IO.puts("Training Job Created Successfully!")
IO.puts("========================================")
IO.puts("Dataset ID:    #{dataset.id}")
IO.puts("Job ID:        #{job.id}")
IO.puts("Job Status:    #{job.status}")
IO.puts("Corpus Path:   #{corpus_path}")
IO.puts("Model ID:      #{job.model_id}")
IO.puts("========================================\n")
```

**Save the Job ID and Dataset ID** - you'll need them for testing!

---

### Terminal 3: Test with curl

Once the job is created, test the API:

```bash
# Poll for jobs (should return your job)
curl http://localhost:5001/api/jobs/poll | jq

# Get corpus path (replace DATASET_ID)
curl http://localhost:5001/api/datasets/DATASET_ID/corpus | jq

# Start training (replace JOB_ID)
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/status \
  -H 'Content-Type: application/json' \
  -d '{"status": "running"}' | jq

# Report metrics
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/metrics \
  -H 'Content-Type: application/json' \
  -d '{
    "metrics": {"loss": 2.5, "accuracy": 0.45, "perplexity": 12.2},
    "phase": 1
  }' | jq

# Upload checkpoint
curl -X POST http://localhost:5001/api/jobs/JOB_ID/checkpoints \
  -H 'Content-Type: application/json' \
  -d '{
    "checkpoint_url": "file:///tmp/models/shakespeare-p1.keras",
    "phase": 1
  }' | jq

# Complete training
curl -X PATCH http://localhost:5001/api/jobs/JOB_ID/status \
  -H 'Content-Type: application/json' \
  -d '{
    "status": "completed",
    "final_model_id": "shakespeare-v1"
  }' | jq
```

---

### Terminal 4: Start Cerebros Service (Optional - Automated)

For automatic job processing:

```bash
cd /home/mo/DEV/Thunderline/thunderhelm/cerebros_service

# First time setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set environment
export THUNDERLINE_API_URL=http://localhost:5001
export MLFLOW_TRACKING_URI=http://localhost:5000
export POLL_INTERVAL=5

# Start service
python cerebros_service.py
```

The service will:
- Poll for jobs every 5 seconds
- Pick up queued jobs automatically
- Execute training
- Log to MLflow
- Report progress back to Thunderline

---

## Verify in MLflow UI

Open browser: **http://localhost:5000**

You should see:
- **Experiments**: `shakespeare-mlflow-test`
- **Runs**: With parameters (n_epochs, batch_size, learning_rate, etc.)
- **Metrics**: loss, accuracy, perplexity (over time)
- **Artifacts**: Checkpoints and models

---

## Check Job Status in IEx

Back in Terminal 2 (IEx):

```elixir
# Reload job (use your job ID)
job = CerebrosTrainingJob
  |> Ash.Query.filter(id == ^"YOUR-JOB-ID-HERE")
  |> Ash.read_one!()

# Check status
IO.inspect(job.status, label: "Status")
IO.inspect(job.phase, label: "Phase")
IO.inspect(job.metrics, label: "Metrics")
IO.inspect(job.checkpoint_urls, label: "Checkpoints")
IO.inspect(job.final_model_id, label: "Final Model")
```

---

## Troubleshooting

### "Could not connect to thunderline@ataro"

**Solution**: Don't use remote shell. Instead:
```bash
cd /home/mo/DEV/Thunderline
export MLFLOW_TRACKING_URI=http://localhost:5000
iex -S mix phx.server
```

This starts Phoenix **with** an IEx console directly.

### Oban Errors During Startup

```
[error] GenServer {Oban.Registry, {Oban, Oban.Peer}} terminating
** (ArgumentError) errors were found at the given arguments:
  * 2nd argument: not a key that exists in the table
```

**This is normal!** These errors happen during the first 10-30 seconds of startup as Oban initializes. They resolve automatically. Just wait for:
```
[info] Running ThunderlineWeb.Endpoint...at 127.0.0.1:5001
```

### MLflow Not Starting

```bash
# Check if port 5000 is in use
lsof -i :5000

# Kill existing process
kill -9 <PID>

# Restart MLflow
cd thunderhelm/mlflow
mlflow server --host 0.0.0.0 --port 5000 ...
```

### Server Not Responding

```bash
# Check if server is running
curl http://localhost:5001/api/jobs/poll

# Check process
ps aux | grep "mix phx.server"

# Restart if needed
pkill -f "mix phx.server"
iex -S mix phx.server
```

---

## Quick Scripts

### One-line Job Creation (after IEx is ready)

```elixir
alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}; ds = Ash.create!(TrainingDataset, %{name: "QuickTest"}); ds = ds |> Ash.Changeset.for_update(:freeze) |> Ash.update!(); File.write!("/tmp/corpus.jsonl", "{\"text\": \"test data\"}"); ds = ds |> Ash.Changeset.for_update(:set_corpus_path, %{corpus_path: "/tmp/corpus.jsonl"}) |> Ash.update!(); job = Ash.create!(CerebrosTrainingJob, %{training_dataset_id: ds.id, model_id: "test", hyperparameters: %{"n_epochs" => 3}}); IO.puts("Job ID: #{job.id}")
```

### Start All Services (separate terminals)

Use the helper script:
```bash
./start_with_iex.sh
```

---

## File Reference

- **Complete Guide**: `CEREBROS_MLFLOW_QUICKSTART.md`
- **Testing Guide**: `CEREBROS_MANUAL_TEST_GUIDE.md`
- **Original Docs**: `CEREBROS_TESTING.md`
- **Start Script**: `start_with_iex.sh`

---

**Last Updated**: November 22, 2025  
**Status**: Production-ready for manual job submission with MLflow 3
