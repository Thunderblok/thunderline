#!/usr/bin/env bash
set -euo pipefail

echo "[demo-reset] Resetting Thunderline demo database & seeds"
export MIX_ENV=prod

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL must be set" >&2
  exit 1
fi

mix ecto.drop || true
mix ecto.create
mix ash_postgres.migrate
if [ -f priv/repo/demo_seeds.exs ]; then
  mix run priv/repo/demo_seeds.exs
fi
echo "[demo-reset] Complete"
