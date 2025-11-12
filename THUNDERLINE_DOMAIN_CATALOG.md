# Thunderline Domain Catalog  
**Audit Date:** November 5, 2025  
**Auditor:** Domain Reorganization Team  
**Status:** 🔄 Updated – ThunderJam/ThunderClock consolidated per architectural intent  

---

### ⚡ ThunderBlock Domain  
- **Location:** `lib/thunderline/thunderblock/`  
- **Purpose:** VM, Runtime, Persistence, Timing & Scheduling  
- **Status:** ⚠️ PARTIAL — Active retention system, several resources missing Ash policy compliance  
- **Expanded Scope:** Now includes all timing/scheduling functionality (formerly ThunderClock)
- **Resources:**  
  - ✅ `retention.ex`, `jobs/retention_sweep_worker.ex`  
  - ⚠️ `resources/vault_*` (partially compliant, pending policy fixes)  
  - ❌ `resources/pac_home.ex` – commented policies (see DOMAIN_SECURITY_PATTERNS.md)  
  - 🔄 **NEW:** `timing/` - Timer, scheduler, cron job management (from ThunderClock)
- **Key Responsibilities:**
  - Vault memory & persistence
  - Retention policies & Oban sweeps
  - Timer/scheduler management
  - Delayed execution
  - Cron job orchestration
  - VM runtime lifecycle
- **Notes:** Stale "authorize_if always()" resources flagged in `DOMAIN_SECURITY_PATTERNS.md`.  
  Requires completion of AUDIT‑01; no missing dependencies.  
  **Migration:** ThunderClock functionality consolidated here (runtime concern).

---

### ⚙️ ThunderBolt Domain  
- **Location:** `lib/thunderline/thunderbolt/`  
- **Purpose:** ML/AI Execution, HPO, AutoML & Numeric Computation  
- **Status:** 🟢 ACTIVE — Cerebros migrated; ML infrastructure ready for implementation (Python TensorFlow 2.20.0 + Elixir Ortex 0.1.10).  
- **Resources:**  
  - ✅ `mlflow/`, `resources/upm_*`, `hpo_executor.ex`, `auto_ml_driver.ex`  
  - ✅ `cerebros_bridge/` — migrated modules (Client, Cache, Contracts, Invoker, Persistence, Translator, Validator)  
  - ⚠️ `resources/cerebros_training_job.ex`, `resources/model_run.ex`, `resources/model_trial.ex` — rely on external Cerebros Bridge  
  - ❌ `resources/model_artifact.ex` — deprecated, not referenced  
- **Key Responsibilities:**
  - ML workflow execution & orchestration
  - Hyperparameter Optimization (HPO) execution
  - AutoML driver management
  - MLflow integration & experiment tracking
  - Cerebros NAS bridge (neural architecture search)
  - UPM (Unified Project Management) coordination
  - Numeric computation & solver routines
  - Model training job execution
- **Notes:** Cerebros extraction complete (see `phase3_cerebros_bridge_complete.md`).  
  Domain partially delegated to `/home/mo/DEV/cerebros`.  
  References now controlled via `CerebrosBridge.*` clients, toggled by `features.ml_nas`.  
  Execution domain - does NOT handle governance (see ThunderCrown for policies).  

---

### 🔮 ThunderCrown Domain  
- **Location:** `lib/thunderline/thundercrown/`  
- **Purpose:** AI Governance, Policy Decisions & Orchestration Coordination  
- **Status:** ✅ ACTIVE — All key modules functional and tested.  
- **Resources:**  
  - ✅ `domain.ex`, `policy.ex`, `resources/agent_runner.ex`, `signing_service.ex`, `jobs/`  
