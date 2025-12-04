# ThunderBolt Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thunderbolt/domain.ex`  
**Vertex Position**: Control Plane Ring — ML & Execution Layer

## Purpose

ThunderBolt is the **ML engine and core compute domain** of Thunderline. It handles:
- Machine learning model lifecycle (training, inference, versioning)
- Cerebros NAS (Neural Architecture Search) orchestration
- ThunderCell/Lane cellular automata orchestration
- Virtual Ising Machine (VIM) optimization
- Unified Persistent Model (UPM) management
- Python/ML interop via Snex bridges

## Domain Extensions

```elixir
use Ash.Domain,
  extensions: [AshAdmin.Domain, AshOban.Domain, AshJsonApi.Domain, AshGraphql.Domain]
```

- **AshAdmin** — Admin dashboard enabled
- **AshOban** — Background job processing
- **AshJsonApi** — REST API at `/api/thunderbolt`
- **AshGraphql** — GraphQL mutations/queries for CoreAgent

## Directory Structure

```
lib/thunderline/thunderbolt/
├── domain.ex                   # Main Ash domain (55+ resources)
├── supervisor.ex               # Domain supervisor
├── auto_ml_driver.ex           # AutoML workflow driver
├── hpo_executor.ex             # Hyperparameter optimization
├── erlang_bridge.ex            # Erlang interop
├── dataset_manager.ex          # Dataset lifecycle
├── topology_*.ex               # Topology distribution (3 files)
├── thunderlane.ex              # Lane orchestration
├── lane_coupling_pipeline.ex   # Lane coupling Broadway
├── cerebros_*.ex               # Cerebros modules (4 files)
├── ca/                         # Cellular Automata (10 files)
│   ├── neighborhood.ex, rule_parser.ex, stepper.ex, runner.ex
│   └── snapshot.ex, perturbation.ex, rule_actions.ex (Ash resource)
├── cerebros/                   # Cerebros NAS (14 files)
│   ├── adapter.ex, encoder.ex, features.ex, metrics.ex
│   ├── telemetry.ex, event_publisher.ex, pac_compute.ex
│   └── data/, utils/
├── cerebros_bridge/            # Python bridge (3 files)
├── cerebros_facade/            # Cerebros facade (3 files)
│   ├── automat.ex, bridge.ex
│   └── mini/
├── changes/                    # Ash changes (5 files)
├── continuous/                 # Continuous math (5 files)
├── criticality/                # Dynamics analysis (4 files)
├── difflogic/                  # Differentiable logic (2 files)
├── evolution/                  # MAP-Elites subdomain
│   ├── domain.ex               # Separate Ash Domain!
│   └── resources/elite_entry.ex
├── events/                     # Event modules
├── export/                     # Training export (1 file)
├── ising_machine/              # VIM core (6 files)
│   ├── api.ex, kernel.ex, lattice.ex
│   ├── anneal.ex, temper.ex, scheduler.ex
├── lane_coordinator/           # Lane GenServer (2 files)
├── ml/                         # ML core (21 files)
│   ├── Resources: training_dataset.ex, feature_view.ex, consent_record.ex
│   ├── Resources: model_spec.ex, model_artifact.ex, model_version.ex, training_run.ex
│   ├── sla_selector.ex, cerebros_generator.ex, tokenizer_bridge.ex
│   └── trainer/
├── mlflow/                     # MLflow integration (5 files)
│   ├── experiment.ex, run.ex (Ash resources)
│   └── client.ex, config.ex, sync_worker.ex
├── moe/                        # Mixture of Experts (2 files)
│   └── expert.ex, decision_trace.ex (Ash resources)
├── nca/                        # Neural CA (2 files)
├── nlp/                        # NLP port (1 file)
├── numerics/                   # Numerical adapters
│   ├── native.ex
│   └── adapters/
├── policy/                     # ML policy (1 file)
├── rag/                        # RAG system (5 files)
│   └── document.ex (Ash resource)
├── reflex_handlers/            # Reflex handlers
├── resources/                  # Core Ash resources (39 files)
├── sagas/                      # Saga orchestration (12 files)
│   ├── saga_state.ex (Ash resource)
│   ├── base.ex, registry.ex, supervisor.ex
│   ├── cerebros_nas_saga.ex, upm_activation_saga.ex
│   └── user_provisioning_saga.ex
├── signal/                     # Signal processing (7 files)
├── sparse/                     # Sparse computation (1 file)
├── stream_manager/             # Stream management
├── tak/                        # TAK persistence (6 files)
├── tae/                        # TAE engine (2 files)
├── thunderbit/                 # Thunderbit struct (1 file)
├── thundercell/                # ThunderCell orchestration (9 files)
├── upm/                        # Unified Persistent Model (10 files)
└── workers/                    # Oban workers (1 file)
```

