# Thunderline Domain Catalog  
**Audit Date:** October 31, 2025  
**Auditor:** Rookie Documentation Squad  
**Status:** ✅ Completed Audit – Cerebros extraction noted  

---

### ⚡ ThunderBlock Domain  
- **Location:** `lib/thunderline/thunderblock/`  
- **Purpose:** Persistence layer, Vault memory, retention policies, and Oban sweeps  
- **Status:** ⚠️ PARTIAL — Active retention system, several resources missing Ash policy compliance  
- **Resources:**  
  - ✅ `retention.ex`, `jobs/retention_sweep_worker.ex`  
  - ⚠️ `resources/vault_*` (partially compliant, pending policy fixes)  
  - ❌ `resources/pac_home.ex` – commented policies (see DOMAIN_SECURITY_PATTERNS.md)  
- **Notes:** Stale “authorize_if always()” resources flagged in `DOMAIN_SECURITY_PATTERNS.md`.  
  Requires completion of AUDIT‑01; no missing dependencies.

---

### ⚙️ ThunderBolt Domain  
- **Location:** `lib/thunderline/thunderbolt/`  
- **Purpose:** ML/AI orchestration, Cerebros NAS bridge, CA solver, and MLflow integration.  
- **Status:** ⚠️ PARTIAL — Cerebros migrated; bridge modules retained for interoperability.  
- **Resources:**  
  - ✅ `mlflow/`, `resources/upm_*`, `hpo_executor.ex`, `auto_ml_driver.ex`  
  - ✅ `cerebros_bridge/` — migrated modules (Client, Cache, Contracts, Invoker, Persistence, Translator, Validator)  
  - ⚠️ `resources/cerebros_training_job.ex`, `resources/model_run.ex`, `resources/model_trial.ex` — rely on external Cerebros Bridge  
  - ❌ `resources/model_artifact.ex` — deprecated, not referenced  
- **Notes:** Cerebros extraction complete (see `phase3_cerebros_bridge_complete.md`).  
  Domain partially delegated to `/home/mo/DEV/cerebros`.  
  References now controlled via `CerebrosBridge.*` clients, toggled by `features.ml_nas`.  

---

### 🔮 ThunderCrown Domain  
- **Location:** `lib/thunderline/thundercrown/`  
- **Purpose:** AI governance, orchestration, policy decision layer.  
- **Status:** ✅ ACTIVE — All key modules functional and tested.  
- **Resources:**  
  - ✅ `domain.ex`, `policy.ex`, `resources/agent_runner.ex`, `signing_service.ex`, `jobs/`  
- **Notes:** Fully integrated with governance policies and event ledger.  
  Key directive modules verified in `T72H_EVENT_LEDGER.md`.

---

### 🚦 ThunderFlow Domain  
- **Location:** `lib/thunderline/thunderflow/`  
- **Purpose:** Event pipeline, Broadway consumers, Telemetry, Reactor orchestration.  
- **Status:** ✅ ACTIVE — EventBus, pipeline, telemetry, and observability tools operational.  
- **Resources:**  
  - ✅ `domain.ex`, `event_bus.ex`, `pipelines/*`, `telemetry/*`, `support/*`, `resources/*`  
- **Notes:** Boundary violations (Flow→Gate metrics) noted in CODEBASE_STATUS.md (AUDIT‑02).  
  Otherwise production‑ready per HC audit.

---

### 🛡️ ThunderGate Domain  
- **Location:** `lib/thunderline/thundergate/`  
- **Purpose:** Security, authentication, authorization, ingress bridge.  
- **Status:** ⚠️ PARTIAL — Policy enforcement inconsistent; ~25% of resources lack tenant policies.  
- **Resources:**  
  - ✅ `domain.ex`, `authentication/magic_link_sender.ex`, `actor_context.ex`  
  - ⚠️ `resources/policy_rule.ex`, `resources/system_action.ex`, `resources/audit_log.ex` – missing tenancy checks  
- **Notes:** Core gateway active. Cross‑domain fix (Flow→Gate metrics) underway via event subscription model.  

---

### 🌐 ThunderGrid Domain  
- **Location:** `lib/thunderline/thundergrid/`  
- **Purpose:** Spatial data modeling, ECS-like grid for runtime orchestration.  
- **Status:** ⚠️ PARTIAL — Operable but lacks updated Ash policy enforcement on spatial resources.  
- **Resources:**  
  - ✅ `domain.ex`, `resources/grid_zone.ex`, `resources/zone.ex`, `resources/spatial_coordinate.ex`  
  - ⚠️ Zone-related policies commented out (see DOMAIN_SECURITY_PATTERNS.md).  
