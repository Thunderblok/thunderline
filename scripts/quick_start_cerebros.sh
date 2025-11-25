#!/bin/bash
# Quick Start: Cerebros + MLflow Testing
# This script starts the services in the CURRENT terminal and provides instructions

echo "======================================"
echo "Cerebros + MLflow Quick Start"
echo "======================================"
echo ""

# Kill any existing processes
echo "Cleaning up any existing processes..."
pkill -f "mlflow server" 2>/dev/null || true
pkill -f "mix phx.server" 2>/dev/null || true
pkill -f "cerebros_service.py" 2>/dev/null || true
sleep 2

echo "✓ Cleanup complete"
echo ""

echo "======================================"
echo "Starting Services"
echo "======================================"
echo ""

# Get directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📊 Step 1: Start MLflow Server"
echo "Run this in TERMINAL 1:"
echo ""
echo "  cd $DIR/thunderhelm/mlflow"
echo "  pip install 'mlflow>=3.0.0'"
echo "  mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns"
echo ""
echo "Wait for: 'Listening at: http://0.0.0.0:5000'"
echo ""

echo "🚀 Step 2: Start Thunderline Server"
echo "Run this in TERMINAL 2:"
echo ""
echo "  cd $DIR"
echo "  export MLFLOW_TRACKING_URI=http://localhost:5000"
echo "  mix phx.server"
echo ""
echo "Wait for: '[info] Running ThunderlineWeb.Endpoint...at 127.0.0.1:5001'"
echo ""

echo "💡 Step 3: Create Training Job"
echo "Run this in TERMINAL 3:"
echo ""
echo "  cd $DIR"
echo "  iex --sname test --remsh thunderline@\$(hostname -s)"
echo ""
echo "Then paste this in IEx:"
echo ""
cat << 'EOF'
  alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
  alias Thunderline.Thunderbolt.Domain

  # Create dataset
  {:ok, ds} = TrainingDataset.create(%{
    name: "Shakespeare Test",
    description: "MLflow integration test",
    status: :collecting
  }, domain: Domain)

  # Freeze it
  {:ok, ds} = TrainingDataset.freeze(ds, domain: Domain)

  # Create corpus file
  corpus = "/tmp/shakespeare_#{System.system_time(:second)}.jsonl"
  File.write!(corpus, """
  {"text": "To be, or not to be, that is the question"}
  {"text": "Whether 'tis nobler in the mind to suffer"}
  {"text": "The slings and arrows of outrageous fortune"}
  """)

  # Set corpus path
  {:ok, ds} = TrainingDataset.set_corpus_path(ds, corpus, domain: Domain)

  # Create job
  {:ok, job} = CerebrosTrainingJob.create(%{
    training_dataset_id: ds.id,
    model_id: "gpt-4o-mini",
    hyperparameters: %{
      "n_epochs" => 5,
      "batch_size" => 64,
      "learning_rate" => 0.001
    }
  }, domain: Domain)

  IO.puts("\n✓ Job created!")
  IO.puts("Dataset ID: #{ds.id}")
  IO.puts("Job ID: #{job.id}")
EOF
echo ""

echo "🤖 Step 4: Start Cerebros Service"
echo "Run this in TERMINAL 4:"
echo ""
echo "  cd $DIR/thunderhelm/cerebros_service"
echo "  python3 -m venv venv  # First time only"
echo "  source venv/bin/activate"
echo "  pip install -r requirements.txt  # First time only"
echo "  export THUNDERLINE_API_URL=http://localhost:5001"
echo "  export MLFLOW_TRACKING_URI=http://localhost:5000"
echo "  python cerebros_service.py"
echo ""

echo "======================================"
echo "Monitoring"
echo "======================================"
echo ""
echo "• MLflow UI:     http://localhost:5000"
echo "• Thunderline:   http://localhost:5001"
echo ""
echo "Test connectivity:"
echo "  curl http://localhost:5000/health  # MLflow"
echo "  curl http://localhost:5001/api/jobs/poll  # Thunderline"
echo ""

echo "======================================"
echo "Full Documentation"
echo "======================================"
echo "  $DIR/CEREBROS_MLFLOW_QUICKSTART.md"
echo ""
