# TODO Audit - October 11, 2025

## Summary

| Domain | TODO Count | Primary Themes |
| --- | ---: | --- |
| Thunderbolt | 103 | Ash 3.x state machines, orchestration, ML automation |
| Thunderlink | 89 | Dashboard metrics, Ash 3.x fragments/validations |
| Thunderblock | 21 | Ash 3.x policies, Oban wiring |
| Thundergrid | 16 | Route DSL, validations, policy reinstatement |
| Thundercrown | 2 | Documentation + governance backlog |
| Thunderflow | 1 | Dependency upgrade placeholder |
| Thundergate | 1 | Integration sync |
| Thunderforge | 0 | — |

Total TODOs audited: 233.

## Category 1: Ash 3.x Migration (P0 - Blocks HC Missions)

### Thunderbolt
- [ ] Lifecycle state machine and callback escape fixes (covers TODOs lines 80-317) — [`chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:80)
- [ ] Restore AshStateMachine DSL + Oban/notification wiring — [`chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:423)
- [ ] Update AshOban schedule DSL for activation rules — [`activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:215)
- [ ] Re-enable notifications + orchestration records post-Ash 3.x upgrade — [`activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:230)
- [ ] Normalize AshOban schedule definitions for resource allocation — [`resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:224)
- [ ] Repair Ash 3.x prepare build usage in orchestration events (query + filter blocks) — [`orchestration_event.ex`](lib/thunderline/thunderbolt/resources/orchestration_event.ex:101)
- [ ] Reinstate Ash aggregates for Ising telemetry — [`ising_performance_metric.ex`](lib/thunderline/thunderbolt/resources/ising_performance_metric.ex:198)
- [ ] Re-enable calculation DSL in optimization runs — [`ising_optimization_run.ex`](lib/thunderline/thunderbolt/resources/ising_optimization_run.ex:19)

### Thunderlink
- [ ] Replace fragment-based calculations with expr() in role permissions — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:511)
- [ ] Fix federation configuration fragments (Ash 3.x) — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:526)
- [ ] Update expiry fragment + filtering logic — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:538)
- [ ] Remove inline sort from filters (Ash 3.x compliance) — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:463)
- [ ] Convert validation syntax to on: list semantics — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:579)
- [ ] Refresh AshOban trigger syntax for role jobs — [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:808)
- [ ] Restore message fragment calculations using Ash 3.x DSL — [`resources/message.ex`](lib/thunderline/thunderlink/resources/message.ex:477)
- [ ] Migrate message validations to updated syntax — [`resources/message.ex`](lib/thunderline/thunderlink/resources/message.ex:582)
- [ ] Rework federation socket fragment calls — [`resources/federation_socket.ex`](lib/thunderline/thunderlink/resources/federation_socket.ex:524)
- [ ] Update federation socket validations — [`resources/federation_socket.ex`](lib/thunderline/thunderlink/resources/federation_socket.ex:614)
- [ ] Restore community query fragments with Ash 3.x expr — [`resources/community.ex`](lib/thunderline/thunderlink/resources/community.ex:500)
- [ ] Remove deprecated prepare build from channel resource — [`resources/channel.ex`](lib/thunderline/thunderlink/resources/channel.ex:464)
- [ ] Add Ash relationship for channel participants once resource ready — [`resources/channel.ex`](lib/thunderline/thunderlink/resources/channel.ex:674)

### Thundercom
- [ ] Mirror ThunderLink fragment fixes in role permissions — [`resources/role.ex`](lib/thunderline/thundercom/resources/role.ex:511)
- [ ] Align ThunderCom role validations with Ash 3.x semantics — [`resources/role.ex`](lib/thunderline/thundercom/resources/role.ex:579)
- [ ] Refresh ThunderCom federation socket fragments — [`resources/federation_socket.ex`](lib/thunderline/thundercom/resources/federation_socket.ex:524)
- [ ] Update ThunderCom message validations — [`resources/message.ex`](lib/thunderline/thundercom/resources/message.ex:581)
- [ ] Remove Ash 1.x prepare calls from community queries — [`resources/community.ex`](lib/thunderline/thundercom/resources/community.ex:506)
- [ ] Fix channel prepare build usage — [`resources/channel.ex`](lib/thunderline/thundercom/resources/channel.ex:459)

### Thundergrid
- [ ] Convert route DSL to Ash 3.x for zone boundaries — [`resources/zone_boundary.ex`](lib/thunderline/thundergrid/resources/zone_boundary.ex:55)
- [ ] Reinstate boundary validation modules post-Ash upgrade — [`resources/zone_boundary.ex`](lib/thunderline/thundergrid/resources/zone_boundary.ex:281)
- [ ] Restore zone->agent relationships with compliant policy hooks — [`resources/zone.ex`](lib/thunderline/thundergrid/resources/zone.ex:235)
- [ ] Port spatial coordinate routes to new DSL — [`resources/spatial_coordinate.ex`](lib/thunderline/thundergrid/resources/spatial_coordinate.ex:51)
- [ ] Reinstate spatial coordinate validation module — [`resources/spatial_coordinate.ex`](lib/thunderline/thundergrid/resources/spatial_coordinate.ex:281)
- [ ] Fix grid resource validations and AshOban wiring — [`resources/grid_resource.ex`](lib/thunderline/thundergrid/resources/grid_resource.ex:415)
- [ ] Re-enable zone event aggregates with group_by syntax — [`resources/zone_event.ex`](lib/thunderline/thundergrid/resources/zone_event.ex:310)

### Thunderblock
- [ ] Restore policy enforcement after AshAuthentication migration — [`resources/vault_user.ex`](lib/thunderline/thunderblock/resources/vault_user.ex:138)
- [ ] Update vault knowledge node calculations to Ash 3.x expr — [`resources/vault_knowledge_node.ex`](lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:15)
- [ ] Convert prepare blocks + filters to Ash 3.x syntax — [`resources/vault_knowledge_node.ex`](lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:535)
- [ ] Refresh PAC home fragment logic — [`resources/pac_home.ex`](lib/thunderline/thunderblock/resources/pac_home.ex:581)
- [ ] Fix PAC home validations under new DSL — [`resources/pac_home.ex`](lib/thunderline/thunderblock/resources/pac_home.ex:639)
- [ ] Upgrade AshOban triggers for PAC home + workflow tracker — [`resources/pac_home.ex`](lib/thunderline/thunderblock/resources/pac_home.ex:888)
- [ ] Normalize TaskOrchestrator AshOban config — [`resources/task_orchestrator.ex`](lib/thunderline/thunderblock/resources/task_orchestrator.ex:275)

### Platform-Wide
- [ ] Replace deprecated UUID note once library available — [`thunderflow/event.ex`](lib/thunderline/thunderflow/event.ex:26)

## Category 2: Dashboard Metrics (P1 - User Visible)

- [ ] Implement system CPU/memory/process metrics pipeline — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:92)
- [ ] Fill uptime calculation with historical tracking — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:100)
- [ ] Deliver agent/neural inference metrics feed — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:109)
- [ ] Provide operations + cache + network telemetry — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:131)
- [ ] Wire orchestration metrics (chunks, load balancer, scaling) — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:154)
- [ ] Surface Thundergrid spatial telemetry — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:187)
- [ ] Report governance/policy dashboards — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:211)
- [ ] Add community/message/federation metrics — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:247)
- [ ] Capture observability + anomaly tracing stats — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:260)
- [ ] Compute job completion times from telemetry sources — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:306)
- [ ] Instrument event/pipeline throughput — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:476)
- [ ] Populate storage/network performance metrics — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:490)
- [ ] Measure link transport latency + stability — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:503)
- [ ] Summarize ThunderFlow + Thunderblock pipelines — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:517)
- [ ] Implement downtime history + load measurement — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:1016)

## Category 3: Integration & Automation Stubs (P2)

### Thunderbolt
- [ ] Expose chunk MCP tooling for orchestration control — [`resources/chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:50)
- [ ] Provide MCP tool for chunk activation — [`resources/chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:63)
- [ ] Implement cluster resource availability checks — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:261)
- [ ] Reserve cluster resources before allocation — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:267)
- [ ] Build optimization heuristics for allocation — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:278)
- [ ] Apply rebalancing changes to running chunks — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:284)
- [ ] Calculate scale up/down allocations — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:295)
- [ ] Emit orchestration events from allocation flow — [`resources/resource_allocation.ex`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:352)
- [ ] Store dataset metadata + load HuggingFace datasets — [`dataset_manager.ex`](lib/thunderline/thunderbolt/dataset_manager.ex:53)
- [ ] Replace simulated model training — [`hpo_executor.ex`](lib/thunderline/thunderbolt/hpo_executor.ex:54)
- [ ] Integrate Optuna ask() APIs — [`auto_ml_driver.ex`](lib/thunderline/thunderbolt/auto_ml_driver.ex:149)
- [ ] Persist trials to MLflow — [`auto_ml_driver.ex`](lib/thunderline/thunderbolt/auto_ml_driver.ex:220)
- [ ] Add chunk context enrichment + history updates — [`resources/orchestration_event.ex`](lib/thunderline/thunderbolt/resources/orchestration_event.ex:323)
- [ ] Derive event durations from tracked timestamps — [`resources/orchestration_event.ex`](lib/thunderline/thunderbolt/resources/orchestration_event.ex:348)
- [ ] Initialize ML model scaffolding for activation rules — [`resources/activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:239)
- [ ] Implement evaluation + training cycles — [`resources/activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:265)
- [ ] Record activation results & orchestration events — [`resources/activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:282)
- [ ] Validate activation model accuracy thresholds — [`resources/activation_rule.ex`](lib/thunderline/thunderbolt/resources/activation_rule.ex:308)
- [ ] Add ML-based health thresholds — [`resources/chunk_health.ex`](lib/thunderline/thunderbolt/resources/chunk_health.ex:178)
- [ ] Implement secure key management for rule sets — [`resources/lane_rule_set.ex`](lib/thunderline/thunderbolt/resources/lane_rule_set.ex:466)
- [ ] Provide 3D partitioning strategies — [`topology_partitioner.ex`](lib/thunderline/thunderbolt/topology_partitioner.ex:5)

