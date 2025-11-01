# Thunderline Dependency Map

## Elixir Dependencies
| Name | Version | Category | Status | Notes |
|------|----------|-----------|--------|-------|
| Phoenix | 1.8.1 | Web Framework | ✅ Active | Primary web backend using LiveView |
| Ash | 3.7.6 | ORM / Data Framework | ✅ Active | Core domain modeling framework |
| Ash AI | 0.3.0 | AI/Bridge | ✅ Active | Powers CerebrosBridge integration |
| Ash Postgres | 2.6.23 | Database/ORM | ✅ Active | Ecto-backed persistence |
| Oban | 2.20.1 | Background Jobs | ⚠️ Partial | Some jobs unreferenced post-refactor |
| Oban Web | 2.11.6 | Background Jobs | ✅ Active | Job UI management |
| NX / Axon / EXLA | 0.9–0.10 | AI/Neural Backend | ✅ Active | Neural ops for CerebrosBridge |
| Bumblebee | 0.6.3 | AI Model Zoo | ⚠️ Partial | Limited pretrained transformer use |
| Polaris | 0.1 | AI Utils | ✅ Active | Used in RAG pipeline |
| Pythonx | 0.4.7 | Bridge/Interop | ✅ Active | Embedded Python bridge (CerebrosBridge) |
| Venomous | 0.7.7 | Runtime Bridge | ✅ Active | Elixir↔Python interop via ErlPort |
| Postgres / Postgrex | 0.21.1 | Database | ✅ Active | Primary database adapter |
| Telemetry / OpenTelemetry | 1.3.0+ | Infra/Metrics | ✅ Active | Integrated tracing and metrics |
| Req | 0.5.15 | HTTP Client | ✅ Active | MLflow and API client |
| Plug / Plug.Cowboy | 2.7.4 | Web Server | ✅ Active | HTTP dispatch layer |
| Phoenix HTML / LV / Dashboard | 4.3.0 / 1.1 / 0.8.7 | UI Components | ✅ Active | Live interface and dashboards |
| Tailwind | 0.2.4 | Build Tools | ✅ Active | Asset pipeline |
| Ecto / EctoSQL | 3.13.x | Database | ✅ Active | Repo layer for Ash Postgres |
| Reactor | 0.15.6 | Orchestration | ✅ Active | Async workflows for domain pipelines |
| Broadway | 1.2.1 | Queue Processor | ⚠️ Partial | Used internally by Thunderflow |
| Rustler | 0.36.2 | NIF / Native | ⚠️ Partial | For libcerebros_numerics bindings |
| Timex | 3.7.13 | Utility | ✅ Active | Time ops |
| Credo | 1.7.13 | Lint | ✅ Active | Dev, code quality |
| Dialyxir | 1.4.6 | Dev Tools | ✅ Active | Static analysis |
| Gettext | 0.26.2 | Infra | ✅ Active | Localization |
| Tidewave | 0.5.0 | Dev Tools | ⚠️ Partial | Experimental MCP server |
| Ash Jido | latest | AI/Bridge | ⚠️ Partial | Limited use with Jido agents |

---

## Python Dependencies
| Package | Version | Context | Status |
|----------|----------|---------|--------|
| TensorFlow | ≥2.15.0 | ML/Training | ✅ Active |
| MLflow | ≥2.9.0 | Model Tracking | ✅ Active |
| Numpy | ≥1.24.0 | ML/Numerical | ✅ Active |
| Requests | ≥2.31.0 | Networking | ✅ Active |
| Colorlog | ≥6.8.0 | Logging | ⚠️ Partial |

**Notes:**  
Used by `thunderhelm/cerebros_service` for MLflow tracking, TensorFlow model orchestration, and communication with Elixir via Pythonx.

---

## Node/Frontend Dependencies
| Package | Version | Category | Notes |
|----------|----------|----------|-------|
| React | ^18.3.1 | UI Framework | Core for Cerebros Dashboard |
| ReactDOM | ^18.3.1 | UI Framework | Rendering layer |
| @llm-ui/react, markdown, code | ^0.13.3 | Cerebros Components | Frontend bindings for AI output rendering |
| React Markdown | ^9.0.1 | Visualization | Markdown display for model responses |
| Recharts | ^2.12.0 | Data Visualization | Dashboard charts |
| Phoenix LiveView | ^1.0.0 | Live Framework | Reactive Elixir↔JS interface |
| Phoenix HTML | ^4.0.0 | View Helpers | Template engine |
| TypeScript | ^5.4.0 | Build | Source typing |
| Esbuild | ^0.23.0 | Build Tool | Asset bundler |
| Three.js | ^0.168.0 | Visualization | 3D experimental dashboard components |

---

## Cross‑Stack Integration Notes
- **CerebrosBridge**:
  - Elixir (`pythonx`, `venomous`) connects to Python ML code in `thunderhelm/cerebros_service`.
  - Exchanges tensor and model run metadata via MLflow HTTP APIs using `Req` and `Requests`.
- **AI/Training Loop Integration**:
  - TensorFlow models triggered from Elixir orchestrations via task pipelines.
  - MLflow stores metadata and artifacts consumed by `Thunderline.Thunderbolt.MLflow.Client`.
- **Frontend Communication**:
  - React dashboard visualizes model telemetry data from Elixir’s LiveView API.
  - Uses `@llm-ui/react` for generated AI logs and Markdown responses.
- **Observability**:
  - Telemetry traces connect Phoenix, Oban, and Ash pipelines, exported via OpenTelemetry.

---

### Summary
**Total Dependencies Mapped:**  
- Elixir: 34 core packages (including framework + infra)  
- Python: 5  
- Node: 10  
**Deprecated/Partial:** 7 (e.g., Broadway, Bumblebee, Rustler experimental use)

**Key Integration Points:**  
- Elixir↔Python bridge through **CerebrosBridge (Pythonx + Venomous)**  
- ML tracking via **MLflow APIs**  
- React UI binds model outputs through **Cerebros React Components**
