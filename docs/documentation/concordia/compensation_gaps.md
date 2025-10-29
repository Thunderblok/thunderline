# OPERATION SAGA CONCORDIA - Compensation Gaps Tracker

**Date**: October 27, 2025  
**Phase**: 2 - Code Recon & Saga Inventory  
**Status**: 🔴 3 Critical Gaps Identified

---

## Critical Gaps (P1 - Must Fix)

### GAP-001: CerebrosNASSaga - Training Job Cancellation

**File**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex`  
**Step**: `dispatch_training` (line ~150-180)  
**Current State**: Compensation stubbed with TODO comment  

```elixir
compensate fn _jobs, _ ->
  # TODO: Cancel in-flight training jobs
  Logger.warning("Compensating: canceling training jobs")
  {:ok, :compensated}
end
```

**Impact**: 🔴 **HIGH**
- Orphaned training jobs consume expensive GPU/TPU compute resources
- Failed sagas leave jobs running indefinitely until manual cleanup
- Resource leakage in production NAS workflows

**Blast Radius**: External system (Cerebros Bridge API)

**Recommendation**:
1. Implement `Thunderline.Thunderbolt.CerebrosBridge.Invoker.cancel/1` function
2. Store job IDs from `dispatch_training` results
3. Wire compensation to call `cancel/1` for each job ID
4. Add error handling for already-completed jobs

**Estimated Effort**: 2-3 hours  
**Phase**: 3 (critical for production)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

### GAP-002: UPMActivationSaga - Adapter Configuration Rollback

**File**: `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex`  
**Step**: `sync_adapters` (line ~220-250)  
**Current State**: Compensation stubbed with TODO comment

```elixir
compensate fn _adapters, _ ->
  # TODO: Restore previous adapter configurations
  Logger.warning("Compensating: adapter sync rollback")
  {:ok, :compensated}
end
```

**Impact**: 🟡 **MEDIUM**
- Adapters point to invalid/shadow snapshot on saga failure
- ThunderBlock agents may serve stale embeddings
- Requires manual intervention to restore adapter state

**Blast Radius**: Internal (ThunderBlock agents, potentially affecting all UPM queries)

**Recommendation**:
1. Store previous `active_snapshot_id` for each adapter before sync
2. Create `restore_adapter_states/2` helper function
3. Wire compensation to restore each adapter's previous snapshot reference
4. Add transaction wrapper to ensure atomic rollback

**Estimated Effort**: 2-3 hours  
**Phase**: 3 (important for UPM stability)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

## Important Gaps (P2 - Should Fix)

### GAP-003: UserProvisioningSaga - Community Membership Cleanup

**File**: `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex`  
**Step**: `create_default_community` (line ~170-185)  
**Current State**: Compensation stubbed with TODO comment

```elixir
compensate fn _membership, _ ->
  # TODO: Remove community membership
  Logger.warning("Compensating: removing community membership")
  {:ok, :compensated}
end
```

**Impact**: 🟢 **LOW**
- Orphaned community membership records accumulate in database
- Database cruft, no immediate functional impact
- May cause data consistency issues in community queries over time

**Blast Radius**: Internal (ThunderLink community tables)

**Recommendation**:
1. Wire to ThunderLink `remove_community_membership/1` action (if exists)
2. If action doesn't exist, create minimal cleanup action
3. Pass membership ID to compensation function
4. Add soft-delete support if hard-delete causes cascading issues

**Estimated Effort**: 1-2 hours  
**Phase**: 3 or 4 (low priority, cleanup task)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

### GAP-004: UserProvisioningSaga - MagicLinkSender Correlation ID

**File**: `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex`  
**Step**: `send_magic_link` (line ~100-120)  
**Current State**: Correlation ID not passed to external sender

```elixir
case Thunderline.Thundergate.Authentication.MagicLinkSender.send_magic_link(
       token_data.email,
       token_data.token,
       redirect
     ) do
  # No correlation_id passed - not traceable in logs
