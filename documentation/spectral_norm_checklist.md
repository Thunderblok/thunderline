# Spectral Norm Integration - Quick Start Checklist

**Mission**: Lay groundwork for spectral normalization constraint integration

---

## ✅ Immediate Actions (Today)

- [x] Review High Command specification
- [x] Create implementation plan document
- [x] Create architecture overview document
- [ ] Share plan with team for feedback
- [ ] Set priority level with High Command

---

## 🏗️ Phase 1: Foundation (Start This Week)

### Database & Resources

- [ ] **Extend Trial Ash Resource**
  ```bash
  # Create migration
  mix ash_postgres.generate_migrations --name add_spectral_norm_to_trials
  
  # Review generated migration
  cat priv/repo/migrations/*_add_spectral_norm_to_trials.exs
  
  # Run migration
  mix ecto.migrate
  ```

- [ ] **Add attributes to Trial resource**
  - `attribute :spectral_norm, :boolean, default: false`
  - `attribute :mlflow_run_id, :string`

- [ ] **Write unit tests**
  ```bash
  # Test file: test/thunderline/thunderbolt/trial_test.exs
  mix test test/thunderline/thunderbolt/trial_test.exs
  ```

### Expected Files

```
lib/thunderline/thunderbolt/trial.ex              # Modified
priv/repo/migrations/*_add_spectral_norm.exs      # Created
test/thunderline/thunderbolt/trial_test.exs       # Modified
```

---

## 📡 Phase 2: Event Infrastructure (Next Week)

### Event Definitions

- [ ] **Create MLEvents module**
  ```bash
  # File: lib/thunderline/thunderflow/ml_events.ex
  touch lib/thunderline/thunderflow/ml_events.ex
  ```

- [ ] **Define event schemas**
  - `[:thunderline, :ml, :run, :start]`
  - `[:thunderline, :ml, :run, :stop]`
  - `[:thunderline, :ml, :run, :metric]`

- [ ] **Add to event catalog**
  ```bash
  # Update: documentation/thunderflow_event_catalog.md
  ```

### ThunderGate API

- [ ] **Create events controller**
  ```bash
  # File: lib/thunderline_web/controllers/events_controller.ex
  mix phx.gen.context Events Event events --no-schema
  ```

- [ ] **Add route**
  ```elixir
  # In router.ex
  scope "/api", ThunderlineWeb do
    pipe_through :api
    post "/events/ml", EventsController, :create_ml_event
  end
  ```

- [ ] **Test event ingestion**
  ```bash
  curl -X POST http://localhost:4000/api/events/ml \
    -H "Content-Type: application/json" \
    -d '{
      "event": "ml.run.start",
      "trial_id": "test-123",
      "metadata": {"spectral_norm": true}
    }'
  ```

---

## 🌉 Phase 3: Bridge Extension (Week 3)

### CerebrosBridge Updates

- [ ] **Extend Bridge Client**
  - Add `spectral_norm` to trial config payload
  - Update `start_trial/1` function

- [ ] **Update Translator**
  - Map `spectral_norm` from Cerebros results
  - Extract `mlflow_run_id` from response

- [ ] **Add bridge telemetry**
  - Emit `[:cerebros, :bridge, :invoke, :start]`
  - Emit `[:cerebros, :bridge, :invoke, :stop]`

### Expected Files

```
lib/thunderline/thunderbolt/cerebros_bridge/client.ex      # Modified
lib/thunderline/thunderbolt/cerebros_bridge/translator.ex  # Modified
test/thunderline/thunderbolt/cerebros_bridge_test.exs      # Modified
```

---

## 🐍 Phase 4: Cerebros Python Integration (Coordinate Externally)

**Note**: This requires access to Cerebros Python repository

### Optuna Configuration

- [ ] **Add spectral_norm hyperparameter**
  ```python
  # File: cerebros/config/optuna_config.py
  "spectral_norm": {"type": "categorical", "choices": [False, True]}
  ```

### Model Builder

- [ ] **Apply spectral norm conditionally**
  ```python
  # File: cerebros/models/model_builder.py
  if config.get('spectral_norm', False):
      linear = torch.nn.utils.spectral_norm(linear)
  ```

### Training Loop

- [ ] **Emit events to Thunderline**
  ```python
  # POST to http://thunderline:4000/api/events/ml
  ```

- [ ] **Log to MLflow**
  ```python
  mlflow.log_param('spectral_norm', use_spectral)
  mlflow.set_tag('trial_id', trial_id)
  mlflow.log_artifact('model.pth')
  ```

---

## 📊 Phase 5: MLflow Setup (Week 4)

### Configuration

- [ ] **Set up MLflow tracking server**
  ```bash
  # Check if MLflow is running
  curl http://localhost:5000/health
  ```

- [ ] **Configure artifact storage**
  - Point to ThunderBlock S3/vault
  - Set up credentials

