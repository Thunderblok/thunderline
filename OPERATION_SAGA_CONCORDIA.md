# OPERATION SAGA CONCORDIA

**Mission Codename**: SAGA CONCORDIA  
**Lead**: CAPTAIN IRON TIDE  
**Branch**: `concordia/iron_tide_mvp`  
**Timeline**: October 27 - November 7, 2025  
**Status**: 🟢 ACTIVE

---

## Mission Overview

**Objective**: Harmonize orchestration across ThunderBolt ↔ ThunderFlow ↔ ThunderGate ↔ ThunderCrown, ensuring sagas and events follow one canonical protocol.

**Strategic Alignment**: Operation SAGA CONCORDIA integrates with High Command mission framework (HC-01 through HC-10) to establish unified orchestration patterns across all Thunder domains.

**Standing Principle**:  
*"Cut nothing that runs clean. Flag, isolate, and prove before you remove. We evolve the Line by tightening interfaces, not by heroics."*

---

## Four-Phase Execution Plan

### Phase 1 — Documentation Integration (IMMEDIATE)

**Deadline**: Monday, October 27, 2025 EOD  
**Tags**: IRON_TIDE-001, IRON_TIDE-002

**Tasks**:

1. **README Surface Area**
   - Add "Strategic Planning" section with links to:
     - [IMMEDIATE_ACTION_PLAN.md](documentation/planning/IMMEDIATE_ACTION_PLAN.md)
     - [THUNDERLINE_REBUILD_INITIATIVE.md](documentation/planning/THUNDERLINE_REBUILD_INITIATIVE.md)
     - [Q4_2025_PAC_Distributed_Agent_Network_STATUS.md](documentation/planning/Q4_2025_PAC_Distributed_Agent_Network_STATUS.md)
     - [DEVELOPER_QUICK_REFERENCE.md](documentation/planning/DEVELOPER_QUICK_REFERENCE.md)
     - [PR_REVIEW_CHECKLIST.md](documentation/planning/PR_REVIEW_CHECKLIST.md)
     - [QUICKSTART.md](documentation/planning/QUICKSTART.md)

2. **PR Discipline**
   - Promote `PR_REVIEW_CHECKLIST.md` to `.github/PULL_REQUEST_TEMPLATE.md`
   - Ensure copy-paste ready format for all future PRs

3. **Historical Tagging**
   - Prefix older audits with `[HISTORICAL]_`:
     - `CODEBASE_AUDIT_2025-10-08.md` → `[HISTORICAL]_CODEBASE_AUDIT_2025-10-08.md`
     - `CODEBASE_REVIEW_OCT_12_2025.md` → `[HISTORICAL]_CODEBASE_REVIEW_OCT_12_2025.md`

4. **Mission File**
   - This document (`OPERATION_SAGA_CONCORDIA.md`) at repository root

**Acceptance Criteria**:
- ✅ README Strategic Planning section visible from main entry point
- ✅ PR template enforces 12-section quality gate
- ✅ Historical context clearly marked
- ✅ Mission charter accessible to all team members

---

### Phase 2 — Code Recon & Saga Inventory

**Deadline**: Wednesday, October 29, 2025 EOD  
**Tag**: IRON_TIDE-003

**Tasks**:

1. **ThunderBolt Sweep**
   - Enumerate all saga entrypoints in `lib/thunderline/thunderbolt/sagas/`
   - Document for each saga:
     - Module name and file path
     - `run/2` function steps
     - `rollback/2` compensation logic
     - Lines of code
     - Compensation gaps (missing rollback, incomplete undo)

2. **Event Conformance**
   - For each saga step:
     - Extract emitted event topics (via `:telemetry.execute` or `EventBus.publish_event`)
     - Document payload schemas
     - Cross-reference with [EVENT_TAXONOMY.md](documentation/EVENT_TAXONOMY.md) v0.2
     - Flag unclassified events with `TODO[CONCORDIA]`

3. **Correlation Discipline**
   - Verify `correlation_id` propagation:
     - Saga step to step
     - Saga to external service calls
     - Saga to event emissions
   - Document propagation gaps
   - Add test assertions for `correlation_id` presence

**Deliverables** (commit to `/docs/concordia/`):
- `saga_inventory.md` - Table of sagas, steps, compensations, gaps
- `event_matrix.md` - Topic → payload → taxonomy mapping
- `correlation_audit.md` - Correlation ID propagation verification

**Acceptance Criteria**:
- ✅ Complete saga inventory with compensation gap analysis
- ✅ All saga events mapped to EVENT_TAXONOMY v0.2 categories
- ✅ Correlation ID audit documents propagation paths and gaps

---

### Phase 3 — Provisioning Reactor (MVP-safe)

**Deadline**: Friday, October 31, 2025 EOD  
**Tag**: IRON_TIDE-004

**Tasks**:

