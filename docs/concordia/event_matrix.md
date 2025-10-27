# OPERATION SAGA CONCORDIA - Event Conformance Audit

**Date**: Sunday, October 27, 2024  
**Task**: 2.2 - Event Conformance Audit  
**Status**: ⏳ IN PROGRESS  
**Reference**: `documentation/EVENT_TAXONOMY.md` v0.2

---

## Executive Summary

**Audit Scope**: 3 saga domain events + 7 reactor lifecycle events  
**Taxonomy Compliance**: **2 of 3 saga events NOT in canonical registry**  
**Critical Findings**:
- 2 custom events without registry entries (user.onboarding.complete, ai.upm.snapshot.activated)
- 1 name mismatch (ml.run.complete vs ml.run.completed)
- Domain/category compliance: ✅ ALL VALID (gate:system, bolt:ml.run, bolt:system)
- Reactor lifecycle events: ✅ ALL VALID (flow:flow.reactor compliant)

**Remediation Required**: Add 2 events to canonical registry OR flag as project-specific extensions

---

## 1. Saga Domain Events (3 total)

| Event Name | Saga | Type | Domain | Category | Registry Status | Domain Matrix | Drift |
|-----------|------|------|--------|----------|----------------|---------------|-------|
| `user.onboarding.complete` | UserProvisioningSaga | :user_lifecycle | `:gate` | `system` | ❌ MISSING | ✅ gate:system | **DRIFT-001** |
| `ai.upm.snapshot.activated` | UPMActivationSaga | :upm_lifecycle | `:bolt` | `system` | ❌ MISSING | ✅ bolt:system | **DRIFT-002** |
| `ml.run.complete` | CerebrosNASSaga | :ml_lifecycle | `:bolt` | `ml.run` | ⚠️ NAME MISMATCH | ✅ bolt:ml.run | **DRIFT-003** |

### 1.1 Event Details

#### DRIFT-001: `user.onboarding.complete`

**Location**: `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex:219`

**Current Implementation**:
```elixir
event_attrs = %{
  name: "user.onboarding.complete",
  type: :user_lifecycle,
  domain: :gate,
  source: "UserProvisioningSaga",
  correlation_id: correlation_id,
  payload: %{user_id: user.id, email: user.email, vault_id: vault.id},
  meta: %{pipeline: :cross_domain}
}
```

**Taxonomy Analysis**:
- **Namespace Parsing**: `user.onboarding.complete`
  - Expected format: `<layer>.<domain>.<category>.<action>[.<phase>]`
  - Parsed: layer=`user`, domain=`onboarding`, category=missing, action=`complete`
  - ⚠️ **Non-conformant namespace** (4 segments instead of 5)
- **Domain Matrix Check**: `:gate` → allowed categories: `[ui.command, system, presence, device]`
  - Event type: `:user_lifecycle` → maps to `system` category
  - ✅ **Matrix compliant** (gate:system is valid)
- **Registry Check**: ❌ **Not present** in canonical registry (Section 7)
- **Reliability**: `cross_domain` (persistent event)

**Suggested Remediation**:
```elixir
# Option A: Add to canonical registry (Section 7)
name: "user.onboarding.complete"
version: 1
description: "User completes onboarding flow (email verified, vault provisioned, default community created)"
source: "UserProvisioningSaga"
reliability: persistent
payload_schema:
  user_id: {type: uuid, required: true}
  email: {type: string, required: true}
  vault_id: {type: uuid, required: true}

# Option B: Use existing system namespace
name: "system.gate.user.onboarding.complete"
# Conforms to: <layer>.<domain>.<category>.<action>.<phase>
# Maps to: gate:system (valid per domain matrix)
```

**TODO[CONCORDIA]**: Add "user.onboarding.complete" to EVENT_TAXONOMY.md Section 7 OR refactor to "system.gate.user.onboarding.complete"

---

#### DRIFT-002: `ai.upm.snapshot.activated`

**Location**: `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex:255`

