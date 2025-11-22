#!/bin/bash
# Complete Cerebros + MLflow Stack Startup Script

set -e

THUNDERLINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$THUNDERLINE_DIR"

echo "======================================"
echo "Cerebros + MLflow Stack Startup"
echo "======================================"
echo ""

# Check if already running
if lsof -Pi :5001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port 5001 already in use (Thunderline may be running)"
    echo "Kill existing processes? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Stopping existing processes..."
        pkill -f "mix phx.server" || true
        pkill -f "mlflow server" || true
        pkill -f "cerebros_service.py" || true
        sleep 2
    else
        echo "Exiting..."
        exit 1
    fi
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."
if ! command_exists mix; then
    echo "❌ Elixir/Mix not found. Please install Elixir first."
    exit 1
fi

if ! command_exists python3; then
    echo "❌ Python not found. Please install Python 3.13+ first."
    exit 1
fi

echo "✓ Prerequisites OK"
echo ""

# Step 1: Start MLflow
echo "======================================"
echo "Step 1: Starting MLflow Server"
echo "======================================"

cd thunderhelm/mlflow

if ! command_exists mlflow; then
    echo "Installing MLflow..."
    pip install "mlflow>=3.0.0"
fi

mkdir -p mlruns

echo "Starting MLflow on http://localhost:5000..."
mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri sqlite:///mlflow.db \
    --default-artifact-root ./mlruns \
    > mlflow.log 2>&1 &

MLFLOW_PID=$!
echo "✓ MLflow started (PID: $MLFLOW_PID)"
echo "  Logs: thunderhelm/mlflow/mlflow.log"

# Wait for MLflow to be ready
echo -n "Waiting for MLflow to be ready"
for i in {1..30}; do
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        echo " ✓"
        break
    fi
    echo -n "."
    sleep 1
done

cd "$THUNDERLINE_DIR"
echo ""

# Step 2: Start Thunderline
echo "======================================"
echo "Step 2: Starting Thunderline Server"
echo "======================================"

export MLFLOW_TRACKING_URI=http://localhost:5000

echo "Starting Phoenix on http://localhost:5001..."
mix phx.server > thunderline.log 2>&1 &
THUNDERLINE_PID=$!
echo "✓ Thunderline started (PID: $THUNDERLINE_PID)"
echo "  Logs: thunderline.log"

# Wait for Thunderline to be ready (longer timeout for Oban init)
echo -n "Waiting for Thunderline to be ready (this may take 30-60 seconds)"
for i in {1..90}; do
    if curl -s http://localhost:5001/api/jobs/poll > /dev/null 2>&1; then
        echo " ✓"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# Step 3: Setup Python environment for Cerebros
echo "======================================"
echo "Step 3: Setting up Cerebros Service"
echo "======================================"

cd thunderhelm/cerebros_service

if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "Installing dependencies..."
pip install -q -r requirements.txt

echo "✓ Cerebros environment ready"
cd "$THUNDERLINE_DIR"
echo ""

# Summary
echo "======================================"
echo "✓ Stack Started Successfully!"
echo "======================================"
echo ""
echo "Services:"
echo "  • MLflow UI:     http://localhost:5000"
echo "  • Thunderline:   http://localhost:5001"
echo "  • Cerebros:      Ready to start manually"
echo ""
echo "Process IDs:"
echo "  • MLflow:        $MLFLOW_PID"
echo "  • Thunderline:   $THUNDERLINE_PID"
echo ""
echo "Logs:"
echo "  • MLflow:        thunderhelm/mlflow/mlflow.log"
echo "  • Thunderline:   thunderline.log"
echo ""
echo "======================================"
echo "Next Steps:"
echo "======================================"
echo ""
echo "1. Create a training job (in new terminal):"
echo "   cd $THUNDERLINE_DIR"
echo "   iex --sname test --remsh thunderline@\$(hostname -s)"
echo ""
echo "   Then paste the job creation commands from:"
echo "   CEREBROS_MLFLOW_QUICKSTART.md (Step 3)"
echo ""
echo "2. Start Cerebros service (in new terminal):"
echo "   cd $THUNDERLINE_DIR/thunderhelm/cerebros_service"
echo "   source venv/bin/activate"
echo "   export THUNDERLINE_API_URL=http://localhost:5001"
echo "   export MLFLOW_TRACKING_URI=http://localhost:5000"
echo "   python cerebros_service.py"
echo ""
echo "3. Monitor in browser:"
echo "   MLflow UI: http://localhost:5000"
echo ""
echo "======================================"
echo "To stop all services:"
echo "======================================"
echo "  kill $MLFLOW_PID $THUNDERLINE_PID"
echo "  # Or run: pkill -f 'mlflow server|mix phx.server|cerebros_service'"
echo ""
