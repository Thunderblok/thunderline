# High Command Readiness — Domain Cleanup Report

Generated: Tue Sep 23 02:05:15 AM UTC 2025

## Repo misuse outside Thunderblock (Repo.* outside thunderblock)
Thunderline/lib/mix/tasks/thunder.diag.ex:12:    case Thunderline.Repo.query("SELECT now()") do
Thunderline/lib/thunderline/dev/credo_checks/domain_guardrails.ex:36:    if String.contains?(text, "Repo.") and not allow? do
Thunderline/lib/thunderline/migration_runner.ex:88:        case Thunderline.Repo.start_link() do
Thunderline/lib/thunderline_web/controllers/health_controller.ex:57:      case Thunderline.Repo.query("SELECT 1", []) do

## Policy usage in Thunderlink (should be in Crown)
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:188:      # TODO: Implement policy monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:486:      # TODO: Implement policy monitoring
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:98:  #   policy always() do
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:217:        # Presence policy check (deny-by-default enforcement)
Thunderline/lib/thunderline/thunderlink/resources/community.ex:24:  - Sovereign policy enforcement and resource management
Thunderline/lib/thunderline/thunderlink/resources/community.ex:102:  #   policy always() do
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:94:  #   policy always() do
Thunderline/lib/thunderline/thunderlink/resources/message.ex:90:  #   policy always() do
Thunderline/lib/thunderline/thunderlink/resources/role.ex:104:  #   policy always() do
Thunderline/lib/thunderline/thunderlink/resources/ticket.ex:69:  # Link domain policy purged (WARHORSE) – background job bypass removed (handled centrally)
Thunderline/lib/thunderline/thunderlink/transport/store.ex:3:  Store-and-forward retention policy behaviour under Thunderlink.
Thunderline/lib/thunderline/thunderlink/voice/device.ex:51:  # Link domain policy purged (WARHORSE)
Thunderline/lib/thunderline/thunderlink/voice/participant.ex:67:  # Link domain policy purged (WARHORSE)
Thunderline/lib/thunderline/thunderlink/voice/room.ex:66:  # Link domain policy purged (WARHORSE) – governance moves to Crown

