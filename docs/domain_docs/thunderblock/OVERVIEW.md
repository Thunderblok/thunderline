# ThunderBlock Domain Overview

**Vertex Position**: Data Plane Ring — Persistence Layer

**Purpose**: Persistent runtime foundation providing storage, retention, timing, and orchestrated infrastructure for every Thunderline workload.

## Charter

ThunderBlock supplies the durable state and runtime services that keep Thunderline operational. The domain owns Postgres, Mnesia, and cache coordination; enforces retention policies; and now houses the consolidated ThunderClock timing system. It ensures that all domains can rely on consistent storage, scheduled activities, and fault-tolerant orchestration without duplicating infrastructure concerns.

## Core Responsibilities

1. **Persistent Storage** — manage vault knowledge graphs, embeddings, decisions, and system logs in Postgres and distributed caches.
2. **Retention & Lifecycle** — enforce archival, purge, and snapshot policies across vault resources and event logs.
3. **Timing & Scheduling** — provide timers, cron jobs, and delayed execution (former ThunderClock) to drive time-based workflows.
4. **Distributed Coordination** — expose supervision trees, execution containers, and DAG orchestration to support ThunderBolt and ThunderFlow.
5. **Infrastructure Telemetry** — emit retention, timing, and queue metrics that power Thunderwatch dashboards.
6. **Security & Tenancy** — maintain multi-tenant isolation, resource ownership boundaries, and audit trails for storage access.

## Ash Resources

- [`Thunderline.Thunderblock.Resources.VaultKnowledgeNode`](lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:1) — durable knowledge representation for agents and models.
- [`Thunderline.Thunderblock.Resources.RetentionPolicy`](lib/thunderline/thunderblock/resources/retention_policy.ex:1) — declarative policies controlling retention and archival workflows.
- [`Thunderline.Thunderblock.Resources.ExecutionContainer`](lib/thunderline/thunderblock/resources/execution_container.ex:13) — runtime container records used to coordinate compute jobs.
- [`Thunderline.Thunderblock.Resources.Workf‌lowTracker`](lib/thunderline/thunderblock/resources/workflow_tracker.ex:1) — tracks DAG execution state for orchestrated workflows.
- [`Thunderline.Thunderblock.Resources.TaskOrchestrator`](lib/thunderline/thunderblock/resources/task_orchestrator.ex:12) — manages cross-domain tasks triggered by timers or retention events.

### Timing Subdomain (ThunderClock)

- [`Thunderline.Thunderblock.Timing.Timer`](docs/domains/thunderblock/timing/OVERVIEW.md) — consolidated timer resource for one-shot and recurring execution.
- [`Thunderline.Thunderblock.Timing.CronJob`](docs/domains/thunderblock/timing/OVERVIEW.md) — cron scheduler driving recurring maintenance operations.
- [`Thunderline.Thunderblock.Timing.DelayedJob`](docs/domains/thunderblock/timing/OVERVIEW.md) — delayed execution records for future tasks.

## Supporting Modules

- [`Thunderline.Thunderblock.Domain`](lib/thunderline/thunderblock/domain.ex:2) — Ash domain definition tying resources to the persistence layer.
- [`Thunderline.Thunderblock.Telemetry.Retention`](lib/thunderline/thunderblock/telemetry/retention.ex:1) — emits retention metrics and alerts.
- [`Thunderline.Thunderblock.SupervisionTree`](lib/thunderline/thunderblock/resources/supervision_tree.ex:19) — supervises workflow and retention workers.
- [`Thunderline.Thunderblock.Timing.TimerScheduler`](docs/domains/thunderblock/timing/OVERVIEW.md) — GenServer orchestrating timer execution.
- [`Thunderline.Thunderblock.Timing.CronScheduler`](docs/domains/thunderblock/timing/OVERVIEW.md) — cron driver executing scheduled jobs.

## Integration Points

### Vertical Edges

- **ThunderBolt → ThunderBlock**: persists model artifacts, lane telemetry, and UPM snapshots in vault resources.
- **ThunderFlow → ThunderBlock**: stores event history, system actions, and audit logs for compliance.
- **ThunderBlock → ThunderFlow**: publishes `system.persistence.*` events when retention sweeps or timing jobs complete.
- **ThunderBlock → ThunderLink**: supplies real-time state changes for dashboards via EventBus.
- **ThunderBlock → ThunderVine**: sends provenance updates reflecting storage changes for lineage tracking.

### Horizontal Edges

- **ThunderBlock ↔ ThunderCrown**: consumes governance directives for retention policies and reports back audit results.
- **ThunderBlock ↔ ThunderGate**: enforces tenancy and capability checks for storage access via shared policy modules.
- **ThunderBlock ↔ ThunderGrid**: coordinates zone-specific storage or replication strategies when spatial placement matters.

## Telemetry Events

- `[:thunderline, :thunderblock, :retention, :sweep_started|:sweep_completed]`
- `[:thunderline, :thunderblock, :timing, :timer_fired]`
- `[:thunderline, :thunderblock, :cron, :job_executed]`
- `[:thunderline, :thunderblock, :vault, :policy_violation]`
- `[:thunderline, :thunderblock, :workflow, :state_changed]`

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Vault read/write | 10 ms | 60 ms | 5k/s |
| Retention sweep batch | 500 ms | 2 s | 100/min |
| Timer firing | 20 ms | 120 ms | 1k/s |
| Cron job dispatch | 40 ms | 200 ms | 500/min |
| Workflow checkpoint | 30 ms | 150 ms | 2k/min |

## Security & Policy Notes

- Audit highlighted numerous `authorize_if always()` patterns in vault resources (see [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:365)); remediation is required to enforce tenancy.
- Retention jobs must log deletions and archive actions for auditable trails.
- Timing jobs should respect governance capability checks before executing cross-domain actions.
- Feature flags controlling retention tiers and timing experiments must be documented in `FEATURE_FLAGS.md`.

## Testing Strategy

- Unit tests for retention policy evaluation, timer scheduling, and cron parsing.
- Integration tests covering end-to-end retention sweeps and workflow orchestration.
- Property tests for vault knowledge graph consistency and embedding vector uniqueness.
- Chaos testing of timing recovery (ensure timers resume after crashes) and retention sweeps under heavy load.

## Development Roadmap

1. **Phase 1 — Policy Remediation**: reinstate Ash policies across vault resources and remove direct `authorize_if always()`.
2. **Phase 2 — Retention Metrics**: complete metric export for DLQ and retention sweeps; integrate with Thunderwatch dashboards.
3. **Phase 3 — Timing Hardening**: add distributed coordination and clock drift detection for the timing subsystem.
4. **Phase 4 — Workflow Modernization**: migrate legacy ThunderChief orchestration remnants into official workflow trackers and document shutdown paths.

## References

- [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md:8)
- [`docs/domains/thunderblock/timing/OVERVIEW.md`](docs/domains/thunderblock/timing/OVERVIEW.md:1)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:78)
- [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:365)
- [`docs/documentation/HC_EXECUTION_PLAN.md`](docs/documentation/HC_EXECUTION_PLAN.md:67)