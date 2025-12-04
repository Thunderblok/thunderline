# ThunderBolt Domain Overview

**Vertex Position**: Control Plane Ring — ML & Execution Layer

**Purpose**: Machine Learning orchestration domain that executes ML workloads, manages Cerebros bridges, orchestrates ThunderCell chunks, and coordinates the Unified Persistent Model (UPM) lifecycle. Adjacent to ThunderBit (automata).

## Charter

ThunderBolt is the **ML engine** of Thunderline. While ThunderBit defines the automata structure and categories, ThunderBolt **trains, optimizes, and runs inference** on those automata. The domain manages neural architecture search, Virtual Ising Machines (VIM), ThunderCell orchestration, and all Python/ML interop via Snex bridges.

## Domain Relationship: ThunderBit ↔ ThunderBolt

| Aspect | ThunderBit (Automata) | ThunderBolt (ML) |
|--------|----------------------|------------------|
| **Role** | Defines structure | Trains & executes |
| **Focus** | Categories, wiring, transitions | Models, embeddings, inference |
| **Analogy** | CPU (logic) | GPU (acceleration) |
| **Data** | State machines, CA patterns | Weights, embeddings, gradients |

## Core Responsibilities

1. **ML Model Lifecycle** — register, version, and track ML models, datasets, artifacts, and trial runs.
2. **Cerebros Integration** — coordinate NAS experiments via Snex bridge (GIL-free Python interop).
3. **ThunderCell Orchestration** — manage ThunderCell chunks from ThunderBit, run lane engines, and coordinate cell-level ML.
4. **Virtual Ising Machine (VIM)** — optimization layer for combinatorial problems.
5. **Unified Persistent Model (UPM)** — run training and replay jobs for the platform-wide agent brain.
6. **Python Interop** — Snex-based GIL-free Python calls for ML operations.
7. **Policy Compliance** — enforce governance policies from ThunderCrown.

## Subdomains

```
thunderbolt/
├── ca/              # CA pattern execution (from ThunderBit specs)
├── cerebros/        # Cerebros NAS orchestration
├── cerebros_bridge/ # Snex/Python interop (snex_invoker.ex is primary)
├── ml/              # Core ML resources & trainer
├── moe/             # Mixture of Experts
├── nlp/             # NLP processing
├── numerics/        # Numerical adapters (Axon, ONNX)
├── policy/          # ML policy execution
├── rag/             # RAG (Retrieval Augmented Generation)
├── sagas/           # ML workflow sagas
├── signal/          # Signal processing
├── sparse/          # Sparse computation
├── tak/             # TAK persistence
├── thundercell/     # ThunderCell chunk orchestration
├── upm/             # Unified Persistent Model
└── vim/             # Virtual Ising Machine (planned)
```

## Core Responsibilities

1. **Model Lifecycle Management** — register, version, and track ML models, datasets, artifacts, and trial runs.
2. **Cerebros Integration** — coordinate NAS experiments via the Cerebros bridge, including job submission, validation, and persistence.
3. **ThunderCell Lane Orchestration** — manage lane rule sets, telemetry, and performance tuning for cellular automata workloads.
4. **Unified Persistent Model (UPM) Execution** — run training and replay jobs that continuously refine the platform-wide agent brain.
5. **Event Publication & Telemetry** — emit orchestration events consumed by ThunderFlow and ThunderVine for lineage and observability.
6. **Policy Compliance** — enforce governance policies handed down by ThunderCrown, ensuring approved workloads and signed artifacts only.
7. **Automation & Tooling** — provide AutoML drivers, HPO executors, and resource allocators for high-scale experimentation.

## Ash Resources

- [`Thunderline.Thunderbolt.Resources.ModelRun`](lib/thunderline/thunderbolt/ml/model_run.ex:1) — encapsulates a single model execution with links to datasets, artifacts, and metrics.
- [`Thunderline.Thunderbolt.Resources.TrainingRun`](lib/thunderline/thunderbolt/ml/training_run.ex:1) — records batch training jobs, including hyperparameters and reproducibility hashes.
- [`Thunderline.Thunderbolt.Resources.AutomataRun`](lib/thunderline/thunderbolt/resources/automata_run.ex:1) — manages ThunderCell lane executions and CA telemetry snapshots.
- [`Thunderline.Thunderbolt.Resources.LaneRuleSet`](lib/thunderline/thunderbolt/resources/lane_rule_set.ex:1) — houses declarative rules governing ThunderCell behavior.
- [`Thunderline.Thunderbolt.Resources.ResourceAllocation`](lib/thunderline/thunderbolt/resources/resource_allocation.ex:1) — tracks compute resource assignments for active jobs.