**Current Implementation**:
```elixir
event_attrs = %{
  name: "ai.upm.snapshot.activated",
  type: :upm_lifecycle,
  domain: :bolt,
  source: "UPMActivationSaga",
  correlation_id: correlation_id,
  payload: %{snapshot_id: snapshot.id, activated_at: snapshot.activated_at, adapter_count: adapters.count},
  meta: %{pipeline: :realtime}
}
```

**Taxonomy Analysis**:
- **Namespace Parsing**: `ai.upm.snapshot.activated`
  - Expected format: `<layer>.<domain>.<category>.<action>[.<phase>]`
  - Parsed: layer=`ai`, domain=`upm`, category=`snapshot`, action=`activated`
  - ✅ **Conformant namespace** (4-segment format, phase optional)
- **Domain Matrix Check**: `:bolt` → allowed categories: `[ml.run, system, pac, thundra]`
  - Event type: `:upm_lifecycle` → maps to `system` category
  - ✅ **Matrix compliant** (bolt:system is valid)
- **Registry Check**: ❌ **Not present** in canonical registry (Section 7)
- **Reliability**: `realtime` (transient event)

**Suggested Remediation**:
```elixir
# Add to canonical registry (Section 7)
name: "ai.upm.snapshot.activated"
version: 1
description: "Unified Persistent Model snapshot promoted to active (all adapters synchronized)"
source: "UPMActivationSaga"
reliability: transient
payload_schema:
  snapshot_id: {type: uuid, required: true}
  activated_at: {type: datetime, required: true}
  adapter_count: {type: integer, required: true}
```

**TODO[CONCORDIA]**: Add "ai.upm.snapshot.activated" to EVENT_TAXONOMY.md Section 7

---

#### DRIFT-003: `ml.run.complete` (NAME MISMATCH)

**Location**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex:256`

**Current Implementation**:
```elixir
event_attrs = %{
  name: "ml.run.complete",
  type: :ml_lifecycle,
  domain: :bolt,
  source: "CerebrosNASSaga",
  correlation_id: correlation_id,
  payload: %{run_id: run.id, best_model_id: model.id, best_score: model.score},
  meta: %{pipeline: :cross_domain}
}
```

**Taxonomy Analysis**:
- **Namespace Parsing**: `ml.run.complete`
  - Expected format: `<layer>.<domain>.<category>.<action>[.<phase>]`
  - Parsed: layer=`ml`, domain=`run`, category=missing, action=`complete`
  - ⚠️ **Non-conformant namespace** (3 segments instead of 4-5)
- **Domain Matrix Check**: `:bolt` → allowed categories: `[ml.run, system, pac, thundra]`
  - Event type: `:ml_lifecycle` → maps to `ml.run` category
  - ✅ **Matrix compliant** (bolt:ml.run is valid)
- **Registry Check**: ⚠️ **NAME MISMATCH**
  - Registry has: `ml.run.completed` (past tense)
  - Saga emits: `ml.run.complete` (present tense)
- **Reliability**: `cross_domain` (persistent event)

**Canonical Registry Entry** (Section 7):
```yaml
name: "ml.run.completed"
version: 1
description: "Machine learning run finishes (success or failure)"
source: "ThunderBolt.ML"
reliability: persistent
payload_schema:
  run_id: {type: uuid, required: true}
  status: {type: string, enum: [completed, failed], required: true}
  metrics: {type: map, required: false}
```

**Suggested Remediation**:
```elixir
# Option A: Update saga to match registry (RECOMMENDED)
name: "ml.run.completed"  # Change from "ml.run.complete"

# Option B: Update registry to use present tense
# (Less preferred - breaks existing consumers)
```

**TODO[CONCORDIA]**: Refactor CerebrosNASSaga to emit "ml.run.completed" (past tense per taxonomy standard)

---

## 2. Reactor Lifecycle Events (7 total)

**Source**: `lib/thunderline/thunderbolt/sagas/base.ex:160`

| Event Name | Category | Domain | Registry Status | Domain Matrix | Conformance |
|-----------|----------|--------|----------------|---------------|-------------|
| `reactor.saga.start` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.step.start` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.step.stop` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.step.exception` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.compensate` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.complete` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |
| `reactor.saga.fail` | `flow.reactor` | `:flow` | ❓ IMPLICIT | ✅ flow:flow.reactor | ✅ VALID |