1. **Reactor Scaffold**
   - Create `Thunderline.Thunderblock.ProvisionReactor` module
   - Implement 3-step saga:
     1. `ExecutionContainer.create` → compensate: `destroy`
     2. `SupervisionTree.start_block/1` → compensate: `stop`
     3. `emit_online_event` → compensate: `emit_offline_event` (optional)
   - Include `correlation_id` propagation through all steps
   - Add telemetry spans: `[:saga, :provision_reactor, :step_name, :start/:stop/:exception]`

2. **Ash Action Integration**
   - Wire `ExecutionContainer` resource with `:provision` action
   - Action uses `run: ProvisionReactor`
   - Preserve existing `:create` action (back-compat)
   - Add feature flag: `:provision_reactor_enabled` (default: false)

3. **Event Wiring**
   - **Inbound**: Subscribe to `orchestrate.intent.provision_block`
   - **Outbound**: Emit:
     - `saga.provision_reactor.started`
     - `saga.provision_reactor.step_completed`
     - `saga.provision_reactor.completed` / `saga.provision_reactor.failed`
     - `thunderline:block.online` (final step)
   - Verify all events conform to EVENT_TAXONOMY v0.2

4. **Comprehensive Tests**
   - **Success path**: Container created → supervision started → online event emitted
   - **Failure injection**: Inject failure at step 2 → verify container destroyed (compensation)
   - **Event conformance**: All events match taxonomy
   - **Correlation ID**: Present end-to-end in all events and spans
   - **Feature flag**: `:provision` action routes correctly based on flag
   - **Coverage target**: ≥ +2% test coverage delta

**Acceptance Criteria**:
- ✅ ProvisionReactor module implements 3-step saga with compensation
- ✅ ExecutionContainer `:provision` action wired to reactor
- ✅ All events conform to EVENT_TAXONOMY v0.2
- ✅ Test suite green with ≥ +2% coverage increase
- ✅ Feature flag allows safe rollout

---

### Phase 4 — Bridge Checkpoint (Cerebros)

**Deadline**: November 3-7, 2025  
**Tag**: IRON_TIDE-005

**Tasks**:

1. **Audit Cerebros Sagas**
   - Review sagas that interact with Cerebros (from Phase 2 inventory)
   - Verify: All calls to Cerebros use Bridge Facade APIs (not direct MLflow)
   - Check: Authorization on bridge API calls
   - Document: Any direct MLflow calls bypassing facade

2. **Add Telemetry Spans**
   - Identify critical operations:
     - Model trial initiation
     - Artifact promotion
     - Rollback/compensation
   - Add spans: `[:cerebros, :bridge, :operation_name, :start/:stop/:exception]`
   - Include metadata: `model_run_id`, `trial_id`, `actor_id`, `duration`
   - Verify spans propagate `correlation_id`

3. **Document Findings**
   - Create: `/docs/concordia/bridge_checkpoint.md`
   - Sections:
     - Cerebros Bridge Facade usage audit results
     - Authorization verification
     - Telemetry span coverage
     - Identified gaps and remediation
     - Cross-reference with [CEREBROS_BRIDGE_PLAN.md](documentation/CEREBROS_BRIDGE_PLAN.md)

**Deliverables**:
- `/docs/concordia/bridge_checkpoint.md`
- Telemetry additions to Cerebros sagas
- Authorization audit report

**Acceptance Criteria**:
- ✅ All Cerebros sagas use Bridge Facade APIs exclusively
- ✅ Authorization verified on all bridge calls
- ✅ Telemetry spans cover model trial, promotion, rollback
- ✅ Correlation ID propagates through all operations
- ✅ Documentation complete with gap remediation plan

---

## Quality Gates

**Pre-PR Checklist** (run before every PR):

```bash
# Compile with warnings-as-errors
mix compile --warnings-as-errors

# Run test suite
mix test

# Event taxonomy compliance
mix thunderline.events.lint

# Ash resource verification
mix ash.doctor

# Code quality
mix credo --strict

# Security scan (Phase 3+)
mix sobelow --config
```

**Phase 3 Specific**:
- Test coverage must increase by ≥ +2%
- All new events must pass `mix thunderline.events.lint`

---

## Integration with High Command Missions

Operation SAGA CONCORDIA leverages and extends existing HC mission framework:

| HC Mission | CONCORDIA Integration |
|------------|----------------------|
| **HC-01**: EventBus Restoration | Phase 2 event conformance validates EventBus taxonomy |
| **HC-02**: Bus Shim Retirement | Phase 2 identifies legacy Bus usage in sagas |
| **HC-03**: Event Taxonomy Documentation | Phase 2 aligns all saga events to taxonomy v0.2 |
| **HC-04**: Cerebros Lifecycle Completion | Phase 4 Bridge Checkpoint extends lifecycle work |
| **HC-09**: Error Classifier + DLQ Policy | Phase 3 reactor uses error classification patterns |

**PAC Distributed Agent Network Context**:
- Phase 3 ProvisionReactor supports PAC execution container lifecycle
- Aligns with Q4 PAC roadmap (Pillar 2: Orchestration & ThunderCell Automata)
- Enables future NAS trial provisioning automation

---

