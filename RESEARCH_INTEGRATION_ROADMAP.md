# Thunderline Research Integration Roadmap

> **Status**: Draft Implementation Plan  
> **Created**: 2025-11-04  
> **Based On**: High Command Codebase Review & Research Papers  
> **Current Progress**: UPM SnapshotManager 74% complete (17/23 tests passing)

---

## Executive Summary

This roadmap integrates 6 major research insights into Thunderline's existing Thunderbolt domain:

1. **Meta-learning for Inverse Ising** - O(d³ log p / K) sample complexity reduction
2. **Dual-model Imputation & Prediction** - Ising-Traffic pipeline (98.7% accuracy, 10⁶× faster)
3. **Resonance & Near-Critical Dynamics** - Edge-of-chaos metrics for adaptability
4. **GeoCoT Relation Identification** - Spatial reasoning for topology
5. **Multi-concept AutoML & MAJ Scheduler** - Portfolio search with diversity
6. **Hardware Acceleration** - Abstract solver for BRIM/digital annealing

**Implementation Strategy**: Incremental, building on existing infrastructure with clear milestones.

---

## Phase 0: Foundation (Current Work)

**Priority**: ⚠️ **CRITICAL - COMPLETE FIRST**

### Task 0.1: Complete UPM SnapshotManager Tests
**Status**: 🔄 IN PROGRESS (17/23 passing, 74%)  
**Remaining**: 6 test failures  
**Estimated Time**: 1.5-2 hours  
**Owner**: Current work stream

**Remaining Failures**:
- Line 589: Rollback scenario (policy violation) - Medium fix
- Line 800: Large model handling (data type) - Medium fix  
- Line 494: Version progression workflow - Investigation
- Line 221: Deactivate previous snapshot - Investigation
- Line 640: Cleanup with retention - Investigation
- Line 254: Activation event emission - Investigation

**Completion Criteria**:
- ✅ 23/23 tests passing (100%)
- ✅ All UPM policies enforced correctly
- ✅ Telemetry events verified
- ✅ Clean commit with HC-22 Task #3 marked complete

**Blocking**: All research integration work should wait for this foundation.

---

## Phase 1: Ising Infrastructure Extension (Week 1-2)

**Priority**: 🟢 **HIGH** - Foundational for 3 research areas  
**Dependencies**: Phase 0 complete

### Task 1.1: Create IsingInverseGraph Resource

**Purpose**: Support meta-learning for structure discovery (Research Area #1)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/ising_inverse_graph.ex
defmodule Thunderline.Thunderbolt.Resources.IsingInverseGraph do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events]

  postgres do
    table "ising_inverse_graphs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    # Task family grouping
    attribute :task_family, :string do
      allow_nil? false
      description "Shared family identifier (e.g., 'zone_A', 'traffic_west')"
    end
    
    # Support set (estimated non-zero couplings)
    attribute :support_set, {:array, :map} do
      allow_nil? false
      description "Array of {node_i, node_j} pairs with non-zero coupling"
    end
    
    # Learning metadata
    attribute :num_tasks_pooled, :integer do
      allow_nil? false
      description "Number of tasks used in pooled learning (K in paper)"
    end
    
    attribute :sample_complexity, :integer do
      description "Total samples used: O(d³ log p / K)"
    end
    
    attribute :method, :atom do
      constraints one_of: [:pooled_l1_logistic, :graphical_lasso, :restricted_refit]
      default :pooled_l1_logistic
    end
    
    # Performance tracking
    attribute :support_recovery_accuracy, :decimal do
      description "Precision/recall of estimated support vs ground truth"
    end
    
    attribute :metadata, :map do
      default %{}
      description "Regularization params, convergence info, etc."
    end
    
    create_timestamp :learned_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :problems, Thunderline.Thunderbolt.Resources.IsingOptimizationProblem do
      description "Problems that share this learned structure"
    end
  end

  actions do
    defaults [:read, :destroy]
    
    create :learn_structure do
      description "Pool data from task family and learn support set"
      accept [:task_family, :num_tasks_pooled, :method, :metadata]
      
      argument :problem_ids, {:array, :uuid} do
        allow_nil? false
        description "IDs of problems in this task family"
      end
      
      change fn changeset, _context ->
        # TODO: Implement pooled ℓ1-logistic neighbourhood selection
        # See research paper: O(d³ log p / K) complexity
        changeset
      end
    end
    
    update :update_accuracy do
      accept [:support_recovery_accuracy]
    end
  end

  code_interface do
    define :learn_structure, args: [:task_family, :problem_ids]
    define :get_by_family, action: :read, args: [:task_family]
  end
end
```

**Supporting Module**:

```elixir
# File: lib/thunderline/thunderbolt/inverse_ising_learner.ex
defmodule Thunderline.Thunderbolt.InverseIsingLearner do
  @moduledoc """
  Implements pooled ℓ1-regularized logistic regression for inverse Ising.
  
  Based on research: "Meta-learning for Inverse Ising Problems"
  - Pools data from K related tasks to learn common support
  - Reduces sample complexity from O(d³ log p) to O(d³ log p / K)
  - Uses neighbourhood selection followed by restricted refit
  
  ## Algorithm
  
  1. Pool binary outcome traces from all tasks in family
  2. Run ℓ1-logistic regression to estimate support set
  3. Store support for use in target task optimization
  4. Optionally: restricted refit on target task data
  """
  
  import Nx.Defn
  
  @doc """
  Learn support set from pooled task data.
  
  ## Parameters
  - problems: List of IsingOptimizationProblem records with run history
  - regularization: λ parameter for ℓ1 penalty
  - opts: Additional options (threshold, max_iterations, etc.)
  
  ## Returns
  {:ok, support_set} where support_set is list of {i, j} node pairs
  """
  def learn_support(problems, regularization \\ 0.1, opts \\ []) do
    # TODO: Implement pooled neighbourhood selection
    # 1. Extract binary traces from IsingOptimizationRun records
    # 2. Stack data across tasks: X shape (n_total_samples, p)
    # 3. For each node j, run logistic regression: X_j ~ X_{-j}
    # 4. Threshold coefficients to get support
    # 5. Return edge list
    
    {:ok, []}  # Placeholder
  end
  
  @doc """
  Compute sample complexity for task family.
  
  Returns estimated number of samples needed: O(d³ log p / K)
  where d = max degree, p = num nodes, K = num tasks
  """
  def compute_sample_complexity(num_nodes, max_degree, num_tasks) do
    p = num_nodes
    d = max_degree
    k = num_tasks
    
    # Theoretical bound from paper
    complexity = ceil(d * d * d * :math.log(p) / k)
    complexity
  end