### 2.1 Lifecycle Event Details

**Implementation**: `lib/thunderline/thunderbolt/sagas/base.ex:158-175`

```elixir
defp maybe_emit_event(event, saga_name, correlation_id, status) do
  if feature?(:reactor_events) do
    event_name = "reactor.saga.#{event}"

    event_attrs = %{
      name: event_name,
      type: :saga_lifecycle,
      domain: :flow,
      source: "Reactor.Saga.#{saga_name}",
      correlation_id: correlation_id,
      payload: %{saga_name: saga_name, status: status},
      meta: %{pipeline: :realtime}
    }

    EventBus.publish_event(event_attrs)
  end
end
```

**Taxonomy Analysis**:
- **Namespace Parsing**: `reactor.saga.<event>`
  - Format matches: `<layer>.<domain>.<category>.<action>`
  - layer=`reactor`, domain=`saga`, category=`flow.reactor` (implicit), action=variable
  - ⚠️ **Namespace ambiguity** (3 segments vs expected 4-5)
- **Domain Matrix Check**: `:flow` → allowed categories: `[flow.reactor, system]`
  - Event type: `:saga_lifecycle` → maps to `flow.reactor` category
  - ✅ **Matrix compliant** (flow:flow.reactor is valid)
- **Registry Check**: ❓ **Not explicitly listed** (framework events, implicitly valid)
- **Reliability**: `realtime` (transient events)
- **Feature Flag**: Gated behind `feature?(:reactor_events)` (currently disabled by default)

**Conformance Assessment**: ✅ **VALID**
- Reactor lifecycle events are framework-level orchestration events
- Domain matrix compliance: flow:flow.reactor is explicitly allowed
- Not listed in canonical registry (Section 7) because they are infrastructure events
- Recommendation: No changes needed (implicit framework events)

---

## 3. Domain Matrix Compliance Summary

**Reference**: EVENT_TAXONOMY.md Section 12

| Saga | Domain | Event Category | Matrix Entry | Allowed? | Conformance |
|------|--------|---------------|--------------|----------|-------------|
| UserProvisioningSaga | `:gate` | `system` | gate:system | ✅ YES | ✅ COMPLIANT |
| UPMActivationSaga | `:bolt` | `system` | bolt:system | ✅ YES | ✅ COMPLIANT |
| CerebrosNASSaga | `:bolt` | `ml.run` | bolt:ml.run | ✅ YES | ✅ COMPLIANT |
| Base (all sagas) | `:flow` | `flow.reactor` | flow:flow.reactor | ✅ YES | ✅ COMPLIANT |

**Domain Matrix Extract**:
```
:gate  → [ui.command, system, presence, device]
:bolt  → [ml.run, system, pac, thundra]
:flow  → [flow.reactor, system]
:crown → [ai.intent, system, pac]
:block → [system, pac]
:link  → [ui.command, system, voice.signal, voice.room, device]
:bridge → [system, ui.command]
```

**Conclusion**: ✅ **ALL DOMAIN/CATEGORY PAIRINGS VALID** per Section 12 matrix

---

## 4. Correlation/Causation Compliance

**Reference**: EVENT_TAXONOMY.md Section 13

### 4.1 Saga Event Emission Pattern

**All Sagas Follow This Pattern**:
```elixir
# Step 1: Accept correlation_id as saga input
def run(input, context) do
  correlation_id = input.correlation_id || UUID.uuid4()
  
  # Step 2: Propagate to all steps via Reactor context
  Reactor.run(steps, %{correlation_id: correlation_id}, context)
  
  # Step 3: Final event emission includes correlation_id
  EventBus.publish_event(%{
    name: "...",
    correlation_id: correlation_id,  # From saga input
    causation_id: nil,  # First event in saga flow
    ...
  })
end
```

### 4.2 Correlation Rule Compliance

**Rule**: "First event in a flow sets `correlation_id = id`, `causation_id = nil`. Derived events inherit correlation_id and set `causation_id = parent.id`"

**Saga Implementation**:
- ✅ **Correlation ID**: Propagated from saga input to final event
- ⚠️ **Causation ID**: Set to `nil` (assumes saga is first in flow)
- **Issue**: Sagas may be triggered by other events (e.g., UI command), should inherit causation chain

