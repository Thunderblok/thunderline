# ThunderBlock Domain Overview

**Vertex Position**: Data Plane Ring — Persistence Layer  
**Namespace**: `Thunderline.Thunderblock.*`  
**Last Verified**: 2025-12-04

## Purpose

ThunderBlock is the persistent runtime foundation providing storage, retention, timing, and orchestrated infrastructure for every Thunderline workload. This is the **only domain** that may directly access `Thunderline.Repo`.

## Charter

ThunderBlock supplies durable state and runtime services. It owns Postgres, Mnesia, and cache coordination; enforces retention policies; and houses the timing subsystem. All other domains access persistence through Ash actions on ThunderBlock resources.

## Directory Structure (Grounded)

\`\`\`
lib/thunderline/thunderblock/
├── domain.ex                    # Ash Domain with AshAdmin
├── checkpoint.ex                # Checkpoint operations
├── domain_activation.ex         # Domain activation helpers
├── domain_registry.ex           # Domain registry
├── health.ex                    # Health checks
├── migration_runner.ex          # Migration execution
├── oban_introspection.ex        # Oban queue inspection
├── retention.ex                 # Retention operations
├── thunder_memory.ex            # Memory management
├── validations.ex               # Shared validations (Ash Resource)
├── jobs/                        # Oban workers
│   ├── cross_domain_processor.ex     # ⚠️ Empty stub
│   ├── domain_sync_processor.ex      # ✅ Active - domain sync
│   ├── retention_sweep_worker.ex     # ✅ Active - retention sweeps
│   └── scheduled_workflow_processor.ex # ⚠️ Empty stub
├── rate_limiting/               # Rate limit infrastructure
├── resources/                   # ✅ 27 Ash Resources
│   ├── active_domain_registry.ex    # Domain activation
│   ├── channel_participant.ex       # Channel participation
│   ├── cluster_node.ex              # Cluster nodes
│   ├── community.ex                 # ExecutionTenant (renamed)
│   ├── distributed_state.ex         # Distributed state
│   ├── execution_container.ex       # Execution containers
│   ├── load_balancing_rule.ex       # Load balancing
│   ├── pac_home.ex                  # PAC user homes
│   ├── rate_limit_policy.ex         # Rate limiting
│   ├── retention_policy.ex          # Retention policies
│   ├── supervision_tree.ex          # Supervision tracking
│   ├── system_event.ex              # System events
│   ├── task_orchestrator.ex         # Task orchestration
│   ├── vault_action.ex              # Vault actions
│   ├── vault_agent.ex               # Vault agents
│   ├── vault_cache_entry.ex         # Cache entries
│   ├── vault_decision.ex            # Decision records
│   ├── vault_embedding_vector.ex    # Embedding vectors
│   ├── vault_experience.ex          # Experience records
│   ├── vault_knowledge_node.ex      # ⭐ Knowledge graph nodes
│   ├── vault_knowledge_node/        # KnowledgeNode helpers
│   ├── vault_memory_node.ex         # Memory nodes
│   ├── vault_memory_record.ex       # Memory records
│   ├── vault_query_optimization.ex  # Query optimization
│   ├── vault_user.ex                # Vault users
│   ├── vault_user_token.ex          # User tokens
│   ├── workflow_tracker.ex          # Workflow tracking
│   └── zone_container.ex            # Zone containers
├── retention/                   # Retention subsystem
├── telemetry/                   # Telemetry modules
└── timing/                      # Timing/scheduling subsystem
    ├── delayed_execution.ex     # Delayed job execution
    ├── generic_worker.ex        # Generic Oban worker
    ├── scheduler.ex             # Timer scheduler
    └── timer.ex                 # Timer definitions
├── types/                       # Custom Ash types
\`\`\`

## Ash Domain Registration

**Domain**: \`Thunderline.Thunderblock.Domain\`  
**Extensions**: \`AshAdmin.Domain\`

### Registered Resources (27 total)
| Category | Resource | Table |
|----------|----------|-------|
| **Infrastructure** | ExecutionContainer | \`execution_containers\` |
| | TaskOrchestrator | \`task_orchestrators\` |
| | ZoneContainer | \`zone_containers\` |
| | SupervisionTree | \`supervision_trees\` |
| | ExecutionTenant | \`communities\` |
| | ClusterNode | \`cluster_nodes\` |
| | DistributedState | \`distributed_states\` |
| | LoadBalancingRule | \`load_balancing_rules\` |
| | RateLimitPolicy | \`rate_limit_policies\` |
| | SystemEvent | \`system_events\` |
| | RetentionPolicy | \`retention_policies\` |
| | WorkflowTracker | \`workflow_trackers\` |
| | ActiveDomainRegistry | \`active_domain_registries\` |
| | ChannelParticipant | \`channel_participants\` |
| **Vault (Storage)** | VaultAction | \`vault_actions\` |
| | VaultAgent | \`vault_agents\` |
| | VaultCacheEntry | \`vault_cache_entries\` |
| | VaultDecision | \`vault_decisions\` |
| | VaultEmbeddingVector | \`vault_embedding_vectors\` |
| | VaultExperience | \`vault_experiences\` |
| | VaultKnowledgeNode | \`vault_knowledge_nodes\` |
| | VaultMemoryNode | \`vault_memory_nodes\` |
| | VaultMemoryRecord | \`vault_memory_records\` |
| | VaultQueryOptimization | \`vault_query_optimizations\` |
| | VaultUser | \`vault_users\` |
| | VaultUserToken | \`vault_user_tokens\` |
| **PAC** | PACHome | \`pac_homes\` |

### Domain Delegated Functions
\`\`\`elixir
# VaultKnowledgeNode operations exposed at domain level
Domain.add_relationship!/5
Domain.remove_relationship!/4
Domain.consolidate_knowledge!/3
Domain.verify_knowledge!/4
Domain.record_access!/4
Domain.search_knowledge!/5
Domain.traverse_graph!/5
Domain.by_domain!/2
Domain.optimize_relationships!/1
Domain.recalculate_metrics!/1
Domain.cleanup_deprecated!/1
\`\`\`

## Core Modules

### Infrastructure & Runtime
| Module | Status | Purpose |
|--------|--------|---------|
| \`Checkpoint\` | Active | State checkpointing |
| \`Health\` | Active | Health check endpoints |
| \`DomainActivation\` | Active | Domain lifecycle |
| \`DomainRegistry\` | Active | Domain registration |
| \`MigrationRunner\` | Active | Migration execution |
| \`ObanIntrospection\` | Active | Oban queue inspection |
| \`ThunderMemory\` | Active | Memory management |
| \`Retention\` | Active | Retention operations |

### Timing Subsystem
| Module | Status | Purpose |
|--------|--------|---------|
| \`Timing.Timer\` | Active | Timer definitions |
| \`Timing.Scheduler\` | Active | Timer scheduling |
| \`Timing.DelayedExecution\` | Active | Delayed jobs |
| \`Timing.GenericWorker\` | Active | Generic Oban worker |

### Background Jobs (Oban)
| Worker | Status | Queue | Purpose |
|--------|--------|-------|---------|
| \`RetentionSweepWorker\` | Active | \`:retention\` | Retention sweeps |
| \`DomainSyncProcessor\` | Active | \`:domain_sync\` | Domain synchronization |
| \`CrossDomainProcessor\` | ⚠️ Stub | — | Empty file |
| \`ScheduledWorkflowProcessor\` | ⚠️ Stub | — | Empty file |

## Integration Points

### Vertical Edges
- **ThunderBolt → Block**: Persists model artifacts, UPM snapshots
- **ThunderFlow → Block**: Stores event history, audit logs
- **Block → ThunderFlow**: Publishes \`system.persistence.*\` events
- **Block → ThunderLink**: Real-time state for dashboards
- **Block → ThunderVine**: Provenance updates for storage changes

### Horizontal Edges
- **Block ↔ ThunderCrown**: Governance directives for retention
- **Block ↔ ThunderGate**: Tenancy/capability checks for storage
- **Block ↔ ThunderGrid**: Zone-specific storage strategies

## Telemetry Events

\`\`\`elixir
[:thunderline, :thunderblock, :retention, :sweep_started]
[:thunderline, :thunderblock, :retention, :sweep_completed]
[:thunderline, :thunderblock, :timing, :timer_fired]
[:thunderline, :thunderblock, :vault, :policy_violation]
[:thunderline, :thunderblock, :workflow, :state_changed]
[:thunderline, :thunderblock, :checkpoint, :created]
[:thunderline, :thunderblock, :health, :check]
\`\`\`

## Known Issues & TODOs

1. **Empty Stub Jobs**: \`cross_domain_processor.ex\`, \`scheduled_workflow_processor.ex\` need implementation or removal
2. **Policy Coverage**: Many vault resources have \`authorize_if always()\` - need proper policies
3. **File Naming**: \`community.ex\` defines \`ExecutionTenant\` - consider renaming file
4. **Delegation Pattern**: Domain delegates to VaultKnowledgeNode - consider if this is the right pattern

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Vault read/write | 10 ms | 60 ms | 5k/s |
| Retention sweep batch | 500 ms | 2 s | 100/min |
| Timer firing | 20 ms | 120 ms | 1k/s |
| Workflow checkpoint | 30 ms | 150 ms | 2k/min |
| Knowledge graph query | 50 ms | 200 ms | 500/s |

## Security & Policy Notes

- **Repo Access**: Only ThunderBlock may call \`Thunderline.Repo\` directly
- **Policy Audit**: Many resources have placeholder policies (\`authorize_if always()\`)
- Retention jobs must log deletions for audit trails
- Timing jobs should respect governance checks before cross-domain actions

## Development Priorities

1. **Phase 1**: Remove or implement empty stub jobs
2. **Phase 2**: Policy remediation across vault resources
3. **Phase 3**: Timing subsystem hardening (distributed coordination)
4. **Phase 4**: Workflow tracker modernization

## References

- Domain definition: [domain.ex](../../../lib/thunderline/thunderblock/domain.ex)
- VaultKnowledgeNode: [vault_knowledge_node.ex](../../../lib/thunderline/thunderblock/resources/vault_knowledge_node.ex)
- Retention: [retention.ex](../../../lib/thunderline/thunderblock/retention.ex)