end
```

**Estimated Effort**: 3-4 days  
**Tests**: 5 unit tests + 2 integration tests  
**Documentation**: Module docs + research paper references

---

### Task 1.2: Add task_family to IsingOptimizationProblem

**Purpose**: Enable grouping problems for meta-learning

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/ising_optimization_problem.ex
# Add new attribute:

attribute :task_family, :string do
  description "Optional family identifier for meta-learning (e.g., 'zone_A')"
  public? true
end

# Add relationship:
belongs_to :inverse_graph, Thunderline.Thunderbolt.Resources.IsingInverseGraph do
  description "Learned structure shared across task family"
end

# Add action:
update :assign_family do
  accept [:task_family]
  
  change after_action(fn changeset, problem, _context ->
    # Auto-link to inverse graph if family exists
    case IsingInverseGraph.get_by_family(problem.task_family) do
      {:ok, graph} -> 
        problem
        |> Ash.Changeset.for_update(:link_inverse_graph, %{inverse_graph_id: graph.id})
        |> Ash.update!()
      _ -> 
        problem
    end
    
    {:ok, problem}
  end)
end
```

**Migration**: `mix ash.codegen add_task_family_to_ising`

**Estimated Effort**: 1 day  
**Tests**: 3 unit tests

---

### Task 1.3: Create IsingImputationRun Resource

