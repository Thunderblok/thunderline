# 🧠 Thunderline CerebrosBridge Architecture

**Sprint Context:** Rookie Team Sprint 2 — Epic 3: _CerebrosBridge Integration Prep (Priority: CRITICAL)_  
**Purpose:** Document the architecture and data flow between **Thunderline (Elixir)** and **Cerebros Service (Python)** for immediate senior team integration.

---

## 1. Overview

CerebrosBridge is the Elixir ↔ Python interoperability layer connecting **Thunderline.Thunderbolt** to external Cerebros NAS, MLflow, and training services.

### Components
| Subsystem | Module | Purpose |
|------------|---------|----------|
| Cache | [`cache.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/cache.ex) | ETS-based in-memory cache for run contract results (supports TTL and eviction). |
| Client | [`client.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/client.ex) | Central API for performing bridge invocations, telemetry emission, and caching logic. |
| Contracts | [`contracts.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/contracts.ex) | Versioned structs representing standard NAS lifecycle contracts. |
| Invoker | [`invoker.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/invoker.ex) | Executes subprocesses calling the Cerebros Python scripts; retry and timeout logic. |
| Persistence | [`persistence.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/persistence.ex) | Synchronizes Trial/Run data into Ash resources (ModelRun, ModelTrial). |
| RunOptions | [`run_options.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/run_options.ex) | Generates standardized run specs and metadata for Oban jobs. |
| RunWorker | [`run_worker.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex) | Orchestrates the NAS lifecycle across start/run/finalize with telemetry integration. |
| Translator | [`translator.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/translator.ex) | Encodes bridge contracts into JSON payloads for Python consumption; decodes results. |
| Validator | [`validator.ex`](../../../lib/thunderline/thunderbolt/cerebros_bridge/validator.ex) | Environment sanity checker for Cerebros compatibility and configuration correctness. |

---

## 2. Data Flow

```mermaid
flowchart TD
    A[Phoenix/LiveView (User Triggers Run)] -->|Spec via RunOptions| B[RunWorker]
    B -->|Creates RunStartedV1 contract| C[Client.start_run()]
    C -->|Translate contract| D[Translator.encode()]
    D -->|Executes| E[Invoker.invoke() -> system(cmd)]
    E -->|PyBridge (via Pythonx / Venomous)| F[thunderhelm/cerebros_service.py]
    F -->|JSON result| G[Invoker.decode()]
    G -->|Success| H[Persistence.record_*()]
    H --> I[ModelRun & ModelTrial Updated]
    I --> J[MLflow.SyncWorker -> Python MLflow API]
    J --> K[Telemetry + EventBus.Emit]
```

---

## 3. Runtime Behavior

### 3.1 Telemetry & Retry Logic
- Invoker emits unified telemetry keys:
  - `[:cerebros, :bridge, :invoke, :start|:stop|:exception]`
- Retry logic using exponential backoff (`retry_backoff_ms` default 750ms).
- Timeout per attempt from configuration (default `15_000` ms).
- Cache tier (ETS) removes heat loads from repeat invocations.

### 3.2 Configuration Source
Loaded from `config :thunderline, :cerebros_bridge`.
```elixir
%{
  enabled?: true,
  repo_path: "thunderhelm/cerebros_service",
  script_path: "thunderhelm/cerebros_service/cerebros_service.py",
  python_executable: "python3",
  invoke: %{default_timeout_ms: 15000, max_retries: 2},
  cache: %{enabled?: true, ttl_ms: 30000}
}
```

### 3.3 Failure Modes
| Condition | Response | Responsible Module |
|------------|-----------|--------------------|
| Python timeout | Builds `ErrorClass :timeout` | Invoker |
| Script missing | Raises configuration error | Translator |
| MLflow unavailable | Emits warning via `MLEvents` | Persistence |
| Telemetry failure | Logged, non-fatal | Client |
| Unexpected exceptions | Captured, stored in `ModelRun.error_message` | RunWorker |

