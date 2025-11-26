# HC-22 Unified Persistent Model - Implementation Status

**Last Updated**: 2025-01-09  
**Status**: ~70% Complete (Core infrastructure ready)  
**Blocker**: M1-EMAIL-AUTOMATION milestone

---

## 🎯 Executive Summary

The Unified Persistent Model (UPM) provides online learning infrastructure for ThunderBolt agents, enabling continuous model improvement through incremental training, shadow validation, and controlled rollout phases (shadow → canary → global).

**Core Components Implemented** (7/10):
- ✅ TrainerWorker - Online training loop with SGD updates
- ✅ ReplayBuffer - Out-of-order event handling & deduplication
- ✅ SnapshotManager - Persistence with compression & checksums
- ✅ DriftMonitor - Shadow comparison & quarantine triggers
- ✅ AdapterSync - Snapshot distribution to agents
- ✅ UPM.Supervisor - Dynamic trainer management
- ✅ Application Integration - Feature-flagged wiring
- ⏳ EventBus Subscriptions (required)
- ⏳ ThunderCrown Policies (required)
- ⏳ Test Suite (required)

**Key Metrics**:
- ~2,400 lines of production code
- 8 telemetry event types instrumented
- 5 EventBus contracts defined
- 0 compilation errors (warnings only)

---

## 📂 File Structure

```
lib/thunderline/thunderbolt/upm/
├── trainer_worker.ex      (460 lines) - Core training loop
├── replay_buffer.ex       (340 lines) - Event ordering & deduplication
├── snapshot_manager.ex    (450 lines) - Persistence & activation
├── drift_monitor.ex       (432 lines) - Shadow comparison & safety
├── adapter_sync.ex        (370 lines) - Distribution to agents
└── supervisor.ex          (350 lines) - Dynamic trainer supervision

lib/mix/tasks/
└── thunderline.upm.validate.ex (360 lines) - Configuration validation

lib/thunderline/
└── application.ex         (modified) - UPM integration

Existing (not modified):
lib/thunderline/thunderbolt/resources/
├── upm_trainer.ex
├── upm_snapshot.ex
├── upm_adapter.ex
└── upm_drift_window.ex

priv/repo/migrations/
└── 20251003190000_create_upm_tables.exs
```

---

## 🏗️ Architecture

### Training Pipeline

```
ThunderFlow (feature windows)
       ↓
ReplayBuffer (ordering + dedup)
       ↓
TrainerWorker (SGD updates)
       ↓
SnapshotManager (persistence)
       ↓
AdapterSync (distribution)
       ↓
ThunderBlock Agents (inference)
```

### Safety Layer

```
Shadow Predictions ──┐
                     ├─→ DriftMonitor → Quarantine Trigger
Ground Truth ────────┘                   ↓
                                   ThunderCrown Policy
                                         ↓
                                   Rollback or Continue
```

### Supervision Tree

```
Thunderline.Application
└── UPM.Supervisor (if :unified_model enabled)
    ├── TrainersSupervisor (DynamicSupervisor)
    │   └── [Per-Trainer Supervision Trees]
    │       ├── TrainerWorker
    │       └── DriftMonitor
    └── AdapterSync (global)
```

---

## 🔧 Configuration

### Feature Flag

```elixir
# config/runtime.exs
config :thunderline, :features, %{
  unified_model: System.get_env("TL_FEATURES_UNIFIED_MODEL") == "1"
}
```

### Worker Configuration

