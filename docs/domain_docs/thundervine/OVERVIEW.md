# ThunderVine Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thundervine/domain.ex`  
**Vertex Position**: Data Plane Ring — Workflow Orchestration

## Purpose

ThunderVine is the **workflow orchestration and DAG management domain**:
- Event-sourced workflow tracking
- Lineage analysis and replay
- Behavior graph execution (HC-Δ-1)
- Thunderoll evolutionary experiments (HC-Δ-7)

## Domain Extensions

```elixir
use Ash.Domain,
  validate_config_inclusion?: false,
  extensions: [AshGraphql.Domain]
```

- **AshGraphql** — Extensive GraphQL queries/mutations (authorize? true)

## Registered Resources (10)

### Workflow Resources
| Resource | Module |
|----------|--------|
| Workflow | `Thunderline.Thundervine.Resources.Workflow` |
| WorkflowNode | `Thunderline.Thundervine.Resources.WorkflowNode` |
| WorkflowEdge | `Thunderline.Thundervine.Resources.WorkflowEdge` |
| WorkflowSnapshot | `Thunderline.Thundervine.Resources.WorkflowSnapshot` |

### TAK Resources
| Resource | Module |
|----------|--------|
| TAKChunkEvent | `Thunderline.Thundervine.Resources.TAKChunkEvent` |
| TAKChunkState | `Thunderline.Thundervine.Resources.TAKChunkState` |

### Behavior DAG (HC-Δ-1)
| Resource | Module |
|----------|--------|
| BehaviorGraph | `Thunderline.Thundervine.Resources.BehaviorGraph` |
| GraphExecution | `Thunderline.Thundervine.Resources.GraphExecution` |

### Thunderoll (HC-Δ-7)
| Resource | Module |
|----------|--------|
| Experiment | `Thunderline.Thundervine.Thunderoll.Resources.Experiment` |
| Generation | `Thunderline.Thundervine.Thunderoll.Resources.Generation` |

## GraphQL API

**Authorization enabled**: `authorize? true`

### Queries
- Workflow: `workflow`, `workflows`, `workflow_by_correlation`
- WorkflowNode: `workflow_nodes`
- WorkflowEdge: `workflow_edges`
- WorkflowSnapshot: `workflow_snapshot`, `workflow_snapshots`
- BehaviorGraph: `behavior_graph`, `behavior_graphs`, `active_behavior_graphs`, `behavior_graph_by_name`
- GraphExecution: `graph_execution`, `graph_executions`, `recent_graph_executions`
- Thunderoll: `thunderoll_experiment(s)`, `thunderoll_experiments_running`, `thunderoll_generations`

### Mutations
- Workflow: `start_workflow`, `seal_workflow`, `update_workflow_metadata`
- WorkflowNode: `record_node_start`, `mark_node_success`, `mark_node_error`
- WorkflowEdge: `create_workflow_edge`
- WorkflowSnapshot: `capture_workflow_snapshot`
- BehaviorGraph: `create_behavior_graph`, `create_behavior_graph_from_struct`, `update_behavior_graph`, `archive_behavior_graph`, `delete_behavior_graph`
- GraphExecution: `start_graph_execution`, `complete_graph_execution`, `fail_graph_execution`, `cancel_graph_execution`
- Thunderoll: `start_thunderoll_experiment`, `begin_thunderoll_experiment`, `complete_thunderoll_experiment`, `fail_thunderoll_experiment`, `abort_thunderoll_experiment`, `record_thunderoll_generation`

## Supporting Modules

| Module | Purpose |
|--------|---------|
| Executor | Workflow execution engine |
| Graph | Graph utilities |
| Node | Node management |
| Replay | Event replay functionality |
| SpecParser | Workflow spec parsing |
| TAKEventRecorder | TAK event recording |
| WorkflowCompactor | Workflow compaction |
| FieldChannel/FieldChannels | Field channel management |

## Related Domains

- **ThunderGrid** → Spatial events logged to Vine lineage
- **ThunderFlow** → Event publication
- **ThunderBolt** → Compute orchestration
