# ML Pipeline Execution Roadmap

**Status**: 🟢 ACTIVE - Magika Complete, ONNX In Progress  
**Updated**: November 12, 2025  
**Completion**: 33% (Magika ✅, ONNX + Voxel + spaCy pending)

## Overview

This roadmap tracks the end-to-end ML pipeline implementation from file classification through inference to DAG packaging. Surgical execution order prioritizes impact: **ONNX first** (speed + in-process reliability), then **Voxelization** (DAG truth), **spaCy hardened** right after.

**Philosophy**: *Festina lente* — make haste, slowly. Ship with acceptance criteria, telemetry, and graceful degradation at every layer.

---

## Progress Tracker

### Phase 0: Magika Integration ✅ **COMPLETE**
**Duration**: 2 weeks (Oct 28 - Nov 11, 2025)  
**Deliverables**: 
- ✅ Core wrapper (420 lines)
- ✅ Unit tests (11 cases) + Integration tests (6 scenarios)
- ✅ Broadway consumer + EventBus producer
- ✅ Configuration + Supervision
- ✅ Documentation (MAGIKA_QUICK_START.md)
- ✅ Production-ready status

**Events**: `ui.command.ingest.received` → `system.ingest.classified`  
**Telemetry**: `[:thunderline, :thundergate, :magika, :classify, :*]`

---

## Active Work

### Phase 1: Sanity & Guardrails (0.5 days - Parallelizable)
**Status**: 🟡 NOT STARTED  
**Owner**: DevOps/Core Elixir  
**Priority**: P0 (blocks ONNX production rollout)

#### Tasks

**1.1 Magika E2E CI Smoke Tests**
- **Goal**: Validate end-to-end file classification in CI
- **Scope**:
  - Test 6-10 real file types (PDF, PNG, JSON, HTML, MP4, DOCX, etc.)
  - Assert `system.ingest.classified` event emission
  - Verify DLQ routing on failures
  - Confirm correlation ID propagation through pipeline
- **Deliverable**: CI job "Magika E2E" passes on every commit
- **Files**: `.github/workflows/magika-e2e.yml`, `test/integration/magika_ci_test.exs`

**1.2 Feature Flag Verification**
- **Goal**: Ensure graceful degradation when ML pipeline disabled
- **Scope**:
  - Boot with `TL_ENABLE_ML_PIPELINE=false`
  - Verify no crashes, no error spam
  - Document fallback behavior
- **Deliverable**: Test case validates flag flip safety
- **Files**: `test/integration/ml_pipeline_flag_test.exs`

**1.3 Telemetry Budget & Metrics**
- **Goal**: Production-grade observability for Magika
- **Scope**:
  - Confirm metric names + cardinality limits (< 1000 unique label combinations)
  - Cap labels (max 10 per metric)
  - Add histogram: `[:thunderline, :thundergate, :magika, :classify, :latency]`
  - Create Grafana panel: p50/p95/p99 latency
- **Deliverable**: Grafana dashboard renders live Magika metrics
- **Files**: `priv/grafana/magika_dashboard.json`

**Acceptance**:
- ✅ CI job "Magika E2E" green
- ✅ Feature flag flip has no crashes
- ✅ Grafana panel shows p50/p95/p99 for Magika

---

### Phase 2: ONNX Inference Adapter (2-3 days)
**Status**: 🟡 NOT STARTED  
**Owner**: Core Elixir  
**Priority**: P0 (critical path)

**Goal**: Run models in-process on BEAM using ONNX Runtime (Ortex). No external Python process for inference.

#### Tasks

**2.1 Model I/O Contract**
- **Goal**: Define standardized tensor input/output contracts
- **Scope**:
  ```elixir
  defmodule Thunderline.ML.Input do
    @type t :: %__MODULE__{
      tensor: Nx.Tensor.t(),
      dtype: atom(),
      shape: tuple()
    }
    defstruct [:tensor, :dtype, :shape]
  end

  defmodule Thunderline.ML.Output do
    @type t :: %__MODULE__{
      tensor: Nx.Tensor.t(),
      meta: map()
    }
    defstruct [:tensor, :meta]
  end
  ```
  - Create `Thunderline.ML.Normalize` helpers:
    - `cast_to_float32/1`
    - `reshape_nhwc_to_nchw/1` (image format conversion)
    - `standardize/2` (mean/std normalization)
