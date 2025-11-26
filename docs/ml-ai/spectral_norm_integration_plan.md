# Spectral Norm Constraint Integration - Implementation Plan

**Status**: Planning Phase  
**Priority**: Medium (Groundwork for future ML enhancements)  
**Complexity**: High (Cross-system integration)

---

## Executive Summary

Integrate spectral normalization as a toggleable constraint for linear layers in Cerebros training, exposing results through Thunderline's observability stack while maintaining clean architectural boundaries via the anti-corruption pattern.

---

## Phase 1: Foundation & Data Models (Week 1)

**Goal**: Extend Thunderline's Ash resources to support spectral norm metadata

### Tasks

1. **Extend Trial Resource** (`lib/thunderline/thunderbolt/trial.ex`)
   - Add `:spectral_norm` boolean attribute
   - Add `:mlflow_run_id` string attribute for cross-reference
   - Update migrations
   - Add query helpers for filtering by constraint type

2. **Update ModelRun Resource** (if needed)
   - Ensure relationship to Trial supports new fields
   - Add aggregates for spectral norm usage stats

3. **Test Data Layer**
   - Unit tests for Trial creation with spectral_norm flag
   - Query tests for filtering trials by constraint type

**Deliverables**:
- [ ] Updated Ash resources
- [ ] Database migrations
- [ ] Unit test coverage >90%

**Files to Create/Modify**:
```
lib/thunderline/thunderbolt/trial.ex
priv/repo/migrations/XXXXXX_add_spectral_norm_to_trials.exs
test/thunderline/thunderbolt/trial_test.exs
```

---

## Phase 2: Event Schema & Telemetry (Week 2)

**Goal**: Define canonical event formats for ML training lifecycle

### Tasks

1. **Define Event Taxonomy**
   - Document `[:thunderline, :ml, :run, :start]` event schema
   - Document `[:thunderline, :ml, :run, :stop]` event schema
   - Document `[:thunderline, :ml, :run, :metric]` event schema (optional)
   - Add to ThunderFlow event catalog

2. **Create Event Emitter Module**
   ```elixir
   # lib/thunderline/thunderflow/ml_events.ex
   defmodule Thunderline.ThunderFlow.MLEvents do
     @moduledoc """
     Canonical ML training event emitters for ThunderFlow pipeline.
     Ensures consistent event structure across Cerebros bridge.
     """
     
     def emit_training_start(trial_id, model_run_id, hyperparams) do
       # Implementation
     end
     
     def emit_training_stop(trial_id, metrics, duration_ms) do
       # Implementation
     end
     
     def emit_training_metric(trial_id, epoch, measurements) do
       # Implementation
     end
   end
   ```

3. **ThunderGate API Endpoint** (for Cerebros to POST events)
   - Create `/api/events/ml` endpoint
   - Validate event payloads
   - Inject into ThunderFlow pipeline

**Deliverables**:
- [ ] Event schema documentation
- [ ] MLEvents emitter module
- [ ] ThunderGate API endpoint
- [ ] Integration tests

**Files to Create/Modify**:
```
lib/thunderline/thunderflow/ml_events.ex
lib/thunderline_web/controllers/events_controller.ex
lib/thunderline_web/router.ex
test/thunderline/thunderflow/ml_events_test.exs
documentation/thunderflow_event_catalog.md
```

---

## Phase 3: Cerebros Bridge Extension (Week 3)

**Goal**: Extend CerebrosBridge to pass spectral_norm flag and translate results

### Tasks

1. **Extend Bridge Client**
   ```elixir
   # lib/thunderline/thunderbolt/cerebros_bridge/client.ex
   # Add spectral_norm to trial configuration
   def start_trial(trial_config) do
     params = %{
       hyperparams: trial_config.hyperparams,
       spectral_norm: trial_config.spectral_norm,  # NEW
       dataset_id: trial_config.dataset_id
     }
     # ... invoke Cerebros
   end
   ```

2. **Update Translator**
   - Map Cerebros trial results to Trial resource
   - Extract spectral_norm from returned metadata
   - Create Artifact records for model checkpoints

3. **Add Bridge Telemetry**
   - Emit `[:cerebros, :bridge, :invoke, :start]`
   - Emit `[:cerebros, :bridge, :invoke, :stop]`
   - Include spectral_norm in metadata

**Deliverables**:
- [ ] Updated Bridge modules
- [ ] Translator handles spectral_norm
- [ ] Bridge telemetry events
- [ ] Integration tests (mocked Cerebros)

**Files to Create/Modify**:
```
lib/thunderline/thunderbolt/cerebros_bridge/client.ex
lib/thunderline/thunderbolt/cerebros_bridge/translator.ex
lib/thunderline/thunderbolt/cerebros_bridge/invoker.ex
test/thunderline/thunderbolt/cerebros_bridge_test.exs
```

---

## Phase 4: Optuna Integration (External - Python Side)

**Goal**: Add spectral_norm as Optuna hyperparameter

### Tasks (Cerebros Repository)

1. **Update Optuna Search Space**
   ```python
   # cerebros/optuna_config.py
   def create_study_config():
       return {
           "spectral_norm": {"type": "categorical", "choices": [False, True]},
           "learning_rate": {"type": "loguniform", "low": 1e-5, "high": 1e-2},
           # ... other hyperparams
       }
   ```

2. **Modify Model Builder**
   ```python
   # cerebros/model_builder.py
   def build_model(config):
       # ... 
       linear = nn.Linear(in_features, out_features)
       if config.get('spectral_norm', False):
           linear = torch.nn.utils.spectral_norm(linear)
       # ...
   ```

3. **Update Training Loop**
   - Emit events to Thunderline via HTTP POST to `/api/events/ml`
   - Log to MLflow: params, metrics, artifacts
   - Add MLflow tags: trial_id, model_run_id, constraint_method

