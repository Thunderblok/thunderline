# MODULE_NAMING_STANDARDS.md  
**Epic 2: Module Organization Cleanup - Rookie Team Sprint 2**

---

## 🧭 Purpose  
Define and enforce consistent naming conventions across the Thunderline codebase per domain (`Thunderbolt`, `Thunderblock`, `Thundergate`, etc.).  
This ensures traceability, reduces redundancy, and supports domain-driven consistency under the `Thunderline.Rebuild Initiative`.

---

## ✳️ General Principles
| Aspect | Convention | Example |
|---------|-------------|----------|
| **Root Namespace** | All modules under `Thunderline.*` | `Thunderline.Thunderbolt.ML.ModelSpec` |
| **Resource Modules** | Place under `*.Resources.*` | `Thunderline.Thunderbolt.Resources.ModelRun` |
| **Domain Modules** | End with `.Domain` | `Thunderline.Thundergate.Domain` |
| **Worker / Task Modules** | Use `.Workers.` prefix | `Thunderline.Workers.CerebrosTrainer` |
| **API Integrations** | Use descriptive suffix (`Bridge`, `Client`, `Adapter`) | `Thunderline.Thunderbolt.CerebrosBridge.Client` |
| **Machine Learning stack** | Prefix with `.ML.` | `Thunderline.Thunderbolt.ML.TrainingRun` |

---

## 🏗️ Domain Naming Guidelines

### ⚡ Thunderbolt — ML, Compute, Orchestration
- Use `ML.*` for all machine learning resources and workers.  
- `Cerebros`, `AutoML`, `MLflow` represent specific service integrations.  
- Consolidate ad-hoc patterns (`TrainingDataset`, `CerebrosTrainingJob`)  
  → Phase 2 rename targets:  
  - `TrainingDataset` → `ML.Dataset`  
  - `CerebrosTrainingJob` → `ML.Job`  
  - `AutoMLDriver` → `ML.StudyCoordinator`  
- Example:  
  ```
  Thunderline.Thunderbolt.ML.Dataset
  Thunderline.Thunderbolt.ML.Job
  Thunderline.Thunderbolt.ML.StudyCoordinator
  ```

### 🔒 Thundergate — Access and Authentication
- Auth-related Plug and MagicLink modules remain in `.Thundergate.Authentication.*`  
- Avoid usage of abbreviated forms like `AuthCtrl` or `MagicLinker`; use full, semantically clear names.  
- Standard:
  ```
  Thunderline.Thundergate.Authentication.MagicLinkSender
  Thunderline.Thundergate.Plug.ActorContextPlug
  ```

### 🧠 Thundercrown — Policy and Decision Systems
- Keep `.Policy` and `.Action` modules grouped under `.Thundercrown`.  
- Example:
  ```
  Thunderline.Thundercrown.Policy
  Thunderline.Thundercrown.Action
  ```

### 🔗 Thunderlink — Federation and Communication
- Use `.Resources.*` for all linkable entities (`Community`, `Message`, `Role`).  
- Federation resources mirror naming in `Thundergate`.  
- Example:
  ```
  Thunderline.Thunderlink.Resources.Community
  Thunderline.Thunderlink.Resources.Role
  ```

### 💠 Thunderblock — Persistence and Vaults
- All vault, workflow, and PAC homes in `.Resources.*`.  
- Domain-level service modules (`VaultSecurity`, `WorkflowTracker`) standardized under `.Thunderblock.Resources`.

---

## 🪐 Cross-Domain Guidelines
- **Avoid duplicate conceptual roots** — e.g. `MachineTrainer`, `TrainerMachine`, and `MLTrainer` are redundant variants.
- **Use shared patterns for similar structures:**  
  - `<Domain>.<System>.<Entity>` (standardized)
  - Avoid `<Domain>.<Entity><System>` hybrids.

| Incorrect | Correct |
|------------|----------|
| `Thunderline.MLflowDriver` | `Thunderline.Thunderbolt.MLflow.Driver` |
| `Thunderline.TrainingJob` | `Thunderline.Thunderbolt.ML.TrainingJob` |

---

## 🧩 Phase-based Migration Plan

### **Phase 1 — Immediate Audit Alignment (Sprint 2–3)**
Rename and relocate low-risk modules (aliases, wrappers).  
- `EventBus` → `Deprecated.EventBusShim`
- `InMemory.Subscription` → `Support.Legacy.InMemorySubscription`

### **Phase 2 — Domain-Level Refactor (Thunderbolt ML Stack)**
- Merge duplicated ML job abstractions:
  ```
  CerebrosTrainingJob → ML.Job
  TrainingDataset → ML.Dataset
  HPOExecutor → ML.Optimizer
  ```
- Align internal folder structure:
  ```
  lib/thunderline/thunderbolt/ml/*
  ```

### **Phase 3 — Federation and Gate Unification**
- Normalize `Thundergate` & `Thunderlink` shared auth logic.
- Align `ActorContextPlug` across both via unified `AccessContextPlug`.

### **Phase 4 — Deprecation + Removal**
- Remove obsolete shims, including:
  - `EventBus`
  - `Thunderforge`
  - legacy adapters under `Support.Jido.InMemory.*`

---

## ⚙️ Enforcement
- Integrated via `mix lint.naming` (planned Sprint 4).
- Linter enforces domain suffixes and root namespace patterns.
- CI will fail for modules outside `Thunderline.*` root.
- Naming checks integrated with `mix precommit`.

---

**Generated:** 2025-10-31  
**Auditor:** Rookie Team Sprint 2  
**Reference:** `THUNDERLINE_DOMAIN_CATALOG.md`  
**Template:** Sprint Plan — Epic 2 (Module Organization Cleanup)