- **Notes:** Used by Crown orchestration and Vine pipelines; no broken dependencies.

---

### 🛰️ ThunderLink Domain  
- **Location:** `lib/thunderline/thunderlink/`  
- **Purpose:** Real-time federation, communication, LiveView event streaming.  
- **Status:** ⚠️ PARTIAL — Communication components active; federation policies outdated.  
- **Resources:**  
  - ✅ `domain.ex`, `chat/`, `transport/`, `presence/`  
  - ⚠️ `resources/channel.ex`, `resources/community.ex`, `resources/message.ex` – commented policies  
- **Notes:** Boundary violation flagged (Link→Block direct access). Pending AUDIT‑02 remediation.  

---

### 🍇 ThunderVine Domain  
- **Location:** `lib/thunderline/thundervine/`  
- **Purpose:** Workflow compaction and event rule parsing for Vine Ingress.  
- **Status:** ✅ ACTIVE — Compacting workers and parsers operational.  
- **Resources:**  
  - ✅ `events.ex`, `workflow_compactor.ex`, `workflow_compactor_worker.ex`  
- **Notes:** Integration verified through Vine‑Ingress tests; no policy violations.

---

### 🧠 ThunderForge Domain  
- **Location:** `lib/thunderline/thunderforge/`  
- **Purpose:** Factory blueprint and assembly orchestration for system synthesis.  
- **Status:** ✅ ACTIVE  
- **Resources:**  
  - ✅ `domain.ex`, `blueprint.ex`, `factory_run.ex`  

---

### 🧰 ThunderChief Domain  
- **Location:** `lib/thunderline/thunderchief/`  
- **Purpose:** Orchestration layer and job processor.  
- **Status:** ✅ ACTIVE  
- **Resources:**  
  - ✅ `orchestrator.ex`, `jobs/demo_job.ex`, `workers/demo_job.ex`  

---

### 👁️ ThunderWatch Domain  
- **Location:** `lib/thunderline/thunderwatch/`  
- **Purpose:** Legacy system observability (migrated to Gate).  
- **Status:** ⚠️ PARTIAL — Retained for backward compatibility only.  
- **Notes:** Functionality moved to `Thundergate.Thunderwatch`.  

---

### ⚡ ThunderCom Domain  
- **Location:** `lib/thunderline/thundercom/`  
- **Purpose:** Communication layer for unified chat and voice messaging.  
- **Status:** ❌ BROKEN — Deprecated in favor of ThunderLink voice modules.  
- **Resources:**  
  - ❌ `resources/voice_*`, `mailer.ex`  
- **Notes:** Redirect integrations to `Thunderline.Thunderlink.Voice.*`.  

---

### 🌩️ Additional Supporting Namespaces
| Domain | Location | Purpose | Status |
|---------|-----------|----------|--------|
| RAG | `lib/thunderline/rag/` | Retrieval-Augmented Generation models | ✅ ACTIVE |
| Dev | `lib/thunderline/dev/` | Internal diagnostics and linting | ✅ ACTIVE |
| Maintenance | `lib/thunderline/maintenance/` | Cleanup utilities | ✅ ACTIVE |
| ServiceRegistry | `lib/thunderline/service_registry/` | Service health & discovery | ✅ ACTIVE |

---

## Summary Statistics
| Classification | Count | Domains |
|----------------|--------|----------|
| ✅ Active | 6 | ThunderFlow, ThunderCrown, ThunderForge, ThunderChief, ThunderVine, RAG |
| ⚠️ Partial | 5 | ThunderBolt, ThunderGate, ThunderGrid, ThunderLink, ThunderWatch |
| ❌ Broken | 1 | ThunderCom |

**Total Domains Found:** 12 primary domains + 4 supporting namespaces  

---

## Cerebros Findings Summary  
- Cerebros modules under `thunderbolt/cerebros_*` fully migrated to standalone repo `/home/mo/DEV/cerebros`.  
- Bridge layer (`Thunderline.Thunderbolt.CerebrosBridge.*`) remains operational and gated by `features.ml_nas`.  
- Resources referencing old `Thunderbolt.Cerebros.*` paths are deprecated; all live references routed through Bridge.  
- Migration tracked in docs:  
  - `docs/documentation/phase3_cerebros_bridge_complete.md`  
  - `CEREBROS_REACT_SETUP.md`  
  - `CEREBROS_BRIDGE_PLAN.md`  

---

**✅ Deliverable ready:** `docs: domain catalog audited (Cerebros extraction noted)`