```elixir
# TrainerWorker
config :thunderline, Thunderline.Thunderbolt.UPM.TrainerWorker,
  snapshot_interval: 1000,        # Create snapshot every N windows
  learning_rate: 0.001,
  batch_size: 32

# ReplayBuffer
config :thunderline, Thunderline.Thunderbolt.UPM.ReplayBuffer,
  max_buffer_size: 1000,          # Max windows buffered
  release_delay_ms: 5000,         # Delay before releasing sequence
  late_window_tolerance_ms: 60_000  # 1 minute tolerance

# SnapshotManager
config :thunderline, Thunderline.Thunderbolt.UPM.SnapshotManager,
  base_path: "/data/thunderline/upm/snapshots",
  compression: :zstd,             # :zstd | :gzip | :none
  retention_days: 30

# DriftMonitor
config :thunderline, Thunderline.Thunderbolt.UPM.DriftMonitor,
  window_duration_ms: 3_600_000,  # 1 hour windows
  drift_threshold: 0.2,           # P95 threshold for quarantine
  sample_size: 1000,              # Min samples before evaluation
  quarantine_enabled: true

# AdapterSync
config :thunderline, Thunderline.Thunderbolt.UPM.AdapterSync,
  sync_batch_size: 100,           # Adapters per batch
  sync_timeout_ms: 30_000,
  max_retries: 3,
  retry_backoff_ms: 1000

# Default Trainers
config :thunderline, Thunderline.Thunderbolt.UPM.Supervisor,
  enabled: true,
  default_trainers: [
    [name: "default", mode: :shadow, tenant_id: nil]
  ]
```

---

## 📊 Telemetry Events

### Trainer Events
```elixir
[:upm, :trainer, :update]
  %{loss: float, duration_ms: integer, window_count: integer}

[:upm, :trainer, :snapshot]
  %{snapshot_id: binary, version: integer, size_bytes: integer}
```

### Replay Buffer Events
```elixir
[:upm, :replay_buffer, :add]
  %{window_id: binary, buffer_size: integer}

[:upm, :replay_buffer, :release]
  %{count: integer, sequence_start: DateTime, sequence_end: DateTime}

[:upm, :replay_buffer, :duplicate]
  %{window_id: binary}

[:upm, :replay_buffer, :late_arrival]
  %{window_id: binary, delay_ms: integer}
```

### Drift Monitor Events
```elixir
[:upm, :drift, :score]
  %{drift_p95: float, drift_mean: float, drift_max: float, sample_count: integer}

[:upm, :drift, :quarantine]
  %{trainer_id: binary, drift_p95: float, threshold: float}
```

### Adapter Sync Events
```elixir
[:upm, :adapter, :sync, :start]
  %{snapshot_id: binary, adapter_count: integer}

[:upm, :adapter, :sync, :success]
  %{adapter_id: binary, snapshot_id: binary, duration_ms: integer}

[:upm, :adapter, :sync, :failure]
  %{adapter_id: binary, snapshot_id: binary, reason: term, retry_count: integer}
```

---

## 🔁 EventBus Contracts

### Consumed Events
```elixir
system.feature_window.created (ThunderFlow → TrainerWorker)
  %{
    window_id: binary,
    window_start: DateTime,
    window_end: DateTime,
    features: map,
    tenant_id: binary | nil
  }
```

### Emitted Events
```elixir
ai.upm.snapshot.created (TrainerWorker → EventBus)
  %{
    snapshot_id: binary,
    trainer_id: binary,
    version: integer,
    created_at: DateTime,
    metadata: map
  }

ai.upm.snapshot.activated (SnapshotManager → EventBus)
  %{
    snapshot_id: binary,
    trainer_id: binary,
    version: integer,
    activated_at: DateTime,
    previous_snapshot_id: binary | nil
  }

ai.upm.shadow_delta (DriftMonitor → EventBus) [per comparison]
  %{
    trainer_id: binary,
    prediction_id: binary,
    shadow_prediction: term,
    ground_truth: term,
    drift_score: float,
    timestamp: DateTime
  }

ai.upm.drift.quarantine (DriftMonitor → EventBus)
  %{
    trainer_id: binary,
    drift_window_id: binary,
    drift_p95: float,
    threshold: float,
    recommendation: "rollback" | "pause",
    quarantined_at: DateTime
  }

ai.upm.rollback (SnapshotManager → EventBus)
  %{
    trainer_id: binary,
    from_snapshot_id: binary,
    to_snapshot_id: binary,
    reason: binary,
    rolled_back_at: DateTime
  }
```

