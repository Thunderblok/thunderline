# ThunderFlow Domain Overview

**Vertex Position**: Data Plane Ring — Event Layer  
**Namespace**: `Thunderline.Thunderflow.*`  
**Last Verified**: 2025-12-04

## Purpose

ThunderFlow is the event processing backbone. It validates, routes, and observes every signal emitted across Thunderline using Broadway pipelines, Mnesia queues, and structured telemetry.

## Charter

ThunderFlow anchors all domain-to-domain communication. The domain owns event validation, routing semantics, and telemetry that prove the health of every pipeline. It provides Broadway-based fanout, guarantees idempotency across distributed workers, and ensures that every event conforms to the shared taxonomy before it is accepted.

## Directory Structure (Grounded)

\`\`\`
lib/thunderline/thunderflow/
├── domain.ex                    # Ash Domain with AshAdmin
├── supervisor.ex                # OTP Supervisor
├── blackboard.ex                # Shared key-value store
├── blackboard_tripwire.ex       # Blackboard monitoring
├── broadway_integration.ex      # Broadway lifecycle helpers
├── broadway_monitoring.ex       # Broadway metrics
├── demo_realtime_emitter.ex     # Demo/testing emitter
├── dlq.ex                       # Dead letter queue handling
├── domain_processor.ex          # Domain event processor
├── error_class.ex               # Error classification types
├── error_classifier.ex          # Error classification logic
├── error_classifier_telemetry.ex # Error telemetry
├── event.ex                     # Core event struct
├── event_buffer.ex              # Event buffering
├── event_bus.ex                 # ⭐ EventBus facade (main entrypoint)
├── event_ops.ex                 # Event operations
├── event_producer.ex            # Broadway producer
├── event_validator.ex           # Event taxonomy validation
├── heartbeat.ex                 # System heartbeat
├── intrinsic_reward.ex          # Reward signal module
├── metric_sources.ex            # Metric collection
├── ml_events.ex                 # ML-specific events
├── mnesia_producer.ex           # Mnesia-backed producer
├── mnesia_tables.ex             # Mnesia table definitions
├── pipeline_telemetry.ex        # Pipeline metrics
├── resurrector.ex               # Event recovery
├── retry_policy.ex              # Retry configuration
├── telemetry.ex                 # Telemetry module
├── telemetry_seeder.ex          # Telemetry bootstrap
├── consumers/                   # Event consumers
├── events/                      # Event definitions
│   ├── event.ex                 # ✅ Ash Resource - canonical event
│   ├── clear_all_records.ex     # Event replay clearing
│   ├── linter.ex                # Event taxonomy linting
│   ├── payloads.ex              # Typed payloads
│   └── registry.ex              # Event registry
├── event_bus/                   # EventBus internals
├── features/
│   └── feature_window.ex        # ✅ Ash Resource - feature materialization
├── flow/                        # Flow primitives
│   ├── processor.ex
│   ├── producer.ex
│   ├── sink.ex
│   └── telemetry.ex
├── jobs/                        # Oban workers
│   ├── demo_job.ex
│   ├── domain_processor.ex
│   ├── domain_processors.ex
│   └── process_event.ex
├── lineage/
│   └── edge.ex                  # ✅ Ash Resource - provenance edges
├── observability/               # Monitoring modules
│   ├── drift.ex
│   ├── drift_metrics_producer.ex
│   ├── fanout_aggregator.ex
│   ├── fanout_guard.ex
│   ├── ndjson.ex
│   ├── queue_depth_collector.ex
│   └── ring_buffer.ex
├── pipelines/                   # Broadway pipelines
│   ├── cross_domain_pipeline.ex # Inter-domain routing
│   ├── event_pipeline.ex        # General event processing
│   ├── example_domain_pipeline.ex
│   ├── realtime_pipeline.ex     # Low-latency fanout
│   └── vine_ingress.ex          # Vine integration
├── probing/                     # Probing/drift detection
│   ├── attractor.ex
│   ├── attractor_service.ex
│   ├── embedding.ex
│   ├── engine.ex
│   ├── metrics.ex
│   ├── monte_carlo.ex
│   ├── provider.ex
│   ├── providers/
│   └── workers/
├── processor/                   # Event processors
├── producers/                   # Broadway producers
├── resources/                   # Domain resources
│   ├── consciousness_flow.ex    # ✅ Ash Resource
│   ├── event_ops.ex             # ✅ Ash Resource
│   ├── event_stream.ex          # ✅ Ash Resource
│   ├── probe_attractor_summary.ex # ✅ Ash Resource
│   ├── probe_lap.ex             # ✅ Ash Resource
│   ├── probe_run.ex             # ✅ Ash Resource
│   └── system_action.ex         # ✅ Ash Resource
├── support/                     # Support modules
└── telemetry/                   # Telemetry handlers
\`\`\`

## Ash Domain Registration

**Domain**: \`Thunderline.Thunderflow.Domain\`  
**Extensions**: \`AshAdmin.Domain\`

### Registered Resources
| Resource | Module | Table | Purpose |
|----------|--------|-------|---------|
| ConsciousnessFlow | \`Thunderflow.Resources.ConsciousnessFlow\` | — | Agent consciousness streams |
| EventStream | \`Thunderflow.Resources.EventStream\` | — | Event stream definitions |
| SystemAction | \`Thunderflow.Resources.SystemAction\` | — | System actions |
| Event | \`Thunderflow.Events.Event\` | \`events\` | Canonical event schema |
| ProbeRun | \`Thunderflow.Resources.ProbeRun\` | \`probe_runs\` | Probing runs |
| ProbeLap | \`Thunderflow.Resources.ProbeLap\` | \`probe_laps\` | Probing laps |
| ProbeAttractorSummary | \`Thunderflow.Resources.ProbeAttractorSummary\` | \`probe_attractor_summaries\` | Attractor analysis |
| FeatureWindow | \`Thunderline.Features.FeatureWindow\` | \`feature_windows\` | Feature materialization |
| Edge | \`Thunderline.Lineage.Edge\` | \`lineage_edges\` | Provenance edges |

**Note**: \`FeatureWindow\` and \`Edge\` have root namespace (\`Thunderline.Features\`, \`Thunderline.Lineage\`) but belong to Thunderflow domain.

## Broadway Pipeline Architecture

### Pipelines
| Pipeline | Purpose | Queue |
|----------|---------|-------|
| \`EventPipeline\` | General domain event processing | Mnesia |
| \`CrossDomainPipeline\` | Inter-domain routing | Mnesia |
| \`RealTimePipeline\` | Low-latency UI/dashboard fanout | Mnesia |
| \`VineIngress\` | DAG provenance integration | — |

### Event Routing
\`\`\`elixir
# Auto-routing based on event type
process_event(:agent_updated, data)     # → realtime
process_event(:cross_domain_message, data) # → cross_domain
process_event(:other, data)             # → event (general)
\`\`\`

## Core Modules

### Event Infrastructure
| Module | Status | Purpose |
|--------|--------|---------|
| \`EventBus\` | Active | Main entrypoint for event publishing |
| \`Event\` | Active | Core event struct |
| \`EventValidator\` | Active | Taxonomy validation |
| \`EventBuffer\` | Active | Buffering layer |
| \`MnesiaProducer\` | Active | Mnesia-backed Broadway producer |
| \`DLQ\` | Active | Dead letter queue |
| \`RetryPolicy\` | Active | Exponential backoff config |

### Observability
| Module | Status | Purpose |
|--------|--------|---------|
| \`FanoutAggregator\` | Active | Downstream delivery metrics |
| \`FanoutGuard\` | Active | Fanout protection |
| \`QueueDepthCollector\` | Active | Broadway queue stats |
| \`DriftMetricsProducer\` | Active | Drift detection |
| \`Drift\` | Active | Drift analysis |

### Probing System
| Module | Status | Purpose |
|--------|--------|---------|
| \`Probing.Engine\` | Active | Probe execution engine |
| \`Probing.Attractor\` | Active | Attractor analysis |
| \`Probing.AttractorService\` | Active | Attractor service |
| \`Probing.Embedding\` | Active | Embedding generation |
| \`Probing.MonteCarlo\` | Active | Monte Carlo simulation |

### Background Jobs (Oban)
| Worker | Queue | Purpose |
|--------|-------|---------|
| \`ProcessEvent\` | \`:events\` | Event processing |
| \`DomainProcessor\` | \`:domain\` | Domain-specific processing |
| \`DemoJob\` | \`:demo\` | Demo/testing |

## Integration Points

### Downstream (Flow → X)
- **→ ThunderBolt**: Cross-domain batches enqueue Oban workers
- **→ ThunderLink**: Real-time pipeline publishes to \`thunderline:channels\`
- **→ ThunderVine**: Lineage edges update DAG provenance
- **→ ThunderBlock**: Persistence via EventOps

### Upstream (X → Flow)
- **ThunderGate →**: Ingress normalizes external signals before EventBus
- **ThunderCrown →**: Governance decisions emit \`ai.intent.*\` events
- **ThunderBlock →**: Vault updates trigger downstream events

## Telemetry Events

\`\`\`elixir
[:thunderline, :flow, :event, :validated]     # Successful validation
[:thunderline, :flow, :event, :published]     # Broadway accepted batch
[:thunderline, :flow, :event, :dropped]       # Validation failure
[:thunderline, :flow, :dlq, :enqueue]         # Dead letter entry
[:thunderline, :pipeline, :domain_events, :start]  # Batch start
[:thunderline, :pipeline, :domain_events, :stop]   # Batch complete
[:thunderline, :blackboard, :put]             # Blackboard write
[:thunderline, :blackboard, :fetch]           # Blackboard read
[:thunderline, :heartbeat, :tick]             # System heartbeat
\`\`\`

## Known Issues & TODOs

1. **Namespace Inconsistency**: \`FeatureWindow\` and \`Edge\` use root namespace but belong to Thunderflow domain
2. **DLQ Dashboard**: Need to finalize DLQ dashboards in Thunderwatch
3. **Policy Coverage**: Some resources have placeholder policies
4. **Probing Workers**: Status of probing workers directory unclear

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Event validation | 5 ms | 20 ms | 5k/s |
| Event enqueue (Mnesia) | 10 ms | 40 ms | 3k/s |
| Cross-domain dispatch | 25 ms | 120 ms | 1k/s |
| Real-time fanout | 15 ms | 60 ms | 2k/s |
| DLQ dequeue | 50 ms | 200 ms | 200/s |

## Security & Policy Notes

- Enforce taxonomy linting via \`mix thunderline.events.lint\` before deploying new event families
- Broadway pipelines must be registered under correct supervision tree
- Gate external publishes through ThunderGate capability checks
- Audit trail persistence is mandatory for compliance

## Development Priorities

1. **Phase 1**: Telemetry hardening - finalize DLQ dashboards
2. **Phase 2**: Policy reinforcement - add Ash policy coverage
3. **Phase 3**: Self-healing pipelines - auto-pruning and DLQ replay tooling
4. **Phase 4**: Federated observability - OTLP exporters

## References

- Domain definition: [domain.ex](../../../lib/thunderline/thunderflow/domain.ex)
- EventBus: [event_bus.ex](../../../lib/thunderline/thunderflow/event_bus.ex)
- Event taxonomy: [EVENT_TAXONOMY.md](../../EVENT_TAXONOMY.md)
