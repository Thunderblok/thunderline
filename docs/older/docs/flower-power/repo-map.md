# Thunderline Repository Map (Domains • MCP • Docs) — Sep 22, 2025

Scope
- High-level inventory of domains, notable resources, MCP integration surface, and documentation state.
- Confirms “everything under domains” alignment and Thundercrown ownership of MCP tooling.

Domains (lib/thunderline)
- thundercrown (Governance/AI Orchestration)
  - Domain: lib/thunderline/thundercrown/domain.ex
    - use Ash.Domain, extensions: [AshAi]
    - tools do … tool :run_agent, Thunderline.Thundercrown.Resources.AgentRunner, :run
  - Resources (selected):
    - resources/agent_runner.ex
    - resources/orchestration_ui.ex
    - resources/ai_policy.ex (present)
    - resources/mcp_bus.ex (present, content currently empty/placeholder)
  - Introspection:
    - introspection/supervision_tree_mapper.ex (+ test)
  - Jobs:
    - jobs/cross_domain_processor.ex
    - jobs/scheduled_workflow_processor.ex

- thunderflow (Events/Pipelines/Telemetry)
  - Domain: lib/thunderline/thunderflow/domain.ex
  - Resources:
    - resources/* (event stream, probe runs, lineage, features)
  - EventBus, Heartbeat, Observability, Broadway integrations live across domain root (event_bus.ex, heartbeat.ex, etc.)

- thunderbolt (Execution/ML/CA)
  - Domain: lib/thunderline/thunderbolt/domain.ex
  - Resources: extensive ML/automata/lanes artifacts (model_run, training datasets, lane configs, etc.)
  - thundercell/ & ML components

- thunderblock (Persistence/Infra)
  - Domain: lib/thunderline/thunderblock/domain.ex
  - Resources: vault_*, dag_*, workflow_*, cluster_node, etc. (DB/infra ownership)

- thundergate (Auth/External Integration)
  - Domain: lib/thunderline/thundergate/domain.ex
  - Resources: user, token, realm_identity, audit_log, etc.

- thunderlink (Comms/Realtime)
  - Domain: lib/thunderline/thunderlink/domain.ex (extensions: AshOban.Domain, AshGraphql.Domain, AshTypescript.Rpc)
  - Resources: community/channel/message, voice (room/device/participant)

- thundergrid (Spatial/Grid/GraphQL Surface)
  - Domain: lib/thunderline/thundergrid/domain.ex (validate_config_inclusion?: false)
  - Resources: zone/grid resources, coordinates/boundaries

MCP Integration (ownership under Thundercrown)
- Router: lib/thunderline_web/router.ex
  - pipeline :mcp includes AshAuthentication.Strategy.ApiKey.Plug (required?: false currently)
  - scope "/mcp" forward "/", AshAi.Mcp.Router,
    tools: [:run_agent], protocol_version_statement: System.get_env("MCP_PROTOCOL_VERSION", "2024-11-05"), otp_app: :thunderline
- Domain: Thundercrown
  - tools do includes :run_agent via AgentRunner resource
- Note:
  - resources/mcp_bus.ex file exists but is empty in this snapshot. Either implement (as a façade for tool/event orchestration) or remove to avoid confusion.
- Actor identity:
  - Ensure API-key issuance and tightening required?: true in production for :mcp pipeline.

Documentation state
- Flower Power docs relocated under Thunderline/documentation/docs/flower-power/
  - README, architecture, prereqs, configuration, contracts (+ sample spec), deploy-dev, deploy-k8s
  - observability (metric/trace catalog) + dashboards/flower-power.json
  - security (mTLS/JWS/RLS/DP)
  - runbooks: start_federation, enroll_clients, artifacts_and_promotion, dashboards
  - integrating-ash-ash_ai-jido.md (new guide linking Ash+ash_ai+Jido to domain code paths)
- Older Thunderline/docs/flower-power/ is not present (avoids drift).

Findings and alignment with doctrine
- “Everything under domains”:
  - MCP tool ownership confirmed under Thundercrown. Router-scope entrypoint is unified and auth-aware.
  - Eventing (Thunderflow), persistence (Thunderblock), execution (Thunderbolt) boundaries match OKO Handbook doctrine.
- OKO Handbook read-through confirms guardrails (Event Validator, single heartbeat, RepoOnly check, Link policy purge) and governance/SLO posture; the repo’s code surfaces align with that narrative.

Recommendations / Next deltas
- MCP production hardening:
  - Flip :mcp pipeline API key required?: true for production; document issuance path.
  - Implement or remove empty resources/mcp_bus.ex to reduce ambiguity.
- Incident Response and Roadmap docs (pending):
  - Author incident_response.md (client churn, round stall, artifact integrity, Postgres/MinIO/OTLP outages).
  - Author roadmap.md (hardened Flower image, strategy extensions, pgvector selector, watts/token probes, GPU node pools).
- Optional chart enhancements:
  - ServiceMonitor/PodMonitor templates (if Prom Operator present)
  - HPA/PDB examples
  - Existing Secret binding support (when using External Secrets or SealedSecrets)
  - GPU nodeProfiles example (nodeSelector + tolerations)

References
- Thundercrown domain: lib/thunderline/thundercrown/domain.ex
- MCP router: lib/thunderline_web/router.ex (scope "/mcp")
- Handbook: Thunderline/OKO_HANDBOOK.md
- Domain catalogs/playbook: Docs/THUNDERLINE_DOMAIN_CATALOG.md, Docs/THUNDERLINE_MASTER_PLAYBOOK.md
- Flower Power docs: Thunderline/documentation/docs/flower-power/*
