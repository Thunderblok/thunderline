#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Restarting Phoenix with Database Connection"
echo "=============================================="
echo ""

# Kill existing Phoenix/BEAM processes
echo "🛑 Stopping existing processes..."
pkill -9 beam.smp 2>/dev/null || echo "  (no beam processes found)"
pkill -9 epmd 2>/dev/null || echo "  (no epmd found)"
sleep 2

# Set database environment
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/thunderline"
export PGHOST="localhost"
export PGPORT="5432"
export PGUSER="postgres"
export PGPASSWORD="postgres"
export PGDATABASE="thunderline"

echo ""
echo "✅ Environment configured:"
echo "  DATABASE_URL=$DATABASE_URL"
echo ""

# Navigate to project root
cd "$(dirname "$0")/.."

# Recompile with fixes
echo "🔨 Recompiling..."
mix compile --force 2>&1 | tail -10
echo ""

# Start Phoenix
echo "🚀 Starting Phoenix server..."
echo "  (Phoenix will be available at http://localhost:5001)"
echo ""

iex -S mix phx.server
