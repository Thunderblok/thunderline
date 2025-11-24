#!/bin/bash
# Quick training job submission script
# This script helps you submit a real training job to Cerebros

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo ""
echo "======================================"
echo "🚀 Cerebros Training Job Launcher"
echo "======================================"
echo ""

# Check if Phoenix server is running
if ! lsof -i :5001 > /dev/null 2>&1; then
    echo "❌ Phoenix server not running on port 5001"
    echo ""
    echo "Start it with:"
    echo "  mix phx.server"
    echo ""
    exit 1
fi

echo "✓ Phoenix server detected on port 5001"
echo ""

# Check if MLflow is running
if ! lsof -i :5000 > /dev/null 2>&1; then
    echo "⚠️  MLflow server not detected on port 5000"
    echo ""
    echo "Starting MLflow server..."
    source .venv/bin/activate 2>/dev/null || true
    mlflow server --host 127.0.0.1 --port 5000 --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns &
    MLFLOW_PID=$!
    echo "✓ MLflow started (PID: $MLFLOW_PID)"
    sleep 2
else
    echo "✓ MLflow server detected on port 5000"
fi

echo ""
echo "======================================"
echo "📝 Submitting Training Job"
echo "======================================"
echo ""

# Get hostname for remsh
HOSTNAME=$(hostname -s)

# Connect to running Phoenix server and execute the script
iex --sname training_submit_$$ --remsh thunderline@$HOSTNAME --eval "
IO.puts(\"Connecting to thunderline@$HOSTNAME...\")
Code.require_file(\"$DIR/scripts/submit_real_training.exs\")
" || {
    echo ""
    echo "❌ Failed to connect to Phoenix server"
    echo ""
    echo "Make sure Phoenix was started with a node name:"
    echo "  iex --sname thunderline -S mix phx.server"
    echo ""
    echo "Or try manual submission:"
    echo "  iex --sname test --remsh thunderline@$HOSTNAME"
    echo "  Code.require_file(\"scripts/submit_real_training.exs\")"
    echo ""
    exit 1
}

echo ""
echo "======================================"
echo "✅ Job Submitted!"
echo "======================================"
echo ""
echo "🔍 Check status at:"
echo "  http://localhost:5001/cerebros"
echo ""
echo "📊 View MLflow experiments:"
echo "  http://localhost:5000"
echo ""
