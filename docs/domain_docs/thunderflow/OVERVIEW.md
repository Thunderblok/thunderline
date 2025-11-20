# ThunderFlow Domain Overview

**Vertex Position**: Data Plane Ring — Event Layer

**Purpose**: Event processing backbone that validates, routes, and observes every signal emitted across Thunderline.

## Charter

ThunderFlow anchors all domain-to-domain communication. The domain owns event validation, routing semantics, and telemetry that prove the health of every pipeline.
It provides Broadway-based fanout, guarantees idempotency across distributed workers, and ensures that every event conforms to the shared taxonomy before it is accepted.

## Core Responsibilities

1. **Canonical Event Validation** — enforce taxonomy, reserved prefixes, and correlation requirements before enqueueing events.
2. **Broadway Pipeline Orchestration** — operate general, cross-domain, and real-time pipelines with consistent batching and backpressure.
3. **Dead Letter & Retry Governance** — maintain DLQ statistics and retry policies for anything published via EventBus.
4. **Telemetry Fanout** — emit low-latency PubSub updates and structured telemetry spans for every stage of processing.
5. **Event Persistence** — manage Mnesia/Memento storage for transient queues and long-lived audit buffers.
6. **Consciousness Flows** — stream high-signal agent activity to consumers such as dashboards and AI governance.
7. **Operational Tooling** — expose queue depth, drift metrics, and liveness probes consumed by Thunderwatch and dashboards.

## Ash Resources

- [`Thunderline.Thunderflow.Events.Event`](lib/thunderline/thunderflow/events/event.ex:1) — canonical event schema with taxonomy validation and correlation helpers.
- [`Thunderline.Thunderflow.Events.Payloads`](lib/thunderline/thunderflow/events/payloads.ex:1) — typed payload helpers for domain-specific event bodies.
- [`Thunderline.Thunderflow.Lineage.Edge`](lib/thunderline/thunderflow/lineage/edge.ex:1) — lineage bookkeeping that links events to ThunderVine provenance.
- [`Thunderline.Thunderflow.Features.FeatureWindow`](lib/thunderline/thunderflow/features/feature_window.ex:1) — streaming feature materialization for ML experiments.
- [`Thunderline.Thunderflow.EventBus`](lib/thunderline/thunderflow/event_bus.ex:1) — Ash action wrapper that orchestrates publish, enqueue, and fanout flows.

## Supporting Modules

- [`Thunderline.Thunderflow.Pipelines.EventPipeline`](lib/thunderline/thunderflow/pipelines/event_pipeline.ex:1) — primary Broadway pipeline for domain events.
- [`Thunderline.Thunderflow.Pipelines.CrossDomainPipeline`](lib/thunderline/thunderflow/pipelines/cross_domain_pipeline.ex:1) — routes orchestration commands into ThunderBolt workloads.
- [`Thunderline.Thunderflow.Pipelines.RealTimePipeline`](lib/thunderline/thunderflow/pipelines/real_time_pipeline.ex:1) — low-latency fanout for UI and monitoring.
- [`Thunderline.Thunderflow.Observability.FanoutAggregator`](lib/thunderline/thunderflow/observability/fanout_aggregator.ex:1) — aggregates downstream delivery metrics.
- [`Thunderline.Thunderflow.Observability.QueueDepthCollector`](lib/thunderline/thunderflow/observability/queue_depth_collector.ex:1) — samples Broadway queue statistics for dashboards.

## Integration Points

### Vertical Edges

- **Thundergate → ThunderFlow**: ingress bridge normalizes external signals before invoking [`Thunderline.Thunderflow.EventBus.publish_event/1`](lib/thunderline/thunderflow/event_bus.ex:59).
- **Thundercrown → ThunderFlow**: governance decisions emit `ai.intent.*` events that enter the CrossDomain pipeline for orchestration.
- **ThunderBlock → ThunderFlow**: persistence layer broadcasts vault updates via EventBus to trigger downstream retraining runs.

### Horizontal Edges

- **ThunderFlow → ThunderBolt**: cross-domain batches call out to Broadway handlers that enqueue [`Thunderline.Thunderflow.Jobs.ProcessEvent`](lib/thunderline/thunderflow/jobs/process_event.ex:1) Oban workers.
- **ThunderFlow → ThunderLink**: real-time pipeline publishes UI topics (e.g. `thunderline:channels`) for live dashboards and presence.
- **ThunderFlow ↔ ThunderVine**: lineage edges update the DAG via [`Thunderline.Thunderflow.Lineage.Edge`](lib/thunderline/thunderflow/lineage/edge.ex:1) to keep provenance synchronized.

## Telemetry Events

- `[:thunderline, :flow, :event, :validated]` — successful validation prior to enqueue.
- `[:thunderline, :flow, :event, :published]` — Broadway accepted an event batch.
- `[:thunderline, :pipeline, :domain_events, :start]` / `:stop` — batch lifecycle metrics for EventPipeline.
- `[:thunderline, :flow, :event, :dropped]` — validation failure or policy rejection.
- `[:thunderline, :flow, :dlq, :enqueue]` — dead-letter queue entries awaiting remediation.

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Event validation | 5 ms | 20 ms | 5k/s |
| Event enqueue (Mnesia) | 10 ms | 40 ms | 3k/s |
| Cross-domain dispatch | 25 ms | 120 ms | 1k/s |
| Real-time fanout | 15 ms | 60 ms | 2k/s |
| DLQ dequeue | 50 ms | 200 ms | 200/s |

## Security & Policy Notes

- Enforce taxonomy linting via `mix thunderline.events.lint` before deploying new event families.
- Confirm Broadway pipelines are registered under the correct supervision tree to avoid orphaned processes.
- Coordinate remediation of commented tenancy policies recorded in [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:395).
- Gate external publishes through Thundergate capability checks to avoid bypassing rate limits.

## Testing Strategy

- Unit tests for EventBus validation and payload helpers.
- Integration tests covering Broadway end-to-end (publish → batch handler → observer).
- Property tests asserting idempotency of replayed events and lineage completeness.
- Load testing harness exercises queue depth collectors and telemetry fanout.

## Development Roadmap

1. **Phase 1 — Telemetry Hardening**: finalize DLQ dashboards and extend queue depth sampling into Thunderwatch.
2. **Phase 2 — Policy Reinforcement**: re-enable commented tenancy policies and add Ash policy coverage for lineage resources.
3. **Phase 3 — Self-healing Pipelines**: add auto-pruning of stale queues and Ops tooling for replaying DLQ batches.
4. **Phase 4 — Federated Observability**: integrate with platform-wide OTLP exporters (Operation Proof of Sovereignty).

## References

- [`docs/EVENT_FLOWS.md`](docs/EVENT_FLOWS.md:1)
- [`docs/documentation/T72H_TELEMETRY_HEARTBEAT.md`](docs/documentation/T72H_TELEMETRY_HEARTBEAT.md:42)
- [`docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md`](docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md:557)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:259)