**Purpose**: Support dual-model reconstruction (Research Area #2)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/ising_imputation_run.ex
defmodule Thunderline.Thunderbolt.Resources.IsingImputationRun do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ising_imputation_runs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    # Input configuration with missing values
    attribute :incomplete_config, :map do
      allow_nil? false
      description "Spin configuration with missing/uncertain values"
    end
    
    attribute :missing_mask, {:array, :boolean} do
      allow_nil? false
      description "Boolean mask: true = missing, false = observed"
    end
    
    # Reconstruction results
    attribute :reconstructed_config, :map do
      description "Imputed spin configuration (low-energy state)"
    end
    
    attribute :reconstruction_energy, :float do
      description "Final energy of reconstructed state"
    end
    
    # Method and performance
    attribute :imputation_method, :atom do
      constraints one_of: [:simulated_annealing, :mean_field, :belief_propagation]
      default :simulated_annealing
    end
    
    attribute :reconstruction_accuracy, :decimal do
      description "Accuracy vs ground truth (if available)"
    end
    
    attribute :runtime_ms, :integer
    attribute :num_iterations, :integer
    
    # Metadata
    attribute :metadata, :map, default: %{}
    
    create_timestamp :started_at
    attribute :completed_at, :utc_datetime_usec
  end

  relationships do
    belongs_to :problem, Thunderline.Thunderbolt.Resources.IsingOptimizationProblem do
      allow_nil? false
    end
    
    has_one :prediction_run, Thunderline.Thunderbolt.Resources.IsingPredictionRun do
      description "Subsequent prediction phase (dual-model pipeline)"
    end
  end

  actions do
    defaults [:read]
    
    create :reconstruct do
      accept [:incomplete_config, :missing_mask, :imputation_method, :metadata]
      
      argument :problem_id, :uuid, allow_nil?: false
      
      change fn changeset, context ->
        # TODO: Run Ising machine to impute missing values
        # Use simulated annealing or mean-field to find low-energy completion
        changeset
      end
      
      change fn changeset, context ->
        # Emit telemetry
        :telemetry.execute(
          [:thunderline, :ising, :imputation, :complete],
          %{runtime_ms: 0, accuracy: 0.0},
          %{problem_id: "id", method: :simulated_annealing}
        )
        changeset
      end
    end
  end

  code_interface do
    define :reconstruct, args: [:problem_id, :incomplete_config, :missing_mask]
  end
end
```

**Estimated Effort**: 2-3 days  
**Tests**: 4 unit tests + 1 integration test

---

### Task 1.4: Create IsingPredictionRun Resource

**Purpose**: Second phase of dual-model pipeline (Research Area #2)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/ising_prediction_run.ex
defmodule Thunderline.Thunderbolt.Resources.IsingPredictionRun do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ising_prediction_runs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    # Input from imputation phase
    attribute :input_config, :map do
      allow_nil? false
      description "Reconstructed configuration from imputation"
    end
    
    # Prediction output
    attribute :prediction, :map do
      allow_nil? false
      description "Final forecast (e.g., future state, classification)"
    end
    
    attribute :prediction_type, :atom do
      constraints one_of: [:classification, :regression, :next_state]
      default :next_state
    end
    
    # Predictor model
    attribute :predictor_type, :atom do
      constraints one_of: [:logistic, :gnn, :mlp, :linear]
      default :logistic
    end
    
    attribute :predictor_params, :map do
      description "Model weights/parameters (serialized)"
    end
    
    # Performance
    attribute :accuracy, :decimal
    attribute :runtime_ms, :integer
    attribute :metadata, :map, default: %{}
    
    create_timestamp :predicted_at
  end

  relationships do
    belongs_to :imputation_run, Thunderline.Thunderbolt.Resources.IsingImputationRun do
      allow_nil? false
    end
    
    belongs_to :problem, Thunderline.Thunderbolt.Resources.IsingOptimizationProblem
  end

  actions do
    defaults [:read]
    
    create :predict do
      accept [:input_config, :prediction_type, :predictor_type, :predictor_params, :metadata]
      
      argument :imputation_run_id, :uuid, allow_nil?: false
      
      change fn changeset, context ->
        # TODO: Run lightweight predictor on reconstructed config
        # Use logistic/GNN/MLP head trained on historical data
        changeset
      end
    end
  end

  calculations do
    calculate :end_to_end_speedup, :decimal, expr(
      # Compare dual-model time vs baseline
      imputation_run.runtime_ms + runtime_ms
    )
  end

  code_interface do
    define :predict, args: [:imputation_run_id, :input_config]
  end
end
```

**Estimated Effort**: 2 days  
**Tests**: 3 unit tests

---

### Task 1.5: Implement Dual-Model Pipeline Module

**Purpose**: Orchestrate Ising-Traffic workflow (Research Area #2)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/dual_model_pipeline.ex
defmodule Thunderline.Thunderbolt.DualModelPipeline do
  @moduledoc """
  Implements the Ising-Traffic dual-model pipeline.
  
  Based on research showing:
  - Phase A: Ising machine reconstructs missing signals (98.7% accuracy)
  - Phase B: Lightweight predictor makes final forecast
  - 5% more accurate than tensor completion baseline
  - Almost 2 orders of magnitude faster (10⁶× on hardware)
  
  ## Pipeline Flow
  
  1. Receive incomplete data (e.g., sensor outages, partial telemetry)
  2. Run IsingImputationRun to reconstruct missing values
  3. Pass reconstructed config to IsingPredictionRun
  4. Return final prediction + performance metrics
  
  ## Use Cases
  
  - Agent state imputation (partial observations)
  - Traffic prediction with missing sensors
  - Distributed system telemetry reconstruction
  - Cellular automaton state interpolation
  """
  
  alias Thunderline.Thunderbolt.Resources.{
    IsingOptimizationProblem,
    IsingImputationRun,
    IsingPredictionRun
  }
  
  @doc """
  Run full dual-model pipeline.
  
  ## Parameters
  - problem_id: Ising problem defining energy landscape
  - incomplete_data: Map with missing values (nil or :missing marker)
  - predictor_type: :logistic | :gnn | :mlp
  - opts: Pipeline options (timeout, quality threshold, etc.)
  
  ## Returns
  {:ok, %{prediction: result, imputation_accuracy: acc, total_time_ms: time}}
  """
  def run(problem_id, incomplete_data, predictor_type \\ :logistic, opts \\ []) do
    with {:ok, problem} <- Ash.get(IsingOptimizationProblem, problem_id),
         {:ok, imputation} <- reconstruct_phase(problem, incomplete_data, opts),
         {:ok, prediction} <- prediction_phase(imputation, predictor_type, opts) do
      
      # Compute end-to-end metrics
      total_time = (imputation.runtime_ms || 0) + (prediction.runtime_ms || 0)
      
      result = %{
        prediction: prediction.prediction,
        reconstructed_config: imputation.reconstructed_config,
        imputation_accuracy: imputation.reconstruction_accuracy,
        prediction_accuracy: prediction.accuracy,
        total_time_ms: total_time,
        imputation_id: imputation.id,
        prediction_id: prediction.id
      }
      
      # Emit telemetry
      :telemetry.execute(
        [:thunderline, :dual_model, :complete],
        %{total_time_ms: total_time, accuracy: prediction.accuracy},
        %{problem_id: problem_id, predictor: predictor_type}
      )
      
      {:ok, result}
    end
  end
  
  defp reconstruct_phase(problem, incomplete_data, opts) do
    # Extract missing mask
    missing_mask = Enum.map(incomplete_data, fn {_k, v} -> 
      is_nil(v) or v == :missing 
    end)
    
    # Run imputation
    IsingImputationRun.reconstruct(
      problem.id,
      incomplete_data,
      missing_mask,
      imputation_method: Keyword.get(opts, :imputation_method, :simulated_annealing)
    )
  end
  
  defp prediction_phase(imputation, predictor_type, opts) do
    IsingPredictionRun.predict(
      imputation.id,
      imputation.reconstructed_config,
      prediction_type: Keyword.get(opts, :prediction_type, :next_state),
      predictor_type: predictor_type
    )
  end
end
```

**Estimated Effort**: 2 days  
**Tests**: 5 integration tests  
**Documentation**: Full pipeline example with benchmarks

---

## Phase 2: Resonance Metrics & Near-Critical Dynamics (Week 3-4)

**Priority**: 🟡 **MEDIUM** - Applies to multiple systems  
**Dependencies**: Phase 1 complete

### Task 2.1: Create ResonanceMetric Resource

**Purpose**: Track edge-of-chaos metrics (Research Area #3)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/resonance_metric.ex
defmodule Thunderline.Thunderbolt.Resources.ResonanceMetric do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "resonance_metrics"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    # Near-critical dynamics indicators
    attribute :plv, :decimal do
      allow_nil? false
      description "Phase-locking value (0-1, higher = more synchrony)"
    end
    
    attribute :sigma, :decimal do
      allow_nil? false
      description "Propagation coefficient (target: ~1.0 for criticality)"
    end
    
    attribute :lambda_hat, :decimal do
      allow_nil? false
      description "Finite-time Lyapunov exponent (target: ≤0 for stability)"
    end
    
    attribute :eta_arch, :decimal do
      description "Architecture entropy (optional, measures diversity)"
    end
    
    attribute :r_tau, :decimal do
      description "Cross-layer resonance (optional, correlation strength)"
    end
    
    # Metadata
    attribute :window_size, :integer do
      default 128
      description "Number of timesteps used for computation"
    end
    
    attribute :sampling_rate, :float do
      description "Hz if time-series, or steps/sec"
    end
    
    attribute :metadata, :map, default: %{}
    
    create_timestamp :measured_at
  end

  relationships do
    # Polymorphic - can attach to multiple run types
    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun
    belongs_to :ising_run, Thunderline.Thunderbolt.Resources.IsingOptimizationRun
    belongs_to :automata_run, Thunderline.Thunderbolt.Resources.AutomataRun
  end

  actions do
    defaults [:read]
    
    create :record_metrics do
      accept [:plv, :sigma, :lambda_hat, :eta_arch, :r_tau, :window_size, :metadata]
      
      argument :run_id, :uuid, allow_nil?: false
      argument :run_type, :atom do
        constraints one_of: [:model, :ising, :automata]
      end
    end
  end

  calculations do
    calculate :is_critical, :boolean, expr(
      # Near edge-of-chaos: σ ≈ 1.0 and λ̂ ≤ 0
      sigma >= 0.9 and sigma <= 1.1 and lambda_hat <= 0.05
    )
    
    calculate :chaos_distance, :decimal, expr(
      # How far from ideal criticality
      abs(sigma - 1.0) + max(lambda_hat, 0.0)
    )
  end

  code_interface do
    define :record_metrics, args: [:run_id, :run_type]
  end
end
```

**Estimated Effort**: 2 days  
**Tests**: 4 unit tests

---

### Task 2.2: Implement ResonanceComputer Module

**Purpose**: Compute PLV, σ, λ̂ from activation tensors

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resonance_computer.ex
defmodule Thunderline.Thunderbolt.ResonanceComputer do
  @moduledoc """
  Computes near-critical dynamics metrics from system activations.
  
  Based on research showing that controlling these metrics keeps systems
  at the edge of chaos, improving adaptability and preventing runaway.
  
  ## Metrics
  
  - **PLV** (Phase-Locking Value): Measures synchronization between signals
  - **σ** (Propagation Coefficient): Layer-to-layer gradient magnitude ratio
  - **λ̂** (Finite-time Lyapunov): Sensitivity to initial conditions
  - **η_arch**: Architecture entropy (layer diversity)
  - **r_τ**: Cross-layer resonance (temporal correlation)
  
  ## Target Ranges
  
  - PLV: 0.3-0.7 (moderate synchrony)
  - σ: 0.9-1.1 (critical propagation)
  - λ̂: ≤0 (stable, not chaotic)
  """
  
  import Nx.Defn
  
  @doc """
  Compute phase-locking value between two signals.
  
  Uses Hilbert transform to extract instantaneous phase,
  then computes mean phase difference consistency.
  """
  defn compute_plv(signal1, signal2, opts \\ []) do
    # 1. Extract instantaneous phase via Hilbert transform
    # 2. Compute phase difference: Δφ(t) = φ1(t) - φ2(t)
    # 3. PLV = |⟨exp(i·Δφ)⟩|
    
    # Placeholder - full implementation requires FFT
    Nx.tensor(0.5)
  end
  
  @doc """
  Compute propagation coefficient across layers.
  
  σ = ||∇L_out|| / ||∇L_in||
  Target: σ ≈ 1.0 for critical regime
  """
  defn compute_sigma(layer_activations) do
    # 1. Compute gradient magnitudes for each layer
    # 2. Take ratio of consecutive layers
    # 3. Average across batch
    
    Nx.tensor(1.0)
  end
  
  @doc """
  Compute finite-time Lyapunov exponent.
  
  Measures divergence of nearby trajectories via Jacobian.
  Target: λ̂ ≤ 0 for stable (not chaotic) dynamics
  """
  defn compute_lambda_hat(jacobian, time_window) do
    # 1. Take eigenvalues of Jacobian product
    # 2. Compute log(max eigenvalue) / time_window
    
    Nx.tensor(0.0)
  end
  
  @doc """
  Compute all metrics from activation history.
  
  ## Parameters
  - activations: List of layer activation tensors [batch, features]
  - window_size: Number of timesteps to analyze
  
  ## Returns
  %{plv: float, sigma: float, lambda_hat: float, ...}
  """
  def compute_all_metrics(activations, window_size \\ 128) do
    # TODO: Full implementation
    %{
      plv: 0.5,
      sigma: 1.0,
      lambda_hat: 0.0,
      eta_arch: 0.8,
      r_tau: 0.6
    }
  end
end
```

**Estimated Effort**: 4-5 days (complex signal processing)  
**Tests**: 8 unit tests  
**Dependencies**: May need `Scholar.Signal` or custom Nx kernels

---

### Task 2.3: Add Resonance Instrumentation to IsingMachine

**Purpose**: Track criticality during Ising runs

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/ising_machine.ex
# Add resonance tracking to run_annealing/3

def run_annealing(problem, initial_state, opts \\ []) do
  track_resonance? = Keyword.get(opts, :track_resonance, false)
  
  result = # ... existing annealing logic
  
  if track_resonance? do
    # Compute metrics from state history
    metrics = ResonanceComputer.compute_all_metrics(
      result.state_history,
      window_size: 128
    )
    
    # Store metrics
    {:ok, _metric} = ResonanceMetric.record_metrics(
      result.run_id,
      :ising,
      plv: metrics.plv,
      sigma: metrics.sigma,
      lambda_hat: metrics.lambda_hat
    )
  end
  
  result
end
```

**Estimated Effort**: 1 day  
**Tests**: 2 integration tests

---

### Task 2.4: Implement Loop Detector

**Purpose**: Detect repeating patterns in LLM outputs or CA states

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/loop_detector.ex
defmodule Thunderline.Thunderbolt.LoopDetector do
  @moduledoc """
  Broadway processor for detecting periodic loops in sequences.
  
  Uses spectral analysis (FFT) to detect repeating patterns at
  periodicities of 3-12 tokens/states. Publishes ai.loop.detected
  events when loops occur.
  
  Based on research showing that near-critical systems can exhibit
  oscillatory behavior that should be detected and dampened.
  """
  
  use Broadway
  
  alias Thunderline.Thunderflow.EventBus
  
  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "token_stream"},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 4]
      ]
    )
  end
  
  @impl true
  def handle_message(_processor, message, _context) do
    # Extract token sequence from message
    tokens = message.data.tokens
    
    # Compute FFT to detect periodicities
    case detect_loop(tokens) do
      {:loop_detected, period, strength} ->
        # Publish event
        EventBus.publish_event!([
          Thunderline.Event.new!(
            "ai.loop.detected",
            :thunderbolt,
            %{
              period: period,
              strength: strength,
              sequence_length: length(tokens),
              run_id: message.data.run_id
            }
          )
        ])
        
        message
      
      :no_loop ->
        message
    end
  end
  
  defp detect_loop(tokens) when length(tokens) < 12, do: :no_loop
  
  defp detect_loop(tokens) do
    # 1. Convert tokens to numeric embedding indices
    # 2. Compute FFT
    # 3. Find peaks at periodicities 3-12
    # 4. If peak > threshold, return {:loop_detected, period, strength}
    
    :no_loop  # Placeholder
  end