**Deliverables** (Cerebros side):
- [ ] Optuna config with spectral_norm
- [ ] Model builder applies spectral norm conditionally
- [ ] Event emission to Thunderline
- [ ] MLflow logging complete

**Note**: This phase requires coordination with Cerebros Python codebase

---

## Phase 5: MLflow Integration (Week 4)

**Goal**: Ensure MLflow and Thunderline records stay in sync

### Tasks

1. **MLflow Configuration**
   - Configure artifact storage (S3/ThunderBlock vault)
   - Set up experiment naming convention
   - Create MLflow client wrapper in Elixir (optional)

2. **Artifact Synchronization**
   - When Cerebros logs artifact to MLflow, create Ash Artifact record
   - Store MLflow artifact URI in ThunderBlock
   - Add cleanup/retention policies

3. **Cross-Reference System**
   - Store mlflow_run_id in Trial resource
   - Store trial_id as MLflow tag
   - Enable bidirectional lookup

**Deliverables**:
- [ ] MLflow configuration docs
- [ ] Artifact sync mechanism
- [ ] Cross-reference tests

**Files to Create/Modify**:
```
lib/thunderline/thunderblock/artifact_sync.ex
config/mlflow_config.exs
documentation/mlflow_integration.md
```

---

## Phase 6: Dashboard & Visualization (Week 5)

**Goal**: Create UI for monitoring spectral norm experiments

### Tasks

1. **Real-Time Training Monitor** (LiveView)
   - Subscribe to `[:thunderline, :ml, :run, *]` events
   - Show running trials with spectral_norm indicator
   - Plot live metrics as events stream

2. **Experiment Comparison View**
   - Query Trial resources grouped by spectral_norm
   - Bar charts: accuracy with/without constraint
   - Scatter plots colored by constraint type

3. **MLflow Integration Link**
   - Add "Open in MLflow" button on ModelRun page
   - Deep link to filtered MLflow experiment view

**Deliverables**:
- [ ] LiveView training monitor
- [ ] Comparison dashboard
- [ ] MLflow deep links

**Files to Create/Modify**:
```
lib/thunderline_web/live/ml_training_monitor_live.ex
lib/thunderline_web/live/ml_comparison_live.ex
lib/thunderline_web/components/ml_charts.ex
```

---

## Phase 7: Testing & Validation (Week 6)

**Goal**: End-to-end validation with dry-run experiments

### Tasks

1. **Integration Testing**
   - Mock Cerebros responses with spectral_norm data
   - Test event flow: Cerebros → ThunderGate → ThunderFlow
   - Verify Trial/Artifact creation

2. **Dry-Run Experiment**
   - Run 5-10 trials with spectral_norm toggle
   - Validate MLflow logging
   - Verify dashboard displays correctly

3. **Performance Testing**
   - Measure event ingestion latency
   - Check database query performance for filtered trials
   - Verify no memory leaks in LiveView subscriptions

**Deliverables**:
- [ ] Comprehensive integration tests
- [ ] Dry-run experiment results
- [ ] Performance report

---

## Domain Alignment Checklist

Ensure clean boundaries across Thunderline's 7-domain architecture:

- **ThunderBolt** (ML Orchestration)
  - [ ] Trial/ModelRun resources extended
  - [ ] CerebrosBridge acts as anti-corruption layer
  - [ ] No direct Python/ML library imports

- **ThunderFlow** (Event Pipeline)
  - [ ] Canonical event formats defined
  - [ ] Events routed without special-case logic
  - [ ] Broadway consumers handle ML events

- **ThunderBlock** (Persistence)
  - [ ] Artifact resources track model checkpoints
  - [ ] MLflow artifact storage uses ThunderBlock vault
  - [ ] Retention policies applied

- **ThunderGate** (External Integration)
  - [ ] API endpoint accepts Cerebros events
  - [ ] Validation prevents malformed payloads
  - [ ] Rate limiting applied

- **ThunderLink** (UI/LiveView)
  - [ ] Dashboards subscribe to ThunderFlow events
  - [ ] No direct database queries (use Ash)
  - [ ] Real-time updates via PubSub

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| MLflow-Thunderline data divergence | Medium | High | Implement sync validation checks |
| Cerebros event format changes | Low | High | Version API contract, validate payloads |
| LiveView performance with high event volume | Medium | Medium | Use streams, debouncing, sampling |
| Spectral norm slows training significantly | Low | Low | Make toggle easily reversible |

---

## Success Metrics

- [ ] 100% of trials record spectral_norm flag
- [ ] <100ms latency for event ingestion (p95)
- [ ] MLflow-Thunderline data consistency >99.9%
- [ ] Dashboard loads in <2s with 1000+ trials
- [ ] Zero data leaks across domain boundaries

---

## Next Steps

**Immediate Actions**:
1. Review this plan with team/High Command
2. Set up development environment with MLflow
3. Begin Phase 1: Extend Ash resources
4. Create tracking issue/project board

**Questions for High Command**:
- Is Cerebros codebase ready for modification?
- Do we have MLflow infrastructure provisioned?
- What's the priority timeline (urgent vs. incremental)?
- Should we prototype Phase 1-2 first for validation?

---

## References

- [Spectral Normalization Paper](https://arxiv.org/abs/1802.05957)
- [PyTorch Spectral Norm Docs](https://pytorch.org/docs/stable/generated/torch.nn.utils.spectral_norm.html)
- Thunderline NAS Integration Design
- Cerebros Bridge Plan
- ThunderFlow Event Catalog
- Thunderline Domain Architecture Guide

---

**Last Updated**: 2025-10-05  
**Owner**: Mo + Guardian Architect  
**Status**: ✅ Planning Complete - Ready for Phase 1
