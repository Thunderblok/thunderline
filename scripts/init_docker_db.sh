#!/usr/bin/env bash
set -euo pipefail

# Thunderline Docker PostgreSQL Database Initialization
# This script initializes the Thunderline database in the existing Docker container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🗄️  Thunderline Docker Database Initialization"
echo "=============================================="
echo ""

# Check if Docker container is running
CONTAINER_NAME="thunderline_postgres"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container '$CONTAINER_NAME' is not running!"
    echo ""
    echo "Starting it with docker-compose..."
    cd "$PROJECT_ROOT"
    docker-compose up -d postgres
    sleep 3
fi

echo "✅ Container '$CONTAINER_NAME' is running"
echo ""

# Check PostgreSQL version
PG_VERSION=$(docker exec "$CONTAINER_NAME" psql -U postgres -t -c "SELECT version();" 2>/dev/null | grep -oP 'PostgreSQL \K\d+' || echo "unknown")
echo "📊 PostgreSQL Version: $PG_VERSION"
echo ""

# Connection details
echo "🔌 Connection Details:"
docker exec "$CONTAINER_NAME" env | grep -E "POSTGRES_(DB|USER|PASSWORD)" || echo "  (using container defaults)"
echo ""

# Check current database state
echo "📋 Current Databases:"
docker exec "$CONTAINER_NAME" psql -U postgres -c "\l" | grep -E "thunderline|Name|---" || echo "  (none)"
echo ""

# Ask to reset database
echo "⚠️  This will:"
echo "  1. Drop and recreate 'thunderline' database (if exists)"
echo "  2. Install required extensions"
echo "  3. Run Ash PostgreSQL migrations"
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Drop and recreate database
echo ""
echo "🔧 Resetting database..."

docker exec "$CONTAINER_NAME" psql -U postgres <<'EOF'
-- Drop existing database
DROP DATABASE IF EXISTS thunderline;

-- Recreate database
CREATE DATABASE thunderline OWNER postgres;

-- Connect to new database
\c thunderline

-- Create required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "vector";  -- pgvector extension

-- Verify extensions
\dx

-- Show database info
SELECT current_database(), current_user, version();
EOF

echo ""
echo "✅ Database reset complete!"
echo ""

# Run Ash migrations
echo "📝 Running Ash PostgreSQL migrations..."
cd "$PROJECT_ROOT"

export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/thunderline"
export PGHOST="localhost"
export PGPORT="5432"
export PGUSER="postgres"
export PGPASSWORD="postgres"
export PGDATABASE="thunderline"

# Create Ecto database (should already exist, but ensures schema)
mix ecto.create 2>/dev/null || echo "  Database already exists (expected)"

# Run Ash migrations
echo ""
echo "Running: mix ash_postgres.create"
mix ash_postgres.create

echo ""
echo "Running: mix ash_postgres.migrate"
mix ash_postgres.migrate

echo ""
echo "🎉 Database initialization complete!"
echo ""
echo "Connection string:"
echo "  DATABASE_URL=postgresql://postgres:postgres@localhost:5432/thunderline"
echo ""
echo "To start Phoenix:"
echo "  export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/thunderline"
echo "  mix phx.server"
echo ""