### Thunderlink / Thundercom
- [ ] Add channel participant resources for presence — [`resources/channel.ex`](lib/thunderline/thunderlink/resources/channel.ex:44)
- [ ] Same participant linkage for ThunderCom — [`resources/channel.ex`](lib/thunderline/thundercom/resources/channel.ex:44)
- [ ] Resolve AshOban extension loading for messaging — [`resources/message.ex`](lib/thunderline/thunderlink/resources/message.ex:564)
- [ ] Mirror AshOban fix for ThunderCom messaging — [`resources/message.ex`](lib/thunderline/thundercom/resources/message.ex:563)
- [ ] Fix AshOban extension for federation sockets — [`resources/federation_socket.ex`](lib/thunderline/thunderlink/resources/federation_socket.ex:865)
- [ ] Same for ThunderCom federation sockets — [`resources/federation_socket.ex`](lib/thunderline/thundercom/resources/federation_socket.ex:865)
- [ ] Implement governance telemetry for AI dashboards — [`dashboard_metrics.ex`](lib/thunderline/thunderlink/dashboard_metrics.ex:211)

### Thundergrid
- [ ] Consider direct agent relationships for grid resources — [`resources/grid_resource.ex`](lib/thunderline/thundergrid/resources/grid_resource.ex:614)
- [ ] Ensure spatial coordinate agent linkage decisions — [`resources/spatial_coordinate.ex`](lib/thunderline/thundergrid/resources/spatial_coordinate.ex:409)

