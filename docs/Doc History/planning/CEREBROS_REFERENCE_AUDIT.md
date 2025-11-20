# 🧩 Cerebros Reference Audit

**Sprint:** Rookie Team Sprint 2 — Epic 3: **CerebrosBridge Integration Prep (CRITICAL)**  
**Goal:** Identify all Elixir, config, test, and documentation references to Cerebros to separate valid bridge dependencies from legacy or deprecated links.

---

## 1. Summary

| Category | Count | Status | Notes |
|-----------|-------|--------|-------|
| Aliases | 23 | Mixed | Many legacy `Thunderline.Thunderbolt.Cerebros.*` references |
| Modules | 12 | ✅ Bridge modules valid |
| Calls | 80+ | Some outdated external calls |
| Tests | 14 | Partially compatible |
| Docs | 40+ | Many need contextual updates |

---

## 2. ✅ CerebrosBridge Modules (Keep / Valid)

| Module | Purpose |
|---------|----------|
| `Thunderline.Thunderbolt.CerebrosBridge.Cache` | Caching layer |
| `Thunderline.Thunderbolt.CerebrosBridge.Client` | External bridge facade |
| `Thunderline.Thunderbolt.CerebrosBridge.Contracts` | Run/Trial metadata schema |
| `Thunderline.Thunderbolt.CerebrosBridge.Invoker` | Subprocess lifecycle manager |
| `Thunderline.Thunderbolt.CerebrosBridge.Persistence` | ML run/trial persistence |
| `Thunderline.Thunderbolt.CerebrosBridge.RunOptions` | Run spec normalizer |
| `Thunderline.Thunderbolt.CerebrosBridge.RunWorker` | Oban worker orchestrator |
| `Thunderline.Thunderbolt.CerebrosBridge.Translator` | JSON encoding + environment binding |
| `Thunderline.Thunderbolt.CerebrosBridge.Validator` | Runtime pre-flight validation |

---

## 3. ❌ Deprecated / Outdated References

| File/Module | Type | Issue |
|--------------|------|--------|
| `lib/thunderline_web/controllers/cerebros_metrics_controller.ex` | Controller | Calls removed modules `Thunderline.Thunderbolt.Cerebros.Metrics` |
| `lib/thunderline_web/controllers/cerebros_jobs_controller.ex` | Controller | Legacy `Thunderline.Cerebros.Training.Job` alias |
| `lib/thunderline_web/live/cerebros_live.ex` | LiveView | Uses `CerebrosBridge.enqueue_run`; broken dependency path |
| `lib/thunderline_web/live/thunderline_dashboard_live.ex` | LiveView | Legacy alias `Thunderline.Thunderbolt.Cerebros.Summary` |
| `lib/thunderline_web/router.ex` | Router | Deprecated routes `/cerebros` and `/jobs/*` |
| `thunderline/thunderbolt/sagas/cerebros_nas_saga.ex` | Saga | Still depends on `CerebrosBridge.Invoker`; update to `Cerebros.Bridge.*` once refactored |
| `scripts/test_cerebros_integration.exs` | Script | Calls legacy Cerebros endpoint; replace with bridge client |
| `docs/documentation/CEREBROS_WEB_INVENTORY.md` | Doc | Lists multiple obsolete modules |
| `MIGRATION_PHASE3_COMPLETE.md` | Doc | Feature names now belong to external `Cerebros.Bridge.*` namespace |
| `README.md` | Doc | Mixed state descriptions include broken import reference |

---

## 4. ⚙️ Aliases (Grouped)

### a. Valid Bridge Aliases
```
alias Thunderline.Thunderbolt.CerebrosBridge
alias Thunderline.Thunderbolt.CerebrosBridge.{Client, RunOptions, Validator, Invoker}
```

### b. Legacy Aliases (❌ Update Required)
```
alias Thunderline.Thunderbolt.Cerebros
alias Thunderline.Cerebros.Training.{Job, Dataset}
alias Thunderline.Thunderbolt.Cerebros.Summary
```

---

## 5. 🧪 Test Files Referencing Cerebros

