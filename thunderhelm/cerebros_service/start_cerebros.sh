#!/bin/bash
# Start Cerebros training service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Starting Cerebros Training Service"
echo "======================================"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found"
    exit 1
fi

# Check dependencies
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

echo "Activating virtual environment..."
source venv/bin/activate

echo "Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Configuration
export CEREBROS_SERVICE_ID="${CEREBROS_SERVICE_ID:-cerebros-1}"
export THUNDERLINE_URL="${THUNDERLINE_URL:-http://localhost:4000}"
export MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"
export CEREBROS_POLL_INTERVAL="${CEREBROS_POLL_INTERVAL:-5}"
export CEREBROS_HEARTBEAT_INTERVAL="${CEREBROS_HEARTBEAT_INTERVAL:-30}"

echo ""
echo "Configuration:"
echo "  Service ID: $CEREBROS_SERVICE_ID"
echo "  Thunderline URL: $THUNDERLINE_URL"
echo "  MLflow URL: $MLFLOW_TRACKING_URI"
echo "  Poll Interval: ${CEREBROS_POLL_INTERVAL}s"
echo "  Heartbeat Interval: ${CEREBROS_HEARTBEAT_INTERVAL}s"
echo ""

echo "Starting service..."
echo ""

# Run service
python3 cerebros_service.py