### Thunderblock
- [ ] Re-enable policies for vault resources post-governance migration — [`resources/vault_agent.ex`](lib/thunderline/thunderblock/resources/vault_agent.ex:200)
- [ ] Add performance stats action hook — [`resources/vault_query_optimization.ex`](lib/thunderline/thunderblock/resources/vault_query_optimization.ex:32)
- [ ] Implement AshOban syntax verification for workflow tracker — [`resources/workflow_tracker.ex`](lib/thunderline/thunderblock/resources/workflow_tracker.ex:78)

### Thundergate / Platform
- [ ] Synchronize Thunderlane state to PostgreSQL — [`thundergate/thunderlane.ex`](lib/thunderline/thundergate/thunderlane.ex:270)
- [ ] Implement per-domain delegation in domain processor job — [`thunderchief/jobs/domain_processor.ex`](lib/thunderline/thunderchief/jobs/domain_processor.ex:17)
- [ ] Replace temporary UUID v4 once v7 dependency ships — [`thunderflow/event.ex`](lib/thunderline/thunderflow/event.ex:26)

## Category 4: Documentation & Governance (P3)

- [ ] Document JSON schema export follow-ups — [`thundercrown/action.ex`](lib/thunderline/thundercrown/action.ex:29)
- [ ] Expand Thundercrown resource catalog once assets land — [`thundercrown/domain.ex`](lib/thunderline/thundercrown/domain.ex:72)

