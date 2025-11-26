# Thunderhelm Services & Port Mapping

> **Last Updated:** November 24, 2025
> 
> Comprehensive port allocation for all Thunderline + Thunderhelm services in development and production.

## Core Services

### Phoenix Web Application
- **Service:** ThunderlineWeb.Endpoint
- **Dev Port:** `5001` (configurable via `PORT` env var)
- **Docker Port:** `4000` (internal), `4000:4000` (exposed)
- **Protocol:** HTTP
- **Config:** `config/dev.exs`
- **URL:** `http://localhost:5001` (dev), `http://localhost:4000` (docker)

### PostgreSQL Database
- **Service:** PostgreSQL 16 with pgvector
- **Dev Port:** `5432` (host)
- **Docker Port:** `5432:5432`
- **Container:** `thunderline_postgres`
- **Credentials:** postgres/postgres
- **Database:** thunderline
- **Config:** `config/dev.exs`, `docker-compose.yml`

### LiveDebugger (Development Tool)
- **Service:** LiveDebugger Web UI
- **Default Port:** `4007`
- **Protocol:** HTTP
- **Status:** **⚠️ DISABLED** - Port conflict with Phoenix
- **Config:** `config/dev.exs`
- **Notes:** Should be disabled in dev or moved to different port

---

## Thunderhelm Python Services

### Cerebros Training Service
- **Service:** Cerebros ML training worker
- **Location:** `thunderhelm/cerebros_service/`
- **Default Ports:** None (HTTP client only)
- **Connects To:**
  - Thunderline API: `http://localhost:4000` (default)
  - MLflow: `http://localhost:5000`
- **Environment Variables:**
  ```bash
  CEREBROS_SERVICE_ID=cerebros-1
  THUNDERLINE_URL=http://localhost:4000
  MLFLOW_TRACKING_URI=http://localhost:5000
  CEREBROS_POLL_INTERVAL=5
  CEREBROS_HEARTBEAT_INTERVAL=30
  ```
- **Config:** `thunderhelm/cerebros_service/config.py`

### NLP HTTP Server
- **Service:** NLP processing (spaCy wrapper)
- **Location:** `thunderhelm/nlp_http_server.py`
- **Default Port:** `5555` (configurable via `NLP_SERVER_PORT`)
- **Protocol:** HTTP (Flask)
- **Endpoints:**
  - `/health` - Health check
  - `/entities` - Named entity extraction
  - `/tokenize` - Text tokenization
  - `/sentiment` - Sentiment analysis
  - `/syntax` - Syntax analysis
  - `/process` - Full pipeline

### MLflow Tracking Server
- **Service:** MLflow experiment tracking
- **Dev Port:** `5000`
- **Docker Port:** `5000:5000`
- **Container:** `thunderline_mlflow`
- **Protocol:** HTTP
- **Backend:** SQLite (`/mlflow/mlflow.db`)
- **Artifacts:** `/mlartifacts`
- **Config:** `docker-compose.yml`

---

## Additional Services (Config References)

### Numerics Sidecar
- **Default URL:** `http://localhost:8089`
- **Config:** `config/config.exs` (line 113)
- **Environment Variable:** `THUNDERLINE_NUMERICS_SIDECAR_URL`
- **Notes:** Optional GPU/numerics offload service

### Ash GraphQL (Development)
- **Default Port:** `5088`
- **Config:** `config/config.exs` (line 191)
- **Protocol:** GraphQL over HTTP
- **Status:** Development/testing only

---

## Port Allocation Summary

| Port | Service | Environment | Status |
|------|---------|-------------|--------|
| 4000 | Phoenix (Docker) | Production/Docker | Active |
| 4007 | LiveDebugger | Development | ⚠️ **DISABLED** |
| 5000 | MLflow | Development/Docker | Active |
| 5001 | Phoenix | Development | ✅ Active |
| 5088 | Ash GraphQL | Development | Optional |
| 5432 | PostgreSQL | Development/Docker | Active |
| 5555 | NLP HTTP Server | Development | Optional |
| 8089 | Numerics Sidecar | Development | Optional |