**Gap Identified**: Saga events assume they are flow origins (`causation_id: nil`), but may be responses to upstream events

**Recommendation**:
```elixir
# Accept both correlation_id AND causation_id as saga inputs
def run(input, context) do
  correlation_id = input.correlation_id || UUID.uuid4()
  causation_id = input.causation_id  # Inherit from triggering event
  
  EventBus.publish_event(%{
    correlation_id: correlation_id,
    causation_id: causation_id,  # Link to parent event
    ...
  })
end
```

**TODO[CONCORDIA]**: Add `causation_id` to saga inputs for proper event causality chain

---

## 5. Reliability Semantics

**Reference**: EVENT_TAXONOMY.md Section 8

| Event Name | Saga Pipeline | Expected Reliability | Conformance |
|-----------|--------------|---------------------|-------------|
| `user.onboarding.complete` | `cross_domain` | **persistent** | ✅ CORRECT |
| `ai.upm.snapshot.activated` | `realtime` | **transient** | ✅ CORRECT |
| `ml.run.complete` | `cross_domain` | **persistent** | ✅ CORRECT |
| `reactor.saga.*` | `realtime` | **transient** | ✅ CORRECT |

**Reliability Mapping**:
- `meta: %{pipeline: :cross_domain}` → persistent (durable, replayed)
- `meta: %{pipeline: :realtime}` → transient (ephemeral, not replayed)
- `meta: %{pipeline: :general}` → persistent (default)

**Conclusion**: ✅ **ALL EVENTS CORRECTLY CLASSIFIED** for reliability semantics

---

## 6. Linting Validation (Theoretical)

**Reference**: EVENT_TAXONOMY.md Section 14 - `mix thunderline.events.lint`

### 6.1 Expected Lint Failures (Current State)

```bash
$ mix thunderline.events.lint --warnings-as-errors

ERROR: lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex:219
  Event "user.onboarding.complete" not found in canonical registry
  → Add to documentation/EVENT_TAXONOMY.md Section 7 OR refactor namespace

ERROR: lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex:255
  Event "ai.upm.snapshot.activated" not found in canonical registry
  → Add to documentation/EVENT_TAXONOMY.md Section 7

ERROR: lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex:256
  Event "ml.run.complete" not found in canonical registry
  → Did you mean "ml.run.completed"? (name mismatch)

WARNINGS: 0
ERRORS: 3
Exit code: 1
```

### 6.2 Post-Remediation Expected Output

```bash
$ mix thunderline.events.lint --warnings-as-errors

✅ All events validated
✅ Domain/category matrix compliance: 100%
✅ Correlation/causation rules: 100%
✅ Payload schema validation: PASSED
✅ Reliability semantics: PASSED

WARNINGS: 0
ERRORS: 0
Exit code: 0
```

---

## 7. Taxonomy Drift Summary

### 7.1 Critical Drifts (3 total)

| Drift ID | Event Name | Issue | Priority | Effort | Status |
|---------|-----------|-------|----------|--------|--------|
| **DRIFT-001** | `user.onboarding.complete` | Not in registry | P2 | 30 min | ⏳ OPEN |
| **DRIFT-002** | `ai.upm.snapshot.activated` | Not in registry | P2 | 30 min | ⏳ OPEN |
| **DRIFT-003** | `ml.run.complete` | Name mismatch (vs "ml.run.completed") | P1 | 15 min | ⏳ OPEN |

### 7.2 Remediation Plan

**DRIFT-001: user.onboarding.complete**
- **Action**: Add to EVENT_TAXONOMY.md Section 7 canonical registry
- **Schema**:
  ```yaml
  name: "user.onboarding.complete"
  version: 1
  description: "User completes onboarding (email verified, vault provisioned, community created)"
  source: "UserProvisioningSaga"
  reliability: persistent
  payload_schema:
    user_id: {type: uuid, required: true}
    email: {type: string, required: true}
    vault_id: {type: uuid, required: true}
  ```
- **Effort**: ~30 minutes (add to registry + CI validation)
- **Acceptance**: `mix thunderline.events.lint` passes for this event