## Declared domain lines (manual cross-check with path)
Thunderline/lib/thunderline/thunderblock/resources/cluster_node.ex:8:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/community.ex:14:  domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/dag_edge.ex:6:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/dag_node.ex:6:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/dag_snapshot.ex:7:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/dag_workflow.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/distributed_state.ex:8:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/execution_container.ex:13:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/load_balancing_rule.ex:7:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/rate_limit_policy.ex:8:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/supervision_tree.ex:19:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/system_event.ex:8:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/task_orchestrator.ex:12:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_action.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_agent.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_cache_entry.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_decision.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_embedding_vector.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_experience.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:40:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_memory_node.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_memory_record.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_query_optimization.ex:10:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_user.ex:9:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/vault_user_token.ex:9:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/workflow_tracker.ex:11:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/zone_container.ex:18:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:27:    domain: Thunderline.Thunderblock.Domain,
Thunderline/lib/thunderline/thunderbolt/export/training_slice.ex:9:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/consent_record.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/feature_view.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/model_artifact.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/model_spec.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/model_version.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/training_dataset.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/ml/training_run.ex:3:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/moe/decision_trace.ex:9:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/moe/expert.ex:9:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:11:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/automata_run.ex:4:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:11:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/chunk_health.ex:11:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/core_agent.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/core_system_policy.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/core_task_node.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/core_timing_event.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/core_workflow_dag.ex:8:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/ising_optimization_problem.ex:10:    domain: Thunderline.Thunderbolt.Domain
Thunderline/lib/thunderline/thunderbolt/resources/ising_optimization_run.ex:10:    domain: Thunderline.Thunderbolt.Domain
Thunderline/lib/thunderline/thunderbolt/resources/ising_performance_metric.ex:10:    domain: Thunderline.Thunderbolt.Domain
Thunderline/lib/thunderline/thunderbolt/resources/lane_cell_topology.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_consensus_run.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_cross_lane_coupling.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_lane_configuration.ex:25:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_lane_coordinator.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_lane_metrics.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_performance_metric.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_rule_oracle.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_rule_set.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/lane_telemetry_snapshot.ex:10:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/mag_macro_command.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/mag_task_assignment.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/mag_task_execution.ex:7:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/model_run.ex:9:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:11:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:11:    domain: Thunderline.Thunderbolt.Domain,
Thunderline/lib/thunderline/thundercom/resources/channel.ex:25:  domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/community.ex:28:  domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/community.ex:735:  |> Ash.update(domain: Thunderline.Thundercom.Domain)
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:27:  domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/message.ex:26:    domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:27:  domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/role.ex:25:  domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/voice_device.ex:10:    domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/voice_participant.ex:10:    domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/voice_room.ex:20:    domain: Thunderline.Thundercom.Domain,
Thunderline/lib/thunderline/thundercom/resources/voice_room.ex:130:      |> Ash.read_one(domain: Thunderline.Thundercom.Domain) do
Thunderline/lib/thunderline/thundercom/resources/voice_room.ex:132:        _ = Ash.destroy(participant, action: :leave, domain: Thunderline.Thundercom.Domain)
Thunderline/lib/thunderline/thundercrown/resources/agent_runner.ex:4:    domain: Thunderline.Thundercrown.Domain,
Thunderline/lib/thunderline/thundercrown/resources/orchestration_ui.ex:11:    domain: Thunderline.Thundercrown.Domain
Thunderline/lib/thunderline/thunderflow/events/event.ex:10:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/features/feature_window.ex:11:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/lineage/edge.ex:9:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/consciousness_flow.ex:10:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/event_ops.ex:11:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/event_stream.ex:10:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/probe_attractor_summary.ex:10:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/probe_lap.ex:4:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/probe_run.ex:9:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thunderflow/resources/system_action.ex:11:    domain: Thunderline.Thunderflow.Domain,
Thunderline/lib/thunderline/thundergate/resources/alert_rule.ex:11:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/audit_log.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/data_adapter.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/decision_framework.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/error_log.ex:11:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/external_service.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/federated_message.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/federated_realm.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/health_check.ex:11:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/performance_trace.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/policy_rule.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/realm_identity.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/system_action.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/system_metric.ex:10:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/thunderbit_monitor.ex:11:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/thunderbolt_monitor.ex:11:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/token.ex:4:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergate/resources/user.ex:4:    domain: Thunderline.Thundergate.Domain,
Thunderline/lib/thunderline/thundergrid/resources/chunk_state.ex:10:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/grid_resource.ex:11:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/grid_zone.ex:11:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/spatial_coordinate.ex:11:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/zone.ex:10:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/zone_boundary.ex:11:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thundergrid/resources/zone_event.ex:10:    domain: Thunderline.Thundergrid.Domain,
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:25:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/resources/community.ex:28:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:27:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/resources/message.ex:26:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/resources/role.ex:25:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/resources/ticket.ex:10:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/voice/device.ex:6:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/voice/participant.ex:6:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/voice/room.ex:8:    domain: Thunderline.Thunderlink.Domain,
Thunderline/lib/thunderline/thunderlink/voice/room.ex:91:         |> Ash.read_one(domain: Thunderline.Thunderlink.Domain) do
Thunderline/lib/thunderline/thunderlink/voice/room.ex:93:        _ = Ash.destroy(participant, action: :leave, domain: Thunderline.Thunderlink.Domain)

