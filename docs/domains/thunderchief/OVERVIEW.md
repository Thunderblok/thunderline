# ThunderChief Domain Overview

**Vertex Position**: Control Plane Ring — Orchestration Utility Layer

**Purpose**: Legacy orchestration hub that routes work between domains, mediating synchronous and asynchronous execution while full orchestration responsibility migrates into ThunderBolt and ThunderFlow.

## Charter

ThunderChief existed to answer the “how should we run this?” question during earlier phases of Thunderline. It provided a thin orchestration layer that delegated incoming events to either real-time Reactor pipelines or simple domain processors. Although the architecture has since consolidated orchestration into ThunderBolt, ThunderFlow, and ThunderBlock, ThunderChief remains as a compatibility utility to avoid breaking historical integrations until the migration is complete.

## Core Responsibilities

1. **Delegation Strategy** — decide whether to route execution through Reactor or the simple domain processor based on configuration and availability.
2. **Domain Job Dispatch** — enqueue domain-specific Oban jobs when asynchronous processing is required.
3. **Compatibility Shims** — maintain legacy orchestration entry points during the ThunderChief deprecation window.
4. **Telemetry Emission** — publish routing decisions and workload metadata for dashboards and audit trails.
5. **Configuration Gateway** — expose runtime configuration for domain worker mappings and Reactor enablement.

## Key Modules (No Ash Resources)

- [`Thunderline.Thunderchief.Orchestrator`](lib/thunderline/thunderchief/orchestrator.ex:2) — primary orchestrator that routes execution requests through Reactor or domain processors.
- [`Thunderline.Thunderchief.Jobs.DomainProcessor`](lib/thunderline/thunderchief/jobs/domain_processor.ex:1) — legacy Oban worker handling domain-specific jobs.
- [`Thunderline.Thunderchief.Jobs.DemoJob`](lib/thunderline/thunderchief/jobs/demo_job.ex:1) — demonstration job retained for historical context.
- [`Thunderline.Thunderchief.Workers.DemoJob`](lib/thunderline/thunderchief/workers/demo_job.ex:1) — worker implementation for the demo job.
- [`Thunderline.Thunderchief.CONVO`](lib/thunderline/thunderchief/CONVO.MD:1) — project notes covering orchestration migration guidelines.

## Integration Points

### Vertical Edges

- **ThunderFlow → ThunderChief**: legacy event processors still call the orchestrator for routing decisions.
- **ThunderChief → ThunderFlow**: orchestrator enqueues follow-up jobs into Flow pipelines when Reactor is unavailable.
- **ThunderChief → ThunderBolt**: delegates orchestration workloads to ThunderBolt domain processors via Oban jobs.
- **ThunderChief → ThunderBlock**: uses ThunderBlock retention and workflow trackers for historical orchestration state.

### Horizontal Edges

- **ThunderChief ↔ ThunderCrown**: governance decisions feed into the orchestrator when policy mandates synchronous vs. asynchronous execution.
- **ThunderChief ↔ ThunderBlock.Timing**: scheduled workflows rely on ThunderBlock timers to trigger legacy orchestration routines.

## Telemetry Events

- `[:thunderline, :thunderchief, :orchestrator, :routed]` — indicates whether Reactor or simple processor handled the workload.
- `[:thunderline, :thunderchief, :job, :enqueued]` — Oban job created for domain processor.
- `[:thunderline, :thunderchief, :reactor, :fallback]` — Reactor unavailable; fallback path used.

## Performance Targets (Legacy)

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Orchestrator routing decision | 5 ms | 20 ms | 10k/s |
| Legacy Oban job enqueue | 15 ms | 80 ms | 2k/s |

## Security & Policy Notes

- Orchestrator calls should respect ThunderCrown policy decisions; confirm capability checks are applied before invoking ThunderChief.
- Configuration (`config :thunderline, :thunderchief`) should specify permitted domain workers to avoid arbitrary job execution.
- Telemetry and audit logs should be preserved until ThunderChief is fully decommissioned to maintain traceability.

## Decommission Roadmap

1. **Phase 1 — Workload Inventory**: identify callers still using ThunderChief APIs and migrate the logic into ThunderBolt or ThunderFlow.
2. **Phase 2 — Feature Flags**: gate ThunderChief entry points and gradually disable them in lower environments.
3. **Phase 3 — Removal**: delete orchestrator modules and Oban workers once no callers remain; update documentation accordingly.
4. **Phase 4 — Archive**: preserve minimal historical notes (`CONVO.MD`) and remove domain references from catalog.

## References

- [`lib/thunderline/thunderchief/orchestrator.ex`](lib/thunderline/thunderchief/orchestrator.ex:2)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:441)
- [`HOW_TO_AUDIT.md`](HOW_TO_AUDIT.md:238)