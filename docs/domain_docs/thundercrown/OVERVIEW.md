# ThunderCrown Domain Overview

**Vertex Position**: Control Plane Ring — Governance Layer  
**Namespace**: `Thunderline.Thundercrown.*`  
**Last Verified**: 2025-12-04

## Purpose

ThunderCrown is the AI governance and orchestration authority. It decides which operations run, ensures policy compliance, and coordinates multi-agent workflows through AshAI and Hermes MCP integration.

## Charter

ThunderCrown is the policy brain of Thunderline. It encodes Stone.Proof checks, Daisy governance logic, and AshAI workflows to authorize every significant action in the platform. The domain issues commands to ThunderBolt, mediates tool access, and maintains auditable reasoning for each decision.

## Directory Structure (Grounded)

\`\`\`
lib/thunderline/thundercrown/
├── domain.ex                    # Ash Domain with AshAI tools
├── supervisor.ex                # OTP Supervisor
├── action.ex                    # Crown action definitions
├── constraint.ex                # Governance constraints
├── curriculum_policy.ex         # Curriculum/training policies
├── curriculum_rewards.ex        # Reward shaping for curriculum
├── daisy.ex                     # Daisy governance module (stub)
├── orchestrator.ex              # High-level orchestration
├── policy.ex                    # Policy definitions
├── policy_engine.ex             # Policy evaluation engine
├── proof.ex                     # Proof generation/verification
├── signing_service.ex           # Cryptographic signing
├── stone.ex                     # Stone proof primitives
├── introspection/
│   └── supervision_tree_mapper.ex  # Process tree introspection
├── jido/
│   ├── action_registry.ex       # MCP/Jido action catalog
│   └── actions/
│       ├── default_conversation.ex
│       ├── list_available_zones.ex
│       └── register_core_agent.ex
├── jobs/
│   ├── cross_domain_processor.ex      # Oban: cross-domain routing
│   └── scheduled_workflow_processor.ex # Oban: scheduled workflows
├── llm/
│   └── fixed_llm.ex             # Fixed LLM configuration
├── mcp_theta/                   # MCP Theta integration (TBD)
├── policies/
│   └── upm_policy.ex            # UPM-specific policies
└── resources/
    ├── agent_runner.ex          # ✅ Ash Resource - agent execution
    ├── ai_policy.ex             # ⚠️ Empty stub
    ├── conversation_agent.ex    # ✅ Ash Resource - conversation handling
    ├── conversation_tools.ex    # ✅ Ash Resource - conversation utilities
    ├── mcp_bus.ex               # ⚠️ Empty stub
    ├── orchestration_ui.ex      # ✅ Ash Resource - UI/dashboard
    ├── policy_definition.ex     # ✅ Ash Resource - policy storage
    ├── policy_evaluation.ex     # ✅ Ash Resource - policy eval results
    └── workflow_orchestrator.ex # ⚠️ Empty stub
\`\`\`

## Ash Domain Registration

**Domain**: \`Thunderline.Thundercrown.Domain\`  
**Extensions**: \`AshAdmin.Domain\`, \`AshAi\`

### Registered Resources (Active)
- \`Thunderline.Thundercrown.Resources.OrchestrationUI\`
- \`Thunderline.Thundercrown.Resources.AgentRunner\`
- \`Thunderline.Thundercrown.Resources.ConversationTools\`
- \`Thunderline.Thundercrown.Resources.ConversationAgent\`
- \`Thunderline.Thundercrown.Resources.PolicyDefinition\`
- \`Thunderline.Thundercrown.Resources.PolicyEvaluation\`

### AshAI Tools Exposed
\`\`\`elixir
tools do
  tool :run_agent, AgentRunner, :run
  tool :conversation_context, ConversationTools, :context_snapshot
  tool :conversation_run_digest, ConversationTools, :run_digest
  tool :conversation_reply, ConversationAgent, :respond
  tool :onnx_infer, Thunderbolt.Resources.OnnxInference, :infer  # Cross-domain
end
\`\`\`

### Stub Resources (Not Implemented)
- \`ai_policy.ex\` - Empty file
- \`mcp_bus.ex\` - Empty file
- \`workflow_orchestrator.ex\` - Empty file

## Core Modules

### Policy & Governance
| Module | Status | Purpose |
|--------|--------|---------|
| \`Policy\` | Active | Policy definitions and rules |
| \`PolicyEngine\` | Active | Policy evaluation logic |
| \`Constraint\` | Active | Governance constraints |
| \`Proof\` | Active | Proof generation/verification |
| \`Stone\` | Active | Stone proof primitives (\`stone/1\`) |
| \`Daisy\` | Stub | Daisy governance (pending integration) |
| \`SigningService\` | Active | Cryptographic signing |

### Orchestration
| Module | Status | Purpose |
|--------|--------|---------|
| \`Orchestrator\` | Active | High-level workflow orchestration |
| \`Action\` | Active | Crown action definitions |
| \`CurriculumPolicy\` | Active | Training curriculum policies |
| \`CurriculumRewards\` | Active | Reward shaping |

### Jido/MCP Integration
| Module | Status | Purpose |
|--------|--------|---------|
| \`Jido.ActionRegistry\` | Active | MCP/Jido action catalog |
| \`Jido.Actions.DefaultConversation\` | Active | Default conversation action |
| \`Jido.Actions.ListAvailableZones\` | Active | Zone listing action |
| \`Jido.Actions.RegisterCoreAgent\` | Active | Agent registration |

### Background Jobs (Oban)
| Worker | Queue | Purpose |
|--------|-------|---------|
| \`CrossDomainProcessor\` | \`:cross_domain\` | Routes governance outcomes |
| \`ScheduledWorkflowProcessor\` | \`:scheduled\` | Runs scheduled workflows |

## Integration Points

### Downstream (Crown → X)
- **→ ThunderBolt**: Publishes \`ai.intent.*\` events authorizing compute/model ops
- **→ ThunderFlow**: Governance decisions enter Broadway pipelines
- **→ ThunderBlock**: Writes signed governance records

### Upstream (X → Crown)
- **ThunderGate →**: Capability claims evaluated against Crown policies
- **ThunderLink →**: Operator commands requiring governance approval

### Cross-Domain Tools
- Crown exposes \`onnx_infer\` tool from ThunderBolt for ML inference

## Telemetry Events

\`\`\`elixir
[:thunderline, :thundercrown, :policy, :evaluated]      # Policy decision completed
[:thunderline, :thundercrown, :workflow, :start]        # Workflow lifecycle
[:thunderline, :thundercrown, :workflow, :stop]
[:thunderline, :thundercrown, :mcp, :tool_registered]   # MCP tool onboarding
[:thunderline, :thundercrown, :decision, :denied]       # Rejected operation
[:thunderline, :thundercrown, :audit, :recorded]        # Audit log persisted
\`\`\`

## Known Issues & TODOs

1. **Empty Stub Files**: \`ai_policy.ex\`, \`mcp_bus.ex\`, \`workflow_orchestrator.ex\` need implementation or removal
2. **Daisy Integration**: \`daisy.ex\` is a stub pending full integration
3. **Policy Coverage**: Need to migrate all resources to Ash policy authorizers
4. **MCP Theta**: \`mcp_theta/\` directory exists but integration status unclear

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Policy evaluation | 20 ms | 100 ms | 2k/s |
| Workflow dispatch | 50 ms | 250 ms | 200/min |
| MCP tool registration | 300 ms | 1 s | 50/min |
| Audit persistence | 40 ms | 200 ms | 500/min |

## Security & Policy Notes

- Policies must be enforced via \`Ash.Policy.Authorizer\`; remove legacy \`authorize_if always()\` blocks.
- Every decision should be accompanied by Stone proof metadata and Daisy governance rationale.
- Ensure MCP tools remain under Crown stewardship; ungoverned tool registration is forbidden.
- Audit trail persistence is mandatory for compliance standards.

## Development Priorities

1. **Phase 1**: Fill in empty stub resources or remove them
2. **Phase 2**: Complete Daisy governance integration
3. **Phase 3**: MCP Theta integration
4. **Phase 4**: Policy coverage audit and reinforcement

## References

- Domain definition: [domain.ex](../../../lib/thunderline/thundercrown/domain.ex)
- Supervisor: [supervisor.ex](../../../lib/thunderline/thundercrown/supervisor.ex)
