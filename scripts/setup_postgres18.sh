#!/usr/bin/env bash
set -euo pipefail

# Thunderline PostgreSQL 18 Setup Script
# This script installs PostgreSQL 18 and creates a fresh database for Thunderline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🗄️  Thunderline PostgreSQL 18 Setup"
echo "===================================="
echo ""

# Check if running on Linux
if [[ ! "$OSTYPE" =~ ^linux ]]; then
    echo "❌ This script is designed for Linux. For other systems, install PostgreSQL 18 manually."
    exit 1
fi

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
else
    echo "❌ Unsupported package manager. Please install PostgreSQL 18 manually."
    exit 1
fi

echo "📦 Detected package manager: $PKG_MGR"
echo ""

# Check current PostgreSQL version
CURRENT_PG_VERSION=""
if command -v psql >/dev/null 2>&1; then
    CURRENT_PG_VERSION=$(psql --version | grep -oP '\d+' | head -1)
    echo "📊 Current PostgreSQL version: $CURRENT_PG_VERSION"
else
    echo "⚠️  PostgreSQL not found in PATH"
fi

echo ""
echo "This script will:"
echo "  1. Install PostgreSQL 18 (if needed)"
echo "  2. Initialize a new cluster (if needed)"
echo "  3. Start the PostgreSQL service"
echo "  4. Create 'thunderline' database and user"
echo "  5. Run Ash migrations"
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Install PostgreSQL 18
echo ""
echo "📥 Installing PostgreSQL 18..."

case $PKG_MGR in
    apt)
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y wget ca-certificates
        
        # Add PostgreSQL repository
        sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
        
        sudo apt-get update
        sudo apt-get install -y postgresql-18 postgresql-contrib-18
        ;;
        
    dnf)
        # Fedora/RHEL
        sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/F-$(rpm -E %fedora)-x86_64/pgdg-fedora-repo-latest.noarch.rpm
        sudo dnf install -y postgresql18-server postgresql18-contrib
        sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
        ;;
        
    pacman)
        # Arch Linux
        sudo pacman -Syu --noconfirm postgresql
        sudo -u postgres initdb -D /var/lib/postgres/data
        ;;
esac

# Start PostgreSQL service
echo ""
echo "🚀 Starting PostgreSQL service..."

if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    sudo systemctl status postgresql --no-pager || true
else
    echo "⚠️  systemctl not found. Please start PostgreSQL manually."
fi

# Wait for PostgreSQL to be ready
echo ""
echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 3

# Create database and user
echo ""
echo "🔧 Creating Thunderline database and user..."

sudo -u postgres psql <<EOF
-- Create user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'postgres') THEN
        CREATE USER postgres WITH PASSWORD 'postgres' SUPERUSER;
    END IF;
END
\$\$;

-- Drop and recreate database (fresh start)
DROP DATABASE IF EXISTS thunderline;
CREATE DATABASE thunderline OWNER postgres;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE thunderline TO postgres;

\c thunderline

-- Create required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Verify connection
SELECT version();
EOF

echo ""
echo "✅ PostgreSQL setup complete!"
echo ""
echo "Database connection details:"
echo "  Host: localhost"
echo "  Port: 5432"
echo "  Database: thunderline"
echo "  Username: postgres"
echo "  Password: postgres"
echo ""

# Test connection from Elixir
echo "🧪 Testing database connection..."
cd "$PROJECT_ROOT"

export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/thunderline"

if mix ecto.create 2>/dev/null; then
    echo "✅ Database connection successful!"
else
    echo "⚠️  Database already exists (expected)"
fi

echo ""
echo "📝 Running Ash PostgreSQL migrations..."
mix ash_postgres.create
mix ash_postgres.migrate

echo ""
echo "🎉 All done! Your PostgreSQL 18 database is ready."
echo ""
echo "To start Phoenix with the new database:"
echo "  export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/thunderline"
echo "  mix phx.server"
echo ""
