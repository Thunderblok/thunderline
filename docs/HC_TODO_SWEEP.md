# HC TODO Sweep - Technical Debt Remediation Tracker

**Created**: 2025-01-XX (HC Review Response)  
**Status**: IN PROGRESS  
**Context**: High Command external review identified loose ends across the codebase

---

## Executive Summary

This document tracks the systematic cleanup of TODOs, stub implementations, and domain naming inconsistencies identified in the HC external review.

---

## ✅ COMPLETED: Domain Consolidation (HC-49)

### Thunderchief → Thundercrown Migration

**Status**: ✅ COMPLETE

**Changes Made**:
1. Created `lib/thunderline/thundercrown/orchestrator.ex` with consolidated orchestration logic
2. Deleted `lib/thunderline/thunderchief/` directory (orchestrator.ex + workers/demo_job.ex)
3. Updated all references from `Thunderchief` → `Thundercrown`:
   - [event_pipeline.ex](lib/thunderline/thunderflow/pipelines/event_pipeline.ex) - Domain inference, Orchestrator call
   - [event_bus.ex](lib/thunderline/thunderflow/event_bus.ex) - Topic patterns
   - [dashboard_metrics.ex](lib/thunderline/thunderlink/dashboard_metrics.ex) - Metrics function renamed
   - [orchestration_ui.ex](lib/thunderline/thundercrown/resources/orchestration_ui.ex) - Orchestrator call
   - [router.ex](lib/thunderline_web/router.ex) - Route redirect
   - [dashboard_live.ex](lib/thunderline_web/live/dashboard_live.ex) - Domain metrics
   - [domain_panel.ex](lib/thunderline_web/live/components/domain_panel.ex) - UI panel
   - [domain_status.ex](lib/thunderline_web/live/components/dashboard/domain_status.ex) - Icon mapping
   - [domain_stats_controller.ex](lib/thunderline_web/controllers/domain_stats_controller.ex) - Stats API
   - [broadway_monitoring.ex](lib/thunderline/thunderflow/broadway_monitoring.ex) - Test events
   - [event_ops.ex](lib/thunderline/thunderflow/resources/event_ops.ex) - Event processing
   - [event_stream.ex](lib/thunderline/thunderflow/resources/event_stream.ex) - Domain constraints

**Backward Compatibility**:
- `/thunderchief` route redirects to `/thundercrown` 
- `thunderchief_metrics/0` deprecated, delegates to `thundercrown_metrics/0`

---

## 🟡 P1: High - Ash 3.x Syntax Updates

### Validation Syntax Issues

**Pattern**: Many resources use old Ash 2.x validation syntax that needs updating.

**Affected Files**:
| File | Issue |
|------|-------|
| `lib/thunderline/thundergrid/resources/zone_boundary.ex` | Lines 55, 63, 281 - route syntax |
| `lib/thunderline/thundergrid/resources/spatial_coordinate.ex` | Lines 51, 57, 281 - route syntax |
| `lib/thunderline/thunderblock/resources/*.ex` | Policy and validation TODOs |
| `lib/thunderline/thunderlink/resources/*.ex` | Fragment expression TODOs |

### AshOban Integration

**Pattern**: Several resources have AshOban TODOs for proper job integration.

---

## 🟡 P1: High - Saga Compensation Stubs

### Incomplete Compensations

**Pattern**: Reactor sagas have compensation stubs that need full implementation.

| File | Lines | Issue |
|------|-------|-------|
| `lib/thunderline/thunderbolt/sagas/cerebros_nas_saga.ex` | 170, 224 | Compensation stubs |
| `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex` | 117, 226 | Policy wiring stubs |
| `lib/thunderline/thunderbolt/sagas/user_provisioning_saga.ex` | 222, 229 | ThunderLink wiring stubs |

---

## 🟢 P2: Medium - Stub Implementations

### Topology & Grid

| File | Issue |
|------|-------|
| `lib/thunderline/thunderbolt/topology_partitioner.ex` | Line 5 - "TODO: Implement real 3D partitioning" |
| `lib/thunderline/thundergate/federation_socket.ex` | Stub implementation |

### ML Integration

| File | Issue |
|------|-------|
| `lib/thunderline/thunderbolt/resources/activation_rule.ex` | Lines 239, 265, 298 - ML model stubs |
| `lib/thunderline/thunderblock/resources/chunk_health.ex` | ML integration placeholders |

---

## 🔵 P3: Low - Documentation & Metrics

### Dashboard Metrics

The `dashboard_metrics.ex` file has many `"OFFLINE"` placeholders that need real implementations:
- CPU monitoring
- Memory tracking
- Process counting
- Inference rate tracking
- Model accuracy monitoring

### Documentation TODOs

Files in `docs/` with TODOs:
- `docs/ml-ai/` - Multiple ML integration docs
- `docs/architecture/` - Compensation gaps documentation

---

## Progress Tracking

### Completed
- [x] Initial TODO sweep
- [x] Legacy domain identification
- [x] Created this tracking document

### In Progress
- [ ] Thunderchief → Thundercrown consolidation

### Pending
- [ ] Ash 3.x syntax fixes
- [ ] Saga compensation completion
- [ ] ML integration stubs
- [ ] Dashboard metrics implementation

---

## Review Notes

From HC External Review:
> "more than a dozen files contain TODOs or incomplete sections, indicating many areas of the system are still under construction"

> "Domain fragmentation & naming inconsistencies – The codebase still references old domain names (e.g., separate Thunderchief and Thundercrown implementations)"

This sweep addresses both concerns systematically.