## Supporting Modules

- [`Thunderline.Thunderbolt.CerebrosBridge.Invoker`](lib/thunderline/thunderbolt/cerebros_bridge/invoker.ex:1) — orchestrates remote Cerebros runs.
- [`Thunderline.Thunderbolt.CerebrosBridge.Persistence`](lib/thunderline/thunderbolt/cerebros_bridge/persistence.ex:1) — persists Cerebros artifacts locally and syncs with ThunderBlock vaults.
- [`Thunderline.Thunderbolt.AutoMLDriver`](lib/thunderline/thunderbolt/auto_ml_driver.ex:1) — implements large-scale AutoML workflows with configurable search strategies.
- [`Thunderline.Thunderbolt.HPOExecutor`](lib/thunderline/thunderbolt/hpo_executor.ex:1) — runs hyperparameter optimization trials and publishes results.
- [`Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor`](lib/thunderline/thunderbolt/thundercell/cluster_supervisor.ex:1) — supervises ThunderCell lane workers and maintains execution topology.

## Integration Points

### Vertical Edges

- **ThunderCrown → ThunderBolt**: governance decisions trigger orchestration via `ai.intent.*` events that materialize as AutoML or Cerebros jobs.
- **ThunderBolt → ThunderBlock**: persists model artifacts, snapshots, and lane telemetry to the vault.
- **ThunderBolt → Thundervine**: pushes provenance metadata for every training and inference result to maintain reproducible lineage.
- **ThunderBolt → ThunderFlow**: publishes orchestration lifecycle events (`ml.run.*`, `thunderbolt.alert.*`) for streaming consumers.

### Horizontal Edges

- **ThunderBolt ↔ ThunderForge**: consumes compiled ThunderDSL programs and returns execution metrics to inform future compilations.
- **ThunderBolt ↔ ThunderGrid**: requests placement decisions for GPU or CPU zones before scheduling jobs.
- **ThunderBolt ↔ ThunderLink**: streams live execution updates to dashboards and the operator UI.

## Telemetry Events

- `[:thunderline, :thunderbolt, :cerebros, :invocation]` — Cerebros job submission.
- `[:thunderline, :thunderbolt, :lane, :telemetry]` — ThunderCell lane performance snapshot.
- `[:thunderline, :thunderbolt, :upm, :training, :start|:stop]` — UPM training lifecycle markers.
- `[:thunderline, :thunderbolt, :resource, :allocation]` — compute resource assignment changes.
- `[:thunderline, :thunderbolt, :alert, :emitted]` — orchestration anomaly detection.

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Cerebros job submission | 200 ms | 1.2 s | 100/min |
| ThunderCell lane activation | 50 ms | 250 ms | 500/s |
| UPM training dispatch | 500 ms | 2 s | 50/min |
| Artifact persistence (vault sync) | 150 ms | 800 ms | 200/min |
| AutoML trial evaluation | 2 s | 10 s | 20/min |

## Security & Policy Notes

- All Cerebros actions must flow through the bridge modules, which enforce signed requests and hash validation.
- Ash policies on model resources must be updated to remove `authorize_if always()` patterns highlighted in [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:365).
- Feature flags (e.g., `features.ml_nas`) gate production pipeline execution; confirm the flag state before deploying new workloads.
- Ensure ThunderCrown policy decisions (Stone.Proof, Daisy) are recorded for every execution to satisfy audit requirements.

## Testing Strategy

- Unit tests for Cerebros bridge translators, validators, and run options.
- Integration tests covering end-to-end AutoML, HPO, and UPM flows (`test/thunderline/thunderbolt/sagas/*.exs`).
- Property tests verifying lane rule consistency and idempotent orchestration events.
- Load tests for lane telemetry fanout to verify dashboard responsiveness under heavy experimentation.

## Development Roadmap

1. **Phase 1 — Policy Hardening**: restore Ash policies for all ML resources and integrate governance proof checks.
2. **Phase 2 — Telemetry Expansion**: align ThunderBolt telemetry with platform OTLP exporters and dashboard panels.
3. **Phase 3 — UPM Enhancements**: expand replay buffers, improve drift monitoring, and finalize cross-domain lineage.
4. **Phase 4 — Hybrid Execution**: support multi-backend scheduling (GPU, CPU, unikernel) with ThunderGrid awareness.

## References

- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:137)
- [`docs/documentation/phase3_cerebros_bridge_complete.md`](docs/documentation/phase3_cerebros_bridge_complete.md:1)
- [`docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md`](docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md:473)
- [`docs/documentation/HC_EXECUTION_PLAN.md`](docs/documentation/HC_EXECUTION_PLAN.md:52)