**DRIFT-002: ai.upm.snapshot.activated**
- **Action**: Add to EVENT_TAXONOMY.md Section 7 canonical registry
- **Schema**:
  ```yaml
  name: "ai.upm.snapshot.activated"
  version: 1
  description: "UPM snapshot promoted to active (all adapters synchronized)"
  source: "UPMActivationSaga"
  reliability: transient
  payload_schema:
    snapshot_id: {type: uuid, required: true}
    activated_at: {type: datetime, required: true}
    adapter_count: {type: integer, required: true}
  ```
- **Effort**: ~30 minutes (add to registry + CI validation)
- **Acceptance**: `mix thunderline.events.lint` passes for this event

**DRIFT-003: ml.run.complete → ml.run.completed**
- **Action**: Refactor saga to emit "ml.run.completed" (past tense)
- **Change**: `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex:256`
  ```elixir
  # BEFORE
  name: "ml.run.complete",
  
  # AFTER
  name: "ml.run.completed",  # Match canonical registry
  ```
- **Effort**: ~15 minutes (code change + test update)
- **Acceptance**: `mix thunderline.events.lint` passes, event matches registry

**Total Remediation Effort**: ~1.25 hours (can be completed in Phase 3)

---

## 8. Phase 2 Recommendations

### 8.1 Immediate Actions (Phase 2 Complete)

1. ✅ **Document drifts** in this file (event_matrix.md)
2. ✅ **Flag with TODO[CONCORDIA]** in source code
3. ✅ **Add to compensation_gaps.md** as DRIFT tracking

### 8.2 Phase 3 Remediation (Post-IRON_TIDE-003)

1. **Taxonomy Updates** (~1 hour):
   - Add "user.onboarding.complete" to EVENT_TAXONOMY.md Section 7
   - Add "ai.upm.snapshot.activated" to EVENT_TAXONOMY.md Section 7
   - Update domain matrix if needed (currently compliant)

2. **Code Refactoring** (~30 minutes):
   - Refactor CerebrosNASSaga: "ml.run.complete" → "ml.run.completed"
   - Update tests to match new event name
   - Run `mix thunderline.events.lint` to verify

3. **Causation Chain Enhancement** (~2 hours):
   - Add `causation_id` to saga inputs (all 3 sagas)
   - Update saga call sites to pass triggering event ID
   - Verify correlation/causation chain in event DAG

4. **CI Integration** (~1 hour):
   - Enable `mix thunderline.events.lint --warnings-as-errors` in CI
   - Add pre-commit hook for event validation
   - Document linting in CONTRIBUTING.md

**Total Phase 3 Effort**: ~4.5 hours

---

## 9. Conclusion

**Task 2.2 Status**: ✅ **COMPLETE**

**Key Findings**:
- ✅ **Domain/Category Compliance**: 100% (all events valid per Section 12 matrix)
- ⚠️ **Registry Compliance**: 33% (1 of 3 saga events in registry, with name mismatch)
- ⚠️ **Taxonomy Drift**: 3 drifts identified (2 missing, 1 name mismatch)
- ✅ **Reliability Semantics**: 100% (all events correctly classified)
- ⚠️ **Correlation/Causation**: Partial (correlation compliant, causation assumed nil)

**Deliverable**: `/docs/concordia/event_matrix.md` (this file)

**Next Steps**:
- Task 2.3: Correlation ID audit (verify step-to-step propagation)
- Phase 3: Remediate taxonomy drifts (~4.5 hours)
- CI: Enable `mix thunderline.events.lint --warnings-as-errors`

**Quality Gates for Phase 2 Complete**:
- ✅ Saga inventory complete (saga_inventory.md)
- ✅ Event conformance audit complete (event_matrix.md)
- ⏳ Correlation ID audit (Task 2.3 pending)
- ⏳ All 3 deliverables committed + IRON_TIDE-003 tag

---

**Generated**: Sunday, October 27, 2024  
**Author**: OPERATION SAGA CONCORDIA - Phase 2 Agent  
**Taxonomy Version**: v0.2 (documentation/EVENT_TAXONOMY.md)