- **Key Responsibilities:**
  - AI governance policy definitions & enforcement
  - Agent orchestration coordination (coordinates, doesn't execute)
  - Policy decision logic & rule evaluation
  - Agent runner management & lifecycle
  - Signing service for security attestation
  - Job orchestration coordination (not job execution)
  - Cross-domain governance boundaries
- **Notes:** Fully integrated with governance policies and event ledger.  
  Key directive modules verified in `T72H_EVENT_LEDGER.md`.  
  Governance domain - does NOT execute workflows (see ThunderBolt for execution).

---

### 🚦 ThunderFlow Domain  
- **Location:** `lib/thunderline/thunderflow/`  
- **Purpose:** Event Bus, Event Sourcing & Telemetry Pipeline  
- **Status:** ✅ ACTIVE — EventBus, pipeline, telemetry, and observability tools operational.  
- **Resources:**  
  - ✅ `domain.ex`, `event_bus.ex`, `pipelines/*`, `telemetry/*`, `support/*`, `resources/*`  
- **Key Responsibilities:**
  - Event Bus implementation & management
  - Event validation & routing
  - Broadway pipeline orchestration
  - Telemetry collection & aggregation
  - Observability infrastructure
  - Event sourcing & replay
  - Metrics pipeline (NOT rate limiting - see ThunderGate)
- **Notes:** Boundary violations (Flow→Gate metrics) noted in CODEBASE_STATUS.md (AUDIT‑02).  
  Otherwise production‑ready per HC audit.

---

### 🛡️ ThunderGate Domain  
- **Location:** `lib/thunderline/thundergate/`  
- **Purpose:** Security, Authentication, Authorization, Rate Limiting & Bridge  
- **Status:** ⚠️ PARTIAL — Policy enforcement inconsistent; ~25% of resources lack tenant policies.  
- **Expanded Scope:** Now includes all rate limiting/QoS functionality (formerly ThunderJam)
- **Resources:**  
  - ✅ `domain.ex`, `authentication/magic_link_sender.ex`, `actor_context.ex`  
  - ⚠️ `resources/policy_rule.ex`, `resources/system_action.ex`, `resources/audit_log.ex` – missing tenancy checks  
  - 🔄 **NEW:** `rate_limiting/` - Rate limiter, throttling, QoS, token bucket (from ThunderJam)
- **Key Responsibilities:**
  - Authentication (magic link, OAuth, API keys)
  - Authorization & policy enforcement
  - Rate limiting & throttling
  - QoS policies
  - Token bucket algorithms
  - Sliding window limits
  - Audit logging
  - Security bridges to external systems
  - Ingress hardening
- **Notes:** Core gateway active. Cross‑domain fix (Flow→Gate metrics) underway via event subscription model.  
  **Migration:** ThunderJam functionality consolidated here (security concern).  
  **Rate Limiter:** Uses Ash's default rate limiting extension.  

---

### 🌐 ThunderGrid Domain  
- **Location:** `lib/thunderline/thundergrid/`  
- **Purpose:** Network GraphQL Mapping, Spatial Data & ECS Grid  
- **Status:** ⚠️ PARTIAL — Operable but lacks updated Ash policy enforcement on spatial resources.  
- **Resources:**  
  - ✅ `domain.ex`, `resources/grid_zone.ex`, `resources/zone.ex`, `resources/spatial_coordinate.ex`  
  - ⚠️ Zone-related policies commented out (see DOMAIN_SECURITY_PATTERNS.md).  
- **Key Responsibilities:**
  - Spatial coordinate management
  - Grid zone orchestration
  - GraphQL API layer & schema mapping
  - Network topology modeling
  - ECS-like grid for runtime orchestration
  - Spatial query optimization
- **Notes:** Used by Crown orchestration and Vine pipelines; no broken dependencies.

---

### 🛰️ ThunderLink Domain  
- **Location:** `lib/thunderline/thunderlink/`  
- **Purpose:** Network Connections, Transport Layer & Presence  
- **Status:** ⚠️ PARTIAL — Transport components active; presence policies outdated.  
- **Resources:**  
  - ✅ `domain.ex`, `transport/`, `presence/`  
  - ⚠️ Connection pooling, WebSocket management  
- **Key Responsibilities:**
  - TCP/UDP connection management
  - WebSocket connections
  - Presence tracking
  - Transport layer protocols
  - Connection pooling
  - Network-level operations
- **Notes:** Boundary violation flagged (Link→Block direct access). Pending AUDIT‑02 remediation.  
  **Clarification:** Handles CONNECTIONS, not communication content (see ThunderCom for messaging).  

---

### 🍇 ThunderVine Domain  
- **Location:** `lib/thunderline/thundervine/`  
- **Purpose:** DAG Workflows, Event Rule Parsing & Compaction  
- **Status:** ✅ ACTIVE — Compacting workers and parsers operational.  
- **Resources:**  
  - ✅ `events.ex`, `workflow_compactor.ex`, `workflow_compactor_worker.ex`  
- **Key Responsibilities:**
  - Directed Acyclic Graph (DAG) workflow construction
  - Event rule parsing & validation
  - Workflow compaction & optimization
  - Vine Ingress rule management
  - Workflow transformation
- **Notes:** Integration verified through Vine‑Ingress tests; no policy violations.

---

### 🔨 ThunderForge Domain  
- **Location:** `lib/thunderline/thunderforge/`  
- **Purpose:** Parsing, Lexing, Low-Level Processing & Rust Integration  
- **Status:** ✅ ACTIVE  
- **Resources:**  
  - ✅ `domain.ex`, `blueprint.ex`, `factory_run.ex`, `parsers/`, `lexers/`  
- **Key Responsibilities:**
  - Parser implementation
  - Lexer construction
  - AST generation
  - Factory blueprints & assembly
  - System synthesis orchestration
  - Rust NIF integration (low-level operations)
  - Low-level data transformation  

---

### 🧰 ThunderChief Domain  
- **Location:** `lib/thunderline/thunderchief/`  
- **Purpose:** High-Level Orchestration & Cross-Domain Coordination  
- **Status:** ✅ ACTIVE  
- **Resources:**  
  - ✅ `orchestrator.ex`, `jobs/demo_job.ex`, `workers/demo_job.ex`  
- **Key Responsibilities:**
  - High-level orchestration coordination
  - Job processor management
  - Cross-domain workflow coordination
  - Task scheduling coordination (coordinates, doesn't execute)
  - System-wide orchestration logic  

---

### 👁️ ThunderWatch Domain  
- **Location:** `lib/thunderline/thunderwatch/`  
- **Purpose:** Legacy system observability (migrated to Gate).  
- **Status:** ⚠️ PARTIAL — Retained for backward compatibility only.  
- **Notes:** Functionality moved to `Thundergate.Thunderwatch`.  

---

### 💬 ThunderCom Domain  
- **Location:** `lib/thunderline/thundercom/`  
- **Purpose:** Communication, Social, Messaging & Federation  
- **Status:** ⚠️ NEEDS REACTIVATION — Distinct from ThunderLink (handles message content, not connections)  
- **Resources:**  
  - ⚠️ `resources/voice_*`, `mailer.ex`, `chat/`, `messaging/`  
- **Key Responsibilities:**
  - Chat systems & messaging
  - Social features (communities, channels)
  - Federation protocols
  - Voice communication content
  - Message routing & delivery
  - Email/notification systems
- **Notes:** **NOT DEPRECATED** - Separate from ThunderLink.  
  **Clarification:** ThunderCom = communication CONTENT (messages, chat, voice)  
  **vs.** ThunderLink = network CONNECTIONS (transport, presence, websockets).  

---

### 🌩️ Additional Supporting Namespaces
| Domain | Location | Purpose | Status |
|---------|-----------|----------|--------|
| RAG | `lib/thunderline/rag/` | Retrieval-Augmented Generation models | ✅ ACTIVE |
| Dev | `lib/thunderline/dev/` | Internal diagnostics and linting | ✅ ACTIVE |
| Maintenance | `lib/thunderline/maintenance/` | Cleanup utilities | ✅ ACTIVE |
| ServiceRegistry | `lib/thunderline/service_registry/` | Service health & discovery | ✅ ACTIVE |

---

## ❌ Deprecated Domains

### ThunderJam (DEPRECATED — Consolidated into ThunderGate)
- **Former Location:** `lib/thunderline/thunderjam/`
- **Former Purpose:** Rate limiting, throttling, QoS policies, token bucket algorithms
- **Deprecation Date:** November 5, 2025
- **Migration Target:** `ThunderGate.RateLimiting` (subdomain)
- **New Location:** `lib/thunderline/thundergate/rate_limiting/`
- **Rationale:** Rate limiting is a security/ingress concern, not a standalone domain. Consolidating into ThunderGate aligns with architectural principle that rate limiting, throttling, and QoS are fundamentally security boundaries.
- **Action Required:** 
  - Update all references: `Thunderline.Thunderjam.*` → `Thunderline.Thundergate.RateLimiting.*`
  - Use Ash's default rate limiting extension for new implementations
  - See `DOMAIN_REORGANIZATION_PLAN.md` for complete migration checklist
- **Status:** ⚠️ MIGRATION IN PROGRESS — Documentation updated, code migration pending

### ThunderClock (DEPRECATED — Consolidated into ThunderBlock)
- **Former Location:** `lib/thunderline/thunderclock/`
- **Former Purpose:** Timers, schedulers, cron jobs, delayed execution, temporal coordination
- **Deprecation Date:** November 5, 2025
- **Migration Target:** `ThunderBlock.Timing` (subdomain)
- **New Location:** `lib/thunderline/thunderblock/timing/`
- **Rationale:** Timing and scheduling are runtime management concerns, not separate infrastructure. Consolidating into ThunderBlock aligns with architectural principle that timer/scheduler management is intrinsically tied to VM lifecycle and runtime operations.
- **Action Required:**
  - Update all references: `Thunderline.Thunderclock.*` → `Thunderline.Thunderblock.Timing.*`
  - Integrate timer resources with VM runtime lifecycle
  - See `DOMAIN_REORGANIZATION_PLAN.md` for complete migration checklist
- **Status:** ⚠️ MIGRATION IN PROGRESS — Documentation updated, code migration pending

---

## Summary Statistics
| Classification | Count | Domains |
|----------------|--------|----------|
| ✅ Active | 7 | ThunderFlow, ThunderCrown, ThunderForge, ThunderChief, ThunderVine, ThunderBlock (with Timing), RAG |
| ⚠️ Partial | 4 | ThunderBolt, ThunderGate (with RateLimiting), ThunderGrid, ThunderLink |
| ⚠️ Needs Reactivation | 1 | ThunderCom |
| ❌ Legacy | 1 | ThunderWatch |
| ❌ Deprecated | 2 | ThunderJam (→ ThunderGate), ThunderClock (→ ThunderBlock) |

**Total Active/Partial Domains:** 12 canonical domains + 4 supporting namespaces  
**Deprecated Domains:** 2 (consolidated into parent domains)  
**Domain Consolidation:** ThunderJam + ThunderClock eliminated via consolidation strategy  

**Note:** Domain count reflects post-consolidation architecture. ThunderJam functionality now lives in `ThunderGate.RateLimiting`, ThunderClock functionality now lives in `ThunderBlock.Timing`.  

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
