# ORPHANED_CODE_REPORT.md  
**Epic 2: Module Organization Cleanup - Rookie Team Sprint 2**

---

## 🧩 Objective  
Identify small, untested, and flagged modules across `lib/thunderline`, categorize them for retention, deprecation, or deletion, and provide actionable next steps.

---

## ⚙️ Detection Criteria
- **Small modules:** < 20 lines of Elixir code  
- **Untested modules:** No corresponding `*_test.exs` file detected
- **Flagged sections:** Containing `TODO`, `FIXME`, `HACK`, or `XXX` comments

---

## 🔍 Summary of Findings

### 📄 Small / Possibly Orphaned Modules
| Module | Size | Test Coverage | Status | Recommendation |
|---------|------|---------------|----------|----------------|
| Thunderline.Thunderlink.Chat.Message.Types.Source | 3 lines | None | ✅ functional enum | **Keep** |
| Thunderline.UUID | ~50 lines | None | Utility | **Keep (core util)** |
| Thunderline.PostgresTypes | 16 lines | None | DB integration | **Keep** |
| Thunderline.Thunderforge.Blueprint | 25 lines | None | Isolated YAML adapter | **Review for merge** |
| Thunderline.ServiceRegistry | 16 lines | None | Domain entrypoint | **Keep (domain root)** |
| Jido.Bus.Adapters.InMemory.* (shim) | small | Untested | Shim for missing upstream lib | **Move to deprecated/**
| Thunderline.EventBus | 16 lines | Legacy alias | Covered indirectly | **Move to deprecated/** |

---

## 🧪 Modules Lacking Tests
| Module | Domain | Remarks | Action |
|---------|---------|----------|----------|
| Thunderline.ServiceRegistry | core service graph | Critical infra, missing integration tests | **Add test suite** |
| Thunderline.PostgresTypes | DB glue | Low risk, add stub test only | **Keep** |
| Thunderline.Thunderforge.* | Pipeline layer incomplete | Orphaned design | **Deprecate if unused** |
| Thunderline.Support.Jido.InMemory.Subscription | non-core shim | Not maintained upstream | **Deprecate** |

---

## ⚠️ TODO / FIXME / HACK Indicators Summary

### 🔴 High Severity
- `thunderbolt/resources/*`: unfinished ML orchestration logic (`TODO: Implement ML logic`, `validation syntax for Ash 3.x`, etc.)
- `thundergate/resources/*`: incomplete routes and validations
- `thunderlink/resources/*`: AshOban configuration disabled, commented validation rules
- **Action:** Flag for **Phase 3 refactor**, require full QA coverage.

### 🟠 Medium Severity
- Numerous commented `TODO` blocks in telemetry dashboards (`dashboard_metrics.ex`)
- Early prototypes in `thunderbolt/auto_ml_driver.ex`, `thunderbolt/hpo_executor.ex`, `cerebros_bridge`
- **Action:** Move non-critical ML TODOs to `sandbox_deprecated/`.

### 🟢 Low Severity
- Cosmetic cleanups (`# TODO: Rename variables`, `# TODO: improve comments`)
- **Action:** Handle in `mix precommit` backlog.

---

## 🧹 Actionable Categorization

### ✅ **Keep**
- Core domains with active integrations:
  - `Thundergate`, `Thunderbolt`, `Thunderflow`, `RAG`
  - Utility modules (`UUID`, `PostgresTypes`, `PubSub`)

### 🚧 **Move to deprecated/**
- Shims and aliases:
  - `Thunderline.EventBus` (wrapper only)
  - `Support.Jido.InMemory.*` (patches obsoleted by upstream)
  - `Thunderforge.*` (abandoned)

### ❌ **Delete**
- None recommended for immediate removal (phase out unused stubs once CI confirms no references).

---

## 🧭 Next Steps
1. Migrate deprecated modules into `/lib/deprecated/` namespace.  
2. Auto-generate test stubs for `service_registry`, `thunderforge`, and `uuid`.  
3. Track all remaining TODO/FIXME blocks under `docs/documentation/TODO_TRACKER_2025Q4.md`.  
4. Stage domain refactors in `Phase 3 (Crown/Block cleanup)` of Thunderline Rebuild Initiative.

---

**Generated:** 2025-10-31  
**Audit scope:** `lib/thunderline/**/*.ex`  
**Auditor:** Rookie Team Sprint 2 (Automated Elixir Audit)