- **Deliverable**: `lib/thunderline/ml/input.ex`, `lib/thunderline/ml/output.ex`, `lib/thunderline/ml/normalize.ex`
- **Tests**: `test/thunderline/ml/normalize_test.exs` (tensor ops, shape conversions)

**2.2 KerasONNX Adapter Module**
- **Goal**: Elixir-native ONNX inference via Ortex
- **Scope**:
  ```elixir
  defmodule Thunderline.ML.KerasONNX do
    @moduledoc """
    ONNX Runtime adapter using Ortex for in-process ML inference.
    """

    @type model :: %__MODULE__{
      session: Ortex.Session.t(),
      io_spec: map(),
      metadata: map()
    }
    defstruct [:session, :io_spec, :metadata]

    @spec load!(binary() | Path.t(), keyword()) :: model()
    def load!(path_or_bytes, opts \\ [])

    @spec infer(model(), [ML.Input.t()], keyword()) :: 
      {:ok, [ML.Output.t()], map()} | {:error, term()}
    def infer(model, inputs, opts \\ [])
  end
  ```
  - Load ONNX from file or binary blob
  - Extract input/output metadata (names, shapes, dtypes)
  - Run inference with timing + correlation token
  - Return outputs + telemetry metadata
- **Deliverable**: `lib/thunderline/ml/keras_onnx.ex`
- **Tests**: `test/thunderline/ml/keras_onnx_test.exs` (load, infer, error handling)

**2.3 Resource Management & Supervision**
- **Goal**: Long-lived, supervised ONNX sessions
- **Scope**:
  - Supervisor for model sessions: `Thunderline.ML.SessionSupervisor`
  - One supervised process per loaded model
  - Pre-warm models on application boot
  - Health probe: periodic inference on dummy tensor
  - Auto-restart on failure with backoff
  - Graceful shutdown (cleanup ONNX resources)
- **Deliverable**: `lib/thunderline/ml/session_supervisor.ex`, updated `application.ex`
- **Tests**: `test/thunderline/ml/session_supervisor_test.exs` (crash recovery, health probe)

**2.4 Backpressure & Broadway Integration**
- **Goal**: Production-grade inference pipeline with backpressure
- **Scope**:
  - Broadway consumer: `Thunderline.Thunderflow.Consumers.MLInference`
  - Batch size tuning (default: 10 messages/batch)
  - Concurrency config (default: 2 concurrent batches)
  - Drop/queue policy: `:drop_oldest` when overload
  - DLQ on inference failure:
    - Event: `system.dlq.ml_inference_failed`
    - Payload: original event + error reason + stack trace
  - Success event: `system.ml.inference.completed`
    - Metadata: model name, inference time, correlation_id, causation_id
- **Deliverable**: `lib/thunderline/thunderflow/consumers/ml_inference.ex`
- **Tests**: `test/thunderline/thunderflow/consumers/ml_inference_test.exs` (batching, DLQ, backpressure)

**2.5 Configuration & Feature Flags**
- **Goal**: Runtime configuration for ONNX behavior
- **Scope**:
  - Environment variables:
    - `TL_ONNX_ENABLED` (default: `false`, requires opt-in)
    - `TL_ONNX_THREADPOOL` (default: `4`, CPU threads for inference)
    - `TL_ONNX_EXECUTION_PROVIDER` (default: `"cpu"`, future: `"cuda"`)
    - `TL_ONNX_MODEL_DIR` (default: `"priv/models"`)
  - Runtime.exs configuration:
    ```elixir
    config :thunderline, Thunderline.ML.KerasONNX,
      enabled: System.get_env("TL_ONNX_ENABLED", "false") == "true",
      threadpool_size: String.to_integer(System.get_env("TL_ONNX_THREADPOOL", "4")),
      execution_provider: System.get_env("TL_ONNX_EXECUTION_PROVIDER", "cpu"),
      model_dir: System.get_env("TL_ONNX_MODEL_DIR", "priv/models")
    ```
- **Deliverable**: Updated `config/runtime.exs`

