# Thunderline

**A Domain-Driven Intelligent System for Advanced Event Processing and Spatial Computing**

*An OKO Holding Corporation Initiative*

## Overview

Thunderline represents the next evolution in distributed intelligent systems, combining event-driven architecture with spatial computing capabilities. Built on the robust foundation of Phoenix and Ash Framework, Thunderline orchestrates complex domain interactions through a sophisticated network of specialized processing units called Thunderblocks.

The system employs a unique hybrid architecture that seamlessly integrates Entity-Component-System (ECSx) patterns with Ash's declarative resource management, creating an environment where real-time agent coordination meets persistent policy-driven governance.

## Core Architecture

### Domain-Driven Excellence

Thunderline is architected around seven specialized domains (with auxiliary merge/legacy surfaces), each handling distinct aspects of the intelligent system:

- **ThunderBlock**: Secure data persistence and infrastructure management
- **ThunderBolt**: High-performance compute and processing acceleration
- **ThunderCrown**: AI governance, orchestration and decision architecture
- **ThunderFlow**: Event streaming and data pipeline coordination
- **ThunderGate**: External system integrations, security and gateway services
- **ThunderGrid**: Spatial management and coordinate systems
- **ThunderLink**: Federation protocols and inter-system communication
  - (See `Docs/architecture/domain_topdown.md` for the full top-down container & flow map; `Docs/architecture/system_architecture_webrtc.md` for voice/WebRTC path.)

### Event-Driven Foundation

The system leverages **AshEvents** for comprehensive event sourcing, providing:

- Complete audit trails with immutable event logs
- System state reconstruction from historical events
- Temporal queries for analytical insights
- Compliance-ready data governance

### Intelligent Resource Selection

Thunderline incorporates the **THUNDERSTRUCK** algorithm, a sophisticated implementation of the Josephus problem, to mathematically optimize resource allocation and ensure peak system efficiency through strategic selection processes.

## Technical Excellence

### Framework Foundation

- **Phoenix LiveView**: Real-time user interfaces with server-side rendering
- **Ash Framework 3.x**: Declarative resource modeling with built-in APIs
- **ECSx**: High-performance entity-component-system for agent coordination
- **AshEvents**: Enterprise-grade event sourcing and audit capabilities
- **PostgreSQL + Mnesia**: Dual-layer persistence for durability and performance

### Advanced Capabilities

- **3D Cellular Automata**: Real-time spatial computing with 60 FPS visualization
- **Federation Protocols**: Multi-node coordination and distributed consensus
- **Behavioral Intelligence**: Agent-based processing with learning capabilities
- **Spatial Computing**: Hexagonal coordinate systems for complex spatial relationships

## Getting Started

### Prerequisites

- Elixir 1.15+ with OTP 26+
- PostgreSQL 18 for persistent storage
- Node.js 18+ for asset compilation

### Installation

```bash
# Clone the repository
git clone https://github.com/Thunderblok/Thunderline.git
cd Thunderline

# Install dependencies and setup database
mix setup

# (Optional) Skip automatic dependency fetch if deps are already present
SKIP_DEPS_GET=true mix setup

# Start the development server
mix phx.server
```

