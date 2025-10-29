# DIP THV-001: Thundervine DAG + Jido Agent Runtime Integration

Status: Draft (Pending High Command Approval)
Author: Honey Badger Ops (Automated Assistant)
Date: 2025-08-27
Target Release: HC-13 / Post Phase A Voice Consolidation
Revision: 0.1

## 1. Purpose
Establish a unified pattern for capturing, governing, replaying, and optimizing agent (PAC) and domain workflows by integrating:
- Jido (agent/PAC runtime & composable action sequencing)
- Thundervine (durable DAG lineage in ThunderBlock)
- Ash AI (LLM tooling & structured outputs under Crown)
while preserving existing domain sovereignty, event taxonomy integrity, and security choke-points (Gate/ThunderBridge).

## 2. Scope
In Scope:
- Event contract for action/workflow lineage (evt.action.*, dag.*)
- Thundervine DAG resource finalization (schema + migrations)
- In-memory pilot collector & phased Postgres persistence
- Replay API design & deterministic vs adaptive modes
- Feature flag matrix & rollout gating
- Security: Ensuring all LLM/provider egress remains through Gate/Bridge
- Integration adapters (Jido ↔ EventBus; optional Ash action bridge)

Out of Scope (Future DIPs):
- Jido sensor ecosystem expansion
- Advanced AI planning (multi-model arbitration)
- Full semantic embedding & vector-based workflow retrieval
- Cross-tenant DAG replication / sharding strategy

## 3. Motivation
Current state: Live orchestration (Bolt) and durable memory (VaultAction, VaultExperience) exist, but we lack a *topological*, *replayable*, *causally-linked* artifact of successful workflows. Agents must rediscover patterns. Governance lacks full lineage context for policy evaluation and optimization. Thundervine + Jido closes that gap.

## 4. Architectural Positioning
| Layer | Responsibility | Technology | New/Existing |
|-------|----------------|-----------|-------------|
| PAC Runtime | Agent loop, mission steps | Jido | New Integration |
| Orchestration (Live) | Execution scheduling / concurrency | Bolt DAG/Lane/Cell | Existing |
| Durable Lineage | Immutable workflow graphs | Thundervine DAG (ThunderBlock) | Extended |
| LLM / Tooling | Structured outputs & tool calls | Ash AI (Crown) | Existing (Adopt) |
| Security / Egress | Audit, rate-limit, redaction | Gate / ThunderBridge | Existing |
| Event Fabric | Normalization & routing | Flow (Broadway) | Existing |

Separation of concerns: Jido never writes lineage directly; it emits events. Thundervine consumes success events and persists DAG. Replay re-enters via Flow to avoid side-channel drift.

## 5. Event Contract (Canonical)
All lineage and action semantics travel as `%Thunderline.Event{}`.