## Registered Ash Resources (55+ resources)

### Core Processing (ThunderCore → ThunderBolt)
| Resource | Module | File |
|----------|--------|------|
| CoreAgent | `Thunderline.Thunderbolt.Resources.CoreAgent` | resources/core_agent.ex |
| CoreSystemPolicy | `Thunderline.Thunderbolt.Resources.CoreSystemPolicy` | resources/core_system_policy.ex |
| CoreTaskNode | `Thunderline.Thunderbolt.Resources.CoreTaskNode` | resources/core_task_node.ex |
| CoreTimingEvent | `Thunderline.Thunderbolt.Resources.CoreTimingEvent` | resources/core_timing_event.ex |
| CoreWorkflowDAG | `Thunderline.Thunderbolt.Resources.CoreWorkflowDAG` | resources/core_workflow_dag.ex |

### Ising Optimization (Thunder_Ising → ThunderBolt)
| Resource | Module | File |
|----------|--------|------|
| IsingOptimizationProblem | `Thunderline.Thunderbolt.Resources.IsingOptimizationProblem` | resources/ising_optimization_problem.ex |
| IsingOptimizationRun | `Thunderline.Thunderbolt.Resources.IsingOptimizationRun` | resources/ising_optimization_run.ex |
| IsingPerformanceMetric | `Thunderline.Thunderbolt.Resources.IsingPerformanceMetric` | resources/ising_performance_metric.ex |

### Lane Processing (ThunderLane → ThunderBolt)
| Resource | Module | File |
|----------|--------|------|
| CellTopology | `Thunderline.Thunderbolt.Resources.CellTopology` | resources/lane_cell_topology.ex |
| ConsensusRun | `Thunderline.Thunderbolt.Resources.ConsensusRun` | resources/lane_consensus_run.ex |
| CrossLaneCoupling | `Thunderline.Thunderbolt.Resources.CrossLaneCoupling` | resources/lane_cross_lane_coupling.ex |
| LaneConfiguration | `Thunderline.Thunderbolt.Resources.LaneConfiguration` | resources/lane_lane_configuration.ex |
| LaneCoordinator | `Thunderline.Thunderbolt.Resources.LaneCoordinator` | resources/lane_lane_coordinator.ex |
| LaneMetrics | `Thunderline.Thunderbolt.Resources.LaneMetrics` | resources/lane_lane_metrics.ex |
| PerformanceMetric | `Thunderline.Thunderbolt.Resources.PerformanceMetric` | resources/lane_performance_metric.ex |
| RuleOracle | `Thunderline.Thunderbolt.Resources.RuleOracle` | resources/lane_rule_oracle.ex |
| RuleSet | `Thunderline.Thunderbolt.Resources.RuleSet` | resources/lane_rule_set.ex |
| TelemetrySnapshot | `Thunderline.Thunderbolt.Resources.TelemetrySnapshot` | resources/lane_telemetry_snapshot.ex |

### Task Execution (ThunderMag → ThunderBolt)
| Resource | Module | File |
|----------|--------|------|
| MagMacroCommand | `Thunderline.Thunderbolt.Resources.MagMacroCommand` | resources/mag_macro_command.ex |
| MagTaskAssignment | `Thunderline.Thunderbolt.Resources.MagTaskAssignment` | resources/mag_task_assignment.ex |
| MagTaskExecution | `Thunderline.Thunderbolt.Resources.MagTaskExecution` | resources/mag_task_execution.ex |

### Automata Controls
| Resource | Module | File |
|----------|--------|------|
| AutomataRun | `Thunderline.Thunderbolt.Resources.AutomataRun` | resources/automata_run.ex |
| Chunk | `Thunderline.Thunderbolt.Resources.Chunk` | resources/chunk.ex |
| ChunkHealth | `Thunderline.Thunderbolt.Resources.ChunkHealth` | resources/chunk_health.ex |
| ActivationRule | `Thunderline.Thunderbolt.Resources.ActivationRule` | resources/activation_rule.ex |
| OrchestrationEvent | `Thunderline.Thunderbolt.Resources.OrchestrationEvent` | resources/orchestration_event.ex |
| ResourceAllocation | `Thunderline.Thunderbolt.Resources.ResourceAllocation` | resources/resource_allocation.ex |

### Cerebros ML
| Resource | Module | File |
|----------|--------|------|
| ModelRun | `Thunderline.Thunderbolt.Resources.ModelRun` | resources/model_run.ex |
| ModelTrial | `Thunderline.Thunderbolt.Resources.ModelTrial` | resources/model_trial.ex |
| TrainingDataset | `Thunderline.Thunderbolt.Resources.TrainingDataset` | resources/training_dataset.ex |
| DocumentUpload | `Thunderline.Thunderbolt.Resources.DocumentUpload` | resources/document_upload.ex |
| CerebrosTrainingJob | `Thunderline.Thunderbolt.Resources.CerebrosTrainingJob` | resources/cerebros_training_job.ex |