---

## Docker Compose Services

From `docker-compose.yml`:

```yaml
services:
  postgres:        # 5432:5432
  thunderline:     # 4000:4000
  mlflow:          # 5000:5000
```

---

## Development vs Production Differences

### Development (Local)
- Phoenix: Port `5001` (avoid conflict with other services)
- Direct PostgreSQL connection to localhost:5432
- Oban: **DISABLED** (race condition mitigation)
- LiveDebugger: **DISABLED** (port conflict)
- Hot reload enabled
- Debug logging

### Production (Docker)
- Phoenix: Port `4000` (standard)
- PostgreSQL via Docker network (postgres:5432)
- Oban: **ENABLED** (stable environment)
- LiveDebugger: Not included
- Asset compilation optimized
- Production logging

---

## Service Registration Flow

1. **Phoenix starts** → Listens on 5001 (dev) or 4000 (prod)
2. **Cerebros service starts** → Registers with Thunderline at `/api/services/register`
3. **Heartbeats** → Cerebros sends status every 30s to `/api/services/:id/heartbeat`
4. **Job polling** → Cerebros polls `/api/jobs/poll` every 5s
5. **MLflow logging** → Cerebros logs experiments to MLflow:5000

---

## Fixing Port Conflicts

### LiveDebugger Port 4007 Conflict

**Problem:** Phoenix already running uses port 4007 internally
**Solution:** Disable LiveDebugger in development

```elixir
# config/dev.exs
config :live_debugger, enabled: false
```

### Phoenix Port Conflicts

If port 5001 is taken:
```bash
PORT=5002 mix phx.server
```

Or use Docker:
```bash
docker-compose up
# Phoenix will be on http://localhost:4000
```

---

## Environment Variable Reference

### Thunderline (Elixir)
```bash
DATABASE_URL=ecto://postgres:postgres@localhost:5432/thunderline
PORT=5001
BIND_ALL=1                    # Bind to 0.0.0.0 instead of 127.0.0.1
OTEL_DISABLED=1               # Disable OpenTelemetry
GATE_SELFTEST_DISABLED=1      # Disable gate self-tests
```

### Cerebros (Python)
```bash
CEREBROS_SERVICE_ID=cerebros-1
THUNDERLINE_URL=http://localhost:5001
MLFLOW_TRACKING_URI=http://localhost:5000
CEREBROS_POLL_INTERVAL=5
CEREBROS_HEARTBEAT_INTERVAL=30
```

### NLP Server (Python)
```bash
NLP_SERVER_PORT=5555
```

---

## Quick Start Commands

### Development (Local)
```bash
# Terminal 1: Start PostgreSQL (if not using Docker)
docker-compose up postgres

# Terminal 2: Start Phoenix
DATABASE_URL="ecto://postgres:postgres@localhost:5432/thunderline" mix phx.server

# Terminal 3: Start Cerebros (optional)
cd thunderhelm/cerebros_service
source ../../.venv/bin/activate
python cerebros_service.py

# Terminal 4: Start NLP Server (optional)
cd thunderhelm
source ../.venv/bin/activate
python nlp_http_server.py
```

### Docker (All Services)
```bash
docker-compose up
# Phoenix: http://localhost:4000
# MLflow: http://localhost:5000
```

---

## Troubleshooting

### "Address already in use" (EADDRINUSE)
```bash
# Check what's using the port
lsof -i :5001

# Kill existing process
pkill -9 beam.smp

# Or use different port
PORT=5002 mix phx.server
```

### Cerebros Registration Fails
1. Ensure Phoenix is running on expected port
2. Check `THUNDERLINE_URL` matches Phoenix port
3. Verify `/api/services/register` endpoint exists
4. Check Phoenix logs for errors

### MLflow Connection Fails
```bash
# Start MLflow manually
docker-compose up mlflow

# Or use local MLflow
pip install mlflow
mlflow server --host 127.0.0.1 --port 5000
```