### 5.1 Namespaces (Additions)
- `evt.action.started`
- `evt.action.completed`
- `evt.action.failed`
- `cmd.workflow.plan`
- `cmd.workflow.execute`
- `dag.node.recorded` (internal emission, optional external
- `dag.commit`
- `dag.replay.started`
- `dag.replay.completed`

### 5.2 Action Event Shape
```
%Thunderline.Event{
  name: "evt.action.completed",
  source: :pac | :bolt | :crown,
  correlation_id: "<workflow-correlation>",
  causation_id: "<prior-node-or-event>",
  payload: %{
    workflow_id: uuid | nil,        # may be established lazily
    node_id: uuid,                  # globally unique node identifier
    action_ref: "Module.Action" | "Resource#action",
    action_kind: :jido | :ash | :llm_tool | :system,
    resource?: %{domain: :atom, resource: :atom, id: uuid} | nil,
    status: :success | :error,
    latency_ms: integer | nil,
    result: map() | nil,
    error?: map() | nil,
    metadata: map()
  }
}
```

### 5.3 DAG Commit Event
```
name: "dag.commit"
payload: %{workflow_id: uuid, node_count: integer, replayable: boolean, run_signature: binary}
```

## 6. Thundervine DAG Schema (Adjustments Requested Before Migration)
Existing draft resources added (not migrated yet): `DAGWorkflow`, `DAGNode`, `DAGEdge`, `DAGSnapshot`.

Requested field additions prior to migration freeze:
| Resource | Field | Type | Reason |
|----------|-------|------|--------|
| DAGWorkflow | agent_id | :uuid | Associate PAC origin |
| DAGWorkflow | replayable | :boolean (default true) | Mark sealed workflow as replay-safe |
| DAGWorkflow | run_signature | :string | Deduplicate identical runs |
| DAGNode | action_kind | :atom | Distinguish runtime origin |
| DAGNode | sequence_index | :integer | Stable ordering fallback |
| DAGSnapshot | run_signature | :string | Link to workflow signature |

Indices / Constraints:
- `dag_nodes(workflow_id, sequence_index)` – ordering queries
- Partial index `dag_nodes(status='success')` for success-only analysis
- Unique `(workflow_id, sequence_index)`
- `dag_workflows(correlation_id)` unique
- `dag_snapshots(workflow_id, version)` unique

## 7. Replay Modes
| Mode | Correlation Strategy | Use Case |
|------|----------------------|----------|
| Deterministic | New correlation_id; embed `original_workflow_id` in payload | Proven pattern re-execution |
| Adaptive | New correlation_id; attach `replay_parent_id` and mark replacement nodes with edge_type :repair | Partial recovery / optimization |

Replay emits: `dag.replay.started` → (action events) → `dag.replay.completed`.

## 8. Integration Adapters
### 8.1 Jido Adapter (New Module: `Thunderline.PAC.JidoAdapter`)
Responsibilities:
- Translate Jido action lifecycle → event emissions
- Maintain ephemeral map: correlation_id → workflow_id (once persisted)
- Provide helper `record_action_start/finish` with latency calc

### 8.2 Ash Action Bridge (Optional)
Allows selective Ash actions to register as Jido actions via metadata, for hybrid flows.

### 8.3 In-Memory DAG Collector (Pilot)
ETS tables:
- `:thundervine_workflows`
- `:thundervine_nodes`
Used during *Pilot Phase* before Postgres migrations to validate shape & volume.

## 9. Feature Flags
| Flag | Default | Gated Components |
|------|---------|------------------|
| :enable_thundervine_dag | false | DAG persistence + sink activation |
| :enable_jido | false | Jido adapter supervision tree |
| :enable_dag_replay | false | Replay API routes |
| :enable_dag_snapshot | false | Snapshot creation action |

## 10. Security & Governance
- All provider/LLM calls: Crown Tool exec (Ash AI) → GatePolicy → ThunderBridge → Provider → event.
- Jido AI actions (if enabled) must also route via same choke point; direct HTTP forbidden.
- Policy hook: Crown subscribes to `dag.commit` and can emit `ai.policy.workflow.flagged` if anomaly detected.
- Audit: Gate logs all external egress; DAG commit references Gate audit id (add field `audit_ref` optional later).

## 11. Telemetry Plan
| Event | Metrics | Labels |
|-------|---------|--------|
| evt.action.completed | action_latency_ms histogram | action_kind,status |
| dag.commit | dag_node_count gauge (one-shot), workflow_duration_ms | replayable |
| dag.replay.completed | replay_duration_ms | mode, outcome |
| governance.policy.block | policy_blocks_counter | reason |

Traces: Root span = workflow correlation_id; child spans per node.

## 12. Rollout Phases
| Phase | Goals | Exit Criteria |
|-------|-------|---------------|
| Pilot (No Migrations) | ETS collector + Jido adapter + event contract | 3 sample missions captured; replay simulation works in-memory |
| Migration Cut | Add fields + indices; run Ecto migrations | Schema applied; no errors; flags still off |
| Sink Activation | Enable :enable_thundervine_dag | Events persist; dag.commit visible |
| Replay Enable | Enable :enable_dag_replay | Deterministic replay success demo |
| Adaptive Replay | Add edge_type :repair logic | Adaptive test passes with partial re-run |

## 13. Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|-----------|
| Event schema churn mid-pilot | Rework cost | Pilot before migrations; freeze after approval |
| Replay side effects duplication | Data corruption | Idempotency keys per resource_ref; dry-run mode |
| Volume explosion | Storage pressure | Sequence index pruning + configurable retention window + snapshots |
| Dual runtime confusion | Developer errors | Clear docs + naming conventions (`Jido` vs `Ash`) |
| Security bypass via Jido | Unauthorized egress | Static code scan: forbid HTTP clients in Jido actions without Crown Tool context |

## 14. Open Decisions (Require HC Approval)
| ID | Question | Options | Recommendation |
|----|----------|---------|---------------|
| OD1 | Include agent_id in DAGWorkflow? | yes / no | Yes (filter & governance) |
| OD2 | Replay correlation strategy | reuse / new | New correlation_id + parent pointer |
| OD3 | Seal trigger | explicit event / heuristic | Explicit `dag.workflow.seal` action (avoid premature seal) |
| OD4 | Snapshot timing | on seal / scheduled | On seal (first), allow later version increments |
| OD5 | Adaptive edge type taxonomy | :repair only / extended | Start with :repair, extend later |
| OD6 | Jido AI allowance | full / gated | Gated behind Crown Tool mapping |

## 15. Approval Checklist
- [ ] Event namespaces accepted
- [ ] Schema field additions approved
- [ ] Feature flags approved
- [ ] Security choke-point reaffirmed
- [ ] Open Decisions resolved (OD1–OD6)
- [ ] Go signal to proceed with Pilot Phase implementation

## 16. Backwards Compatibility & Decommission Plan
No existing production DAG persistence; zero migration risk. If pilot rejected, delete DAG resource modules and remove domain registration (clean revert). After persistence launch, decommission ETS collector.

## 17. Implementation Responsibility Map
| Component | Primary Owner | Support |
|-----------|---------------|---------|
| Event Contract Module | Flow | Block, Bolt |
| Jido Adapter | PAC/Jido Team | Flow |
| DAG Sink (Broadway stage) | Block | Flow |
| Replay API | Block | Crown |
| Governance Hooks | Crown | Gate |
| Security Gate Enhancements | Gate | Crown |

## 18. Initial Pilot Mission (Proposed)
Mission: "Summarize channel thread & enqueue follow-up action"
Steps:
1. Jido Action: fetch recent messages → evt.action.completed
2. Jido Action: request summary tool (Ash AI) → ai.tool.* → evt.action.completed
3. Jido Action: create follow-up VaultAction → evt.action.completed
Produces DAG with 3 nodes, 2 causal edges.

## 19. Dependencies / Version Pins (Draft)
```
{:jido, "~> 0.2.0"}
{:jido_ai, "~> 0.1", optional: true}
{:ash_ai, github: "ash-project/ash_ai", ref: "<pin-after-approval>"}
```
Add Mix task: `mix thunderline.check_integrations` to assert pinned versions.

## 20. Appendix – Future Enhancements
- pgvector integration for run_signature similarity search
- Adaptive policy engine scoring workflows (reward model)
- Cross-workflow pattern mining (frequent subgraph extraction)
- AI assisted repair suggestions via Crown + Ash AI structured reasoning

---
**Request:** High Command please review Sections 14 & 15 (Open Decisions + Approval Checklist). Provide resolution codes; upon approval we proceed with Pilot (no migrations yet) aligning with Honey Badger consolidation timeline.