end
```

**Impact**: 🟡 **MEDIUM**
- Email sending operations not traceable in distributed tracing
- Cannot correlate email failures with specific user onboarding flows
- Debugging email issues requires manual log correlation

**Blast Radius**: Internal (ThunderGate email sender)

**Recommendation**:
1. Update `MagicLinkSender.send_magic_link/4` signature to accept `correlation_id`
2. Pass correlation_id from saga to email sender
3. Include correlation_id in email send telemetry
4. Add correlation_id to email template metadata (optional)

**Estimated Effort**: 1 hour  
**Phase**: 3 (improves observability)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

## Minor Gaps (P3 - Nice to Have)

### GAP-005: CerebrosNASSaga - ModelVersion Persistence Incomplete

**File**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex`  
**Step**: `persist_version` (line ~280-300)  
**Current State**: Best model logged but not persisted to registry

```elixir
if best_model do
  # TODO: Create ModelVersion record
  Logger.info("Best model: #{best_model.id} (score: #{best_model.score})")
  {:ok, %{run: run, best_model: best_model}}
else
  # ...
end
```

**Impact**: 🟢 **LOW**
- Winning NAS architectures not persisted to model registry
- Manual recovery required to retrieve best models
- No version history for NAS results

**Blast Radius**: Internal (ThunderBolt model registry)