### ML Stack (ml/ subdirectory)
| Resource | Module | File |
|----------|--------|------|
| TrainingDataset | `Thunderline.Thunderbolt.ML.TrainingDataset` | ml/training_dataset.ex |
| FeatureView | `Thunderline.Thunderbolt.ML.FeatureView` | ml/feature_view.ex |
| ConsentRecord | `Thunderline.Thunderbolt.ML.ConsentRecord` | ml/consent_record.ex |
| ModelSpec | `Thunderline.Thunderbolt.ML.ModelSpec` | ml/model_spec.ex |
| ModelArtifact | `Thunderline.Thunderbolt.ML.ModelArtifact` | ml/model_artifact.ex |
| ModelVersion | `Thunderline.Thunderbolt.ML.ModelVersion` | ml/model_version.ex |
| TrainingRun | `Thunderline.Thunderbolt.ML.TrainingRun` | ml/training_run.ex |

### MLflow Integration
| Resource | Module | File |
|----------|--------|------|
| Experiment | `Thunderline.Thunderbolt.MLflow.Experiment` | mlflow/experiment.ex |
| Run | `Thunderline.Thunderbolt.MLflow.Run` | mlflow/run.ex |

### UPM (Unified Persistent Model)
| Resource | Module | File |
|----------|--------|------|
| UpmTrainer | `Thunderline.Thunderbolt.Resources.UpmTrainer` | resources/upm_trainer.ex |
| UpmSnapshot | `Thunderline.Thunderbolt.Resources.UpmSnapshot` | resources/upm_snapshot.ex |
| UpmAdapter | `Thunderline.Thunderbolt.Resources.UpmAdapter` | resources/upm_adapter.ex |
| UpmDriftWindow | `Thunderline.Thunderbolt.Resources.UpmDriftWindow` | resources/upm_drift_window.ex |
| UpmObservation | `Thunderline.Thunderbolt.Resources.UpmObservation` | resources/upm_observation.ex |

### MoE / RAG / Export (⚠️ Namespace Issues)
| Resource | Module | File | Issue |
|----------|--------|------|-------|
| Expert | `Thunderline.MoE.Expert` | moe/expert.ex | Root namespace |
| DecisionTrace | `Thunderline.MoE.DecisionTrace` | moe/decision_trace.ex | Root namespace |
| Document | `Thunderline.Thunderbolt.RAG.Document` | rag/document.ex | ✅ Correct |
| TrainingSlice | `Thunderline.Export.TrainingSlice` | export/training_slice.ex | Root namespace |

### ONNX Inference
| Resource | Module | File |
|----------|--------|------|
| OnnxInference | `Thunderline.Thunderbolt.Resources.OnnxInference` | resources/onnx_inference.ex |

### Saga State
| Resource | Module | File |
|----------|--------|------|
| SagaState | `Thunderline.Thunderbolt.Sagas.SagaState` | sagas/saga_state.ex |

### Thunderbit Definition
| Resource | Module | File |
|----------|--------|------|
| ThunderbitDefinition | `Thunderline.Thunderbolt.Resources.ThunderbitDefinition` | resources/thunderbit_definition.ex |

## Subdomain: Evolution

Separate Ash Domain at `evolution/domain.ex`:

```elixir
defmodule Thunderline.Thunderbolt.Evolution.Domain
```

| Resource | Module | File |
|----------|--------|------|
| EliteEntry | `Thunderline.Thunderbolt.Evolution.Resources.EliteEntry` | evolution/resources/elite_entry.ex |

## Saga System

| Module | Purpose | File |
|--------|---------|------|
| Base | Saga behavior base | sagas/base.ex |
| Registry | Saga registry | sagas/registry.ex |
| Supervisor | Saga supervisor | sagas/supervisor.ex |
| SagaWorker | Generic saga worker | sagas/saga_worker.ex |
| SagaCleanupWorker | Stale saga cleanup | sagas/saga_cleanup_worker.ex |
| TelemetryMiddleware | Saga telemetry | sagas/telemetry_middleware.ex |
| CerebrosNASSaga | NAS orchestration saga | sagas/cerebros_nas_saga.ex |
| UPMActivationSaga | UPM activation saga | sagas/upm_activation_saga.ex |
| UserProvisioningSaga | User provisioning saga | sagas/user_provisioning_saga.ex |

## GraphQL Endpoints

```elixir
queries do
  list CoreAgent, :core_agents, :read
  list CoreAgent, :active_core_agents, :active_agents
end

mutations do
  create CoreAgent, :register_core_agent, :register
  update CoreAgent, :heartbeat_core_agent, :heartbeat
end
```