---

## ✅ Validation

### Run Validation Task
```bash
mix thunderline.upm.validate
```

**Checks Performed**:
1. Feature flag status
2. Configuration keys
3. Storage paths (existence, writability)
4. Ash resources (UpmTrainer, UpmSnapshot, UpmAdapter, UpmDriftWindow)
5. Database migrations
6. Compression support (zstd, gzip)
7. Drift calculation logic (numeric, structured)
8. Replay buffer ordering
9. Worker health (if enabled)

### Manual Validation
```elixir
# IEx session
iex> Application.get_env(:thunderline, :features)[:unified_model]
false  # (or true if enabled)

iex> Thunderline.Thunderbolt.UPM.Supervisor.list_trainers()
[]  # (or list of trainer IDs if running)

iex> Process.whereis(Thunderline.Thunderbolt.UPM.AdapterSync)
#PID<0.1234.0>  # (or nil if disabled)
```

---

## 🚀 Rollout Phases

### Phase 1: Shadow Mode (Current)
- Feature flag: `unified_model = true`
- Trainer mode: `:shadow`
- Behavior: Train only, no inference impact
- Duration: 14 days
- Success criteria: P95 drift < 0.2 for 95% of windows

### Phase 2: Canary Rollout
- Trainer mode: `:canary`
- Rollout: 1% → 5% → 10% → 25% of tenants
- Monitoring: Real inference impact on canary tenants
- Rollback trigger: P95 drift > 0.2 or user-reported issues

### Phase 3: Global Rollout
- Trainer mode: `:active`
- Rollout: 50% → 75% → 100% of tenants
- Final cutover: Deprecate static models

---

## 🔍 Observability

### Grafana Dashboard (UPM-001)
**Planned Panels**:
1. Snapshot Freshness (time since last snapshot creation)
2. Drift P95 (rolling 1h, 24h)
3. Training Loss (per trainer)
4. Adapter Sync Success Rate
5. Quarantine Events (count, reasons)
6. Replay Buffer Size (current, max)

### LiveDashboard UPM Pane
**Planned Metrics**:
- Active trainers (count, mode breakdown)
- Snapshot versions (per trainer)
- Adapter distribution status (pending, synced, errored)
- EventBus throughput (feature_window.created consumption rate)

---

## 🧪 Testing (TODO)

### Unit Tests Required
```
test/thunderline/thunderbolt/upm/
├── trainer_worker_test.exs
│   ├── test_process_window_success
│   ├── test_snapshot_creation_at_interval
│   ├── test_pause_resume
│   └── test_telemetry_emission
├── replay_buffer_test.exs
│   ├── test_deduplication
│   ├── test_ordering
│   ├── test_late_arrival_detection
│   └── test_gap_detection
├── snapshot_manager_test.exs
│   ├── test_checksum_validation
│   ├── test_compression_decompression
│   ├── test_activation_workflow
│   └── test_rollback
├── drift_monitor_test.exs
│   ├── test_p95_calculation
│   ├── test_quarantine_trigger
│   ├── test_numeric_drift
│   └── test_structured_drift
└── adapter_sync_test.exs
    ├── test_bulk_sync
    ├── test_retry_logic
    └── test_status_tracking
```

### Integration Test
```elixir
# test/thunderline/thunderbolt/upm/integration_test.exs
test "end-to-end UPM flow" do
  # 1. Create trainer
  # 2. Emit feature_window event
  # 3. Verify snapshot creation
  # 4. Record drift comparison
  # 5. Trigger activation
  # 6. Verify adapter sync
end
```

---

## 📋 Remaining Work (HC-22 Completion)

### Critical (Required for M1 Unblock)
1. **EventBus Subscriptions** (2 hours)
   - Subscribe TrainerWorker to `system.feature_window.created`
   - Subscribe AdapterSync to `ai.upm.snapshot.activated`
   - Update worker `init/1` callbacks