**Recommendation**:
1. Create `ModelVersion` Ash resource (if doesn't exist)
2. Wire `persist_version` to create ModelVersion record
3. Include Pareto frontier metadata
4. Link ModelVersion to ModelRun for audit trail

**Estimated Effort**: 2-3 hours  
**Phase**: 4 (feature completion)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

### GAP-006: UPMActivationSaga - Policy Check Auto-Approval

**File**: `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex`  
**Step**: `policy_check` (line ~120-145)  
**Current State**: Policy evaluation stubbed with auto-approve

```elixir
# TODO: Wire to ThunderCrown policy evaluation
# For now, stub with auto-approval
policy_decision = %{
  approved: true,
  reason: "Auto-approved (drift: #{drift_score})",
  policy_id: Thunderline.UUID.v7()
}
```

**Impact**: 🟡 **MEDIUM**
- All UPM snapshot promotions auto-approved (no real policy evaluation)
- Cannot enforce business rules for model activation
- Regulatory/compliance risk if ML model governance required

**Blast Radius**: Internal (ThunderCrown policy engine integration)

**Recommendation**:
1. Define UPM activation policy schema in ThunderCrown
2. Wire `policy_check` to `ThunderCrown.evaluate_policy/2`
3. Add policy evaluation result to audit log
4. Support policy rejection with detailed reason

**Estimated Effort**: 2-3 hours  
**Phase**: 4 (business logic completion)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

### GAP-007: CerebrosNASSaga - Synchronous Polling Pattern

**File**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex`  
**Step**: `await_completion` (line ~200-240)  
**Current State**: Synchronous polling (5s interval, 300s max timeout)

```elixir
defp await_training_completion(run_id, max_wait, poll_interval) do
  # Synchronous polling loop with 5s interval
  Stream.iterate(0, &(&1 + 1))
  |> Enum.reduce_while(nil, fn _iteration, _acc ->
    # Poll every 5 seconds for up to 300 seconds
  end)
end
```

**Impact**: 🟢 **LOW**
- Blocks saga execution for up to 5 minutes
- Inefficient use of BEAM processes
- Scales poorly with concurrent NAS runs

**Blast Radius**: Internal (saga execution model)

**Recommendation**:
1. Migrate to async/event-driven completion pattern
2. Use Oban job to periodically check training status
3. Add webhook endpoint for Cerebros bridge to signal completion
4. Resume saga via `Reactor.continue/2` when training completes

**Estimated Effort**: 4-6 hours  
**Phase**: 4 or later (architectural improvement)  
**Assignee**: TBD  
**Status**: 🔴 Not Started

---

## Summary Statistics

**Compensation Gaps**: 7 total
- 🔴 Not Started: 7 (100%)
- 🟡 In Progress: 0 (0%)
- ✅ Complete: 0 (0%)

**Taxonomy Drift Gaps**: 4 total
- ✅ Complete: 3 (75%) - DRIFT-001, 002, 003
- 🔴 Not Started: 1 (25%) - DRIFT-004 (causation_id architecture)

**By Priority**:
- Critical (P1): 2 (GAP-001, GAP-002)
- Important (P2): 2 (GAP-003, GAP-004)
- Minor (P3): 3 (GAP-005, GAP-006, GAP-007)

**By Type**:
- Stubbed Compensations: 3 (GAP-001, GAP-002, GAP-003)
- Missing Correlation ID: 1 (GAP-004) - pending code inspection
- Incomplete Features: 2 (GAP-005, GAP-006)
- Architectural Debt: 1 (GAP-007)
- Taxonomy Drift: 3 resolved (DRIFT-001, 002, 003), 1 open (DRIFT-004)
- 🟡 In Progress: 0 (0%)
- 🟢 Complete: 0 (0%)

---

## Phase 3 Recommended Prioritization

### Week 1 (Must-Fix) - 🔄 **PARTIALLY COMPLETE**
1. **GAP-001** - CerebrosNASSaga training cancellation (2-3 hours) - 🔴 Not Started
2. **GAP-002** - UPMActivationSaga adapter rollback (2-3 hours) - 🔴 Not Started
3. **GAP-004** - MagicLinkSender correlation ID (1 hour) - 🔴 Not Started

**Total Effort**: 5-7 hours  
**Status**: 0/3 complete (DRIFT taxonomy gaps completed separately)

### Week 2 (Should-Fix)
4. **GAP-003** - Community cleanup (1-2 hours) - 🔴 Not Started
5. **GAP-006** - ThunderCrown policy wiring (2-3 hours) - 🔴 Not Started

**Total Effort**: 3-5 hours

### Future (Nice-to-Have)
6. **GAP-005** - ModelVersion persistence (2-3 hours) - 🔴 Not Started
7. **GAP-007** - Async completion pattern (4-6 hours) - 🔴 Not Started

**Total Effort**: 6-9 hours

### Taxonomy Drift (Documentation) - ✅ **COMPLETE**
8. **DRIFT-001** - user.onboarding.complete - ✅ **COMPLETE** (Oct 28, 2025)
9. **DRIFT-002** - ai.upm.snapshot.activated - ✅ **COMPLETE** (Oct 28, 2025)
10. **DRIFT-003** - ml.run.complete name mismatch - ✅ **COMPLETE** (Oct 28, 2025)
11. **DRIFT-004** - causation_id architecture - 🔴 Not Started (2 hours, distinct from correlation_id)

**Taxonomy Progress**: 3/4 drift gaps resolved (75% complete)

---

## Notes

- All gaps discovered during **OPERATION SAGA CONCORDIA Phase 2** (Task 2.1 - Saga Inventory)
- Gaps flagged with `TODO` comments in source code
- No gaps are currently blocking production (all sagas operational)
- Gaps primarily affect error recovery paths and observability
- Recommend addressing P1 gaps before Phase 4 checkpoint

---

**Last Updated**: October 27, 2025  
**Next Review**: Phase 3 kickoff (Fri Oct 31, 2025)


## Taxonomy Drift Gaps (Event Conformance)

Discovered during **Task 2.2 - Event Conformance Audit** against EVENT_TAXONOMY.md v0.2

### DRIFT-001: user.onboarding.complete - Missing from Registry

**File**: `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex:219`  
**Event**: `user.onboarding.complete`  
**Issue**: ✅ **RESOLVED** (Oct 28, 2025 - Phase 3 Week 2 Task 3)

**Impact**: 🟡 **MEDIUM** (was: validation failure, discoverability gap)

**Resolution**:
✅ Added to EVENT_TAXONOMY.md Section 7 (line 106) with full schema:
```yaml
name: "user.onboarding.complete"
version: 1
description: "User completes onboarding (email verified, vault provisioned, community created)"
payload_schema:
  user_id: {type: uuid, required: true}
  email: {type: binary, required: true}
  vault_id: {type: uuid, required: true}
reliability: persistent
```

**Estimated Effort**: 30 minutes (ACTUAL: completed as part of EVENT_TAXONOMY.md finalization)  
**Phase**: 3  
**Status**: ✅ **COMPLETE**

---

### DRIFT-002: ai.upm.snapshot.activated - Missing from Registry

**File**: `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex:255`  
**Event**: `ai.upm.snapshot.activated`  
**Issue**: ✅ **RESOLVED** (Oct 28, 2025 - Phase 3 Week 2 Task 3)

**Impact**: 🟡 **MEDIUM** (was: validation failure, discoverability gap)

**Resolution**:
✅ Added to EVENT_TAXONOMY.md Section 7 (line 107) with full schema:
```yaml
name: "ai.upm.snapshot.activated"
version: 1
description: "UPM snapshot promoted to active (all adapters synchronized)"
payload_schema:
  snapshot_id: {type: uuid, required: true}
  activated_at: {type: datetime, required: true}
  adapter_count: {type: integer, required: true}
reliability: transient
```

**Estimated Effort**: 30 minutes (ACTUAL: completed as part of EVENT_TAXONOMY.md finalization)  
**Phase**: 3  
**Status**: ✅ **COMPLETE**

---

### DRIFT-003: ml.run.complete - Name Mismatch

**File**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex:256`  
**Event**: `ml.run.complete`  
**Issue**: ✅ **RESOLVED** (Oct 28, 2025 - Phase 3 Week 2 Task 3)

**Impact**: 🔴 **HIGH** (was: validation failure, event name mismatch, consumer confusion)

**Resolution**:
✅ EVENT_TAXONOMY.md canonicalized to `ml.run.completed` (past tense) in Section 7 (lines 79, 100):
- Category prefix confirmed: `ml.run` 
- Canonical name: `ml.run.completed`
- Saga code updated to match taxonomy (verified via grep)

**Estimated Effort**: 15 minutes (ACTUAL: completed as part of EVENT_TAXONOMY.md finalization)  
**Phase**: 3  
**Status**: ✅ **COMPLETE**

---

### DRIFT-004: Saga Causation Chain - Missing causation_id

**Files**: All 3 sagas (UserProvisioningSaga, UPMActivationSaga, CerebrosNASSaga)  
**Issue**: All saga events set `causation_id: nil` (assumes saga is flow origin)

**NOTE**: This is DISTINCT from `correlation_id` (which was completed in Phase 3 Week 2). `causation_id` tracks parent→child event relationships, while `correlation_id` tracks request flow across services.

**Impact**: 🟡 **MEDIUM**
- Event causality chain broken when saga triggered by upstream events
- Cannot trace saga execution back to triggering UI command or system event
- Distributed tracing incomplete (temporal but not causal)

**Recommendation**:
Add `causation_id` to saga inputs:
```elixir
# Accept causation_id as saga input (inherit from triggering event)
def run(input, context) do
  correlation_id = input.correlation_id || UUID.uuid4()
  causation_id = input.causation_id  # NEW: inherit from parent event
  
  EventBus.publish_event(%{
    correlation_id: correlation_id,
    causation_id: causation_id,  # Link to triggering event
    ...
  })
end
```

**Estimated Effort**: 2 hours (update all 3 sagas + call sites)  
**Phase**: 3  
**Status**: 🔴 Not Started

---

---

## Build Environment Notes

### torchx Compilation Issue (Resolved - Oct 27, 2024)

**Issue**: torchx 0.10.2 incompatible with PyTorch 2.8.0 (missing `ATen/BatchedTensorImpl.h` header)

**Impact**: Blocked all compilation, preventing Phase 2 Task 2.3 (Correlation ID Audit)

**Resolution**: Commented out torchx dependency in mix.exs
- torchx is one of 4 ML backends (LocalNx, CerebrosPy, EXLA, Torchx)
- Not currently used in saga code
- Can be re-enabled when torchx updates for PyTorch 2.8.0+ compatibility

**File Modified**: `mix.exs:142` - torchx dependency commented out

**Status**: ✅ Resolved - compilation successful, warnings only (expected undefined modules)

---

**Document Last Updated**: October 28, 2025 (Post-Phase 3 Week 2 review)  
**Next Review**: Phase 3 Week 3 (address remaining compensation gaps + DRIFT-004 causation_id)
