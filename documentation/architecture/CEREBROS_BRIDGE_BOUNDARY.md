# Cerebros Bridge Boundary Specification

> **HC-20 Deliverable** | Status: Complete | Date: November 26, 2025

## Overview

This document defines the **formal boundary** between the Cerebros ML repository and Thunderline. It establishes:
- What lives where
- Allowed call directions
- Public API contracts
- Enforcement mechanisms

The goal is to prevent "reach-through" coupling where Thunderline modules directly import Cerebros internals or vice versa.

---

## Repository Boundaries

### Cerebros Repository (`/home/mo/DEV/cerebros`)

**Owned by**: External ML team / David  
**Purpose**: Neural Architecture Search (NAS), model training, experimentation

| Component | Description | Exports |
|-----------|-------------|---------|
| `cerebros/` | Core NAS algorithms | Python scripts, trained models |
| `keras/` | Keras training pipelines | `.h5` / `.keras` models |
| `onnx/` | ONNX conversion utilities | `.onnx` models |
| `flower_app.py` | Federated learning control | gRPC/HTTP endpoints |
| `mlflow/` | Experiment tracking | MLflow artifacts |

**Cerebros NEVER imports from Thunderline.**

### Thunderline Repository (`/home/mo/DEV/Thunderline`)

**Owned by**: Platform team  
**Purpose**: Runtime orchestration, inference, event pipeline, persistence

| Component | Description | Consumes |
|-----------|-------------|----------|
| `Thunderbolt.CerebrosBridge.*` | Bridge layer | Cerebros scripts/models |
| `Thunderbolt.ML.ModelServer` | ONNX session cache | `.onnx` files |
| `Thunderbolt.ML.KerasONNX` | Inference wrapper | Ortex NIF |
| `Thunderflow.EventBus` | Event routing | ML lifecycle events |

**Thunderline NEVER imports Python modules from Cerebros directly.**

---

## Call Direction Rules

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ALLOWED DIRECTIONS                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Thunderline ──────────────────────────► Cerebros                  │
│        │                                      │                     │
│        │  ✅ HTTP/gRPC calls                  │                     │
│        │  ✅ Python subprocess                │                     │
│        │  ✅ ONNX model loading               │                     │
│        │  ✅ MLflow artifact fetch            │                     │
│        │                                      │                     │
│   Cerebros ─────────────X──────────────► Thunderline                │
│                    FORBIDDEN                                        │
│                                                                     │
│   (Cerebros may POST to Thunderline API endpoints,                  │
│    but cannot import Elixir modules)                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Allowed

| From | To | Mechanism |
|------|----| --------- |
| `Thunderline.Cerebros.Bridge` | Cerebros Python | Subprocess via `Port`/`System.cmd` |
| `Thunderline.Cerebros.Bridge` | Cerebros HTTP | `Req.post/get` |
| `Thunderline.Thunderbolt.ML.*` | ONNX models | `Ortex.load/run` |
| Cerebros Python | Thunderline API | HTTP POST to `/api/*` |

### Forbidden

| Pattern | Reason |
|---------|--------|
| Direct `Ortex.*` outside `Thunderline.Cerebros.*` | Breaks encapsulation |
| `System.cmd("python", [...cerebros/...])` outside Bridge | Untracked invocation |
| Importing Cerebros Python modules in application code | Coupling |
| Cerebros importing Thunderline Elixir modules | Cross-repo dependency |

---

## Public API: `Thunderline.Cerebros.Bridge`

The **canonical entry point** for all Cerebros interactions from Thunderline.

### Module: `Thunderline.Cerebros.Bridge`

```elixir
defmodule Thunderline.Cerebros.Bridge do
  @moduledoc """
  Unified entry point for Cerebros ML operations.
  
  All Cerebros interactions MUST go through this module.
  Direct Ortex calls outside this namespace are forbidden.
  """

  # ─────────────────────────────────────────────────────────────
  # Model Loading & Inference
  # ─────────────────────────────────────────────────────────────

  @doc """
  Load a model by name. Returns a session reference for inference.
  Uses ModelServer for caching.
  
  ## Examples
  
      {:ok, session} = Bridge.load_model("cerebros_trained.onnx")
  """
  @spec load_model(String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def load_model(model_name, opts \\ [])

  @doc """
  Run inference on a loaded session.
  
  ## Examples
  
      {:ok, output} = Bridge.run_inference(session, input_tensor)
  """
  @spec run_inference(reference(), Nx.Tensor.t(), keyword()) :: 
        {:ok, Nx.Tensor.t()} | {:error, term()}
  def run_inference(session, input, opts \\ [])

  @doc """
  Convenience: load model and run inference in one call.
  Emits `cerebros.inference.completed` or `cerebros.inference.failed` events.
  
  ## Examples
  
      {:ok, result} = Bridge.infer("cerebros_trained.onnx", input)
  """
  @spec infer(String.t(), Nx.Tensor.t(), keyword()) :: 
        {:ok, map()} | {:error, term()}
  def infer(model_name, input, opts \\ [])

  # ─────────────────────────────────────────────────────────────
  # Model Management
  # ─────────────────────────────────────────────────────────────

  @doc """
  List available models in the model directory.
  """
  @spec list_models(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_models(opts \\ [])

  @doc """
  Get metadata for a specific model.
  """
  @spec get_model_metadata(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_model_metadata(model_name, opts \\ [])

  @doc """
  Preload a model into cache for faster first inference.
  """
  @spec preload(String.t(), keyword()) :: :ok | {:error, term()}
  def preload(model_name, opts \\ [])

  @doc """
  Evict a model from cache.
  """
  @spec evict(String.t(), keyword()) :: :ok | {:error, term()}
  def evict(model_name, opts \\ [])

  # ─────────────────────────────────────────────────────────────
  # Training Bridge (via CerebrosBridge.Client)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Start a Cerebros training run.
  Delegates to CerebrosBridge.Client.start_run/2.
  """
  @spec start_training(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_training(params, opts \\ [])

  @doc """
  Record a trial result.
  Delegates to CerebrosBridge.Client.record_trial/2.
  """
  @spec record_trial(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def record_trial(params, opts \\ [])

  @doc """
  Finalize a training run.
  Delegates to CerebrosBridge.Client.finalize_run/2.
  """
  @spec finalize_training(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def finalize_training(params, opts \\ [])

  # ─────────────────────────────────────────────────────────────
  # Health & Status
  # ─────────────────────────────────────────────────────────────

  @doc """
  Check if the Cerebros bridge is enabled and healthy.
  """
  @spec health() :: {:ok, map()} | {:error, term()}
  def health()

  @doc """
  Returns true if the bridge is enabled (feature flag + config).
  """
  @spec enabled?() :: boolean()
  def enabled?()
end
```