- [ ] **Create test experiment**
  ```python
  import mlflow
  mlflow.set_tracking_uri("http://localhost:5000")
  mlflow.set_experiment("thunderline-test")
  ```

### Sync Mechanism

- [ ] **Create Artifact sync module**
  ```bash
  touch lib/thunderline/thunderblock/artifact_sync.ex
  ```

- [ ] **Implement bidirectional lookup**
  - Trial → MLflow run (via mlflow_run_id)
  - MLflow run → Trial (via trial_id tag)

---

## 🎨 Phase 6: Dashboard (Week 5)

### LiveView Components

- [ ] **Create training monitor LiveView**
  ```bash
  mix phx.gen.live ML TrainingMonitor training_monitors --no-schema
  ```

- [ ] **Create comparison dashboard LiveView**
  ```bash
  mix phx.gen.live ML Comparison comparisons --no-schema
  ```

- [ ] **Add chart components**
  - Real-time metric plots
  - Spectral norm comparison charts

### MLflow Integration

- [ ] **Add "Open in MLflow" button**
  - Deep link to experiment: `http://mlflow:5000/experiments/{exp_id}`
  - Filter by trial_id tag

---

## 🧪 Phase 7: Testing & Validation (Week 6)

### Integration Tests

- [ ] **End-to-end event flow test**
  ```bash
  mix test test/thunderline_web/integration/ml_events_test.exs
  ```

- [ ] **Bridge translation test**
  ```bash
  mix test test/thunderline/thunderbolt/cerebros_bridge_test.exs
  ```

### Dry-Run Experiment

- [ ] **Run 5-10 test trials**
  - Mix of spectral_norm true/false
  - Validate events flow correctly
  - Check MLflow logging

- [ ] **Verify dashboard displays**
  - Real-time updates work
  - Comparison charts accurate

### Performance

- [ ] **Measure event ingestion latency**
  - Target: <100ms p95

- [ ] **Check database query performance**
  - Index on spectral_norm column
  - Aggregate queries fast

---

## 🚨 Blockers & Dependencies

### Current Blockers

- [ ] **Kubernetes cluster down** (from earlier conversation)
  - Need to restart cluster
  - Verify PostgreSQL accessible
  - Check MLflow service

- [ ] **Cerebros repository access**
  - Confirm you have write access
  - Coordinate with team on Python changes

### External Dependencies

- [ ] MLflow server running
- [ ] PostgreSQL database accessible
- [ ] S3/MinIO for artifact storage
- [ ] Cerebros Python codebase ready

---

## 📚 Documentation TODOs

- [ ] Update ThunderFlow event catalog
- [ ] Document CerebrosBridge API contract
- [ ] Add MLflow integration guide
- [ ] Create dashboard user guide
- [ ] Write deployment runbook

---

## 🎯 Success Criteria

When you can answer "YES" to all these:

- [ ] Can create Trial with spectral_norm=true via Ash action
- [ ] Can POST ml.run.start event to /api/events/ml successfully
- [ ] CerebrosBridge passes spectral_norm flag to external training
- [ ] MLflow logs show spectral_norm parameter
- [ ] Dashboard displays trials grouped by constraint type
- [ ] Can query Trial resources filtering by spectral_norm
- [ ] MLflow artifact URI stored in ThunderBlock Artifact resource

---

## 🔄 Weekly Sprint Goals

### Week 1: Foundation
✅ Planning complete  
⏳ Database schema updated  
⏳ Unit tests passing

### Week 2: Events
⏳ ThunderFlow event schemas defined  
⏳ ThunderGate API endpoint working  
⏳ Event ingestion tested

### Week 3: Bridge
⏳ CerebrosBridge extended  
⏳ Integration tests passing  
⏳ Telemetry events emitted

### Week 4: MLflow
⏳ MLflow configured  
⏳ Artifact sync working  
⏳ Cross-reference validated

### Week 5: Dashboard
⏳ LiveView monitor deployed  
⏳ Comparison charts working  
⏳ Real-time updates functional

### Week 6: Validation
⏳ End-to-end tests passing  
⏳ Dry-run experiment complete  
⏳ Performance targets met

---

## 🆘 When You Get Stuck

1. **Check the architecture doc**: `documentation/spectral_norm_architecture.md`
2. **Review the full plan**: `documentation/spectral_norm_integration_plan.md`
3. **Ask High Command**: Clarify priorities or scope
4. **Create specialized agent**: If diving deep into specific area
5. **Take a break**: *Mens sana in corpore sano* (healthy mind in healthy body)

---

**Last Updated**: 2025-10-05  
**Status**: ✅ Groundwork complete - Ready to begin Phase 1  
**Your Next Action**: Extend Trial Ash resource with spectral_norm attribute

*Fortes fortuna adiuvat* - Fortune favors the brave! 🚀