## TODO/FIXME/DEPRECATED markers
Thunderline/lib/mix/tasks/thunderline.flags.audit.ex:15:    IO.puts("TODO: scan Feature.enabled?/1 usage and compare to configured flags")
Thunderline/lib/thunderline/action.ex:29:  TODO (follow-up PRs):
Thunderline/lib/thunderline/thunderblock/resources/task_orchestrator.ex:275:  # TODO: Fix AshOban syntax - commenting out until properly tested
Thunderline/lib/thunderline/thunderblock/resources/vault_action.ex:259:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/vault_agent.ex:200:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/vault_decision.ex:277:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:15:  - Hierar    # TODO: Fix fragment expression referencing relationship_data in Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:120:    # TODO: Comment out interface for commented-out actions
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:535:        # TODO: Fix filter for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:557:    # TODO: Fix variable references in prepare block for Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:585:        # TODO: Fix filter for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:593:    # TODO: Fix fragment expression referencing relationship_data in Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/vault_knowledge_node.ex:614:      # TODO: Fix filter expression for Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/vault_memory_node.ex:366:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/vault_query_optimization.ex:32:    # TODO: Add performance_stats action before uncommenting
Thunderline/lib/thunderline/thunderblock/resources/vault_user.ex:138:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/vault_user_token.ex:129:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderblock/resources/workflow_tracker.ex:78:  # TODO: Fix AshOban syntax - commenting out until properly tested
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:581:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:595:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:639:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:641:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thunderblock/resources/pac_home.ex:888:  # TODO: AshOban syntax needs verification - commenting out until properly tested
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:215:  #     # TODO: Fix schedule syntax for AshOban 3.x
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:230:  # TODO: Configure notifications when proper extension is available
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:239:    # TODO: Initialize ML model based on configuration
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:265:    # TODO: Implement sophisticated evaluation logic
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:282:    # TODO: Record evaluation results for performance tracking
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:293:    # TODO: Create orchestration event record
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:298:    # TODO: Implement ML training cycle using provided training data
Thunderline/lib/thunderline/thunderbolt/resources/activation_rule.ex:308:    # TODO: Validate model accuracy against test data
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:50:  # TODO: MCP Tool exposure for external orchestration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:63:  # TODO: MCP Tool for chunk activation
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:80:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:82:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:84:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:86:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:94:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:96:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:98:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:100:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:109:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:111:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:113:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:121:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:123:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:125:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:127:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:135:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:137:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:139:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:149:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:151:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:153:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:155:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:163:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:171:      # TODO: Fix DateTime.utc_now function reference
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:173:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:175:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:184:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:186:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:188:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:190:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:198:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:200:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:202:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:211:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:213:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:215:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:217:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:225:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:233:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:235:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:244:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:246:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:248:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:250:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:258:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:260:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:262:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:264:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:273:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:275:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:277:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:285:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:287:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:289:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:298:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:300:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:302:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:304:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:312:      # TODO: Fix state machine integration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:314:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:316:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:323:      # TODO: Fix function reference escaping
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:423:  # TODO: Fix AshStateMachine DSL syntax
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:488:  # TODO: Fix Oban trigger configuration
Thunderline/lib/thunderline/thunderbolt/resources/chunk.ex:499:  # TODO: Fix notifications configuration
Thunderline/lib/thunderline/thunderbolt/resources/chunk_health.ex:178:    # TODO: Implement ML-based health threshold evaluation
Thunderline/lib/thunderline/thunderbolt/resources/ising_optimization_run.ex:19:      # TODO: Re-enable when calculation syntax is clarified
Thunderline/lib/thunderline/thunderbolt/resources/ising_optimization_run.ex:217:    # TODO: Add aggregates after confirming proper syntax
Thunderline/lib/thunderline/thunderbolt/resources/ising_performance_metric.ex:198:    # TODO: Add aggregates after confirming proper syntax
Thunderline/lib/thunderline/thunderbolt/resources/ising_performance_metric.ex:203:    # TODO: Add aggregates after confirming proper syntax
Thunderline/lib/thunderline/thunderbolt/resources/lane_cell_topology.ex:497:    # TODO: Implement actual node connectivity validation
Thunderline/lib/thunderline/thunderbolt/resources/lane_rule_set.ex:435:    # TODO: Implement secure key management
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:101:      # TODO: Fix prepare build syntax for Ash 3.x
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:121:      # TODO: Fix prepare build syntax for Ash 3.x
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:277:  # TODO: Configure pub_sub when proper extension is available
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:323:    # TODO: Add chunk-specific context data
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:329:    # TODO: Update chunk's event history statistics
Thunderline/lib/thunderline/thunderbolt/resources/orchestration_event.ex:348:      # TODO: Calculate actual duration if we tracked start time
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:224:  #     # TODO: Fix schedule syntax for AshOban 3.x
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:251:  # TODO: Configure notifications when proper extension is available
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:261:    # TODO: Check cluster-wide resource availability
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:267:    # TODO: Reserve resources at cluster level to prevent over-allocation
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:278:    # TODO: Implement sophisticated resource optimization algorithms
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:284:    # TODO: Apply calculated resource changes to the chunk
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:295:    # TODO: Calculate new resource allocations for scaling up
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:312:    # TODO: Calculate new resource allocations for scaling down
Thunderline/lib/thunderline/thunderbolt/resources/resource_allocation.ex:352:    # TODO: Create orchestration event record
Thunderline/lib/thunderline/thunderbolt/topology_partitioner.ex:5:  TODO: Implement real 3D partitioning (grid/hilbert/load-balanced strategies).
Thunderline/lib/thunderline/thunderchief/jobs/domain_processor.ex:17:    # TODO: Implement per-domain delegation
Thunderline/lib/thunderline/thundercom/resources/channel.ex:214:    # TODO: Add ChannelParticipant resource and relationship
Thunderline/lib/thunderline/thundercom/resources/channel.ex:520:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thundercom/resources/channel.ex:565:      # TODO: Add ChannelParticipant reference when resource exists
Thunderline/lib/thunderline/thundercom/resources/community.ex:574:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thundercom/resources/community.ex:589:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:607:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:622:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:637:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:652:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:774:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thundercom/resources/federation_socket.ex:821:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/message.ex:566:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/message.ex:587:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/message.ex:732:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thundercom/resources/message.ex:750:    # TODO: Fix validation syntax - :edit is not valid in Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/message.ex:752:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:673:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:687:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:820:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:863:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/pac_home.ex:865:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/role.ex:529:      # sort [position: :desc, role_name: :asc]  # TODO: Remove sort from filter - not supported in Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/role.ex:577:      # TODO: Fix fragment expression for permissions checking
Thunderline/lib/thunderline/thundercom/resources/role.ex:592:      # TODO: Fix fragment expression for federation_config checking
Thunderline/lib/thunderline/thundercom/resources/role.ex:604:      # TODO: Fix fragment expression for expiry_config checking
Thunderline/lib/thunderline/thundercom/resources/role.ex:615:      # TODO: Fix fragment expression for expiry filtering
Thunderline/lib/thunderline/thundercom/resources/role.ex:737:  # TODO: Fix trigger syntax for AshOban 3.x
Thunderline/lib/thunderline/thundercom/resources/role.ex:746:  # TODO: Fix remaining trigger syntax for AshOban 3.x
Thunderline/lib/thunderline/thundercom/resources/role.ex:767:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundercom/resources/voice_device.ex:3:  DEPRECATED – Use `Thunderline.Thunderlink.Voice.Device`.
Thunderline/lib/thunderline/thundercom/resources/voice_participant.ex:3:  DEPRECATED – Use `Thunderline.Thunderlink.Voice.Participant`.
Thunderline/lib/thunderline/thundercom/resources/voice_room.ex:3:  DEPRECATED – Use `Thunderline.Thunderlink.Voice.Room`.
Thunderline/lib/thunderline/thundercrown/domain.ex:53:    # TODO: Add other resources when implemented:
Thunderline/lib/thunderline/thundercrown/resources/agent_runner.ex:21:        # TODO: Gate with ThunderGate policy and actual AshAI/Jido invocation
Thunderline/lib/thunderline/thunderflow/event.ex:26:  NOTE: UUID v7 not yet supplied by dependencies; v4 used as interim (TODO: replace when lib available).
Thunderline/lib/thunderline/thundergate/thunderlane.ex:270:    # TODO: Implement Mnesia → PostgreSQL synchronization
Thunderline/lib/thunderline/thundergrid/resources/grid_resource.ex:415:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thundergrid/resources/grid_resource.ex:614:    # TODO: Consider if direct Agent relationship is needed instead
Thunderline/lib/thunderline/thundergrid/resources/grid_resource.ex:617:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thundergrid/resources/grid_zone.ex:337:    # TODO: Consider if direct GridZone->Agent relationship is needed
Thunderline/lib/thunderline/thundergrid/resources/spatial_coordinate.ex:51:      # TODO: Convert to Ash 3.x route syntax after MCP consolidation complete
Thunderline/lib/thunderline/thundergrid/resources/spatial_coordinate.ex:57:      # TODO: Convert to Ash 3.x route syntax - currently causing compilation issues
Thunderline/lib/thunderline/thundergrid/resources/spatial_coordinate.ex:281:    # TODO: Implement Thundergrid.Validations module
Thunderline/lib/thunderline/thundergrid/resources/spatial_coordinate.ex:409:    # TODO: Consider if direct Agent relationship is needed instead
Thunderline/lib/thunderline/thundergrid/resources/zone.ex:225:    # TODO: Add zone_id field to CoreAgent before enabling this relationship
Thunderline/lib/thunderline/thundergrid/resources/zone.ex:237:  # TODO: Re-enable aggregates when agent relationships are properly established
Thunderline/lib/thunderline/thundergrid/resources/zone.ex:259:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thundergrid/resources/zone_boundary.ex:55:      # TODO: Convert to Ash 3.x route syntax after MCP consolidation complete
Thunderline/lib/thunderline/thundergrid/resources/zone_boundary.ex:63:      # TODO: Convert to Ash 3.x route syntax - currently causing compilation issues
Thunderline/lib/thunderline/thundergrid/resources/zone_boundary.ex:281:    # TODO: Implement Thundergrid.Validations module
Thunderline/lib/thunderline/thundergrid/resources/zone_event.ex:310:    # TODO: Fix group_by syntax for events_by_type aggregate
Thunderline/lib/thunderline/thundergrid/resources/zone_event.ex:322:  # TODO: Re-enable policies once AshAuthentication is properly configured
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:67:      # TODO: Implement CPU monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:69:      # TODO: Implement memory monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:71:      # TODO: Implement process counting
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:75:      # TODO: Implement real uptime percentage tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:84:      # TODO: Implement agent counting
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:86:      # TODO: Implement active agent tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:88:      # TODO: Implement NN status
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:90:      # TODO: Implement inference tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:92:      # TODO: Implement accuracy monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:94:      # TODO: Implement memory tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:106:      # TODO: Implement real ops/sec tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:109:      # TODO: Implement cache metrics
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:112:      # TODO: Implement CPU monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:114:      # TODO: Implement network monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:116:      # TODO: Implement connection tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:118:      # TODO: Implement transfer rate monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:120:      # TODO: Implement error rate calculation
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:129:      # TODO: Implement chunk processing tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:131:      # TODO: Implement scaling tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:133:      # TODO: Implement efficiency tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:135:      # TODO: Implement load balancer monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:162:      # TODO: Implement query monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:164:      # TODO: Implement boundary tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:166:      # TODO: Implement efficiency calculation
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:168:      # TODO: Implement grid node counting
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:170:      # TODO: Implement active node tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:172:      # TODO: Implement load monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:174:      # TODO: Implement performance operations tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:176:      # TODO: Implement data stream rate monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:178:      # TODO: Implement storage rate monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:186:      # TODO: Implement decision tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:188:      # TODO: Implement policy monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:190:      # TODO: Implement access tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:192:      # TODO: Implement security scoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:198:  @doc "(DEPRECATED) Get ThunderVault metrics – use thunderblock_vault_metrics/0"
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:200:    Logger.warning("DEPRECATED call to thundervault_metrics/0 – use thunderblock_vault_metrics/0")
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:221:      # TODO: Implement community tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:223:      # TODO: Implement message monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:225:      # TODO: Implement federation tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:234:      # TODO: Implement trace collection
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:236:      # TODO: Implement perf monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:238:      # TODO: Implement anomaly detection
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:240:      # TODO: Implement coverage tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:279:          # TODO: calculate real average completion time
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:443:      # TODO: Implement event processing tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:445:      # TODO: Implement pipeline monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:447:      # TODO: Implement flow rate calculation
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:449:      # TODO: Implement consciousness metrics
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:457:      # TODO: Implement storage operation tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:459:      # TODO: Implement integrity monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:461:      # TODO: Implement compression tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:470:      # TODO: Implement connection tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:472:      # TODO: Implement throughput monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:474:      # TODO: Implement latency measurement
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:476:      # TODO: Implement stability scoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:484:      # TODO: Implement governance tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:486:      # TODO: Implement policy monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:488:      # TODO: Implement compliance scoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:935:      # TODO: Implement real ops/sec tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:938:      # TODO: Implement cache metrics
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:941:      # TODO: Implement CPU monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:943:      # TODO: Implement network monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:945:      # TODO: Implement connection tracking
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:947:      # TODO: Implement transfer rate monitoring
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:949:      # TODO: Implement error rate calculation
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:956:    # TODO: Implement real uptime tracking with downtime history
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:1032:      # TODO: Implement real load measurement
Thunderline/lib/thunderline/thunderlink/dashboard_metrics.ex:1048:    # TODO: Implement telemetry integration
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:44:      # TODO: Add ChannelParticipant reference when resource exists
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:463:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thunderlink/resources/channel.ex:673:    # TODO: Add ChannelParticipant resource and relationship
Thunderline/lib/thunderline/thunderlink/resources/community.ex:500:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thunderlink/resources/community.ex:515:      # TODO: Fix fragment expression for Ash 3.x - commented out variable references
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:524:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:539:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:554:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:569:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:614:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thunderlink/resources/federation_socket.ex:865:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thunderlink/resources/message.ex:477:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/message.ex:498:      # TODO: Fix fragment expression variable reference issues
Thunderline/lib/thunderline/thunderlink/resources/message.ex:564:  # TODO: Fix AshOban extension loading issue
Thunderline/lib/thunderline/thunderlink/resources/message.ex:582:    # TODO: Fix validation syntax - :edit is not valid in Ash 3.x
Thunderline/lib/thunderline/thunderlink/resources/message.ex:584:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thunderlink/resources/role.ex:463:      # sort [position: :desc, role_name: :asc]  # TODO: Remove sort from filter - not supported in Ash 3.x
Thunderline/lib/thunderline/thunderlink/resources/role.ex:511:      # TODO: Fix fragment expression for permissions checking
Thunderline/lib/thunderline/thunderlink/resources/role.ex:526:      # TODO: Fix fragment expression for federation_config checking
Thunderline/lib/thunderline/thunderlink/resources/role.ex:538:      # TODO: Fix fragment expression for expiry_config checking
Thunderline/lib/thunderline/thunderlink/resources/role.ex:549:      # TODO: Fix fragment expression for expiry filtering
Thunderline/lib/thunderline/thunderlink/resources/role.ex:579:    # TODO: Fix validation syntax for Ash 3.x
Thunderline/lib/thunderline/thunderlink/resources/role.ex:808:  # TODO: Fix trigger syntax for AshOban 3.x
Thunderline/lib/thunderline/thunderlink/resources/role.ex:817:  # TODO: Fix remaining trigger syntax for AshOban 3.x
Thunderline/lib/thunderline_web/live/dashboard_live.ex:259:          # TODO: Implement real memory monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:261:          # TODO: Implement real CPU monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:330:       # TODO: Implement real CPU monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:1327:      # TODO: Implement real CPU monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:1334:        # TODO: Implement disk I/O monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:1336:        # TODO: Implement disk I/O monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:1340:        # TODO: Implement network monitoring
Thunderline/lib/thunderline_web/live/dashboard_live.ex:1342:        # TODO: Implement network monitoring
Thunderline/lib/thunderline_web/live/thunderlane_dashboard.ex:13:  TODO (upgrade path):
Thunderline/lib/thunderline_web/router.ex:53:    # TODO (FLAG-G1 follow-up): flip required?: true once API keys issued.
Thunderline/lib/thunderline_web/user_socket.ex:12:    # TODO: tie into AshAuthentication session token -> assign current_user/principal_id

## Potential duplicate function names (rough heuristic)