**2.6 Documentation - ONNX Quick Start**
- **Goal**: Developer-friendly guide for ONNX integration
- **Scope**:
  - Installation: Ortex dependency (already in mix.exs)
  - Model preparation: Keras → ONNX conversion
  - Configuration: Environment variables
  - API reference: `load!/2`, `infer/3`
  - Event flow: `system.ingest.classified` → `system.ml.inference.completed`
  - Telemetry: Event names, measurements, metadata
  - Error handling: DLQ routing, failure modes
  - Examples: Load model, run inference, handle results
- **Deliverable**: `docs/ONNX_QUICK_START.md`

**2.7 Acceptance Testing**
- **Goal**: Production readiness validation
- **Scope**:
  - Load ONNX model (dummy 224x224 image classifier)
  - Round-trip inference: random tensor → predictions
  - Assert p95 latency < 100ms (on dev machine)
  - Test failure → DLQ event + telemetry error
  - Broadway stability: 5× load (50 msg/sec) for 60 seconds
    - No mailbox growth
    - No memory leaks
    - DLQ rate < 1%
- **Deliverable**: `test/integration/onnx_acceptance_test.exs`

**Acceptance**:
- ✅ Load ONNX model and round-trip dummy tensor
- ✅ p95 inference latency recorded in telemetry
- ✅ Failure emits DLQ + telemetry error event
- ✅ Broadway stable under 5× synthetic load without mailbox growth

---

### Phase 3: Keras → ONNX Packaging (1-2 days)
**Status**: 🟡 NOT STARTED  
**Owner**: Python/NLP  
**Priority**: P1 (enables model supply chain)

**Goal**: Trivial path for Keras-trained models to ONNX production deployment.

#### Tasks

**3.1 Exporter CLI**
- **Goal**: Python CLI for Keras → ONNX conversion
- **Scope**:
  ```bash
  python keras2onnx_cli.py \
    --in model.keras \
    --out model.onnx \
    --opset 17 \
    --input-name input_1 \
    --output-name output_1
  ```
  - Uses `tf2onnx` for conversion
  - Validates input/output names
  - Sets ONNX opset version (17 = widely compatible)
  - Logs conversion summary (nodes, params, size)
- **Deliverable**: `python/keras2onnx_cli.py`
- **Tests**: `python/test_keras2onnx.py` (conversion, validation)

**3.2 Equivalence Validation Script**
- **Goal**: Verify Keras ≈ ONNX (numerical equivalence)
- **Scope**:
  - Fixed test vector (e.g., random 224x224x3 image)
  - Run through Keras model → `keras_output`
  - Run through ONNX model → `onnx_output`
  - Assert: `max(abs(keras_output - onnx_output)) ≤ 1e-4`
  - Emit JSON report:
    ```json
    {
      "model": "classifier_v1",
      "max_abs_diff": 8.3e-6,
      "mean_abs_diff": 2.1e-7,
      "status": "PASS",
      "timestamp": "2025-11-12T14:32:00Z"
    }
    ```
- **Deliverable**: `python/validate_equivalence.py`
- **Tests**: `python/test_validation.py`

**3.3 Model Repository Layout**
- **Goal**: Standardized model storage structure
- **Scope**:
  ```
  models/
  ├── classifier_v1/
  │   ├── keras/
  │   │   └── model.keras
  │   ├── onnx/
  │   │   └── model.onnx
  │   ├── sample_io.json      # Example input/output tensors
  │   └── VAL_REPORT.json     # Equivalence validation result
  ├── sentiment_v2/
  │   ├── keras/
  │   ├── onnx/
  │   ├── sample_io.json
  │   └── VAL_REPORT.json
  └── README.md               # Model registry documentation
  ```
- **Deliverable**: `models/` directory structure + `models/README.md`

**3.4 Elixir Model Registry**
- **Goal**: Configuration-driven model loading
- **Scope**:
  ```elixir
  # config/runtime.exs
  config :thunderline, Thunderline.ML.Registry,
    models: [
      classifier: [
        path: "models/classifier_v1/onnx/model.onnx",
        input_shape: {1, 224, 224, 3},
        preload: true  # Load on boot
      ],
      sentiment: [
        path: "models/sentiment_v2/onnx/model.onnx",
        input_shape: {1, 128},
        preload: false  # Lazy load
      ]
    ]
  ```
  - `Thunderline.ML.Registry.get_model(:classifier)` → returns loaded model
  - `Thunderline.ML.Registry.list_models()` → available models
  - Validates checksums on load (SHA256)
