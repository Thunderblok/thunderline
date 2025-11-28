# HC TODO Sweep - Technical Debt Remediation Tracker

**Created**: November 28, 2025 (HC Review Response)  
**Status**: IN PROGRESS  
**Context**: High Command external review identified loose ends across the codebase

**Related Documents**:
- [HC_ARCHITECTURE_SYNTHESIS.md](HC_ARCHITECTURE_SYNTHESIS.md) - Full HC architecture consolidation
- [THUNDERLINE_MASTER_PLAYBOOK.md](../THUNDERLINE_MASTER_PLAYBOOK.md) - Master playbook

---

## Executive Summary

This document tracks the systematic cleanup of TODOs, stub implementations, and domain naming inconsistencies identified in the HC external review.

### Quick Stats
- **P0 Critical**: 1 completed (HC-49 Domain Consolidation)
- **P1 High**: ~15 items (Ash 3.x, Saga stubs)
- **P2 Medium**: ~10 items (Stubs, ML integration)
- **P3 Low**: ~30 items (Dashboard metrics, docs)

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

---

## 🆕 NEW: HC Architecture Directives (Nov 28, 2025)

The following HC items were extracted from High Command strategic discussions and documented in [HC_ARCHITECTURE_SYNTHESIS.md](HC_ARCHITECTURE_SYNTHESIS.md):

### HC-60: Thunderbit Resource & Stepper
**Priority**: P1 | **Owner**: Bolt Steward | **Status**: Not Started

Create foundational Thunderbit infrastructure:
- [ ] `Thunderbolt.Thunderbit` struct with full state vector
- [ ] `Thunderbolt.CA.Stepper` basic CA step execution
- [ ] `Thunderbolt.CA.Neighborhood` 3D neighborhood computation
- [ ] Unit tests: state evolution, neighborhood

### HC-61: CAT Transform Primitives
**Priority**: P1 | **Owner**: Bolt Steward | **Status**: Not Started

Implement Cellular Automata Transforms:
- [ ] `Thunderbolt.CATTransform` module
- [ ] Basis function generation from CA evolution
- [ ] Forward/inverse transform
- [ ] Compression mode (sparse coefficients)
- [ ] Unit tests: orthogonality, reconstruction

### HC-62: NCA Kernel Infrastructure
**Priority**: P1 | **Owner**: Bolt Steward | **Status**: Not Started

Neural CA kernel system:
- [ ] `Thunderbolt.NCAKernel` Ash resource
- [ ] `Thunderbolt.NCAEngine.step/3` execution
- [ ] ONNX integration via Ortex
- [ ] Training curriculum (signal propagation task)
- [ ] Telemetry: `[:thunderline, :bolt, :nca, :*]`

### HC-63: LCA Kernel Infrastructure  
**Priority**: P1 | **Owner**: Bolt Steward | **Status**: Not Started

Latent CA (mesh-agnostic) kernels:
- [ ] `Thunderbolt.LCAKernel` Ash resource
- [ ] `Thunderbolt.LCAEngine.step/2`
- [ ] kNN graph construction
- [ ] Embedding network execution
- [ ] Unit tests: mesh-agnostic operation

### HC-64: TPE Search Space Extension
**Priority**: P2 | **Owner**: Bolt + Crown Stewards | **Status**: Not Started

Extend Cerebros TPE for CAT/NCA:
- [ ] CAT hyperparameter definitions (rule_id, dims, alphabet, radius, window, time_depth)
- [ ] NCA/LCA hyperparameter definitions
- [ ] Cerebros bridge extensions
- [ ] Trial lifecycle events

### HC-65: Training Loop Integration
**Priority**: P2 | **Owner**: Bolt Steward | **Status**: Not Started

Complete training pipeline:
- [ ] Multi-task curriculum definition
- [ ] LoopMonitor as auxiliary loss
- [ ] Kernel registration on success
- [ ] Telemetry dashboards

### HC-66: Co-Lex Ordering Service
**Priority**: P2 | **Owner**: Bolt + Block Stewards | **Status**: Not Started

O(n) space, O(1) time state ordering:
- [ ] Forward-stable reduction (Paige-Tarjan)
- [ ] Co-lex extension computation (Becker et al.)
- [ ] Infimum/supremum graphs + Forward Visit
- [ ] Conflict depth arrays (φ, ψ)
- [ ] `Thunderbolt.CoLex.compare/3` O(1) comparator
- [ ] Integration with Thundervine DAG

### HC-67: WebRTC Circuit Integration
**Priority**: P2 | **Owner**: Link + Bolt Stewards | **Status**: Not Started

Bridge CA routing to WebRTC:
- [ ] CA signaling → WebRTC establishment
- [ ] ICE over CA channel
- [ ] `Thunderlink.CACircuitManager` lifecycle
- [ ] Fallback/rerouting on path degradation

### HC-68: Security Layer
**Priority**: P2 | **Owner**: Gate + Bolt Stewards | **Status**: Not Started

CAT-based security:
- [ ] CAT encryption implementation
- [ ] Key fragment distribution across voxels
- [ ] Per-hop obfuscation
- [ ] Geometric secrecy validation

---

## Key Architecture Concepts (Reference)

### The CA Lattice Insight
> **"The CA is the map, not the carrier."**

The cellular automaton lattice handles:
- Routing paths
- Trust shapes
- Session-key diffusion
- Relay neighborhoods
- Load balancing

WebRTC/WebTransport handles actual payload transport.

### Thunderbit State Vector
Each voxel maintains: `{ϕ_phase, σ_flow, λ̂_sensitivity, trust_score, presence_vector, relay_weight, key_fragment}`

### Four Research Threads
1. **3D CA Lattice** → Routing oracle, presence fields
2. **Neural CA (NCA)** → Trainable universal compute
3. **Latent CA (LCA)** → Mesh-agnostic, any topology
4. **CAT Transforms** → Orthogonal basis, compression, crypto

See [HC_ARCHITECTURE_SYNTHESIS.md](HC_ARCHITECTURE_SYNTHESIS.md) for full details.
