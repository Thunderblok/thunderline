# Thunderline & Cerebros Python Services

This document consolidates all active and experimental Python services deployed across Thunderline and Cerebros ecosystems.

---

## 🧩 **Service Categories**
- **MLflow Tracking**
- **Cerebros NAS Backend**
- **Utility / Sidecar Components**
- **Experimental or Deprecated**

---

## 🧠 Cerebros Python Service
- **Purpose:** Neural Architecture Search backend and training executor for Cerebros models  
- **Location:** `thunderhelm/cerebros_service/`
- **Port:** 8000 (default; defined in orchestration chart)
- **Status:** ⚠️ Partial (requires manual boot)
- **Start Command:**
  ```bash
  cd thunderhelm/cerebros_service
  source ../../.venv/bin/activate
  python cerebros_service.py
  ```
- **Dependencies:**
  - `requests>=2.31.0`
  - `tensorflow>=2.15.0`
  - `mlflow>=2.9.0`
  - `numpy>=1.24.0`
  - `colorlog>=6.8.0`
- **Health Check:**
  ```bash
  curl http://localhost:8000/health
  ```
- **Notes:**  
  - Interacts with **CerebrosBridge** component in Elixir (`lib/thunderline/thunderbolt/cerebros_bridge`).
  - Emits trial completion events carrying `spectral_norm` and `mlflow_run_id`.  
  - Is the upstream consumer from Cerebros Optuna integration.  
  - Used in `run_worker.ex` event translation (see phase3 docs).

---

## 📊 MLflow Tracking Service
- **Purpose:** Experiment tracking and results logging for model trials  
- **Location:** `thunderhelm/mlflow/`
- **Port:** 5000  
- **Status:** ✅ Active (self-contained service via MLflow binary)
- **Start Command:**
  ```bash
  cd thunderhelm/mlflow
  mlflow server --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns --host 0.0.0.0 --port 5000
  ```
- **Dependencies:**
  - `mlflow>=2.9.0`
  - `flask`, `sqlite3`, `gunicorn` (implicit runtime requirements)
- **Health Check:**
  ```bash
  curl http://localhost:5000/api/2.0/mlflow/experiments/list
  ```
- **Notes:**  
  - Thunderline `MLflow.Client` (Elixir) connects here via `MLFLOW_TRACKING_URI`.  
  - Synchronization handled by `lib/thunderline/thunderbolt/mlflow/sync_worker.ex`.  
  - Runs on containerized environment per Helm via `thunderhelm/deploy/chart/templates/mlflow-deployment.yaml`.  
  - Shared state persists at `mlruns/`.  

---

## 🧪 Cerebros Runner Prototype
- **Purpose:** Proof-of-concept orchestration script for Cerebros training workload execution  
- **Location:** `thunderhelm/deploy/cerebros_runner_poc.py`
- **Port:** N/A (local execution script)
- **Status:** ⚠️ Partial (used for research validation)
- **Start Command:**
  ```bash
  cd thunderhelm/deploy
  python cerebros_runner_poc.py
  ```
- **Dependencies:** Mirrors `thunderhelm/cerebros_service/requirements.txt`, but executes local tasks directly.  
- **Health Check:** Manual — verify completion logs for trial IDs.  
- **Notes:**  
  - Referenced from Helm charts under `cerebros-runner-configmap.yaml`.  
  - Acts as executable entrypoint for Cerebros training pods during Kubernetes runs.

---

## 🔬 Thunderline Python Bridge Stub
- **Purpose:** Minimal Python interop stub to simulate Cerebros module presence for Thunderline tests.  
- **Location:** `priv/cerebros_bridge_stub.py`  
- **Port:** N/A  
- **Status:** ⚠️ Partial — mocked utility only for development pipelines.  
- **Start Command:**
  ```bash
  python priv/cerebros_bridge_stub.py
  ```
- **Dependencies:** Standard library only.  
- **Health Check:** None.  
- **Notes:** Used for Elixir integration tests that simulate non-existent remote Python bridge.

---

## ⚙️ Shared Observations

| Service | Active | Port | Linked System |
|----------|---------|------|----------------|
| Cerebros Service | ⚠️ Partial | 8000 | CerebrosBridge |
| MLflow Server | ✅ Active | 5000 | MLflow Client + SyncWorker |
| Cerebros Runner POC | ⚠️ Partial | - | Cerebros Pod |
| Bridge Stub | ⚠️ Partial | - | Thunderline integration tests |

---

## 🧩 Shared Dependencies
| Library | Purpose |
|----------|----------|
| `requests` | HTTP communication between Python services |
| `mlflow` | Experiment tracking backend |
| `tensorflow` | Model training and optimization |
| `numpy` | Vector and matrix operations |
| `colorlog` | Enhanced terminal logging |

---

## 🔄 Thunderbolt ↔️ Cerebros Interoperability
- **Flow Summary (from Phase 3–5 documentation):**
  ```
  Cerebros Python → CerebrosBridge → ModelTrial
                                          ↓
                                      MLflow.Run
                                          ↓
                                      MLflow API
  ```
- **Key Connectors:**
  - `mlflow_run_id` for synchronization between Thunderline and MLflow
  - `spectral_norm` enables neural normalization tracking
  - `emit_trial_complete_event/2` publishes completion via Thunderline’s EventBus

---

## 🧭 Verification Notes
- Verified against:
  - [`docs/documentation/phase3_cerebros_bridge_complete.md`](docs/documentation/phase3_cerebros_bridge_complete.md)
  - [`docs/documentation/phase5_mlflow_foundation_complete.md`](docs/documentation/phase5_mlflow_foundation_complete.md)
  - [`CEREBROS_REACT_SETUP.md`](CEREBROS_REACT_SETUP.md) for frontend-to-backend interface expectations.

---

**✅ Summary Table:**
| Category | Services | Confirmed Active | Comment |
|-----------|-----------|------------------|----------|
| MLflow Tracking | MLflow service | ✅ | core experiment tracking |
| Cerebros NAS Backend | Cerebros service, Cerebros runner | ⚠️ | manual boot required |
| Utilities | Bridge stub | ⚠️ | mock mode only |
| Experimental | POC scripts | ⚠️ | not production-bound |

---

**Generated:** 2025-10-31  
**Maintainer:** Rookie Audit Task 4  
**Next Action:** Automation of deployment health checks via Helm release validator  