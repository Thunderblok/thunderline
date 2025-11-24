#!/bin/bash
# Start MLflow tracking server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Starting MLflow Tracking Server"
echo "======================================"

# Check if mlflow is installed
if ! command -v mlflow &> /dev/null; then
    echo "mlflow not found, installing..."
    pip install mlflow>=2.9.0
fi

# Configuration
HOST="${MLFLOW_HOST:-0.0.0.0}"
PORT="${MLFLOW_PORT:-5000}"
BACKEND_STORE="${MLFLOW_BACKEND_STORE:-sqlite:///mlflow.db}"
ARTIFACT_ROOT="${MLFLOW_ARTIFACT_ROOT:-./mlruns}"

echo ""
echo "Configuration:"
echo "  Host: $HOST"
echo "  Port: $PORT"
echo "  Backend Store: $BACKEND_STORE"
echo "  Artifact Root: $ARTIFACT_ROOT"
echo ""

# Create artifact directory
mkdir -p "$ARTIFACT_ROOT"

echo "Starting MLflow server..."
echo ""

# Start server
mlflow server \
    --host "$HOST" \
    --port "$PORT" \
    --backend-store-uri "$BACKEND_STORE" \
    --default-artifact-root "$ARTIFACT_ROOT"