- **Deliverable**: `lib/thunderline/ml/registry.ex`
- **Tests**: `test/thunderline/ml/registry_test.exs`

**3.5 CI - Model Equivalence Job**
- **Goal**: Automated validation on model changes
- **Scope**:
  - Detect new/changed `.keras` files in `models/`
  - Run `keras2onnx_cli.py` + `validate_equivalence.py`
  - Assert: `VAL_REPORT.json` shows `"status": "PASS"`
  - Fail CI if max_abs_diff > 1e-4
  - Upload artifacts: ONNX models + validation reports
- **Deliverable**: `.github/workflows/model-equivalence.yml`

**Acceptance**:
- ✅ Given `model.keras`, produces `model.onnx` + passing equivalence report
- ✅ CI job "Model Equivalence" green on model changes

---

### Phase 4: Voxel/Thunderbit Packager (2-3 days)
**Status**: 🟡 NOT STARTED  
**Owner**: Core Elixir  
**Priority**: P1 (DAG truth layer)

**Goal**: Package classified artifacts + ML outputs into voxel envelopes for routing, storage, and reasoning.

#### Tasks

**4.1 Voxel Schema Definition**
- **Goal**: Define voxel data structure
- **Scope**:
  ```elixir
  defmodule Thunderline.Voxel do
    @moduledoc """
    Voxel: Spatio-temporal data envelope with lineage tracking.
    """

    use Ash.Resource,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshEvents.Events]

    @type coords :: {t :: integer(), x :: float(), y :: float(), z :: float()}
                  | {t :: integer(), channel :: atom(), position :: integer()}

    attributes do
      uuid_primary_key :id
      attribute :ts, :utc_datetime_usec, allow_nil?: false
      attribute :source, :string, allow_nil?: false
      attribute :coords, :map, allow_nil?: false  # Polymorphic coords
      attribute :traits, :map, default: %{}
      attribute :payload_ref, :string  # Object store key
      attribute :checksums, :map, allow_nil?: false  # SHA256 hashes
      attribute :lineage, {:array, :string}, default: []  # Parent event IDs
    end

    # Lineage must be acyclic (verified in changeset)
  end
  ```
- **Deliverable**: `lib/thunderline/thunderblock/resources/voxel.ex`
- **Tests**: `test/thunderline/thunderblock/voxel_test.exs` (schema, validation)

**4.2 Voxel Builder API**
- **Goal**: Construct voxels from events + features
- **Scope**:
  ```elixir
  defmodule Thunderline.Voxel do
    @spec build(Event.t(), map(), keyword()) :: 
      {:ok, t()} | {:error, term()}
    def build(event, features, opts \\ [])

    @spec persist(t()) :: {:ok, t()} | {:error, term()}
    def persist(voxel)
  end
  ```
  - Extract coords from event metadata
  - Build lineage from event IDs (correlation/causation)
  - Verify acyclic lineage (detect cycles)
  - Compute checksums (SHA256 of payload)
  - Emit event: `system.voxel.created`
    - Metadata: correlation_id, causation_id, voxel_id
- **Deliverable**: `lib/thunderline/voxel/builder.ex`
- **Tests**: `test/thunderline/voxel/builder_test.exs` (build, lineage, cycles)

**4.3 Voxel Persistence Layer**
- **Goal**: Store voxels with large payload support
- **Scope**:
  - Ash resource for voxel metadata (Postgres)
  - Object store for large payloads (S3/local file):
    - Small payloads (< 1MB): inline in Postgres
    - Large payloads (≥ 1MB): external object store
  - Checksum verification on read:
    - Assert SHA256 matches stored checksum
    - Emit warning on mismatch (potential corruption)
  - Integration with ThunderBlock domain
- **Deliverable**: `lib/thunderline/thunderblock/voxel_store.ex`
- **Tests**: `test/thunderline/thunderblock/voxel_store_test.exs` (CRUD, checksums)

**4.4 Voxel Acceptance Testing**
- **Goal**: End-to-end voxel pipeline validation
- **Scope**:
  - Unit tests:
    - Lineage integrity (no cycles)
    - Checksum verification (SHA256)
    - Coords validation (various formats)
  - Integration test:
    - Flow: `Magika` → `(optional ONNX)` → `Voxel` → `stored`
    - Assert: `system.voxel.created` event emitted
    - Verify: correlation_id chain intact
    - Check: payload retrievable with correct checksum
