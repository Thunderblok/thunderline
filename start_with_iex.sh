#!/bin/bash
# Start Thunderline with IEx for interactive development

cd "$(dirname "$0")"

echo "======================================"
echo "Starting Thunderline with IEx Console"
echo "======================================"
echo ""

# Set MLflow URI
export MLFLOW_TRACKING_URI=http://localhost:5000

echo "Starting Phoenix server with IEx console..."
echo "This will give you an interactive shell to create jobs."
echo ""
echo "After startup (30-60 seconds), you can run commands directly."
echo ""

iex -S mix phx.server