---

## 4. Cross‑Language Integration

From [`DEPENDENCY_MAP.md`](../../../DEPENDENCY_MAP.md):

**Bridge stack:** `Pythonx + Venomous + TensorFlow + MLflow`  

**Python entrypoint:** `thunderhelm/cerebros_service/cerebros_service.py`  
↳ receives STDIN JSON payloads matching contract versions  
↳ returns structured JSON results for NAS trials.

**Environment Variables Injected by Translator:**
| Name | Description |
|------|--------------|
| `CEREBROS_BRIDGE_OP` | Active operation (start_run, record_trial...) |
| `CEREBROS_BRIDGE_RUN_ID` | Current run identifier |
| `CEREBROS_BRIDGE_CORRELATION` | Trace correlation ID |
| `CEREBROS_BRIDGE_STATUS` | Run completion state |
| `CEREBROS_BRIDGE_PAYLOAD` | JSON input payload |

---

## 5. Dependency Cross‑References

| External Layer | Integration | Direction |
|----------------|--------------|-------------|
| **Cerebros Service (Python)** | Receives bridge JSON | Outbound |
| **MLflow Server** | Writes/reads Run metadata | Outbound |
| **Phoenix Controllers (Cerebros*)** | Expose web endpoints for UI | Inbound |
| **Ash Resources** | Update ModelRun, ModelTrial, ModelArtifact | Internal |
| **Telemetry + EventBus** | Publish real-time run events | Internal |
| **Oban Worker Queue** | Executes long tasks asynchronously | Internal |

---

## 6. Known Broken Points / Technical Debt

| Location | Issue |
|-----------|--------|
| [`run_worker.ex:26`](../../../lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex#L26) | Missing alias mismatch — `Thunderline.Thunderbolt.Cerebros.Telemetry` should be under `CerebrosBridge.Telemetry`. |
| `CerebrosMetricsController` and `CerebrosLive` | Deprecated bridge references per `CEREBROS_WEB_INVENTORY.md`. |
| TaskSupervision | No monitoring of Task shutdown failures in Invoker. |
| Cache eviction | No distributed cache sync; limited to node-local ETS. |

---

## 7. Observability and Telemetry

- Integrated with OpenTelemetry—emits `:cerebros_bridge` span events.
- Each bridge event carries:
  - `duration_ms`, `returncode`, and summarised payload excerpts.
- Telemetry tags enable cross-system visualization in observability dashboard.

---

## 8. Configuration Parity Validation

- Validator enforces environment existence:
  - Ensures Python executable exists & script path resolves.
  - Confirms MLflow, repo, cache entries configured.
- Used by operator CLI task:
  ```bash
  mix thunderline.ml.validate
  ```

---

## 9. Summary Table

| Layer | Technology | Function | Status |
|-------|-------------|-----------|---------|
| Bridge Layer | Elixir ↔ Pythonx | Translation/Orchestration | ✅ Stable |
| Model Lifecycle | Ash + MLflow | Run/Trial persistence | ✅ Active |
| EventBus/Telemetry | Phoenix + OpenTelemetry | Monitoring | ✅ Active |
| Frontend | React Dashboard via LiveView | Visualization | ⚠️ Partial |
| Cerebros Python Backend | TensorFlow + MLflow | NAS Backend | ⚠️ Partial |
| Oban + MLflow Sync | Async Integration | Background persistence | ✅ Stable |

---

**✅ Alignment Complete:**
Cross-verified against:  
- [`PYTHON_SERVICES.md`](../../../PYTHON_SERVICES.md)  
- [`CEREBROS_WEB_INVENTORY.md`](../../../docs/documentation/CEREBROS_WEB_INVENTORY.md)  
- [`DEPENDENCY_MAP.md`](../../../DEPENDENCY_MAP.md)  

**Generated:** 2025‑10‑31  
**Maintainer:** Rookie Team Sprint 2 — Bridge Audit Task 3