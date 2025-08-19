#!/usr/bin/env bash
set -euo pipefail

# Wait for Postgres
echo "[entrypoint] Waiting for Postgres at $DATABASE_URL"
for i in {1..30}; do
  if pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; then
    echo "[entrypoint] Postgres is ready"
    break
  fi
  echo "[entrypoint] Postgres not ready yet ($i)" && sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[entrypoint] Postgres never became ready" >&2
    exit 1
  fi
done

# Run codegen & migrations (safe idempotent) then start Phoenix
mix ash.codegen || true
mix ash_postgres.migrate || true
exec mix phx.server