- **Deliverable**: 
  - `test/thunderline/voxel_test.exs` (unit)
  - `test/integration/voxel_pipeline_test.exs` (E2E)

**Acceptance**:
- ✅ Unit tests for lineage integrity and checksum verification
- ✅ E2E: Magika→(optional ONNX)→Voxel→stored; emits `system.voxel.created`

---

### Phase 5: spaCy Sidecar (1-2 days)
**Status**: 🟡 NOT STARTED  
**Owner**: Python/NLP + Core Elixir  
**Priority**: P1 (NLP pipeline)

**Goal**: Robust NLP processing via subprocess boundary. JSON over stdin/stdout, msgpack later if needed.

#### Tasks

**5.1 spaCy CLI Hardening**
- **Goal**: Production-ready Python CLI
- **Scope**:
  ```python
  # spacy_cli.py
  import sys
  import json
  import spacy
  import signal

  # Timeout handling (SIGALRM)
  # Streaming JSON lines (one doc per line)
  # Schema version in response: {"version": "1.0", ...}
  # Graceful shutdown on SIGTERM
  ```
  - Timeout: 10s per document (configurable)
  - Streaming: Process one doc at a time, emit JSON line
  - Schema versioning: Include `version` field in response
  - Error handling: Return `{"error": "...", "doc_id": "..."}` on failure
- **Deliverable**: `python/spacy_cli.py`
- **Tests**: `python/test_spacy_cli.py` (timeout, errors, streaming)

**5.2 Elixir Wrapper - Port Pool**
- **Goal**: Supervised port pool for spaCy processes
- **Scope**:
  - Port pool: 4 spaCy processes (configurable)
  - Retries: 3 attempts per document
  - Circuit breaker: Open after 10 failures in 60s
  - Backpressure: Broadway integration (batch processing)
  - Event flow:
    - Input: `system.ingest.classified` (text documents)
    - Output: `system.nlp.processed`
    - DLQ: `system.dlq.nlp_failed`
- **Deliverable**: `lib/thunderline/thunderflow/nlp_processor.ex`
- **Tests**: `test/thunderline/thunderflow/nlp_processor_test.exs` (pool, retries, circuit breaker)

**5.3 NLPResult Schema**
- **Goal**: Minimal contract for NLP output
- **Scope**:
  ```elixir
  defmodule Thunderline.NLP.Result do
    @type t :: %__MODULE__{
      doc_id: String.t(),
      lang: String.t(),
      entities: [entity()],
      noun_chunks: [String.t()],
      sentences: [String.t()],
      confidence: float()
    }

    @type entity :: %{
      text: String.t(),
      label: String.t(),
      start: integer(),
      end: integer()
    }

    defstruct [:doc_id, :lang, :entities, :noun_chunks, :sentences, :confidence]
  end
  ```
  - JSON schema version: `1.0`
  - Backwards compatibility: Support version upgrades
- **Deliverable**: `lib/thunderline/nlp/result.ex`

**5.4 Robustness Tests**
- **Goal**: Validate failure modes
- **Scope**:
  - Test cases:
    - Accented text (UTF-8 handling): "Café français"
    - Large document (10KB text)
    - Unsupported language (fallback to English)
    - SIGPIPE simulation (port crash)
  - Performance:
    - p95 < 250ms for 1KB document (on dev machine)
    - Memory stable under 1000 document soak test
  - Failure modes:
    - Timeout → DLQ with timeout reason
    - Parse error → DLQ with JSON error
    - Process crash → Restart + retry
- **Deliverable**: `test/integration/spacy_robustness_test.exs`

**Acceptance**:
- ✅ p95 < 250ms for 1KB doc on dev machine
- ✅ Failure modes mapped to DLQ
- ✅ Memory stable under soak test

---

### Phase 6: Observability & SLOs (0.5 days)
**Status**: 🟡 NOT STARTED  
**Owner**: DevOps/Observability  
**Priority**: P1 (production visibility)

**Goal**: Production-grade dashboards and alerting for ML pipeline.

#### Tasks