The application will be available at [localhost:4000](http://localhost:4000).

#### Dependency Fetch Behavior

`mix setup` no longer always runs `mix deps.get`. It now:

1. Skips entirely if `SKIP_DEPS_GET=true`
2. Runs `deps.get` only when `mix.lock` or a representative dep directory (e.g. `deps/phoenix`) is missing
3. Logs why it ran or skipped (`[setup] Running deps.get (dependencies missing)` / `[setup] deps.get skipped (deps already present)`).

Run `mix deps.get` manually when you intentionally want to resolve/update dependencies.

### Docker Development (Optional)

Thunderline includes a minimal `docker-compose.yml` providing a Postgres 18 service and a placeholder app service definition.

### Developer Environment Health Check

Run `bash scripts/dev_health.sh` to quickly diagnose common WSL / Linux dev issues (Docker daemon, Postgres availability, inotify limits, port conflicts, Elixir/Erlang versions, ElixirLS cache size). This helps when encountering ElixirLS `EPIPE` crashes or intermittent `connection refused` errors.

Start only Postgres (run Elixir locally):

```bash
docker compose up -d postgres
export DATABASE_URL=ecto://postgres:postgres@localhost:5432/thunderblock
mix thunderline.dev.init   # create db, codegen, migrate
mix phx.server
```

Diagnostics:

```bash
docker exec -it thunderline_postgres pg_isready -U postgres
mix thunderline.doctor.db
mix thunderline.oban.dash   # live in-terminal Oban telemetry & job stats snapshot
```

Full stack (when a Dockerfile is added):

```bash
docker compose up -d
docker compose logs -f thunderline
```

Hard reset (DESTROYS data):

```bash
docker compose down -v
docker compose up -d postgres
mix thunderline.dev.init
```

### Livebook HPO/NAS Demo

Use the `livebook/cerebros_thunderline.livemd` notebook to drive a full Thunderline × Cerebros loop against your local Postgres state. The notebook boots Thunderline’s Ash domains inside Livebook, seeds a demo dataset/model spec, then walks through proposal generation, trial evaluation, Pareto inspection, and artifact/version persistence.

1. Ensure the database is ready: `mix ecto.create && mix ecto.migrate`
2. Launch Livebook from the repo root: `livebook server`
3. Open `livebook/cerebros_thunderline.livemd`
4. Pick a mode:
  - `CEREBROS_MODE=mock` (default) → everything runs locally with synthetic metrics
  - `CEREBROS_MODE=remote` plus `CEREBROS_URL=http://host:port` → calls an external Cerebros service that implements `/propose` and `/train`
5. Run the sections in order; results persist via the existing `ModelRun`, `ModelArtifact`, and `ModelVersion` tables.

Set `TL_LIVEBOOK_TENANT` (default `demo-tenant`) when you want the notebook to operate under a specific Ash actor context. The Livebook disables Oban/Vault so you can iterate without starting the entire Phoenix stack; restart the app normally when you need all workers.

Seed a baseline community & channel (needs existing user UUID):

```bash
OWNER_USER_ID=<uuid> COMMUNITY_SLUG=general CHANNEL_SLUG=lobby mix thunderline.dev.init
```

Entrypoint script `scripts/docker/dev_entrypoint.sh` waits for DB readiness and runs migrations idempotently before launching Phoenix.

### Cerebros Bridge Readiness Check

Before enabling the Cerebros NAS bridge in a shared environment, run the validator mix task to confirm the feature flag, configuration, and Python tooling are wired correctly:

```bash
SKIP_JIDO=true mix thunderline.ml.validate
```

Add `--require-enabled` to fail if `config :thunderline, :cerebros_bridge, enabled: false` is still set, and `--json` when you want machine-readable output for pipelines. The command exits non-zero on any failed check, making it suitable for CI/CD gates. Re-run it whenever you change the Cerebros checkout, Python virtualenv, or bridge configuration.

When the validator passes, export `CEREBROS_ENABLED=1` (or set it via Helm) so the runtime config flips `:cerebros_bridge` on and the `:ml_nas` feature flag becomes active without recompiling.

### RAG System - Semantic Search & Document Retrieval

Thunderline includes a production-ready RAG (Retrieval-Augmented Generation) system built on `ash_ai` and PostgreSQL's `pgvector` extension. The system provides semantic search capabilities for document retrieval using machine learning embeddings.

#### Architecture

- **Storage**: PostgreSQL with pgvector extension (native vector operations)
- **Embeddings**: Bumblebee + sentence-transformers/all-MiniLM-L6-v2 (384 dimensions)
- **Resource**: `Thunderline.RAG.Document` (Ash resource with automatic vectorization)
- **Performance**: ~7-10ms per query (after initial 7-8s model load)

#### API Usage

```elixir
alias Thunderline.RAG.Document

# Create a document with metadata
{:ok, doc} = Document.create_document(%{
  content: "Your text here",
  metadata: %{
    source: "file.txt",
    type: "documentation",
    author: "system"
  }
})

# Generate embeddings (automatic vectorization)
{:ok, doc_with_vector} = Document.update_embeddings(doc)

# Semantic search with cosine similarity
{:ok, results} = Document.semantic_search(
  "your query text",
  limit: 5,           # Max results
  threshold: 0.7      # Cosine distance threshold (0.0-2.0, lower = more similar)
)

# Results are ranked by semantic relevance
Enum.each(results, fn doc ->
  IO.puts("Content: #{doc.content}")
  IO.puts("Metadata: #{inspect(doc.metadata)}")
end)
```

#### Configuration

The RAG system is **enabled by default in development** (`config/dev.exs`). For production deployments, set:

```bash
export RAG_ENABLED=1
```

The Bumblebee model serving starts automatically via the supervision tree and loads the embedding model on first use (~7-8 seconds). Subsequent queries reuse the loaded model for fast performance.

#### Testing

Run the acceptance test to verify the full RAG pipeline:

```bash
MIX_ENV=dev mix run test_rag_acceptance.exs
```

This test ingests the README.md, generates embeddings for all chunks, and performs semantic search queries to validate:
- Document ingestion and storage
- Automatic embedding generation
- Vector similarity search with PostgreSQL
- Query performance and ranking quality

#### Technical Details

**Migration from Chroma**: The system was refactored from Chroma HTTP API to native PostgreSQL for better performance and simpler architecture:

| Metric | Chroma HTTP | ash_ai + pgvector | Improvement |
|--------|-------------|-------------------|-------------|
| Query Latency | ~150ms | ~7-10ms | **95% faster** |
| Code Complexity | 580 LOC | 200 LOC | **65% reduction** |
| External Services | Required | None | **Simplified** |
| Database | Separate | Unified PostgreSQL | **Single source** |

**PostgreSQL Type Casting**: The system uses explicit `::vector` casts when querying to ensure proper type matching with pgvector's operators:

```elixir
# Correct: Explicit cast for parameter
fragment("(? <=> ?::vector)", vector_column, ^embedding_list)
```

This tells PostgreSQL to convert the array parameter to the `vector` type for cosine distance operations.

### Feature Flags & Environment Toggles

These environment variables gate optional subsystems or alter setup heuristics:

| Variable | Values | Purpose | Default |
|----------|--------|---------|---------|
| `CEREBROS_ENABLED` | `1`, `true` | Enable Cerebros bridge runtime (`:cerebros_bridge.enabled`) and turn on the `ml_nas` feature | disabled |
| `RAG_ENABLED` | `1`, `true` | Enable RAG (Retrieval-Augmented Generation) system with ash_ai + pgvector for semantic search | **enabled in dev** |
| `ENABLE_NDJSON` | `1` | Enable NDJSON structured event logging writer (UI toggle present) | disabled |
| `ENABLE_UPS` | `1` | Start UPS watcher process (publishes power status to status bus) | disabled |
| `ENABLE_SIGNAL_STACK` | `1` | Start experimental signal‑processing stack (PLL/Hilbert etc.) | disabled |
| `FEATURES_AI_CHAT_PANEL` | `1` | Enable experimental Ash AI backed chat assistant panel on dashboard | disabled |
| `RETENTION_SWEEPER_CRON` | cron expression | Override the Oban retention sweep schedule (default hourly) | `0 * * * *` |
| `DISABLE_RETENTION_SWEEPER_CRON` | `1`, `true` | Disable scheduling of the retention sweeper cron entirely | disabled |
| `TL_ENABLE_REACTOR` | `true/false` | Switch between simple EventProcessor path and Reactor orchestration | false |
| `SKIP_DEPS_GET` | `true/false` | Skip automatic deps fetch during `mix setup` heuristic | false |
| `SKIP_ASH_SETUP` | `true/false` | Skip Ash migrations in test alias for DB‑less unit tests | false |

> **Cerebros NAS toggle** – Set `CEREBROS_ENABLED=1` to flip the runtime config (`config :thunderline, :cerebros_bridge, enabled: true`) and automatically enable the `:ml_nas` feature flag. Keep it disabled by default, run `mix thunderline.ml.validate --require-enabled`, then export the toggle once every check passes.

Set in your shell or `.envrc`:

```bash
export ENABLE_NDJSON=1
export ENABLE_UPS=1
```

#### Retention sweeper configuration

The hourly retention job (`Thunderline.Thunderblock.Jobs.RetentionSweepWorker`) pulls its targets from `config :thunderline, Thunderline.Thunderblock.Retention.Sweeper, targets: [...]`. Each target entry should provide a `:resource` atom plus loader/deleter functions (zero-arity loader, unary deleter). Use the `RETENTION_SWEEPER_CRON` variable to adjust the schedule or `DISABLE_RETENTION_SWEEPER_CRON` to suspend the cron while keeping manual `RetentionSweepWorker.enqueue/1` available. Telemetry is published to the `"retention:sweeps"` PubSub topic and surfaced via `Thunderline.Thunderblock.Telemetry.Retention.stats/0`.

### Secret & MCP Token Handling

- Never commit MCP credentials. The `.roo/` and `mcp/` directories are ignored and must stay untracked (verify with `git ls-files`).
- Supply tokens through your shell or `.envrc`. We recommend [direnv](https://direnv.net/) for automatic loading.
- The GitHub MCP server expects `GITHUB_PERSONAL_ACCESS_TOKEN`; other servers may use their own env vars. Keep values in your local environment only.
- Run the secret scanner before every push:

  ```bash
  gitleaks protect --verbose --redact
  ```

- Enforce local scans by installing the bundled pre-push hook:

  ```bash
  ./scripts/git-hooks/install.sh
  ```

- CI also blocks merges if `gitleaks` finds any secrets.

Copy `.envrc.example` to `.envrc` (ignored) or create your own `.envrc.local` (do **not** commit):

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
export GITHUB_TOOLSETS=""
export GITHUB_READ_ONLY="1"   # optional read-only mode
```

If a credential ever hits the tree, revoke it immediately, rotate the secret, and rewrite the offending commits before pushing again.

### Former BOnus Modules Migration

Previously experimental modules under a `BOnus/` path have been promoted into their appropriate domain namespaces (`lib/thunderline/**`). The build no longer alters `elixirc_paths` to include a BOnus directory; references in historical documentation now refer to migrated code. If you encounter an old note mentioning `BOnus/lib`, treat it as already consolidated.

### Observability & Diagnostics Additions

- In-memory noise buffer: `Thunderline.Thunderflow.Observability.RingBuffer` (live surfaced via noise console component) replaces legacy `Thunderline.Log.RingBuffer` path.
- Oban telemetry capture: `Thunderline.Thunderflow.Telemetry.Oban` stores recent job lifecycle events in ETS and powers `mix thunderline.oban.dash`.
- Deprecated module `Thunderline.Automata.Blackboard` fully replaced by canonical `Thunderline.Thunderbolt.Automata.Blackboard` (wrapper removed).

### Production Deployment

For production environments, Thunderline supports containerized deployment with comprehensive monitoring and distributed coordination capabilities. Consult the deployment documentation for environment-specific configuration guidance.

## System Capabilities

### Real-Time Processing

Thunderline processes events with sub-millisecond latency through its distributed event architecture, enabling real-time decision making and immediate system responsiveness.

### Intelligent Coordination

The system employs sophisticated algorithms for resource allocation, task distribution, and agent coordination, ensuring optimal performance across all operational domains.

### Comprehensive Observability

Built-in monitoring and observability tools provide deep insights into system behavior, performance metrics, and operational health across all domains.

### Scalable Architecture

The domain-driven design allows for selective scaling of individual system components based on load patterns and operational requirements.

## Event Processing Pipeline

### Gated Architecture (Phase-0 Operational Improvements)

Thunderline uses a **gated event processing architecture** that provides both simplicity and power:

**Default Path (TL_ENABLE_REACTOR=false)**:

- Simple, direct event processing via `Thunderline.Thunderflow.Processor` (replaces deprecated `Thunderline.EventProcessor`)
- Optimized for high-throughput with minimal overhead
- Exponential backoff with jitter for resilient retries
- Circuit breaker protection for external services
- Comprehensive telemetry and error classification

**Advanced Path (TL_ENABLE_REACTOR=true)**:

- Reactor-based saga orchestration (available when needed)
- Complex compensation and undo logic
- Recursive workflows and advanced DAG patterns

### Operational Features

**Smart Retry Strategy:**

```elixir
# Exponential backoff: 1s → 2s → 4s → 8s → 16s (capped at 5min)
# With ±20% jitter to prevent thundering herd
```

**Circuit Breaker Protection:**

```elixir
# Protects against failing domains:
# 5 failures → open for 30s → half-open test → closed
```

**Error Classification:**

- `:transient` - Network/timeout errors (retry)
- `:permanent` - Validation/constraint errors (discard)
- `:unknown` - Unclassified errors (retry with caution)

**Key Telemetry Metrics:**

- `thunderline.jobs.retries` - Retry attempts by queue/worker
- `thunderline.jobs.failures` - Failures by error type
- `thunderline.cross_domain.latency` - Cross-domain operation timing
- `thunderline.circuit_breaker.calls` - Circuit breaker activity

### Usage

**Simple Event Processing:**

```elixir
# Canonical interface - routes to simple processor by default
Ash.run!(Thunderline.Integrations.EventOps, :process_event, %{
  event: %{
    "type" => "agent_created", 
    "payload" => %{"agent_id" => "123", "status" => "active"},
    "source_domain" => "thundercrown",
    "target_domain" => "thunderlink"
  }
})
```

**Job Queue Integration:**

```elixir
# For background processing
%{"event" => %{
  "type" => "cross_domain_sync",
  "payload" => sync_data,
  "source_domain" => "thunderblock"
}}
|> Thunderline.Thunderflow.Jobs.ProcessEvent.new()
|> Oban.insert()
```

**Canonical Event Structure:**

```elixir
# All events normalized to this shape
%Thunderline.Event{
  type: :agent_created,
  payload: %{"agent_id" => "123"},
  source_domain: "thundercrown",
  target_domain: "thunderlink",
  timestamp: ~U[2025-08-16 10:30:00Z],
  correlation_id: "abc123...",
  hop_count: 0,
  priority: :normal,
  metadata: %{}
}
```

## Development Philosophy

Thunderline embodies a commitment to architectural excellence through:

- **Systematic Methodology**: Every component designed with mathematical precision
- **Event-Driven Clarity**: Complete system transparency through comprehensive event logging
- **Domain Expertise**: Specialized processing units optimized for specific operational domains
- **Intelligent Adaptation**: Self-optimizing algorithms that improve system performance over time

## Contributing

Thunderline development follows rigorous engineering standards with comprehensive testing, documentation-driven development, and systematic code review processes. The system maintains living documentation through the OKO Handbook, ensuring continuous knowledge preservation and team alignment.

### Strategic Planning

**Mission & Roadmap**:
- **[OPERATION_SAGA_CONCORDIA.md](OPERATION_SAGA_CONCORDIA.md)** - Current mission: Harmonize orchestration layers (Oct 27 - Nov 7, 2025) ⚡
- **[IMMEDIATE_ACTION_PLAN.md](documentation/planning/IMMEDIATE_ACTION_PLAN.md)** - Week 1 recovery plan (48-hour critical path)
- **[THUNDERLINE_REBUILD_INITIATIVE.md](documentation/planning/THUNDERLINE_REBUILD_INITIATIVE.md)** - Master plan (10 High Command missions) ⭐
- **[Q4_2025_PAC_Distributed_Agent_Network_STATUS.md](documentation/planning/Q4_2025_PAC_Distributed_Agent_Network_STATUS.md)** - PAC technical roadmap (8 pillars)

**Developer Resources**:
- **[DEVELOPER_QUICK_REFERENCE.md](documentation/planning/DEVELOPER_QUICK_REFERENCE.md)** - Dev cheat sheet (Mix tasks, Ash patterns, pitfalls)
- **[PR_REVIEW_CHECKLIST.md](documentation/planning/PR_REVIEW_CHECKLIST.md)** - 12-section quality gate (now enforced via PR template)
- **[QUICKSTART.md](documentation/planning/QUICKSTART.md)** - Quick start guide

### Documentation

**Core Documentation**:
- **[THUNDERLINE_DOMAIN_CATALOG.md](THUNDERLINE_DOMAIN_CATALOG.md)** - Authoritative domain and resource inventory
- **[HOW_TO_AUDIT.md](HOW_TO_AUDIT.md)** - Systematic codebase audit methodology ⭐ **READ THIS BEFORE AUDITING**
- **[CODEBASE_AUDIT_2025.md](CODEBASE_AUDIT_2025.md)** - Latest audit findings and verification
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development workflow and guidelines

**⚠️ Important**: Always use the file-by-file audit methodology in `HOW_TO_AUDIT.md` for any architectural assessment. GitHub search alone cannot determine production status or resource counts.

### Automated Maintenance & Release Workflow

To keep the platform secure and current while minimizing manual toil, Thunderline uses:

- **Dependabot** (`.github/dependabot.yml`) – daily Elixir/Mix dependency checks grouped by stack (Ash, Phoenix, Oban, ML toolchain) and weekly GitHub Actions updates.
- **Grouped Updates** – related libraries (e.g. Ash extensions) are upgraded together to reduce transitive breakage and ease review.
- **CI Pipeline** (`.github/workflows/ci.yml`) – runs compile (warnings-as-errors), tests, Credo, Dialyzer, and Sobelow security scanning on every PR and push to `main`.
- **Auto‑Merge (Optional)** – Dependabot PRs auto-squash when the full CI matrix is green (see `dependency-auto-merge` job). Disable by removing that job if manual review is preferred.
- **Semantic Versioning & Changelog** – `git_ops` (dev-only) + `.gitops.json` manage `mix.exs` version bumps and CHANGELOG sections based on commit prefixes.
- **Schema Drift Guard** – CI runs `ash_postgres.generate_migrations --check --dry-run`; PRs fail if resources and DB snapshots diverge. See `CONTRIBUTING.md`.

Developer responsibilities:

1. Use Conventional Commit prefixes (`feat:`, `fix:`, `chore:`, etc.).
2. Ensure new Ash resources have migrations & tests before merging.
3. Address Dialyzer warnings intentionally (no blanket ignores).
4. Keep security scans passing; never suppress Sobelow findings without justification.

Release flow (simplified):

1. Land changes on `main` with proper commit prefixes.
2. Run `mix git_ops.release --yes` (dev env) to cut a tagged release (updates version + CHANGELOG + README if configured).
3. Push the tag; deployment pipeline (future) consumes the tag for artifact builds.

## License

This project is proprietary software of OKO Holding Corporation. All rights reserved.

## Architectural Guardrails (IRONWOLF)

### RepoOnly Boundary

All persistence access is routed through the Block domain. Direct `Repo.*` calls are only permitted in:

- `lib/thunderline/thunderblock/**`
- `priv/repo/migrations/**`
- Explicit resource repo configuration blocks

Custom Credo check (`Thunderline.Dev.CredoChecks.DomainGuardrails`) enforces this. Set `REPO_ONLY_ENFORCE=1` in CI to escalate violations from warnings to errors.

Rationale: Preserve domain seams, simplify auditing, prevent cross-domain leakage of transactional concerns.

### Event Emission Discipline

All event publishing flows through `Thunderline.Thunderflow.EventBus.publish_event/1`. Callers must branch on return `{:ok, ev} | {:error, reason}`—no silent assumptions. Validator runs first; invalid events produce telemetry `[:thunderline, :event, :dropped]` (prod) or raise (test).

### Gate Auth Telemetry

Authentication outcomes surface via `[:thunderline, :gate, :auth, :result]` with result tags `:success|:missing|:expired|:deny`. Dashboards consume these metrics for real‑time visibility.

### Blackboard Migration

Legacy Automata blackboard deprecated; canonical implementation is `Thunderline.Thunderflow.Blackboard`. Removal of the legacy delegator proceeds after a zero‑call window on `[:thunderline, :blackboard, :legacy_call]`.

---

**Engineered with precision. Operated with intelligence.**

⚡ ⚡

"Aut viam inveniam aut faciam"