## Code Interfaces (Domain-level)

| Function | Resource | Action |
|----------|----------|--------|
| `create_training_dataset` | TrainingDataset | :create |
| `update_training_dataset` | TrainingDataset | :update |
| `update_corpus_path` | TrainingDataset | :set_corpus_path |
| `get_training_dataset` | TrainingDataset | :read (get_by: [:id]) |
| `list_training_datasets` | TrainingDataset | :read |
| `freeze_dataset` | TrainingDataset | :freeze |
| `create_document_upload` | DocumentUpload | :create |
| `list_document_uploads` | DocumentUpload | :read |
| `process_upload` | DocumentUpload | :mark_processed |
| `create_training_job` | CerebrosTrainingJob | :create |
| `get_training_job` | CerebrosTrainingJob | :read (get_by: [:id]) |
| `start_job` | CerebrosTrainingJob | :start |
| `update_fine_tuned_model` | CerebrosTrainingJob | :update_fine_tuned_model |
| `complete_job` | CerebrosTrainingJob | :complete |
| `fail_job` | CerebrosTrainingJob | :fail |
| `mark_model_loaded` | CerebrosTrainingJob | :mark_model_loaded |
| `infer` | OnnxInference | :infer |
| `get_saga_state` | SagaState | :read (get_by: [:id]) |
| `list_saga_states` | SagaState | :list |
| `list_sagas_by_status` | SagaState | :list_by_status |
| `list_sagas_by_module` | SagaState | :list_by_module |
| `find_stale_sagas` | SagaState | :stale_sagas |

## Key Supporting Modules

| Module | Purpose | File |
|--------|---------|------|
| Thunderbit (struct) | 3D CA voxel cell | thunderbit.ex |
| AutoMLDriver | AutoML workflow driver | auto_ml_driver.ex |
| HPOExecutor | Hyperparameter optimization | hpo_executor.ex |
| DatasetManager | Dataset lifecycle | dataset_manager.ex |
| ErlangBridge | Erlang interop | erlang_bridge.ex |
| LaneCouplingPipeline | Broadway pipeline | lane_coupling_pipeline.ex |
| IsingMachine.API | VIM API | ising_machine/api.ex |
| UPM.Supervisor | UPM supervisor | upm/supervisor.ex |
| UPM.TrainerWorker | UPM training worker | upm/trainer_worker.ex |
| ThunderCell.Supervisor | CA cell supervisor | thundercell/supervisor.ex |

## Known Issues & TODOs

### 1. Namespace Inconsistencies
The following resources use root namespace but are registered in Thunderbolt domain:
- `Thunderline.MoE.Expert` → Should be `Thunderline.Thunderbolt.MoE.Expert`
- `Thunderline.MoE.DecisionTrace` → Should be `Thunderline.Thunderbolt.MoE.DecisionTrace`
- `Thunderline.Export.TrainingSlice` → Should be `Thunderline.Thunderbolt.Export.TrainingSlice`

### 2. Duplicate Resource Names
Two `TrainingDataset` resources exist:
- `Thunderline.Thunderbolt.Resources.TrainingDataset` (resources/)
- `Thunderline.Thunderbolt.ML.TrainingDataset` (ml/)

Need to verify if these are intended or accidental duplication.

### 3. File/Module Naming
Some files don't match their module names:
- Lane resources have `lane_` prefix in filename but not in module name
- This is intentional for organization but worth noting

### 4. Subdomain Isolation
The `Evolution.Domain` is a separate Ash Domain - verify if this is intentional or should be merged.

### 5. Missing Policy Hardening
Many resources likely have placeholder `authorize_if always()` policies that need proper policy implementation.

## Telemetry Events

- `[:thunderline, :thunderbolt, :cerebros, :invocation]`
- `[:thunderline, :thunderbolt, :lane, :telemetry]`
- `[:thunderline, :thunderbolt, :upm, :training, :start|:stop]`
- `[:thunderline, :thunderbolt, :resource, :allocation]`
- `[:thunderline, :thunderbolt, :alert, :emitted]`
- `[:thunderline, :thunderbolt, :saga, :*]`

## Development Priorities

1. **Namespace Cleanup** — Move MoE and Export modules to Thunderbolt namespace
2. **Resource Deduplication** — Resolve TrainingDataset duplication
3. **Policy Implementation** — Add proper Ash policies to all resources
4. **Evolution Domain** — Decide if Evolution should remain separate or merge

## Related Domains

- **ThunderBit** — Automata definitions consumed by ThunderBolt
- **ThunderCrown** — Governance policies enforced here
- **ThunderBlock** — Artifact persistence
- **ThunderFlow** — Event publication
- **ThunderVine** — Lineage tracking
