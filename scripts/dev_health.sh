#!/usr/bin/env bash
set -euo pipefail

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RESET='\033[0m'

ok() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
err() { echo -e "${COLOR_RED}[ERR]${COLOR_RESET} $*"; }

header() { echo -e "\n=== $* ==="; }

header "Toolchain Versions"
elixir -v || err "Elixir not found"
which erl >/dev/null 2>&1 && erl -version 2>&1 | head -n1 || err "Erlang not found"

header "Disk & Memory"
df -h / | tail -n1
free -h || true

header "Inotify Limit"
if [[ -r /proc/sys/fs/inotify/max_user_watches ]]; then
  echo -n "max_user_watches="; cat /proc/sys/fs/inotify/max_user_watches
  val=$(cat /proc/sys/fs/inotify/max_user_watches)
  [[ $val -lt 524288 ]] && warn "Consider increasing to 524288 (sudo sysctl -w fs.inotify.max_user_watches=524288)"
fi

header "Open Files Limit"
ulimit -n || true

header "Docker"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon reachable"
  else
    warn "Docker installed but daemon not reachable (start it or configure WSL integration)"
  fi
else
  warn "Docker CLI not installed"
fi

header "Postgres Connectivity"
PGHOST=${PGHOST:-127.0.0.1}
PGPORT=${PGPORT:-5432}
if command -v pg_isready >/dev/null 2>&1; then
  if pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null 2>&1; then
    ok "Postgres accepting connections at $PGHOST:$PGPORT"
  else
    warn "Postgres not responding at $PGHOST:$PGPORT"
  fi
else
  warn "pg_isready not installed"
fi

header "ElixirLS Cache Size"
if [[ -d .elixir_ls ]]; then
  du -sh .elixir_ls 2>/dev/null || true
else
  warn ".elixir_ls directory not present (has LS started?)"
fi

header "Phoenix Port Availability"
PORT=${PORT:-4000}
if ss -ltn 2>/dev/null | grep -q ":$PORT"; then
  warn "Port $PORT already bound"
else
  ok "Port $PORT free"
fi

header "Environment Summary"
printenv | grep -E '^(MIX_ENV|DATABASE_URL|PGHOST|PGUSER|PGDATABASE|PHX_SERVER|SKIP_ASH_SETUP)=' || true

echo -e "\nRun 'bash scripts/dev_health.sh' anytime to re-check."