## Weekly Warden Reports

**Schedule**: Every Friday EOD (America/New_York)  
**Template**: [WARDEN_CHRONICLES_TEMPLATE.md](documentation/planning/WARDEN_CHRONICLES_TEMPLATE.md)  
**Channel**: Warden Channel

**Report Sections**:
1. **Completed Tasks** (with tag references)
2. **Blockers** (if any)
3. **Next Week Preview**
4. **Metrics**:
   - Test coverage delta
   - Event taxonomy compliance %
   - Saga inventory progress
   - PR review status

---

## Mission-Critical Documents

**Strategic Planning**:
- [IMMEDIATE_ACTION_PLAN.md](documentation/planning/IMMEDIATE_ACTION_PLAN.md) - Week 1 recovery plan
- [THUNDERLINE_REBUILD_INITIATIVE.md](documentation/planning/THUNDERLINE_REBUILD_INITIATIVE.md) - Master plan (10 HC missions)
- [Q4_2025_PAC_Distributed_Agent_Network_STATUS.md](documentation/planning/Q4_2025_PAC_Distributed_Agent_Network_STATUS.md) - PAC roadmap

**Developer Resources**:
- [DEVELOPER_QUICK_REFERENCE.md](documentation/planning/DEVELOPER_QUICK_REFERENCE.md) - Dev cheat sheet
- [PR_REVIEW_CHECKLIST.md](documentation/planning/PR_REVIEW_CHECKLIST.md) - 12-section quality gate
- [QUICKSTART.md](documentation/planning/QUICKSTART.md) - Quick start guide

**Architecture**:
- [CEREBROS_BRIDGE_PLAN.md](documentation/CEREBROS_BRIDGE_PLAN.md) - Cerebros orchestration architecture
- [EVENT_TAXONOMY.md](documentation/EVENT_TAXONOMY.md) - Event categories and naming conventions (v0.2)
- [THUNDERLINE_DOMAIN_CATALOG.md](THUNDERLINE_DOMAIN_CATALOG.md) - Authoritative domain/resource inventory

**Audit Methodology**:
- [HOW_TO_AUDIT.md](HOW_TO_AUDIT.md) - Systematic audit methodology ⭐ **READ THIS BEFORE AUDITING**
- [CODEBASE_AUDIT_2025.md](CODEBASE_AUDIT_2025.md) - Latest audit findings

---

## Branch and Tag Strategy

**Branch**: `concordia/iron_tide_mvp`  
**Tag Sequence**:
- `IRON_TIDE-001`: Phase 1 docs (README, mission doc)
- `IRON_TIDE-002`: Phase 1 docs (PR template, historical tagging)
- `IRON_TIDE-003`: Phase 2 artifacts (saga inventory, event matrix, correlation audit)
- `IRON_TIDE-004`: Phase 3 ProvisionReactor + tests
- `IRON_TIDE-005`: Phase 4 Bridge checkpoint + telemetry

**PR Workflow**:
1. Create feature PR from `concordia/iron_tide_mvp`
2. Use `.github/PULL_REQUEST_TEMPLATE.md` checklist (from Phase 1)
3. Run quality gates
4. Request review from domain stewards
5. Squash merge to `main`
6. Tag merged commit with `IRON_TIDE-XXX`

---

## Success Criteria

**Phase 1** (Documentation Integration):
- ✅ README Strategic Planning section added
- ✅ PR template enforced
- ✅ Historical context marked
- ✅ Mission charter visible

**Phase 2** (Code Recon):
- ✅ Complete saga inventory with compensation analysis
- ✅ Event taxonomy conformance map
- ✅ Correlation ID audit complete

**Phase 3** (ProvisionReactor):
- ✅ 3-step reactor with compensation
- ✅ Ash action integration
- ✅ Event wiring complete
- ✅ Test coverage ≥ +2%
- ✅ Feature flag for safe rollout

**Phase 4** (Bridge Checkpoint):
- ✅ Cerebros Bridge Facade usage verified
- ✅ Authorization audit complete
- ✅ Telemetry spans added
- ✅ Documentation complete

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Saga inventory reveals deep compensation gaps** | High | Flag gaps in Phase 2, prioritize fixes in follow-up mission |
| **Event taxonomy changes break existing integrations** | Medium | Phase 2 audit identifies all affected events; add TODO markers |
| **ProvisionReactor conflicts with existing create flows** | High | Feature flag allows gradual rollout; preserve back-compat |
| **Cerebros sagas bypass Bridge Facade** | High | Phase 4 audit identifies violations; create remediation tickets |
| **Timeline slips due to testing bottlenecks** | Medium | Phase 3 has +2% coverage target (achievable); focus on critical paths |

---

## Contact & Escalation

**Mission Lead**: CAPTAIN IRON TIDE  
**Reporting Channel**: Warden Channel (weekly Friday EOD)  
**Escalation Path**: High Command briefing for blockers

---

**For the Line, the Bolt, and the Crown.** ⚡

*"Aut viam inveniam aut faciam"*
