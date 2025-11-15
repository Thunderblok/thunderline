# OPERATION SAGA CONCORDIA - Phase 2: Saga Inventory

**Date**: October 27, 2025  
**Task**: 2.1 - Enumerate Saga Entrypoints  
**Status**: ✅ Complete  
**Analyst**: Concordia Phase 2 Agent

---

## Executive Summary

Thunderline currently has **3 active Reactor-based sagas** orchestrating cross-domain workflows:

1. **UserProvisioningSaga** - User onboarding flow (Gate → Block → Link)
2. **UPMActivationSaga** - ML model promotion workflow (Bolt ↔ Crown)
3. **CerebrosNASSaga** - Neural Architecture Search pipeline (Bolt ↔ Cerebros Bridge)

All sagas follow a consistent pattern:
- Built on **Reactor DSL** (`use Reactor`)
- Emit **telemetry** via `:telemetry.execute/3` (lifecycle tracking)
- Emit **domain events** via `EventBus.publish_event/1` (completion events)
- Include **compensation logic** for rollback on failure
- Propagate **correlation_id** for distributed tracing

**Total LOC**: 1,196 lines across 6 files (3 concrete sagas + 3 infrastructure files)

---

## Saga Inventory Table

| Saga Module | Path | Steps | Compensations | Events Emitted | LOC | Status | Gaps |
|-------------|------|-------|---------------|----------------|-----|--------|------|
| `UserProvisioningSaga` | `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex` | 8 | 3 | `user.onboarding.complete` | 242 | ✅ Active | Missing community cleanup compensation |
| `UPMActivationSaga` | `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex` | 7 | 3 | `ai.upm.snapshot.activated` | 283 | ✅ Active | Adapter rollback compensation stubbed (TODO) |
| `CerebrosNASSaga` | `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex` | 9 | 2 | `ml.run.complete` | 337 | ✅ Active | Training job cancellation stubbed (TODO) |
| `Base` (infrastructure) | `lib/thunderline/thunderbolt/sagas/base.ex` | N/A | N/A | `reactor.saga.*` (lifecycle) | 172 | ✅ Active | N/A |
| `Supervisor` (infrastructure) | `lib/thunderline/thunderbolt/sagas/supervisor.ex` | N/A | N/A | Telemetry wrapper | 150 | ✅ Active | N/A |
| `Registry` (infrastructure) | `lib/thunderline/thunderbolt/sagas/registry.ex` | N/A | N/A | N/A | 12 | ✅ Active | N/A |

**Totals**: 3 concrete sagas, 24 workflow steps, 8 compensations, 1,196 LOC

---

## Detailed Saga Breakdown

### 1. UserProvisioningSaga

**Purpose**: Orchestrate complete user onboarding flow across ThunderGate, ThunderBlock, and ThunderLink.

**Workflow Steps**:
1. `validate_email` - Regex validation of email format
2. `generate_token` - Create magic link token (UUIDv7, 1-hour expiry)
3. `send_magic_link` - Dispatch email via `MagicLinkSender`
4. `create_user` - Persist user record in ThunderGate
5. `provision_vault` - Create 1GB vault in ThunderBlock
6. `create_default_community` - Bootstrap community membership (ThunderLink)
7. `emit_onboarding_event` - Publish `user.onboarding.complete` to EventBus

**Compensations**:
- ✅ `create_user` → Delete user record via `Ash.destroy/1`
- ✅ `provision_vault` → Deprovision vault via `Ash.destroy/1`
- ⚠️ `create_default_community` → **Stubbed** (TODO: Remove community membership)

**Events Emitted**:
- `user.onboarding.complete` (domain: `:gate`, pipeline: `:cross_domain`)

**Compensation Gaps**:
- **Missing**: Community membership cleanup (step 6 compensation stubbed)
  - **Impact**: Failed saga leaves orphaned community records
  - **Recommendation**: Wire to ThunderLink community cleanup action (Phase 3)

**Correlation ID Propagation**: ✅ Yes (input → token data → event)

**Lines of Code**: 242

---

### 2. UPMActivationSaga

**Purpose**: Promote shadow-trained UPM snapshot to active status with policy evaluation and adapter synchronization.

**Workflow Steps**:
1. `load_snapshot` - Retrieve shadow snapshot from ThunderBlock
2. `validate_drift` - Check drift score against threshold (via `UpmDriftWindow`)
3. `policy_check` - ThunderCrown policy evaluation (stubbed as auto-approve)
4. `deactivate_previous` - Archive currently active snapshot
5. `activate_snapshot` - Promote snapshot to active status
6. `sync_adapters` - Update all `UpmAdapter` references to new snapshot
7. `emit_activation_event` - Publish `ai.upm.snapshot.activated` to EventBus