2. **Test Suite** (1 day)
   - Unit tests for all 5 workers
   - Integration test (end-to-end flow)
   - Test coverage: target 80%+

3. **ThunderCrown Policy Hooks** (4 hours)
   - Create `UPMPolicy` module
   - Authorization for snapshot activation
   - Rollout gating rules (tenant allowlists)

### High Priority
4. **Documentation** (4 hours)
   - Update `docs/documentation/unified_persistent_model.md` with implementation status
   - Add configuration examples (above)
   - Document rollout procedures (above)
   - Add operational runbooks (rollback drill, quarantine resolution)

5. **Real SGD Implementation** (1 day)
   - Replace placeholder `sgd_update/3` with actual gradient descent
   - Integrate with Nx/EXLA for tensor operations
   - Add hyperparameter tuning support

### Medium Priority
6. **Grafana Dashboard** (1 day)
   - Create UPM-001 dashboard with panels above
   - Alert rules (drift P95 > 0.2, snapshot freshness > 2 hours)

7. **LiveDashboard Pane** (1 day)
   - Custom UPM page in LiveDashboard
   - Real-time metrics display

8. **Cleanup Warnings** (1 hour)
   - Fix `Logger.warn` → `Logger.warning` deprecations
   - Remove unused variable warnings

---

## 🐛 Known Issues

1. **Database Migration Validation** (Minor)
   - `mix thunderline.upm.validate` fails on `Ash.read(UpmTrainer, limit: 1)` due to Spark.Options.ValidationError
   - **Impact**: Low (validation task only)
   - **Fix**: Use Ash query syntax `|> Ash.Query.limit(1) |> Ash.read()`

2. **zstd Compression Unavailable** (Minor)
   - `:ezstd` dependency not loading (NIF compilation issue on some systems)
   - **Workaround**: Falls back to `:zlib.gzip` successfully
   - **Fix**: Add `:ezstd` to `mix.exs` optional_deps with proper NIF setup

3. **Configuration Key Deprecation** (Cosmetic)
   - Passing list as application env key triggers deprecation warning
   - **Fix**: Refactor `Application.get_env(:thunderline, [Module, :key])` to atoms

---

## 🎓 Learning Resources

### Codebase References
- **ThunderFlow Integration**: `lib/thunderline/thunderflow/event_bus.ex`
- **Ash Actions**: `lib/thunderline/thunderbolt/resources/upm_trainer.ex`
- **Reactor Sagas**: `lib/thunderline/thunderbolt/sagas/upm_activation_saga.ex`
- **Feature Flags**: `lib/thunderline/feature.ex`

### External Documentation
- **Online Learning**: Bottou, L. (2012). "Stochastic Gradient Descent Tricks"
- **Drift Detection**: Gama, J. et al. (2014). "A survey on concept drift adaptation"
- **Shadow Deployments**: Canini, K. et al. (2011). "Sibyl: A system for large scale machine learning"

---

## 🏆 Success Criteria

### HC-22 Complete When:
- [x] All 5 core workers implemented (TrainerWorker, ReplayBuffer, SnapshotManager, DriftMonitor, AdapterSync)
- [x] UPM.Supervisor created
- [x] Application integration (feature-flagged)
- [ ] EventBus subscriptions active
- [ ] ThunderCrown policy hooks
- [ ] Test suite passing (80%+ coverage)
- [ ] `mix thunderline.upm.validate` passes
- [ ] Documentation complete

### M1-EMAIL-AUTOMATION Unblocked When:
- HC-22 complete (above)
- Shadow mode running for 14 days
- P95 drift < 0.2 for 95% of windows
- No quarantine events in final 48 hours
- Grafana dashboard UPM-001 deployed
- Operational runbook reviewed by team

---

## 📞 Contact

**Domain Owner**: ThunderBolt Team  
**Technical Lead**: @thunderbolt-lead  
**Slack Channel**: #thunderline-upm  
**Oncall**: Check PagerDuty "Thunderline UPM" rotation
