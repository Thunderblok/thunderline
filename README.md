# Thunderline

**A Domain-Driven Intelligent System for Advanced Event Processing and Spatial Computing**

*An OKO Holding Corporation Initiative*

## Overview

Thunderline represents the next evolution in distributed intelligent systems, combining event-driven architecture with spatial computing capabilities. Built on the robust foundation of Phoenix and Ash Framework, Thunderline orchestrates complex domain interactions through a sophisticated network of specialized processing units called Thunderblocks.

The system employs a unique hybrid architecture that seamlessly integrates Entity-Component-System (ECSx) patterns with Ash's declarative resource management, creating an environment where real-time agent coordination meets persistent policy-driven governance.

## Core Architecture

### Domain-Driven Excellence

Thunderline is architected around seven specialized domains, each handling distinct aspects of the intelligent system:

- **ThunderBlock**: Secure data persistence and infrastructure management
- **ThunderBolt**: High-performance compute and processing acceleration
- **ThunderCrown**: AI governance, orchestration and decision architecture
- **ThunderFlow**: Event streaming and data pipeline coordination
- **ThunderGate**: External system integrations, security and gateway services
- **ThunderGrid**: Spatial management and coordinate systems
- **ThunderLink**: Federation protocols and inter-system communication

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
- PostgreSQL 14+ for persistent storage
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

Thunderline includes a minimal `docker-compose.yml` providing a Postgres 16 service and a placeholder app service definition.

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

Seed a baseline community & channel (needs existing user UUID):
```bash
OWNER_USER_ID=<uuid> COMMUNITY_SLUG=general CHANNEL_SLUG=lobby mix thunderline.dev.init
```

Entrypoint script `scripts/docker/dev_entrypoint.sh` waits for DB readiness and runs migrations idempotently before launching Phoenix.

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
- Simple, direct event processing via `Thunderline.EventProcessor`
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

### Automated Maintenance & Release Workflow

To keep the platform secure and current while minimizing manual toil, Thunderline uses:

* **Dependabot** (`.github/dependabot.yml`) – daily Elixir/Mix dependency checks grouped by stack (Ash, Phoenix, Oban, ML toolchain) and weekly GitHub Actions updates.
* **Grouped Updates** – related libraries (e.g. Ash extensions) are upgraded together to reduce transitive breakage and ease review.
* **CI Pipeline** (`.github/workflows/ci.yml`) – runs compile (warnings-as-errors), tests, Credo, Dialyzer, and Sobelow security scanning on every PR and push to `main`.
* **Auto‑Merge (Optional)** – Dependabot PRs auto-squash when the full CI matrix is green (see `dependency-auto-merge` job). Disable by removing that job if manual review is preferred.
* **Semantic Versioning & Changelog** – `git_ops` (dev-only) + `.gitops.json` manage `mix.exs` version bumps and CHANGELOG sections based on commit prefixes.
* **Schema Drift Guard** – CI runs `ash_postgres.generate_migrations --check --dry-run`; PRs fail if resources and DB snapshots diverge. See `CONTRIBUTING.md`.

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

---

**Engineered with precision. Operated with intelligence.**

⚡ ⚡

"Aut viam inveniam aut faciam"