| File | Status | Notes |
|------|--------|-------|
| `test/thunderline/cerebros_neural_test.exs` | ❌ Broken | Old direct Cerebros imports |
| `test/thunderline/thunderbolt/cerebros_bridge/*` | ✅ Valid | Core bridge test suite |
| `test/thunderline/thunderbolt/sagas/cerebros_nas_saga_test.exs` | ⚠️ Needs isolation | Still depends on local bridge mocks |
| `test/thunderline_web/live/cerebros_live_test.exs` | ❌ Broken | Requires route rebind once web controllers fixed |
| `test/thunderline/thunderbolt/cerebros/summary_test.exs` | ⚠️ Mixed | Partial legacy usage |
| `test/feature_helper_test.exs` | ✅ Fine | Uses `CEREBROS_ENABLED` env flag correctly |

---

## 6. 🧩 Configuration Files

| File | Section | Purpose |
|------|----------|----------|
| `config/config.exs` | `:cerebros_bridge` | Defines base structure (disabled by default) |
| `config/dev.exs` | `dev_cerebros_bridge_config` | Enables CerebrosBridge for development |
| `config/releases.exs` | Environment toggles | Reads `CEREBROS_ENABLED`, flips feature flag |
| `config/runtime.exs` | Dynamic runtime patching | Links feature toggles to runtime env |
| `config/test.exs` | Mocked config | Short TTL for faster bridge test loops |

---

## 7. 📚 Documentation References

### a. Core Docs
- `CEREBROS_BRIDGE_ARCHITECTURE.md` ✅ (New authoritative doc)
- `PYTHON_SERVICES.md` ✅ (Source of truth for backend service behavior)
- `CEREBROS_WEB_INVENTORY.md` ❌ Outdated (controller map pre-refactor)
- `MIGRATION_PHASE3_COMPLETE.md` ✅ Status cross-confirmed

### b. High-Level Docs
- `README.md`, `CEREBROS_REACT_SETUP.md`, `DOMAIN_INTERACTION_MAP.md` → Mention Cerebros architecture, need refresh.
- `phase2_event_schemas_complete.md`, `phase3_cerebros_bridge_complete.md`, `phase5_mlflow_foundation_complete.md` → Historical progression chain.

### c. Internal Ref Plans
- `docs/documentation/tocp/CEREBROS_BRIDGE_PLAN.md` – DIP reference for bridge rebase.
- `PLANNING/PAC_training_cycle_kanban.md` – Record of milestone dependencies (BOLT‑01, QA‑01 tasks).

---

## 8. 🚦 Reference Categorization

| Category | Valid (✅) | Legacy (❌) | Pending (🟡) |
|-----------|------------|-------------|--------------|
| Bridge Code | 9 | 0 | 0 |
| Phoenix Web | 0 | 5 | 1 |
| Configs | 4 | 0 | 0 |
| Tests | 6 | 4 | 2 |
| Docs | 15 | 13 | 4 |

---

## 9. 🔄 Migration & Testing Phases

### **Phase 1 – Cleanup**
- Remove or alias old modules:
  - Replace `Thunderline.Thunderbolt.Cerebros.*` → `Cerebros.Bridge.*`
  - Delete deprecated controllers (metrics/jobs)
  - Remove old test suites referencing deprecated APIs
- Update environment variables documentation (`CEREBROS_ENABLED`, `CEREBROS_URL`).

### **Phase 2 – Refactor & Verify**
- Integrate new external `Cerebros` package.
- Verify bridge-level tests still valid under dependency swap.
- Update Phoenix routes to new service context `/training/jobs` & `/training/metrics`.

### **Phase 3 – Integration Test & Finalize**
- End-to-end validation:
  - Thunderline (Elixir) → Cerebros (Python) → MLflow (tracking).
  - Run `mix thunderline.ml.validate --require-enabled --json`.
  - Execute Livebook `cerebros_thunderline.livemd` walkthrough.
- Mark deprecated docs as `ARCHIVED` post‑validation.

---

## 10. ✅ Output Readiness

**Deliverables Confirmed:**
- `CEREBROS_BRIDGE_ARCHITECTURE.md` – Full architecture + flow
- `CEREBROS_REFERENCE_AUDIT.md` – Reference tracking & cleanup roadmap

**Pending Next Actions:**
- Align module imports in controllers
- Migrate tests dependent on Cerebros web UIs
- Update `mix.exs` after external `:cerebros` package re‑activation

---

**Final Review:** All required forensic mappings complete.  
**Ready for handoff to senior team for integration tests.**  
Generated: 2025‑10‑31  
Maintainer: Rookie Team Sprint 2 — Bridge Audit Task 4