end
```

**Estimated Effort**: 3 days  
**Tests**: 5 unit tests + 1 integration test

---

## Phase 3: Spatial Reasoning & AutoML (Week 5-6)

**Priority**: 🟡 **MEDIUM** - Specialized features  
**Dependencies**: Phase 1 complete

### Task 3.1: Create RelFact Resource

**Purpose**: Store discovered geometric/graph relations (Research Area #4)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/rel_fact.ex
defmodule Thunderline.Thunderbolt.Resources.RelFact do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rel_facts"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    # Relation definition
    attribute :relation_type, :atom do
      allow_nil? false
      constraints one_of: [
        :parallel, :perpendicular, :inside, :outside, :tangent,
        :adjacent, :connected, :disjoint, :contains, :overlaps
      ]
      description "Geometric or topological relation"
    end
    
    # Subject and object (can be nodes, zones, cells, etc.)
    attribute :subject_id, :string, allow_nil?: false
    attribute :subject_type, :atom, allow_nil?: false  # :node, :zone, :cell
    
    attribute :object_id, :string, allow_nil?: false
    attribute :object_type, :atom, allow_nil?: false
    
    # Confidence and source
    attribute :confidence, :decimal do
      default 1.0
      description "0.0-1.0, certainty of relation"
    end
    
    attribute :inferred_by, :atom do
      constraints one_of: [:relid_engine, :manual, :topology_scan, :ca_rules]
      default :relid_engine
    end
    
    # Metadata
    attribute :metadata, :map, default: %{}
    attribute :proof_trace, {:array, :string} do
      description "Reverse-reasoning steps (GeoCoT style)"
    end
    
    create_timestamp :discovered_at
  end

  actions do
    defaults [:read, :destroy]
    
    create :infer_relation do
      accept [:relation_type, :subject_id, :subject_type, 
              :object_id, :object_type, :confidence, :metadata, :proof_trace]
    end
  end

  code_interface do
    define :infer_relation
    define :get_by_subject, action: :read, args: [:subject_id]
  end
end
```