**Compensations**:
- ✅ `deactivate_previous` → Restore previous snapshot to active status
- ✅ `activate_snapshot` → Revert snapshot to shadow status
- ⚠️ `sync_adapters` → **Stubbed** (TODO: Restore previous adapter configurations)

**Events Emitted**:
- `ai.upm.snapshot.activated` (domain: `:bolt`, pipeline: `:realtime`)

**Compensation Gaps**:
- **Missing**: Adapter configuration rollback (step 6 compensation stubbed)
  - **Impact**: Failed saga leaves adapters pointing to invalid snapshot
  - **Recommendation**: Store previous adapter states before sync, restore on failure (Phase 3)

**Correlation ID Propagation**: ✅ Yes (input → policy check → event)

**Lines of Code**: 283

---

### 3. CerebrosNASSaga

**Purpose**: Orchestrate Neural Architecture Search via Cerebros bridge (dataset → proposals → training → Pareto analysis → versioning).

**Workflow Steps**:
1. `prepare_dataset` - Load and validate `TrainingDataset`
2. `create_model_run` - Create `ModelRun` record in pending status
3. `generate_proposals` - Call `CerebrosBridge.Invoker.propose/1` for architecture proposals
4. `dispatch_training` - Submit training jobs via `CerebrosBridge.Invoker.train/1`
5. `await_completion` - Poll for training completion (5s interval, 300s max)
6. `collect_artifacts` - Gather `ModelArtifact` records
7. `analyze_pareto` - Compute Pareto frontier (accuracy vs. model size)
8. `persist_version` - Select best model and prepare for versioning (TODO: create `ModelVersion`)
9. `emit_completion_event` - Publish `ml.run.complete` to EventBus

**Compensations**:
- ✅ `create_model_run` → Mark run as failed in database
- ⚠️ `dispatch_training` → **Stubbed** (TODO: Cancel in-flight training jobs)

**Events Emitted**:
- `ml.run.complete` (domain: `:bolt`, pipeline: `:cross_domain`)

**Compensation Gaps**:
- **Missing**: Training job cancellation (step 4 compensation stubbed)
  - **Impact**: Failed saga leaves orphaned training jobs consuming resources
  - **Recommendation**: Implement job cancellation via Cerebros bridge API (Phase 3)
- **TODO**: `persist_version` does not create `ModelVersion` record (only logs best model)
  - **Impact**: Winning architectures not persisted to registry
  - **Recommendation**: Wire to `ModelVersion` creation action (Phase 3)

**Correlation ID Propagation**: ✅ Yes (input → model run → event)

**Lines of Code**: 337

---

## Infrastructure Files

### Base Module (`base.ex`, 172 LOC)

**Purpose**: Shared telemetry and event emission infrastructure for all sagas.

**Key Features**:
- `telemetry_wrapper/0` - Returns Reactor around hook for lifecycle telemetry
- `before_saga/2` - Emits `[:reactor, :saga, :start]` telemetry
- `after_saga/2` - Emits `[:reactor, :saga, :complete]` or `[:reactor, :saga, :fail]`
- `instrument_step/2` - Wraps step functions with start/stop/exception telemetry
- `compensate_step/2` - Logs and emits telemetry for compensation steps
- `maybe_emit_event/4` - Publishes lifecycle events to EventBus (feature-flagged: `:reactor_events`)

**Telemetry Events**:
- `[:reactor, :saga, :start]` - Saga begins
- `[:reactor, :saga, :complete]` - Saga succeeds
- `[:reactor, :saga, :fail]` - Saga fails after compensation
- `[:reactor, :saga, :step, :start]` - Step begins
- `[:reactor, :saga, :step, :stop]` - Step succeeds
- `[:reactor, :saga, :step, :exception]` - Step fails
- `[:reactor, :saga, :compensate]` - Compensation triggered

**EventBus Events** (when `:reactor_events` feature enabled):
- `reactor.saga.complete` (domain: `:bolt`, pipeline: `:realtime`)
- `reactor.saga.fail` (domain: `:bolt`, pipeline: `:realtime`)

---

### Supervisor (`supervisor.ex`, 150 LOC)

**Purpose**: Saga lifecycle management and orchestration.

**Key Features**:
- Wraps saga execution with telemetry via `emit_saga_telemetry/3`
- Handles correlation ID injection
- Supervises saga processes

