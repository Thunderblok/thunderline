#!/usr/bin/env bash
# Quick database status checker

echo "🔍 Thunderline Database Status Check"
echo "====================================="
echo ""

# Check PostgreSQL version
echo "📊 PostgreSQL Version:"
if command -v psql >/dev/null 2>&1; then
    psql --version
else
    echo "  ❌ psql not found in PATH"
fi
echo ""

# Check if service is running
echo "🔄 PostgreSQL Service Status:"
if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl status postgresql --no-pager -l | head -5 || echo "  ❌ Service not running"
else
    ps aux | grep postgres | grep -v grep || echo "  ❌ No PostgreSQL processes found"
fi
echo ""

# Try to connect and check databases
echo "🗄️  Databases:"
if command -v psql >/dev/null 2>&1; then
    psql -U postgres -h localhost -l 2>&1 | grep -E "thunderline|Name|---" || {
        echo "  ⚠️  Cannot connect. Trying with sudo -u postgres..."
        sudo -u postgres psql -l 2>&1 | grep -E "thunderline|Name|---" || echo "  ❌ Connection failed"
    }
else
    echo "  ❌ psql not available"
fi
echo ""

# Check environment variables
echo "🌍 Environment Variables:"
echo "  DATABASE_URL: ${DATABASE_URL:-<not set>}"
echo "  PGHOST: ${PGHOST:-<not set>}"
echo "  PGUSER: ${PGUSER:-<not set>}"
echo "  PGDATABASE: ${PGDATABASE:-<not set>}"
echo ""

# Check dev.exs config
echo "📝 Config (dev.exs):"
if [ -f config/dev.exs ]; then
    grep -A3 "dev_repo_defaults" config/dev.exs | grep -E "username|password|hostname|database|port" || echo "  ⚠️  Cannot parse config"
else
    echo "  ❌ dev.exs not found"
fi