## High Command Mission Mapping

- HC-04 (Thunderbolt Cerebros lifecycle): Category 1 Thunderbolt items and Category 3 automation stubs (chunk lifecycle, activation rules, resource allocation).
- HC-05 (Gate + Link Email slice): Category 1 ThunderLink/ThunderCom Ash 3.x fixes unblock resource reuse for Contact/OutboundEmail scaffolding.
- HC-06 (ThunderLink policies & presence): Category 1 ThunderLink/ThunderCom fragments/validations plus Category 2 metrics to surface presence signals.
- HC-08 (Platform GitHub Actions + audits): Category 1 Ash 3.x fixes reduce lint failures; Category 2 metrics + Category 3 automation feed CI telemetry.
- HC-09 (Error classifier + DLQ): Category 2 event/pipeline metrics and Category 3 domain processor delegation provide observability inputs.
- HC-10 (Feature flag documentation): Category 2 governance metrics and Category 4 documentation tasks supply the needed registry context.

## GitHub Issue Recommendations (Category 1)

1. Thunderbolt Ash 3.x Lifecycle Fixes — scope [`chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:80) and [`chunk.ex`](lib/thunderline/thunderbolt/resources/chunk.ex:423); owner: Bolt Steward.
2. ThunderLink Ash 3.x Fragment Remediation — scope [`resources/role.ex`](lib/thunderline/thunderlink/resources/role.ex:511), [`resources/message.ex`](lib/thunderline/thunderlink/resources/message.ex:477), [`resources/federation_socket.ex`](lib/thunderline/thunderlink/resources/federation_socket.ex:524); owner: Link Steward.
3. ThunderCom Ash 3.x Fragment Parity — scope [`resources/role.ex`](lib/thunderline/thundercom/resources/role.ex:511) and peers; owner: Flow Steward (shared).
4. Thundergrid Route & Validation Migration — scope [`resources/zone_boundary.ex`](lib/thunderline/thundergrid/resources/zone_boundary.ex:55), [`resources/spatial_coordinate.ex`](lib/thunderline/thundergrid/resources/spatial_coordinate.ex:51); owner: Grid Steward.
5. Thunderblock Policy & Oban Update — scope [`resources/vault_knowledge_node.ex`](lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:15), [`resources/pac_home.ex`](lib/thunderline/thunderblock/resources/pac_home.ex:581); owner: Block Steward.

Category 1 issues should be opened immediately with HC task IDs and steward assignment; Categories 2-4 feed subsequent sprints after M1 gating items clear.