**Telemetry Emission**:
- Line 87: `emit_saga_telemetry(saga_module, result, correlation_id)`
- Line 145: `:telemetry.execute([:thunderline, :saga], measurements, metadata)`

---

### Registry (`registry.ex`, 12 LOC)

**Purpose**: Saga registration (currently minimal stub).

**Status**: Minimal implementation, likely placeholder for future saga discovery mechanism.

---

## Compensation Gap Analysis

### Summary

**Total Compensations**: 8 implemented  
**Complete Compensations**: 5 (63%)  
**Stubbed Compensations**: 3 (37%)

### Critical Gaps (P1 - Must Fix)

1. **CerebrosNASSaga - Training Job Cancellation** (`dispatch_training` step)
   - **Impact**: High - Orphaned training jobs consume expensive compute resources
   - **Blast Radius**: External system (Cerebros bridge)
   - **Recommendation**: Implement `CerebrosBridge.Invoker.cancel/1` and wire to compensation
   - **Phase**: 3 (critical for production NAS workflows)

### Important Gaps (P2 - Should Fix)

2. **UPMActivationSaga - Adapter Rollback** (`sync_adapters` step)
   - **Impact**: Medium - Adapters point to invalid snapshot on failure
   - **Blast Radius**: Internal (ThunderBlock agents)
   - **Recommendation**: Store previous adapter states, restore on failure
   - **Phase**: 3 (important for UPM stability)

3. **UserProvisioningSaga - Community Cleanup** (`create_default_community` step)
   - **Impact**: Low - Orphaned community memberships accumulate
   - **Blast Radius**: Internal (ThunderLink)
   - **Recommendation**: Wire to ThunderLink community cleanup action
   - **Phase**: 3 or 4 (low priority, database cruft only)

### Minor Gaps (P3 - Nice to Have)

4. **CerebrosNASSaga - ModelVersion Persistence** (`persist_version` step)
   - **Impact**: Low - Best models not persisted to registry (only logged)
   - **Blast Radius**: Internal (ThunderBolt model registry)
   - **Recommendation**: Wire to `ModelVersion` creation action
   - **Phase**: 4 (feature completion, not critical)

---

## Event Emission Patterns

All sagas follow a **consistent two-layer event strategy**:

### Layer 1: Telemetry Events (Operational)

- **Purpose**: Observability, metrics, tracing
- **Mechanism**: `:telemetry.execute/3` via `Base` module
- **Prefix**: `[:reactor, :saga]`
- **Events**: `:start`, `:complete`, `:fail`, `:step, :start`, `:step, :stop`, `:step, :exception`, `:compensate`
- **Metadata**: `%{saga: module, correlation_id: uuid, ...}`

### Layer 2: Domain Events (Business)

- **Purpose**: Cross-domain integration, event sourcing, audit trails
- **Mechanism**: `EventBus.publish_event/1` via `Thunderline.Event.new/1`
- **Events**:
  - `user.onboarding.complete` (UserProvisioningSaga)
  - `ai.upm.snapshot.activated` (UPMActivationSaga)
  - `ml.run.complete` (CerebrosNASSaga)
  - `reactor.saga.complete` (Base, feature-flagged)
  - `reactor.saga.fail` (Base, feature-flagged)
- **Structure**: Canonical event struct with `name`, `type`, `domain`, `source`, `correlation_id`, `payload`, `meta`

### Event Emission Failure Handling

All sagas treat **event emission failure as non-blocking**:

```elixir
case Thunderline.Event.new(event_attrs) do
  {:ok, event} ->
    Thunderline.Thunderflow.EventBus.publish_event(event)
    {:ok, result}

  {:error, reason} ->
    Logger.warning("Failed to emit event: #{inspect(reason)}")
    {:ok, result}  # <-- Saga continues despite event failure
end
```

**Rationale**: Event emission is observability, not business logic. Saga success should not depend on event bus availability.

---

## Correlation ID Propagation

All sagas **correctly propagate correlation_id** through the entire workflow:

### UserProvisioningSaga
- **Input**: `correlation_id` (required)
- **Propagation Path**: input → `generate_token` → `create_user` → `emit_onboarding_event`
- **External Calls**: Magic link sender (no correlation_id passed - **GAP**)

### UPMActivationSaga
- **Input**: `correlation_id` (required)
- **Propagation Path**: input → policy check → `emit_activation_event`
- **External Calls**: None

### CerebrosNASSaga
- **Input**: `correlation_id` (required)
- **Propagation Path**: input → `create_model_run` → Cerebros bridge calls → `emit_completion_event`
- **External Calls**: Cerebros bridge (correlation_id passed in bridge calls - ✅)

### Correlation ID Gap

