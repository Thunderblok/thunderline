# ThunderCrown Domain Overview

**Vertex Position**: Control Plane Ring — Governance Layer

**Purpose**: AI governance and orchestration authority that decides which operations run, ensures compliance, and coordinates multi-agent workflows.

## Charter

ThunderCrown is the policy brain of Thunderline. It encodes Stone.Proof checks, Daisy governance logic, and AshAI workflows to authorize every significant action in the platform. The domain issues commands to ThunderBolt, mediates tool access, and maintains auditable reasoning for each decision. Its mandate is to answer “should we do this?” before any execution commences.

## Core Responsibilities

1. **Policy Decisioning** — evaluate and issue verdicts for all high-risk operations using Ash policies, Stone proofs, and Daisy modules.
2. **Workflow Orchestration** — manage declarative AshAI workflows that coordinate multiple agents and domain operations.
3. **Tool Governance** — vet and register MCP tools, ensuring only approved capabilities are available to agents.
4. **Scheduling & Delegation** — determine when tasks should run and delegate execution to downstream domains (Bolt, Block, Flow).
5. **Cross-Domain Coordination** — publish governance events that inform ThunderFlow, ThunderBolt, and ThunderBlock of authorized actions.
6. **Audit & Compliance** — persist decision trails and make governance evidence available for audits and incident response.

## Ash Resources

- [`Thunderline.Thundercrown.Policy`](lib/thunderline/thundercrown/policy.ex:1) — central policy definition with Ash-based decision predicates.
- [`Thunderline.Thundercrown.Resources.AgentRunner`](lib/thunderline/thundercrown/resources/agent_runner.ex:2) — executes approved Jido/AshAI tools under governance supervision.
- [`Thunderline.Thundercrown.Resources.AIPolicy`](lib/thunderline/thundercrown/resources/ai_policy.ex:1) — stores AI-specific policy documents and Stone proofs.
- [`Thunderline.Thundercrown.Resources.ConversationAgent`](lib/thunderline/thundercrown/resources/conversation_agent.ex:1) — governs multi-turn agent interactions and tool usage.
- [`Thunderline.Thundercrown.Resources.OrchestrationUI`](lib/thunderline/thundercrown/resources/orchestration_ui.ex:1) — exposes governance dashboards and operator controls.

## Supporting Modules

- [`Thunderline.Thundercrown.Domain`](lib/thunderline/thundercrown/domain.ex:2) — Ash domain definition integrating AshAI extensions.
- [`Thunderline.Thundercrown.Jido.ActionRegistry`](lib/thunderline/thundercrown/jido/action_registry.ex:1) — catalogues MCP/Jido actions available to governed agents.
- [`Thunderline.Thundercrown.Jobs.CrossDomainProcessor`](lib/thunderline/thundercrown/jobs/cross_domain_processor.ex:1) — routes governance outcomes to appropriate domain pipelines.
- [`Thunderline.Thundercrown.Jobs.ScheduledWorkflowProcessor`](lib/thunderline/thundercrown/jobs/scheduled_workflow_processor.ex:1) — runs scheduled governance workflows.
- [`Thunderline.Thundercrown.Introspection.SupervisionTreeMapper`](lib/thunderline/thundercrown/introspection/supervision_tree_mapper.ex:1) — enumerates supervised governance processes for observability.

## Integration Points

### Vertical Edges

- **ThunderGate → ThunderCrown**: capability issuance and identity claims evaluated against Crown policies before external requests proceed.
- **ThunderCrown → ThunderBolt**: publishes `ai.intent.*` events authorizing compute workloads and model deployments.
- **ThunderCrown → ThunderFlow**: governance decisions produce events that enter Broadway pipelines for monitoring and lineage.
- **ThunderCrown → ThunderBlock**: writes signed governance records and policy audit trails into the vault.

### Horizontal Edges

- **ThunderCrown ↔ ThunderForge**: receives compiled ThunderDSL workflows and feeds decision feedback into future compilations.
- **ThunderCrown ↔ ThunderGrid**: consumes spatial data when governance decisions depend on zone ownership or placement.
- **ThunderCrown ↔ ThunderLink**: drives operator-facing dashboards and agent communications with authorized commands.

## Telemetry Events

- `[:thunderline, :thundercrown, :policy, :evaluated]` — policy decision completed.
- `[:thunderline, :thundercrown, :workflow, :start|:stop]` — AshAI workflow lifecycle.
- `[:thunderline, :thundercrown, :mcp, :tool_registered]` — MCP tool onboarding.
- `[:thunderline, :thundercrown, :decision, :denied]` — rejected operation requiring follow-up.
- `[:thunderline, :thundercrown, :audit, :recorded]` — audit log persisted to ThunderBlock.

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Policy evaluation | 20 ms | 100 ms | 2k/s |
| Workflow dispatch | 50 ms | 250 ms | 200/min |
| MCP tool registration | 300 ms | 1 s | 50/min |
| Audit persistence | 40 ms | 200 ms | 500/min |

## Security & Policy Notes

- Policies must be enforced via `Ash.Policy.Authorizer`; remove legacy `authorize_if always()` blocks noted in [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:395).
- Every decision should be accompanied by Stone proof metadata and Daisy governance rationale.
- Ensure MCP tools remain under Crown stewardship; ungoverned tool registration is forbidden.
- Audit trail persistence is mandatory for compliance standards outlined in Operation Proof of Sovereignty.

## Testing Strategy

- Unit tests for policy decision helpers and governance modules.
- Integration tests for AshAI workflows, verifying correct handoffs to ThunderBolt and ThunderFlow.
- Property tests confirming reproducibility of governance decisions given identical context.
- Chaos tests simulating MCP tool failures and ensuring policy fallback logic activates.

## Development Roadmap

1. **Phase 1 — Policy Coverage**: migrate all resources to Ash policy authorizers and plug Daisy modules into evaluations.
2. **Phase 2 — Audit Enhancements**: extend governance audit schema and integrate with ThunderBlock’s checkpointing.
3. **Phase 3 — Tool Governance**: automate MCP tool attestation and revocation workflows.
4. **Phase 4 — Real-time Insight**: bolster ThunderCrown dashboards with decision timelines and anomaly detection.

## References

- [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md:56)
- [`docs/OKO_HANDBOOK.md`](docs/OKO_HANDBOOK.md:1101)
- [`docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md`](docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md:504)
- [`docs/documentation/HC_EXECUTION_PLAN.md`](docs/documentation/HC_EXECUTION_PLAN.md:47)