**6.1 Grafana Dashboards**
- **Goal**: Real-time pipeline observability
- **Scope**:
  - Dashboard 1: **Ingest Success Rate**
    - Metric: `system.ingest.classified` count/min
    - Breakdown: By file type, source
    - SLO: > 95% success rate
  - Dashboard 2: **Classifier Latency**
    - Metric: Magika p50/p95/p99 latency
    - Histogram: Latency distribution
    - SLO: p95 < 1s
  - Dashboard 3: **ONNX Latency**
    - Metric: Inference p50/p95/p99 latency
    - Breakdown: By model
    - SLO: p95 < 100ms
  - Dashboard 4: **Voxel Throughput**
    - Metric: `system.voxel.created` count/min
    - Trend: 1h/24h/7d
  - Dashboard 5: **DLQ Rate**
    - Metric: DLQ events / total events
    - Breakdown: By failure type
    - SLO: < 2%
- **Deliverable**: `priv/grafana/ml_pipeline_dashboard.json`

**6.2 SLO Alerts**
- **Goal**: Proactive incident detection
- **Scope**:
  - Alert 1: **High DLQ Rate**
    - Condition: DLQ rate > 2% for 5 minutes
    - Severity: Warning
    - Action: Slack notification
  - Alert 2: **Magika Latency Spike**
    - Condition: p99 latency > 2× baseline for 5 minutes
    - Severity: Warning
    - Action: Slack notification
  - Alert 3: **ONNX Latency Spike**
    - Condition: p99 latency > 2× baseline for 5 minutes
    - Severity: Critical
    - Action: PagerDuty page
  - Test: Synthetic fault injection
    - Inject 10% error rate
    - Assert: Alert fires within 5 minutes
    - Recover: Alert resolves after fix
- **Deliverable**: `priv/alerts/ml_pipeline_alerts.yml`

**Acceptance**:
- ✅ Dashboards render with live data
- ✅ Two alert rules fire against synthetic fault

---

### Phase 7: Security & Supply Chain (0.5 days)
**Status**: 🟡 NOT STARTED  
**Owner**: DevOps/Security  
**Priority**: P1 (compliance)

**Goal**: Secure model supply chain and runtime sandboxing.

#### Tasks

**7.1 Version Pinning & SBOM**
- **Goal**: Reproducible builds and vulnerability tracking
- **Scope**:
  - Pin versions in `mix.exs`:
    - Ortex: `~> 0.1.10` (exact version)
    - Req: `~> 0.5.15`
  - Pin Python dependencies in `python/requirements.txt`:
    - `magika==0.5.0`
    - `tensorflow==2.20.0`
    - `onnxruntime==1.19.0`
  - Generate SBOM:
    - Tool: `syft` or `cyclonedx`
    - Format: CycloneDX JSON
    - Location: `sbom.json` (artifact in CI)
  - Checksum models:
    - Store SHA256 in `models/*/checksums.txt`
    - Verify on load (fail if mismatch)
  - Disallow writes outside model dir:
    - Sandboxing: ONNX runtime cannot write to disk
    - Validation: Check file permissions on model dir
- **Deliverable**: 
  - Updated `mix.exs` + `python/requirements.txt`
  - CI job: "Generate SBOM" → artifact `sbom.json`
  - `lib/thunderline/ml/security.ex` (checksum validation)

**7.2 Untrusted Model Gate**
- **Goal**: Prevent arbitrary model loading
- **Scope**:
  - Feature flag: `TL_ALLOW_UNTRUSTED_MODELS=false` (default)
  - When `false`:
    - Only load models from `TL_ONNX_MODEL_DIR`
    - Only load models with valid checksums
    - Log security warning on load attempt
  - When `true`:
    - Allow arbitrary model paths (dev/testing only)
    - Emit telemetry event: `[:thunderline, :ml, :untrusted_model_loaded]`
  - Checksum validation:
    - Compute SHA256 of loaded model
    - Compare with `models/*/checksums.txt`
    - Block load if mismatch: `{:error, :checksum_mismatch}`
    - Log: `[security] Model checksum mismatch: expected=..., actual=...`
- **Deliverable**: Updated `lib/thunderline/ml/keras_onnx.ex` (security checks)

**Acceptance**:
- ✅ SBOM artifact in CI
- ✅ Model checksum mismatch blocks load and logs security warning

---

## Pipeline Architecture