**UserProvisioningSaga - Magic Link Sender**:
- **Issue**: `MagicLinkSender.send_magic_link/3` does not accept correlation_id
- **Impact**: Email sending not traceable in distributed system
- **Recommendation**: Add correlation_id to `MagicLinkSender` API (Phase 3)

---

## Architectural Observations

### Strengths

1. **Consistent Reactor Pattern**: All sagas use Reactor DSL uniformly
2. **Comprehensive Telemetry**: Every saga lifecycle event emits telemetry
3. **Domain Event Publishing**: Business-critical state transitions publish to EventBus
4. **Compensation-First Design**: All state-mutating steps include compensation logic
5. **Correlation ID Discipline**: All sagas require correlation_id as input
6. **Shared Base Module**: Reduces duplication, enforces patterns

### Weaknesses

1. **Stubbed Compensations**: 37% of compensations are TODOs (see gaps above)
2. **Polling for Completion**: CerebrosNASSaga uses synchronous polling (5s interval, 300s max)
   - **Recommendation**: Migrate to async/event-driven completion (Oban job + webhook)
3. **Policy Check Stubbed**: UPMActivationSaga auto-approves all promotions
   - **Recommendation**: Wire to ThunderCrown policy engine (Phase 3)
4. **Manual Correlation ID Injection**: No automatic correlation_id generation
   - **Recommendation**: Add Reactor middleware to auto-inject if missing (Phase 4)

### Technical Debt

1. **TODO Count**: 5 explicit TODOs across sagas (community cleanup, adapter rollback, job cancellation, ModelVersion persistence, policy wiring)
2. **Test Coverage**: Unknown (need to audit saga test files in Phase 3)
3. **Feature Flag Dependency**: `reactor_events` feature flag controls Base module event emission (good for gradual rollout, but adds complexity)

---

## Recommendations for Phase 3

### High Priority (P1)

1. **Implement CerebrosNASSaga Training Cancellation**
   - Wire `dispatch_training` compensation to `CerebrosBridge.Invoker.cancel/1`
   - Prevents orphaned compute resources on saga failure
   - **Effort**: 2-3 hours (bridge API + compensation logic)

2. **Complete UPMActivationSaga Adapter Rollback**
   - Store previous adapter snapshot references before sync
   - Restore on compensation
   - **Effort**: 2-3 hours (state capture + rollback logic)

### Medium Priority (P2)

3. **Wire UserProvisioningSaga Community Cleanup**
   - Implement ThunderLink community membership deletion
   - Wire to `create_default_community` compensation
   - **Effort**: 1-2 hours (ThunderLink action + compensation)

4. **Add Correlation ID to MagicLinkSender**
   - Update `MagicLinkSender.send_magic_link/4` to accept correlation_id
   - Pass correlation_id from saga to email sender
   - **Effort**: 1 hour (API change + propagation)

### Low Priority (P3)

5. **Replace Polling with Async Completion**
   - Migrate CerebrosNASSaga to Oban job + webhook pattern
   - Eliminates synchronous polling overhead
   - **Effort**: 4-6 hours (Oban job + webhook handler + saga refactor)

6. **Wire ThunderCrown Policy Engine**
   - Replace UPMActivationSaga auto-approve with real policy evaluation
   - **Effort**: 2-3 hours (ThunderCrown integration)

7. **Create ModelVersion Records**
   - Complete CerebrosNASSaga `persist_version` step
   - **Effort**: 1-2 hours (ModelVersion action + persistence)

---

## Next Steps (Task 2.2)

**Immediate Next Action**: Begin **Event Conformance Audit** (Task 2.2)

1. Map all event emissions to `EVENT_TAXONOMY.md` v0.2
2. Validate event names follow taxonomy conventions
3. Check event `type`, `domain`, `source` consistency
4. Flag any taxonomy drifts with `TODO[CONCORDIA]`
5. Create `docs/concordia/event_matrix.md`

**Estimated Effort**: 3-4 hours

---

## Appendix: File Paths

```
lib/thunderline/thunderbolt/sagas/
├── base.ex                     (172 LOC)
├── cerebros_nas_saga.ex        (337 LOC)
├── registry.ex                 (12 LOC)
├── supervisor.ex               (150 LOC)
├── upm_activation_saga.ex      (283 LOC)
└── user_provisioning_saga.ex   (242 LOC)

Total: 1,196 LOC
```

---

**Task 2.1 Status**: ✅ **Complete**  
**Next Task**: 2.2 - Event Conformance Audit  
**Phase 2 Deadline**: Wed Oct 29, 2025 EOD (~46 hours remaining)