**Estimated Effort**: 1-2 days  
**Tests**: 3 unit tests

---

### Task 3.2: Implement RelID.Engine Module

**Purpose**: GeoCoT-style relation discovery (Research Area #4)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/relid_engine.ex
defmodule Thunderline.Thunderbolt.RelID.Engine do
  @moduledoc """
  Relation Identification Engine using GeoCoT-style reverse reasoning.
  
  Based on research showing that:
  1. Decomposing shapes into primitives (points, lines, planes)
  2. Identifying relations via reverse reasoning
  3. Reduces hallucinations in spatial reasoning
  
  ## Process
  
  1. **Decomposition**: Break down zones/grids into primitives
  2. **Relation Discovery**: Test for parallel, inside, tangent, etc.
  3. **Proof Generation**: Create reasoning trace for auditability
  4. **Fact Storage**: Persist in RelFact resource
  """
  
  alias Thunderline.Thunderbolt.Resources.{RelFact, CellTopology}
  
  @doc """
  Analyze topology and infer all spatial relations.
  
  ## Parameters
  - topology: CellTopology record with grid/graph structure
  - opts: Confidence threshold, relation types to check, etc.
  
  ## Returns
  {:ok, [%RelFact{}]} - List of discovered relations
  """
  def analyze_topology(topology, opts \\ []) do
    # 1. Decompose topology into primitives
    primitives = decompose_topology(topology)
    
    # 2. Test pairwise relations
    relations = for p1 <- primitives, p2 <- primitives, p1 != p2 do
      test_relations(p1, p2)
    end
    |> List.flatten()
    |> Enum.filter(&(&1.confidence >= Keyword.get(opts, :min_confidence, 0.7)))
    
    # 3. Store facts
    facts = Enum.map(relations, fn rel ->
      RelFact.infer_relation!(rel)
    end)
    
    {:ok, facts}
  end
  
  defp decompose_topology(topology) do
    # TODO: Extract nodes, edges, zones from topology
    # Return list of primitives with coordinates/properties
    []
  end
  
  defp test_relations(primitive1, primitive2) do
    # TODO: Test geometric relations
    # - parallel? perpendicular? inside? adjacent?
    # Return list of %{relation_type, subject_id, object_id, confidence, proof_trace}
    []
  end
end
```

**Estimated Effort**: 4-5 days  
**Tests**: 10 unit tests (one per relation type)  
**Documentation**: Example with 3D CellTopology

---

### Task 3.3: Extend CerebrosTrainingJob for Multi-Concept Search

**Purpose**: Portfolio SMBO with MAJ scheduler (Research Area #5)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/resources/cerebros_training_job.ex
# Add new attributes:

attribute :concept_family, :string do
  description "Concept identifier for multi-concept search (e.g., 'CNN_family')"
end

attribute :surrogate_model, :atom do
  constraints one_of: [:tpe, :random_forest, :gp, :smac]
  default :tpe
  description "Which surrogate to use for this concept"
end

attribute :diversity_bonus, :decimal do
  default 0.1
  description "Weight for exploration vs exploitation in MAJ scheduler"
end

attribute :budget_consumed, :integer do
  default 0
  description "Number of evaluations used so far"
end

attribute :cooldown_until, :utc_datetime_usec do
  description "Don't schedule this concept again until this time"
end

# Add relationship:
has_many :concept_peers, __MODULE__ do
  filter expr(concept_family == parent(concept_family))
  description "Other concepts in same portfolio"
end

# Add action:
update :schedule_next_trial do
  accept [:budget_consumed, :cooldown_until]
  
  change fn changeset, context ->
    # Implement MAJ (Multi-Armed Juggling) logic
    # 1. Compute UCB/EI scores for all concepts in family
    # 2. Apply diversity bonus
    # 3. Select concept with highest score
    # 4. Update cooldown to prevent over-scheduling
    
    changeset
  end
end
```

**Migration**: `mix ash.codegen add_multi_concept_to_cerebros`

**Estimated Effort**: 3 days  
**Tests**: 5 unit tests + 2 integration tests

---

### Task 3.4: Implement MAJScheduler Module

**Purpose**: Portfolio scheduling for multi-concept search (Research Area #5)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/maj_scheduler.ex
defmodule Thunderline.Thunderbolt.MAJScheduler do
  @moduledoc """
  Multi-Armed Juggling (MAJ) scheduler for multi-concept AutoML.
  
  Based on research showing that combining multiple surrogate models
  (TPE, Random Forest, GP) in a portfolio search uncovers more distinct
  concept families than any single model.
  
  ## Algorithm
  
  1. Maintain portfolio of concepts (each with own surrogate)
  2. Compute acquisition scores (UCB, EI) for each concept
  3. Apply diversity bonus to encourage exploration
  4. Schedule concept with highest adjusted score
  5. Update budgets and cooldowns
  
  ## Diversity Bonus
  
  Penalizes concepts that are too similar to recently explored ones,
  encouraging exploration of distinct architecture families.
  """
  
  alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
  
  @doc """
  Select next concept to explore from portfolio.
  
  ## Parameters
  - concept_family: Family identifier (e.g., "nas_search_001")
  - budget_remaining: Total evaluations left
  - diversity_weight: 0.0-1.0, higher = more exploration
  
  ## Returns
  {:ok, concept_id} - ID of concept to schedule next
  """
  def select_next_concept(concept_family, budget_remaining, diversity_weight \\ 0.1) do
    # 1. Load all concepts in family
    concepts = CerebrosTrainingJob
    |> Ash.Query.filter(concept_family: ^concept_family)
    |> Ash.Query.filter(is_nil(cooldown_until) or cooldown_until < ^DateTime.utc_now())
    |> Ash.read!()
    
    # 2. Compute scores
    scored = Enum.map(concepts, fn concept ->
      base_score = compute_acquisition_score(concept)
      diversity_bonus = compute_diversity_bonus(concept, concepts, diversity_weight)
      
      %{
        concept: concept,
        score: base_score + diversity_bonus
      }
    end)
    
    # 3. Select best
    best = Enum.max_by(scored, & &1.score)
    
    {:ok, best.concept.id}
  end
  
  defp compute_acquisition_score(concept) do
    # UCB or EI based on concept's surrogate model
    # TODO: Integrate with TPE/RF/GP implementations
    0.5
  end
  
  defp compute_diversity_bonus(concept, all_concepts, weight) do
    # Measure distance to recently explored concepts
    # Higher distance = higher bonus
    # TODO: Use architecture embedding distance
    weight * 0.5
  end
end
```

**Estimated Effort**: 3-4 days  
**Tests**: 6 unit tests  
**Documentation**: Example portfolio search workflow

---

## Phase 4: Evaluation Hygiene & Documentation (Week 7)

**Priority**: 🟢 **HIGH** - Critical for reliability  
**Dependencies**: Phase 3 complete

### Task 4.1: Add Nested CV to CerebrosTrainingJob

**Purpose**: Prevent overtuning (Research Area #5)

**Implementation**:

```elixir
# Add attributes:
attribute :data_split_hash, :string do
  description "Hash of train/val/test splits for reproducibility"
end

attribute :outer_fold, :integer do
  description "Outer CV fold (for nested validation)"
end

attribute :inner_fold, :integer do
  description "Inner CV fold (for hyperparameter selection)"
end

attribute :holdout_split_path, :string do
  description "Path to honest holdout set (never touched during search)"
end

# Add action:
update :record_nested_cv_results do
  accept [:outer_fold, :inner_fold, :data_split_hash]
  
  change fn changeset, context ->
    # Validate that holdout wasn't leaked
    # Log split configuration
    changeset
  end
end
```

**Migration**: `mix ash.codegen add_nested_cv_to_cerebros`

**Estimated Effort**: 2 days  
**Tests**: 4 unit tests

---

### Task 4.2: Add Multi-Seed Reporting

**Purpose**: Confidence intervals for metrics (Research Area #5)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/multi_seed_reporter.ex
defmodule Thunderline.Thunderbolt.MultiSeedReporter do
  @moduledoc """
  Aggregates metrics across multiple random seeds to compute
  confidence intervals, preventing overtuning to single runs.
  
  Based on AutoML hygiene research showing that single-seed
  reporting can mask instability and overfit.
  """
  
  @doc """
  Aggregate metrics from multiple seeds.
  
  ## Parameters
  - job_ids: List of CerebrosTrainingJob IDs (same config, diff seeds)
  
  ## Returns
  %{
    mean: float,
    std: float,
    ci_95: {lower, upper},
    min: float,
    max: float
  }
  """
  def aggregate_metrics(job_ids, metric_name) do
    # 1. Load all jobs
    # 2. Extract metric values
    # 3. Compute mean, std, CI
    # 4. Return summary
    
    %{mean: 0.0, std: 0.0, ci_95: {0.0, 0.0}, min: 0.0, max: 0.0}
  end
end
```

**Estimated Effort**: 1 day  
**Tests**: 3 unit tests

---

### Task 4.3: Create Research Integration Documentation

**Purpose**: Document rationale and cross-reference papers

**Deliverables**:

1. **docs/research/META_LEARNING_ISING.md**
   - Explain pooled ℓ1-logistic selection
   - Sample complexity derivation (O(d³ log p / K))
   - Link to IsingInverseGraph resource
   - Example usage

2. **docs/research/DUAL_MODEL_PIPELINE.md**
   - Ising-Traffic workflow
   - Benchmarks (98.7% accuracy, 10⁶× speedup)
   - Link to IsingImputationRun/IsingPredictionRun
   - Example use case

3. **docs/research/NEAR_CRITICAL_DYNAMICS.md**
   - PLV, σ, λ̂ definitions
   - Target ranges for edge-of-chaos
   - Link to ResonanceMetric resource
   - Instrumentation guide

4. **docs/research/GEOCOT_RELATIONS.md**
   - Relation identification process
   - Proof trace examples
   - Link to RelFact resource
   - Integration with CellTopology

5. **docs/research/MULTI_CONCEPT_AUTOML.md**
   - MAJ scheduler algorithm
   - Portfolio search benefits
   - Link to CerebrosTrainingJob extensions
   - Evaluation hygiene guidelines

6. **Update docs/domains/THUNDERBOLT_OVERVIEW.md**
   - Add section on research-backed enhancements
   - Link to all 5 research docs
   - Migration guide from legacy modules

**Estimated Effort**: 4-5 days (technical writing)

---

## Phase 5: Hardware Abstraction (Week 8+)

**Priority**: 🔵 **LOW** - Future-proofing  
**Dependencies**: All above phases

### Task 5.1: Define IsingMachine.Solver Behaviour

**Purpose**: Abstract solver for CPU/GPU/hardware (Research Area #6)

**Implementation**:

```elixir
# File: lib/thunderline/thunderbolt/ising_machine/solver.ex
defmodule Thunderline.Thunderbolt.IsingMachine.Solver do
  @moduledoc """
  Behaviour for Ising machine solvers.
  
  Enables swapping between CPU (simulated annealing), GPU (Nx),
  and hardware accelerators (BRIM, digital annealing) without
  changing application code.
  """
  
  @type problem :: map()
  @type initial_state :: map()
  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, term()}
  
  @callback solve(problem, initial_state, opts) :: result
  @callback solver_type() :: :cpu | :gpu | :hardware
  @callback max_problem_size() :: integer()
end

# Default CPU implementation
defmodule Thunderline.Thunderbolt.IsingMachine.CPUSolver do
  @behaviour Thunderline.Thunderbolt.IsingMachine.Solver
  
  @impl true
  def solve(problem, initial_state, opts) do
    # Existing simulated annealing code
    {:ok, %{final_state: %{}, energy: 0.0}}
  end
  
  @impl true
  def solver_type, do: :cpu
  
  @impl true
  def max_problem_size, do: 10_000
end
```

**Estimated Effort**: 2 days  
**Tests**: 3 unit tests  
**Future**: Add GPUSolver (Nx), HardwareSolver (BRIM adapter)

---

## Phase 6: Consolidation & Testing (Week 9-10)

**Priority**: 🟢 **HIGH** - Ensure quality  
**Dependencies**: Phases 1-4 complete

### Task 6.1: Integration Test Suite

**Test Scenarios**:

1. **Meta-Learning Workflow**
   - Create 5 problems in task_family "zone_A"
   - Learn support set via IsingInverseGraph
   - Create new problem in same family
   - Verify support is used for optimization
   - Compare sample complexity vs non-pooled

2. **Dual-Model Pipeline**
   - Create problem with 30% missing data
   - Run DualModelPipeline.run()
   - Verify imputation accuracy > 95%
   - Verify prediction accuracy > baseline
   - Benchmark runtime vs tensor completion

3. **Resonance Tracking**
   - Run IsingMachine with track_resonance: true
   - Verify ResonanceMetric created
   - Check σ ≈ 1.0, λ̂ ≤ 0
   - Test loop detector with periodic sequence

4. **Relation Discovery**
   - Create 3D CellTopology grid
   - Run RelID.Engine.analyze_topology()
   - Verify adjacent/inside relations found
   - Check proof traces are complete

5. **Multi-Concept Search**
   - Create concept family with 3 surrogates
   - Run MAJScheduler.select_next_concept()
   - Verify diversity bonus applied
   - Check cooldowns enforced

**Estimated Effort**: 5-6 days  
**Tests**: 15 integration tests

---

### Task 6.2: Performance Benchmarking

**Benchmarks**:

1. **Ising Inverse Learning**
   - Measure time to learn support for K=5,10,20 tasks
   - Compare sample complexity empirically
   - Verify O(d³ log p / K) scaling

2. **Dual-Model vs Baselines**
   - Benchmark imputation accuracy vs tensor completion
   - Measure runtime (target: 100× faster on CPU, 10⁶× on hardware)
   - Test on traffic data, agent states, CA interpolation

3. **Resonance Computation Overhead**
   - Measure PLV/σ/λ̂ computation time
   - Test on 128, 512, 2048-step windows
   - Optimize using Nx or CUDA

4. **RelID Engine Scaling**
   - Test on grids: 10×10, 50×50, 100×100
   - Measure relation discovery time
   - Check memory usage

5. **MAJ Scheduler Throughput**
   - Test with 10, 50, 100 concepts in portfolio
   - Measure scheduling decision time
   - Verify no deadlocks or starvation

**Estimated Effort**: 3-4 days  
**Tools**: Benchee, :observer, custom profilers

---

### Task 6.3: Telemetry Dashboard Integration

**New Metrics for ThunderEye**:

1. **Ising Panel**
   - Inverse graph count by task family
   - Imputation accuracy histogram
   - Dual-model pipeline success rate
   - Hardware vs CPU runtime comparison

2. **Resonance Panel**
   - PLV/σ/λ̂ time series per run
   - Criticality gauge (green = near critical)
   - Loop detection events per hour
   - Chaos distance distribution

3. **Spatial Panel**
   - RelFact count by relation type
   - Proof trace depth histogram
   - Topology coverage (% of grid analyzed)

4. **AutoML Panel**
   - Concept diversity index
   - MAJ scheduler decisions per hour
   - Budget consumption by surrogate
   - Nested CV fold distribution

**Estimated Effort**: 4-5 days  
**Tools**: Phoenix LiveView, :telemetry_metrics

---

## Summary & Milestones

### Critical Path

```
Phase 0 (UPM Tests)       ▓▓▓▓▓▓▓▓▓░ 1.5-2 hours
Phase 1 (Ising Extension) ▓▓▓▓▓▓▓▓▓▓ 2 weeks
Phase 2 (Resonance)       ▓▓▓▓▓▓▓▓▓▓ 2 weeks
Phase 3 (Spatial/AutoML)  ▓▓▓▓▓▓▓▓▓▓ 2 weeks
Phase 4 (Documentation)   ▓▓▓▓▓▓▓░░░ 1 week
Phase 6 (Testing)         ▓▓▓▓▓▓▓▓▓▓ 2 weeks
-------------------------------------------
Total:                    ~9-10 weeks
```

### Key Deliverables

**Week 2**: ✅ Inverse Ising + Dual-Model pipeline functional  
**Week 4**: ✅ Resonance metrics + Loop detector operational  
**Week 6**: ✅ RelID engine + MAJ scheduler complete  
**Week 7**: ✅ Full documentation published  
**Week 10**: ✅ All integration tests passing, benchmarks validated

### Resource Allocation

**Engineering**: 1 senior engineer (full-time, 10 weeks)  
**Code Review**: 1 tech lead (25% time, ongoing)  
**Documentation**: 1 technical writer (50% time, weeks 7-10)  
**Testing**: QA support (25% time, weeks 8-10)

### Risk Mitigation

1. **Complexity Risk**: Start with Phase 1 (well-defined), defer Phase 5 (hardware)
2. **Dependency Risk**: Nx/Scholar may need custom kernels (budget extra time)
3. **Integration Risk**: Incremental integration, test after each phase
4. **Performance Risk**: Early benchmarking in Phase 1-2, optimize in Phase 6

---

## Immediate Next Steps

### After UPM Tests Complete (Today/Tomorrow)

1. ✅ **Commit final UPM work** - Mark HC-22 Task #3 complete
2. 📋 **Create JIRA epic** - "Research Integration: Ising & ML Enhancements"
3. 📋 **Create Phase 1 tickets** - 5 tickets for Tasks 1.1-1.5
4. 📚 **Set up research docs** - Create `docs/research/` directory
5. 🔬 **Prototype IsingInverseGraph** - Test resource structure (1 day spike)

### This Week

- [ ] Complete UPM SnapshotManager (6 tests remaining)
- [ ] Review roadmap with tech lead
- [ ] Start Task 1.1 (IsingInverseGraph resource)
- [ ] Begin research documentation (META_LEARNING_ISING.md)

### This Sprint (2 weeks)

- [ ] Complete Phase 1 Tasks 1.1-1.5
- [ ] All Ising infrastructure extended
- [ ] Dual-model pipeline functional
- [ ] Initial integration tests passing
- [ ] Demo ready for stakeholder review

---

## References & Papers

1. **Meta-learning for Inverse Ising** - Sample complexity O(d³ log p / K)
2. **Ising-Traffic Dual Model** - 98.7% accuracy, 10⁶× faster than tensor completion
3. **Near-Critical Dynamics for LLMs** - PLV, σ, λ̂ metrics for edge-of-chaos
4. **Geometry Chain-of-Thought (GeoCoT)** - Spatial reasoning via reverse decomposition
5. **Multi-concept Design Search** - Portfolio SMBO with MAJ scheduler
6. **Hyperparameter Overtuning Hazards** - Nested CV, multi-seed, honest holdouts

*(Full citations in research docs)*

---

**Status**: 📋 Draft - Ready for Review  
**Next Review**: After UPM tests complete  
**Owner**: Engineering Team  
**Approver**: Tech Lead + High Command