### Event Flow
```
ui.command.ingest.received
  ↓ [EventBus → BroadwayProducer]
Magika Classifier ✅
  ↓ [system.ingest.classified]
spaCy NLP Processor 🟡
  ↓ [system.nlp.processed]
ONNX Inference 🟡
  ↓ [system.ml.inference.completed]
Voxel Packager 🟡
  ↓ [system.voxel.created]
ThunderBlock Persistence
```

### Telemetry Events

**Magika** (Production):
- `[:thunderline, :thundergate, :magika, :classify, :start]`
- `[:thunderline, :thundergate, :magika, :classify, :stop]`
- `[:thunderline, :thundergate, :magika, :classify, :error]`

**ONNX** (Planned):
- `[:thunderline, :ml, :onnx, :infer, :start]`
- `[:thunderline, :ml, :onnx, :infer, :stop]`
- `[:thunderline, :ml, :onnx, :infer, :error]`

**spaCy** (Planned):
- `[:thunderline, :nlp, :spacy, :process, :start]`
- `[:thunderline, :nlp, :spacy, :process, :stop]`
- `[:thunderline, :nlp, :spacy, :process, :error]`

**Voxel** (Planned):
- `[:thunderline, :voxel, :build, :start]`
- `[:thunderline, :voxel, :build, :stop]`
- `[:thunderline, :voxel, :build, :error]`

---

## Assignments by Lane

### Core Elixir
- ONNX adapter implementation (Tasks 2.1-2.7)
- Voxel packager (Tasks 4.1-4.4)
- spaCy Elixir wrapper (Task 5.2)
- Supervision & Broadway tuning (Tasks 2.3, 2.4, 5.2)

### Python/NLP
- Keras→ONNX exporter + equivalence (Tasks 3.1-3.2)
- Model repository layout (Task 3.3)
- spaCy CLI hardening (Task 5.1)
- Robustness tests (Task 5.4)

### DevOps/Observability
- CI jobs: Magika E2E, Model Equivalence, SBOM (Tasks 1.1, 3.5, 7.1)
- Grafana dashboards (Task 6.1)
- SLO alerts (Task 6.2)
- Security: SBOM, version pinning (Task 7.1)

---

## References

### Elixir ML Ecosystem
- **Bumblebee** (Elixir-NX models): https://github.com/elixir-nx/bumblebee
- **Ortex** (Elixir ONNX Runtime): https://github.com/elixir-nx/ortex
- **Nx** (Numerical Elixir): https://github.com/elixir-nx/nx

### ONNX Resources
- **ONNX Runtime Docs**: https://onnxruntime.ai/docs/
- **Training/Inference**: https://onnxruntime.ai/docs/build/training.html
- **TensorFlow→ONNX**: https://github.com/onnx/tensorflow-onnx

### Project Documentation
- **Magika Quick Start**: `docs/MAGIKA_QUICK_START.md`
- **Architecture Spec**: `documentation/MAGIKA_SPACY_KERAS_INTEGRATION.md`
- **Domain Catalog**: `THUNDERLINE_DOMAIN_CATALOG.md`
- **Master Playbook**: `THUNDERLINE_MASTER_PLAYBOOK.md`

---

## Team Communication

**Message to Dev Team**:

> Team—Magika sprint is green ✅. Next up:
> 
> 1. **Build the ONNX adapter** in Elixir via Ortex with backpressure + telemetry.
> 2. **Finish the Keras→ONNX exporter** + equivalence CI.
> 3. **Implement the Voxel packager** (schema, lineage, persistence, event).
> 4. **Harden the spaCy sidecar** (port pool, retries, circuit-breaker).
> 
> SLOs and dashboards included in roadmap. Acceptance criteria are explicit for each task. Ship in this order.
> 
> **Philosophy**: *Festina lente* — make haste, slowly. 🎯

---

**Status Legend**:
- ✅ **COMPLETE** - Production-ready, tested, documented
- 🟢 **IN PROGRESS** - Active development
- 🟡 **NOT STARTED** - Planned, blocked, or pending
- ⚠️ **BLOCKED** - Waiting on dependency or decision
- ❌ **CANCELLED** - Descoped or deprecated

---

**Last Updated**: November 12, 2025  
**Next Review**: Weekly (every Monday)  
**Owner**: ML Infrastructure Team