### Events Emitted

| Event Name | Source | When |
|------------|--------|------|
| `cerebros.model.loaded` | `:bolt` | Model successfully loaded into ModelServer |
| `cerebros.model.evicted` | `:bolt` | Model removed from cache |
| `cerebros.inference.completed` | `:bolt` | Inference succeeded |
| `cerebros.inference.failed` | `:bolt` | Inference failed |
| `ml.run.start` | `:bolt` | Training run started |
| `ml.run.stop` | `:bolt` | Training run completed |
| `ml.run.trial` | `:bolt` | Trial recorded |
| `ml.run.exception` | `:bolt` | Training error |

---

## Enforcement

### CI Guardrail

A simple grep-based check to ensure Ortex is only called from allowed modules:

```bash
#!/usr/bin/env bash
# scripts/ci/check_ortex_boundary.sh

# Find Ortex usage outside allowed modules
VIOLATIONS=$(grep -rn "Ortex\." lib/ \
  --include="*.ex" \
  | grep -v "lib/thunderline/cerebros/" \
  | grep -v "lib/thunderline/thunderbolt/ml/" \
  | grep -v "lib/thunderline/thunderbolt/cerebros_bridge/" \
  | grep -v "# ortex-boundary-ok" \
  || true)

if [ -n "$VIOLATIONS" ]; then
  echo "❌ HC-20 VIOLATION: Ortex called outside Cerebros boundary"
  echo "$VIOLATIONS"
  exit 1
fi

echo "✅ Ortex boundary check passed"
```

### Credo Check (Future)

```elixir
# lib/mix/credo/no_ortex_outside_bridge.ex
defmodule Thunderline.Credo.NoOrtexOutsideBridge do
  @moduledoc """
  Ensures Ortex is only used within the Cerebros bridge namespace.
  """
  use Credo.Check, base_priority: :high

  @allowed_paths [
    "lib/thunderline/cerebros/",
    "lib/thunderline/thunderbolt/ml/",
    "lib/thunderline/thunderbolt/cerebros_bridge/"
  ]

  def run(source_file, params) do
    # Implementation: fail if Ortex.* appears outside allowed paths
  end
end
```

---

## Migration Path

### Phase 1: Document (This PR)
- [x] Create boundary specification document
- [x] Define public API contract

### Phase 2: Implement Bridge Module
- [ ] Create `Thunderline.Cerebros.Bridge` module
- [ ] Wire events through EventBus
- [ ] Add telemetry

### Phase 3: Enforce
- [ ] Add CI boundary check script
- [ ] Audit existing code for violations
- [ ] Fix any violations found

---

## Configuration

```elixir
# config/config.exs
config :thunderline, :cerebros_bridge,
  enabled: true,
  repo_path: "/home/mo/DEV/cerebros",
  script_path: "/home/mo/DEV/cerebros/run.py",
  python_executable: "python3",
  invoke: [
    default_timeout_ms: 15_000,
    max_retries: 2
  ],
  cache: [
    enabled: true,
    ttl_ms: 30_000,
    max_entries: 512
  ]

# Model server config
config :thunderline, Thunderline.Thunderbolt.ML.ModelServer,
  max_models: 10,
  preload: ["cerebros_trained.onnx"],
  model_dir: "priv/models"
```

---

## Appendix: Existing Implementation Mapping

| Existing Module | Role | Kept? |
|-----------------|------|-------|
| `Thunderbolt.CerebrosBridge.Client` | Training bridge | ✅ Delegate from Bridge |
| `Thunderbolt.CerebrosBridge.Contracts` | Message schemas | ✅ Internal |
| `Thunderbolt.CerebrosBridge.Invoker` | Subprocess exec | ✅ Internal |
| `Thunderbolt.CerebrosBridge.Translator` | Payload marshal | ✅ Internal |
| `Thunderbolt.CerebrosBridge.Cache` | Response cache | ✅ Internal |
| `Thunderbolt.ML.ModelServer` | Session cache | ✅ Used by Bridge |
| `Thunderbolt.ML.KerasONNX` | Ortex wrapper | ✅ Used by Bridge |

The new `Thunderline.Cerebros.Bridge` module is a **facade** that unifies access to these internals.

---

## References

- HC-20: Cerebros Bridge (THUNDERLINE_MASTER_PLAYBOOK.md)
- HC-04d: ModelServer (COMPLETE)
- Ortex Documentation: https://hexdocs.pm/ortex
- Cerebros Repository: `/home/mo/DEV/cerebros`
