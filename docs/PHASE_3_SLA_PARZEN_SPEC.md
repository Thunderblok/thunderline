# Phase 3: SLA + Parzen Adaptive Model Selection

**Status**: 🟡 NOT STARTED  
**Priority**: P0 (Intelligence Core)  
**Duration**: 3-4 days  
**Created**: November 13, 2025

## Overview

This phase implements the **adaptive intelligence layer** that sits on top of the ONNX adapter from Phase 2.2. Instead of hardcoding which model to use, we implement a **Stochastic Learning Automaton (SLA)** that learns which model best fits the data distribution by comparing:

- **Parzen window** (non-parametric density) — empirical distribution of actual data
- **Candidate models** (parametric densities) — ONNX models with different architectures/hyperparams

The SLA uses reinforcement learning to converge toward the best model for each (PAC, zone, feature_family) context.

**Paper Reference**: "An Improved Adaptive Parzen Window Approach Based on Stochastic Learning Automata" (2007)

---

## Architecture Overview

```
Thunderflow Events (embeddings/features)
          ↓
    [Parzen Estimator] → builds empirical PDF p_parzen(x)
          ↓
    [SLA Selector] → chooses candidate model M_j with probability P(u_j)
          ↓
    [ONNX Adapter] → runs inference via M_j, gets p_model(x)
          ↓
    [Distance Metric] → computes KL(p_parzen || p_model)
          ↓
    [Reward Calculator] → distance improved? reward=1 : reward=0
          ↓
    [SLA Update] → adjusts P(u_j) via learning automaton rules
          ↓
    [Voxel Builder] → embeds {chosen_model, P(u_j), distances} into voxel metadata
          ↓
    [Thundergrid DAG] → uses adaptive model selection in zone evolution
```

---

## Phase 3 Modules

### 3.1 Module Skeletons

Create 4 new modules with typespecs, docs, and function signatures (no heavy implementation yet):

#### `lib/thunderline/ml/parzen.ex`

**Purpose**: Non-parametric density estimator using Parzen windows.

**Core Concept**: 
```
p_parzen(x) = (1/N) Σ Φ(|x - xᵢ|)
where Φ = Gaussian kernel
```

**MVP Simplification**: Histogram-based density on 1-2 principal components instead of full Parzen kernel.

**Struct**:
```elixir
defmodule Thunderline.ML.Parzen do
  @moduledoc """
  Non-parametric density estimation using Parzen windows.
  
  Maintains a sliding window of feature vectors and builds a histogram-based
  density estimate (MVP) or full kernel density estimate (future).
  
  ## Theory
  
  Parzen windows approximate the PDF without assuming a parametric form:
  
      p(x) = (1/N) Σᵢ₌₁ᴺ K((x - xᵢ)/h)
  
  where K = kernel function (Gaussian), h = bandwidth.
  
  **MVP**: Use PCA to reduce to 1-2 dims, then compute normalized histogram.
  
  ## Usage
  
      iex> parzen = Parzen.init(window_size: 300, bins: 20, dims: 2)
      iex> parzen = Parzen.fit(parzen, batch_of_vectors)
      iex> hist = Parzen.histogram(parzen)
      iex> prob = Parzen.density_at(parzen, point)
  """
  
  @type t :: %__MODULE__{
    window: list(Nx.Tensor.t()),      # Sliding window of recent vectors
    window_size: pos_integer(),        # Max samples to keep (e.g., 300)
    bins: pos_integer(),                # Histogram bins (e.g., 20)
    dims: pos_integer(),                # Target dimensionality (1 or 2)
    pca_basis: Nx.Tensor.t() | nil,    # PCA projection matrix
    histogram: Nx.Tensor.t() | nil,    # Normalized histogram
    bin_edges: list(tuple()) | nil,    # Bin boundaries for each dim
    total_samples: non_neg_integer()   # Total samples processed
  }
  
  defstruct [
    :window,
    :window_size,
    :bins,
    :dims,
    :pca_basis,
    :histogram,
    :bin_edges,
    :total_samples
  ]
  
  @doc """
  Initialize a new Parzen estimator.
  
  ## Options
  
  - `:window_size` - Max samples in sliding window (default: 300)
  - `:bins` - Histogram bins per dimension (default: 20)
  - `:dims` - Target dimensionality after PCA (default: 2)
  """
  @spec init(keyword()) :: t()
  def init(opts \\ [])
  
  @doc """
  Update the Parzen estimator with a new batch of feature vectors.
  
  ## Process
  
  1. Append new vectors to window (FIFO, drop oldest if exceeds window_size)
  2. If first batch or window changed significantly:
     - Compute PCA basis on window
     - Project all vectors to target dims
     - Build histogram
     - Normalize to get density estimate
  
  ## Parameters
  
  - `parzen` - Current Parzen state
  - `batch` - Nx.Tensor of shape {batch_size, feature_dim}
  
  ## Returns
  
  Updated Parzen estimator with new histogram.
  """
  @spec fit(t(), Nx.Tensor.t()) :: t()
  def fit(parzen, batch)
  
  @doc """
  Get the normalized histogram (discrete PDF approximation).
  
  Returns an Nx.Tensor representing the probability density over bins.
  Sum of all bins = 1.0.
  """
  @spec histogram(t()) :: Nx.Tensor.t()
  def histogram(parzen)
  
  @doc """
  Compute density at a specific point (for validation/debugging).
  
  Projects point using PCA basis, finds corresponding bin, returns density.
  """
  @spec density_at(t(), Nx.Tensor.t()) :: float()
  def density_at(parzen, point)
  
  @doc """
  Serialize Parzen state for storage in voxel metadata.
  
  Returns a compact map suitable for JSON encoding.
  """
  @spec snapshot(t()) :: map()
  def snapshot(parzen)
  
  @doc """
  Restore Parzen state from a snapshot.
  """
  @spec from_snapshot(map()) :: t()
  def from_snapshot(snapshot)
end
```

---

#### `lib/thunderline/ml/sla_selector.ex`

**Purpose**: Stochastic Learning Automaton for model selection.

**Core Concept**:
```
Learning Automaton maintains:
  - Actions U = {u₁, u₂, ..., uₘ} (candidate model IDs)
  - Probabilities P = {P(u₁), P(u₂), ..., P(uₘ)}
  - Update rules based on reward/penalty

Reward update (distance improved):
  P(uⱼ) ← P(uⱼ) + α[1 - P(uⱼ)]
  P(uᵢ) ← P(uᵢ) - (α/(m-1))P(uᵢ)  for i ≠ j

Penalty update (distance worsened):
  P(uⱼ) ← (1-v)P(uⱼ)
  P(uᵢ) ← (v/(m-1)) + (1-v)P(uᵢ)  for i ≠ j
```

**Struct**:
```elixir
defmodule Thunderline.ML.SLASelector do
  @moduledoc """
  Stochastic Learning Automaton for adaptive model selection.
  
  Implements the reinforcement learning scheme from:
  "An Improved Adaptive Parzen Window Approach Based on Stochastic Learning Automata"
  
  ## Theory
  
  A learning automaton operates in an unknown random environment, learning
  to choose actions that maximize rewards. In our case:
  
  - **Actions**: Candidate ONNX models {M₁, M₂, ..., Mₘ}
  - **Reward**: Distance between Parzen and model improved (binary)
  - **Goal**: Converge probabilities toward the best model
  
  The SLA maintains a probability vector P(uⱼ) for each action and updates
  it based on feedback using learning rates α (reward) and v (penalty).
  
  ## Usage
  
      iex> sla = SLASelector.init([:model_k1, :model_k2, :model_k3], alpha: 0.1, v: 0.05)
      iex> action = SLASelector.choose_action(sla)  # => :model_k2
      iex> sla = SLASelector.update(sla, :model_k2, reward: 1)
      iex> SLASelector.probabilities(sla)
      %{model_k1: 0.15, model_k2: 0.73, model_k3: 0.12}
  """
  
  @type action :: atom() | String.t()  # Model ID
  @type t :: %__MODULE__{
    actions: list(action()),              # Candidate model IDs
    probabilities: map(),                 # %{action => probability}
    alpha: float(),                       # Reward learning rate (0 < α ≤ 1)
    v: float(),                           # Penalty learning rate (0 < v ≤ 1)
    iteration: non_neg_integer(),         # Update iteration count
    reward_history: list(tuple()),        # [{action, reward, timestamp}]
    last_distance: float() | nil          # Previous distance for comparison
  }
  
  defstruct [
    :actions,
    :probabilities,
    :alpha,
    :v,
    :iteration,
    :reward_history,
    :last_distance
  ]
  
  @doc """
  Initialize a new SLA with uniform probabilities over actions.
  
  ## Options
  
  - `:alpha` - Reward learning rate (default: 0.1)
  - `:v` - Penalty learning rate (default: 0.05)
  - `:history_size` - Max reward history entries (default: 100)
  """
  @spec init(list(action()), keyword()) :: t()
  def init(actions, opts \\ [])
  
  @doc """
  Choose an action using current probability distribution.
  
  ## Strategies
  
  - `:sample` - Sample according to P(uⱼ) (exploration)
  - `:greedy` - Choose argmax P(uⱼ) (exploitation)
  
  Default: `:sample` (recommended for learning phase)
  """
  @spec choose_action(t(), strategy: atom()) :: action()
  def choose_action(sla, opts \\ [])
  
  @doc """
  Update probabilities based on reward feedback.
  
  ## Parameters
  
  - `sla` - Current SLA state
  - `action` - The action that was taken
  - `reward` - Binary reward (1 = success, 0 = failure)
  - `distance` - Current distance metric (optional, for history tracking)
  
  ## Returns
  
  Updated SLA with adjusted probabilities.
  
  ## Algorithm
  
  If reward = 1 (distance improved):
    P(chosen) ← P(chosen) + α[1 - P(chosen)]
    P(other)  ← P(other) - (α/(m-1))P(other)
  
  If reward = 0 (distance worsened):
    P(chosen) ← (1-v)P(chosen)
    P(other)  ← (v/(m-1)) + (1-v)P(other)
  """
  @spec update(t(), action(), keyword()) :: t()
  def update(sla, action, opts)
  
  @doc """
  Get current probability distribution.
  
  Returns a map %{action => probability}.
  """
  @spec probabilities(t()) :: map()
  def probabilities(sla)
  
  @doc """
  Get current state snapshot for introspection/storage.
  
  Returns a map with:
  - `:probabilities` - Current P(uⱼ) distribution
  - `:iteration` - Update count
  - `:best_action` - Action with highest probability
  - `:convergence` - Entropy-based convergence metric (0 = converged, 1 = uniform)
  """
  @spec state(t()) :: map()
  def state(sla)
  
  @doc """
  Check if SLA has converged (one probability > threshold).
  
  Default threshold: 0.85
  """
  @spec converged?(t(), keyword()) :: boolean()
  def converged?(sla, opts \\ [])
  
  @doc """
  Serialize SLA state for storage in voxel metadata.
  """
  @spec snapshot(t()) :: map()
  def snapshot(sla)
  
  @doc """
  Restore SLA from snapshot.
  """
  @spec from_snapshot(map()) :: t()
  def from_snapshot(snapshot)
end
```

---

#### `lib/thunderline/ml/distance.ex`

**Purpose**: Compute distance/divergence between probability distributions.

**Struct**:
```elixir
defmodule Thunderline.ML.Distance do
  @moduledoc """
  Distance metrics for comparing probability distributions.
  
  Used to measure how well a parametric model (ONNX output) matches
  the empirical distribution (Parzen estimate).
  
  ## Metrics
  
  - **KL Divergence** (Kullback-Leibler): KL(P || Q) = Σ P(x) log(P(x)/Q(x))
  - **Cross-Entropy**: H(P,Q) = -Σ P(x) log(Q(x))
  - **Hellinger Distance**: H(P,Q) = sqrt(1 - Σ sqrt(P(x)Q(x)))
  - **Jensen-Shannon Divergence**: Symmetric KL variant
  
  ## Usage
  
      iex> parzen_hist = Nx.tensor([0.1, 0.3, 0.4, 0.2])
      iex> model_hist = Nx.tensor([0.15, 0.25, 0.35, 0.25])
      iex> Distance.kl_divergence(parzen_hist, model_hist)
      0.0234
  """
  
  @epsilon 1.0e-10  # Prevent log(0)
  
  @doc """
  Compute discrete KL divergence: KL(P || Q).
  
  ## Parameters
  
  - `p` - Reference distribution (Parzen histogram)
  - `q` - Approximating distribution (model histogram)
  
  ## Returns
  
  KL divergence as float (≥ 0, lower is better).
  
  ## Notes
  
  - Adds epsilon to prevent log(0)
  - Non-symmetric: KL(P||Q) ≠ KL(Q||P)
  """
  @spec kl_divergence(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def kl_divergence(p, q)
  
  @doc """
  Compute cross-entropy: H(P,Q) = -Σ P(x) log(Q(x)).
  
  Related to KL: H(P,Q) = H(P) + KL(P||Q)
  """
  @spec cross_entropy(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def cross_entropy(p, q)
  
  @doc """
  Compute Hellinger distance (symmetric, bounded [0,1]).
  
  Better behaved than KL when distributions have non-overlapping support.
  """
  @spec hellinger(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def hellinger(p, q)
  
  @doc """
  Compute Jensen-Shannon divergence (symmetric KL).
  
  JS(P,Q) = 0.5 * KL(P||M) + 0.5 * KL(Q||M)
  where M = 0.5(P + Q)
  """
  @spec js_divergence(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def js_divergence(p, q)
  
  @doc """
  Compute all distance metrics and return as map.
  
  Useful for comparison and telemetry.
  """
  @spec all_metrics(Nx.Tensor.t(), Nx.Tensor.t()) :: map()
  def all_metrics(p, q)
end
```

---

#### `lib/thunderline/ml/controller.ex`

**Purpose**: Orchestrate SLA + Parzen + ONNX for adaptive model selection.

**Struct**:
```elixir
defmodule Thunderline.ML.Controller do
  use GenServer
  
  @moduledoc """
  Adaptive model selection controller using SLA + Parzen.
  
  Manages the learning loop for a specific (PAC, zone, feature_family) context:
  
  1. Receive batch of feature vectors
  2. Update Parzen density estimate
  3. SLA chooses candidate model
  4. Run ONNX inference via chosen model
  5. Compute distance between Parzen and model output
  6. Calculate reward (distance improved?)
  7. Update SLA probabilities
  8. Emit `system.ml.model_selection.updated` event
  9. Return model outputs + metadata to downstream
  
  ## Supervision
  
  One Controller per (PAC, feature_family, zone) tuple.
  Managed by DynamicSupervisor under Thunderline.ML.ControllerRegistry.
  
  ## State
  
  - Parzen estimator
  - SLA selector
  - Candidate model registry
  - Last N distances (for reward calculation)
  - Telemetry accumulators
  
  ## Events Emitted
  
  - `system.ml.model_selection.updated`
    - Payload: {chosen_model_id, probabilities, distance_delta, reward, iteration}
  
  ## Telemetry
  
  - `[:ml, :controller, :update, :start]`
  - `[:ml, :controller, :update, :stop]` - measurements: %{distance, reward, iteration}
  - `[:ml, :controller, :model_changed]` - when best model switches
  - `[:ml, :controller, :converged]` - when SLA converges
  """
  
  @type state :: %{
    pac_id: String.t(),
    zone_id: String.t(),
    feature_family: atom(),
    parzen: Parzen.t(),
    sla: SLASelector.t(),
    candidate_models: list(map()),  # [{id, onnx_path, session}]
    distance_metric: atom(),         # :kl | :cross_entropy | :hellinger | :js
    last_chosen_model: atom() | nil,
    iteration: non_neg_integer()
  }
  
  @doc """
  Start a Controller for a specific context.
  
  ## Options
  
  - `:pac_id` - PAC identifier
  - `:zone_id` - Zone identifier
  - `:feature_family` - Feature family atom (e.g., :text_embedding, :telemetry)
  - `:candidate_models` - List of model specs [{id, onnx_path, opts}]
  - `:parzen_opts` - Options for Parzen.init/1
  - `:sla_opts` - Options for SLASelector.init/2
  - `:distance_metric` - Distance function to use (default: :kl)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts)
  
  @doc """
  Process a batch of feature vectors through the adaptive selection loop.
  
  ## Returns
  
  `{:ok, %{model_outputs: outputs, metadata: metadata}}`
  
  Where metadata includes:
  - `:chosen_model_id`
  - `:probabilities` - Current SLA P(uⱼ)
  - `:distance` - Current distance metric
  - `:reward` - Binary reward (0 or 1)
  - `:iteration`
  """
  @spec process_batch(pid() | atom(), Nx.Tensor.t(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def process_batch(controller, batch, opts \\ [])
  
  @doc """
  Get current controller state (for introspection/debugging).
  """
  @spec get_state(pid() | atom()) :: state()
  def get_state(controller)
  
  @doc """
  Get snapshot for voxel metadata embedding.
  
  Returns compact map with Parzen + SLA state.
  """
  @spec snapshot(pid() | atom()) :: map()
  def snapshot(controller)
  
  # GenServer callbacks
  @impl true
  def init(opts)
  
  @impl true
  def handle_call({:process_batch, batch, opts}, _from, state)
  
  @impl true
  def handle_call(:get_state, _from, state)
  
  @impl true
  def handle_call(:snapshot, _from, state)
  
  # Private helpers
  defp load_candidate_models(model_specs)
  defp compute_model_histogram(onnx_session, batch)
  defp calculate_reward(current_distance, last_distance)
  defp emit_update_event(state, metadata)
end
```

---

### 3.2 Parzen MVP Implementation

**File**: `lib/thunderline/ml/parzen.ex`

**Key Implementation Details**:

```elixir
# Simplified histogram approach (MVP)
# Full kernel density comes in Phase 4

def fit(%Parzen{} = parzen, batch) do
  # 1. Append batch to sliding window
  window = update_window(parzen.window, batch, parzen.window_size)
  
  # 2. Compute PCA basis if needed (first fit or window changed significantly)
  pca_basis = maybe_update_pca(parzen.pca_basis, window, parzen.dims)
  
  # 3. Project all window vectors to target dims
  projected = Nx.dot(Nx.concatenate(window), pca_basis)
  
  # 4. Build histogram
  {histogram, bin_edges} = build_histogram(projected, parzen.bins, parzen.dims)
  
  # 5. Normalize to get probability density
  normalized = Nx.divide(histogram, Nx.sum(histogram))
  
  %Parzen{parzen |
    window: window,
    pca_basis: pca_basis,
    histogram: normalized,
    bin_edges: bin_edges,
    total_samples: parzen.total_samples + Nx.axis_size(batch, 0)
  }
end

defp build_histogram(projected, bins, dims) when dims == 1 do
  # 1D histogram
  {min, max} = {Nx.reduce_min(projected), Nx.reduce_max(projected)}
  bin_width = (max - min) / bins
  
  # Create bin edges
  edges = Enum.map(0..bins, fn i -> min + i * bin_width end)
  
  # Count samples per bin (use Nx.histogram when available, or manual binning)
  counts = compute_bin_counts(projected, edges)
  
  {counts, [{min, max, bin_width}]}
end

defp build_histogram(projected, bins, dims) when dims == 2 do
  # 2D histogram (grid)
  # Similar to 1D but creates bins x bins grid
  # ...implementation...
end
```

**Tests**: `test/thunderline/ml/parzen_test.exs`
- Test sliding window FIFO behavior
- Test PCA dimension reduction
- Test histogram normalization (sum = 1.0)
- Test density_at for point queries
- Test snapshot serialization

---

### 3.3 Distance Metric Implementation

**File**: `lib/thunderline/ml/distance.ex`

**Key Implementation**:

```elixir
def kl_divergence(p, q) do
  # KL(P || Q) = Σ P(i) * log(P(i) / Q(i))
  
  # Add epsilon to prevent log(0)
  p_safe = Nx.add(p, @epsilon)
  q_safe = Nx.add(q, @epsilon)
  
  # Compute log ratio
  log_ratio = Nx.log(Nx.divide(p_safe, q_safe))
  
  # Weight by P and sum
  p_safe
  |> Nx.multiply(log_ratio)
  |> Nx.sum()
  |> Nx.to_number()
end

def cross_entropy(p, q) do
  # H(P,Q) = -Σ P(i) * log(Q(i))
  q_safe = Nx.add(q, @epsilon)
  
  p
  |> Nx.multiply(Nx.log(q_safe))
  |> Nx.sum()
  |> Nx.negate()
  |> Nx.to_number()
end

def hellinger(p, q) do
  # H(P,Q) = sqrt(1 - Σ sqrt(P(i) * Q(i)))
  
  sqrt_product = 
    p
    |> Nx.multiply(q)
    |> Nx.sqrt()
    |> Nx.sum()
  
  1.0
  |> Nx.subtract(sqrt_product)
  |> Nx.sqrt()
  |> Nx.to_number()
end
```

**Tests**: `test/thunderline/ml/distance_test.exs`
- Test KL with known distributions
- Test symmetry properties (KL is NOT symmetric, Hellinger IS)
- Test bounds (Hellinger ∈ [0,1])
- Test degenerate cases (identical distributions → distance = 0)

---

### 3.4 SLA Selector Implementation

**File**: `lib/thunderline/ml/sla_selector.ex`

**Key Implementation**:

```elixir
def init(actions, opts) when is_list(actions) and length(actions) > 0 do
  alpha = Keyword.get(opts, :alpha, 0.1)
  v = Keyword.get(opts, :v, 0.05)
  
  # Initialize uniform probabilities
  m = length(actions)
  uniform_prob = 1.0 / m
  probabilities = Map.new(actions, fn action -> {action, uniform_prob} end)
  
  %SLASelector{
    actions: actions,
    probabilities: probabilities,
    alpha: alpha,
    v: v,
    iteration: 0,
    reward_history: [],
    last_distance: nil
  }
end

def choose_action(%SLASelector{} = sla, opts \\ []) do
  strategy = Keyword.get(opts, :strategy, :sample)
  
  case strategy do
    :greedy ->
      # Choose action with max probability
      {action, _prob} = Enum.max_by(sla.probabilities, fn {_k, v} -> v end)
      action
      
    :sample ->
      # Sample according to probability distribution
      rand = :rand.uniform()
      cumulative_sample(sla.actions, sla.probabilities, rand, 0.0)
  end
end

defp cumulative_sample([action | rest], probs, rand, acc) do
  new_acc = acc + Map.get(probs, action)
  if rand <= new_acc do
    action
  else
    cumulative_sample(rest, probs, rand, new_acc)
  end
end

def update(%SLASelector{} = sla, action, opts) do
  reward = Keyword.fetch!(opts, :reward)
  distance = Keyword.get(opts, :distance)
  
  # Apply SLA update rules from paper
  new_probs = 
    if reward == 1 do
      reward_update(sla.probabilities, action, sla.alpha, length(sla.actions))
    else
      penalty_update(sla.probabilities, action, sla.v, length(sla.actions))
    end
  
  # Normalize to ensure sum = 1.0 (handle floating point drift)
  normalized_probs = normalize_probabilities(new_probs)
  
  # Update history
  new_history = 
    [{action, reward, DateTime.utc_now(), distance} | sla.reward_history]
    |> Enum.take(100)  # Keep last 100 updates
  
  %SLASelector{sla |
    probabilities: normalized_probs,
    iteration: sla.iteration + 1,
    reward_history: new_history,
    last_distance: distance
  }
end

defp reward_update(probs, chosen_action, alpha, m) do
  # Reward: chosen action probability increases
  # P(chosen) ← P(chosen) + α[1 - P(chosen)]
  # P(other)  ← P(other) - (α/(m-1))P(other)
  
  Map.new(probs, fn {action, p} ->
    if action == chosen_action do
      {action, p + alpha * (1.0 - p)}
    else
      {action, p - (alpha / (m - 1)) * p}
    end
  end)
end

defp penalty_update(probs, chosen_action, v, m) do
  # Penalty: chosen action probability decreases
  # P(chosen) ← (1-v)P(chosen)
  # P(other)  ← (v/(m-1)) + (1-v)P(other)
  
  Map.new(probs, fn {action, p} ->
    if action == chosen_action do
      {action, (1.0 - v) * p}
    else
      {action, (v / (m - 1)) + (1.0 - v) * p}
    end
  end)
end

def converged?(%SLASelector{} = sla, opts \\ []) do
  threshold = Keyword.get(opts, :threshold, 0.85)
  
  sla.probabilities
  |> Map.values()
  |> Enum.any?(fn p -> p >= threshold end)
end

def state(%SLASelector{} = sla) do
  {best_action, best_prob} = Enum.max_by(sla.probabilities, fn {_k, v} -> v end)
  
  # Entropy-based convergence metric
  entropy = 
    sla.probabilities
    |> Map.values()
    |> Enum.reduce(0.0, fn p, acc -> 
      if p > 0, do: acc - p * :math.log2(p), else: acc
    end)
  
  max_entropy = :math.log2(length(sla.actions))
  convergence = 1.0 - (entropy / max_entropy)  # 0 = uniform, 1 = converged
  
  %{
    probabilities: sla.probabilities,
    iteration: sla.iteration,
    best_action: best_action,
    best_probability: best_prob,
    convergence: convergence,
    entropy: entropy
  }
end
```

**Tests**: `test/thunderline/ml/sla_selector_test.exs`
- Test initialization (uniform probabilities, sum = 1.0)
- Test choose_action (greedy vs sample strategies)
- Test reward update (chosen prob increases, others decrease)
- Test penalty update (chosen prob decreases, others increase)
- Test probability normalization (always sum to 1.0)
- Test convergence detection
- Test state introspection

---

### 3.5 Controller Implementation

**File**: `lib/thunderline/ml/controller.ex`

**Key Flow**:

```elixir
def handle_call({:process_batch, batch, opts}, _from, state) do
  correlation_id = Keyword.get(opts, :correlation_id, UUID.uuid4())
  
  start_time = System.monotonic_time()
  
  :telemetry.execute(
    [:ml, :controller, :update, :start],
    %{},
    %{pac_id: state.pac_id, zone_id: state.zone_id, feature_family: state.feature_family}
  )
  
  # STEP 1: Update Parzen density estimate
  parzen = Parzen.fit(state.parzen, batch)
  parzen_hist = Parzen.histogram(parzen)
  
  # STEP 2: SLA chooses candidate model
  chosen_model_id = SLASelector.choose_action(state.sla)
  
  # STEP 3: Run ONNX inference via chosen model
  model_spec = Enum.find(state.candidate_models, fn m -> m.id == chosen_model_id end)
  
  {:ok, onnx_outputs} = KerasONNX.infer(
    model_spec.session,
    batch,
    correlation_id: correlation_id
  )
  
  # STEP 4: Convert model outputs to histogram (for distance comparison)
  # This depends on model type - for clustering, use cluster probabilities
  # For now, simplified: assume model returns class probabilities
  model_hist = compute_model_histogram(onnx_outputs, parzen.bins)
  
  # STEP 5: Compute distance between Parzen and model
  distance = Distance.kl_divergence(parzen_hist, model_hist)
  
  # STEP 6: Calculate reward
  reward = calculate_reward(distance, state.sla.last_distance)
  
  # STEP 7: Update SLA
  sla = SLASelector.update(state.sla, chosen_model_id, reward: reward, distance: distance)
  
  # STEP 8: Build metadata for response and voxel
  metadata = %{
    chosen_model_id: chosen_model_id,
    probabilities: sla.probabilities,
    distance: distance,
    reward: reward,
    iteration: sla.iteration,
    parzen_bins: parzen.bins,
    convergence: SLASelector.state(sla).convergence,
    correlation_id: correlation_id
  }
  
  # STEP 9: Emit event
  emit_update_event(state, metadata)
  
  # STEP 10: Telemetry
  duration = System.monotonic_time() - start_time
  
  :telemetry.execute(
    [:ml, :controller, :update, :stop],
    %{duration: duration, distance: distance, reward: reward, iteration: sla.iteration},
    %{pac_id: state.pac_id, zone_id: state.zone_id, feature_family: state.feature_family}
  )
  
  # Check if best model changed
  if chosen_model_id != state.last_chosen_model and state.last_chosen_model != nil do
    :telemetry.execute(
      [:ml, :controller, :model_changed],
      %{},
      %{
        pac_id: state.pac_id,
        old_model: state.last_chosen_model,
        new_model: chosen_model_id,
        probabilities: sla.probabilities
      }
    )
  end
  
  # Check if converged
  if SLASelector.converged?(sla) and not SLASelector.converged?(state.sla) do
    :telemetry.execute(
      [:ml, :controller, :converged],
      %{iterations: sla.iteration},
      %{
        pac_id: state.pac_id,
        best_model: SLASelector.state(sla).best_action,
        best_probability: SLASelector.state(sla).best_probability
      }
    )
  end
  
  new_state = %{state |
    parzen: parzen,
    sla: sla,
    last_chosen_model: chosen_model_id,
    iteration: state.iteration + 1
  }
  
  result = %{
    model_outputs: onnx_outputs,
    metadata: metadata
  }
  
  {:reply, {:ok, result}, new_state}
end

defp calculate_reward(current_distance, nil), do: 1  # First iteration, always reward
defp calculate_reward(current_distance, last_distance) do
  if current_distance <= last_distance, do: 1, else: 0
end

defp emit_update_event(state, metadata) do
  Thunderflow.EventBus.publish_event(%{
    name: "system.ml.model_selection.updated",
    payload: %{
      pac_id: state.pac_id,
      zone_id: state.zone_id,
      feature_family: state.feature_family,
      chosen_model_id: metadata.chosen_model_id,
      probabilities: metadata.probabilities,
      distance: metadata.distance,
      reward: metadata.reward,
      iteration: metadata.iteration,
      convergence: metadata.convergence,
      correlation_id: metadata.correlation_id
    },
    correlation_id: metadata.correlation_id,
    timestamp: DateTime.utc_now()
  })
end
```

**Tests**: `test/thunderline/ml/controller_test.exs`
- Test full process_batch flow
- Test model selection changes over iterations
- Test convergence behavior (probabilities should stabilize)
- Test telemetry events emission
- Test event publication
- Test state snapshot

---

### 3.6 Voxel Schema Extension

**File**: Update `lib/thunderline/thundergrid/voxel.ex` (or relevant voxel resource)

**Add field**:

```elixir
attribute :mixture_meta, :map do
  description "Adaptive model selection metadata from SLA + Parzen"
end
```

**Structure**:

```elixir
%{
  mixture_meta: %{
    # Parzen snapshot
    parzen_snapshot: %{
      bins: 20,
      dims: 2,
      total_samples: 1500,
      window_size: 300,
      histogram: [0.05, 0.12, 0.28, ...],  # Serialized as list
      bin_edges: [{-2.5, 2.5, 0.25}]
    },
    
    # Candidate models
    model_candidates: [
      %{id: :model_k1, onnx_path: "priv/models/k1.onnx"},
      %{id: :model_k2, onnx_path: "priv/models/k2.onnx"},
      %{id: :model_k3, onnx_path: "priv/models/k3.onnx"}
    ],
    
    # SLA state
    sla_probabilities: %{
      model_k1: 0.08,
      model_k2: 0.87,  # Converged to k=2
      model_k3: 0.05
    },
    
    # Selection state
    chosen_model_id: :model_k2,
    reward: 1,
    iteration: 47,
    convergence: 0.92,
    
    # Distance tracking
    distances: %{
      current: 0.023,
      previous: 0.031,
      min: 0.019,
      max: 0.156
    },
    
    # Metadata
    feature_family: :text_embedding,
    last_update: ~U[2025-11-13 10:45:23.123Z]
  }
}
```

**Migration**: Generate Ash migration to add `mixture_meta` field.

**Tests**: Update voxel tests to validate mixture_meta structure.

---

### 3.7 Integration Test: 2-Gaussian Mixture

**File**: `test/integration/sla_parzen_gaussian_test.exs`

**Scenario**: Replicate Figure 2/3 from the paper.

```elixir
defmodule Thunderline.Integration.SLAParzenGaussianTest do
  use Thunderline.DataCase, async: false
  
  alias Thunderline.ML.{Parzen, SLASelector, Distance, Controller}
  
  @moduledoc """
  Integration test replicating the 2-Gaussian mixture scenario from:
  "An Improved Adaptive Parzen Window Approach Based on Stochastic Learning Automata"
  
  ## Scenario
  
  1. Generate 300 data points from a 2-Gaussian mixture:
     - 50% from N(μ₁=-2, σ₁=0.5)
     - 50% from N(μ₂=2, σ₂=0.5)
  
  2. Create 3 candidate ONNX models:
     - k=1: Single Gaussian model
     - k=2: 2-Gaussian mixture model
     - k=3: 3-Gaussian mixture model
  
  3. Run 50 SLA update iterations, feeding batches of 20 samples
  
  4. Assert:
     - SLA converges to k=2 model (P(u₂) > 0.85)
     - Distance decreases over iterations
     - Final distance is minimal for k=2
  
  ## Expected Results (from paper Figure 3)
  
  After ~30-40 iterations:
  - P(u₁) ≈ 0.05 (k=1 rejected)
  - P(u₂) ≈ 0.90 (k=2 selected)
  - P(u₃) ≈ 0.05 (k=3 rejected)
  """
  
  @tag :integration
  @tag :ml
  @tag :sla
  test "SLA converges to correct number of Gaussians" do
    # SETUP: Generate 2-Gaussian mixture data
    data = generate_2_gaussian_mixture(n: 300, seed: 42)
    
    # SETUP: Create 3 candidate models (k=1, k=2, k=3)
    # For MVP: use pre-trained ONNX models or mock histograms
    models = [
      %{id: :model_k1, onnx_path: "test/fixtures/models/gaussian_k1.onnx"},
      %{id: :model_k2, onnx_path: "test/fixtures/models/gaussian_k2.onnx"},
      %{id: :model_k3, onnx_path: "test/fixtures/models/gaussian_k3.onnx"}
    ]
    
    # SETUP: Initialize controller
    {:ok, controller} = Controller.start_link(
      pac_id: "test_pac",
      zone_id: "test_zone",
      feature_family: :test_gaussian,
      candidate_models: models,
      parzen_opts: [window_size: 300, bins: 30, dims: 1],
      sla_opts: [alpha: 0.1, v: 0.05]
    )
    
    # RUN: Process batches iteratively
    batch_size = 20
    num_iterations = 15  # 300 samples / 20 per batch
    
    results = 
      for i <- 1..num_iterations do
        # Get batch
        start_idx = (i - 1) * batch_size
        batch = Enum.slice(data, start_idx, batch_size) |> Nx.tensor()
        
        # Process
        {:ok, result} = Controller.process_batch(controller, batch)
        
        %{
          iteration: i,
          chosen_model: result.metadata.chosen_model_id,
          probabilities: result.metadata.probabilities,
          distance: result.metadata.distance,
          reward: result.metadata.reward,
          convergence: result.metadata.convergence
        }
      end
    
    # ASSERT: SLA converged to k=2
    final_result = List.last(results)
    
    assert final_result.probabilities[:model_k2] > 0.85,
      "Expected SLA to converge to k=2 model, got probabilities: #{inspect(final_result.probabilities)}"
    
    # ASSERT: Distance decreased over time
    first_distance = List.first(results).distance
    final_distance = final_result.distance
    
    assert final_distance < first_distance,
      "Expected distance to decrease: first=#{first_distance}, final=#{final_distance}"
    
    # ASSERT: Convergence metric > 0.8
    assert final_result.convergence > 0.8,
      "Expected high convergence, got #{final_result.convergence}"
    
    # LOG: Plot convergence (for visual inspection in test output)
    IO.puts("\n=== SLA Convergence Results ===")
    IO.puts("Iteration | Model | P(k=1) | P(k=2) | P(k=3) | Distance | Reward")
    
    for result <- results do
      IO.puts(
        "#{String.pad_leading(to_string(result.iteration), 9)} | " <>
        "#{String.pad_trailing(to_string(result.chosen_model), 5)} | " <>
        "#{Float.round(result.probabilities[:model_k1], 3)} | " <>
        "#{Float.round(result.probabilities[:model_k2], 3)} | " <>
        "#{Float.round(result.probabilities[:model_k3], 3)} | " <>
        "#{Float.round(result.distance, 4)} | " <>
        "#{result.reward}"
      )
    end
    
    IO.puts("\nFinal convergence: #{Float.round(final_result.convergence, 3)}")
    IO.puts("SLA selected: #{final_result.chosen_model}")
  end
  
  defp generate_2_gaussian_mixture(opts) do
    n = Keyword.get(opts, :n, 300)
    seed = Keyword.get(opts, :seed, :os.system_time())
    
    # Set random seed for reproducibility
    :rand.seed(:exsss, {seed, seed, seed})
    
    # Generate n/2 samples from each Gaussian
    gaussian1 = generate_gaussian(n: div(n, 2), mean: -2.0, std: 0.5)
    gaussian2 = generate_gaussian(n: div(n, 2), mean: 2.0, std: 0.5)
    
    # Shuffle
    (gaussian1 ++ gaussian2)
    |> Enum.shuffle()
  end
  
  defp generate_gaussian(opts) do
    n = Keyword.fetch!(opts, :n)
    mean = Keyword.fetch!(opts, :mean)
    std = Keyword.fetch!(opts, :std)
    
    for _ <- 1..n do
      # Box-Muller transform for Gaussian sampling
      u1 = :rand.uniform()
      u2 = :rand.uniform()
      
      z = :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
      mean + std * z
    end
  end
end
```

**Note**: This test requires creating 3 simple ONNX models (k=1, k=2, k=3 Gaussian mixtures). Can be generated using the existing `generate_demo_model.py` pattern.

---

### 3.8 Documentation

**File**: `docs/SLA_PARZEN_ARCHITECTURE.md`

Create comprehensive design doc covering:

1. **Theory Overview**
   - Parzen windows (non-parametric density)
   - Learning Automata (reinforcement learning)
   - Distance metrics (KL, cross-entropy, etc.)

2. **Architecture**
   - Module responsibilities
   - Data flow diagrams
   - Event flow

3. **API Reference**
   - All public functions with examples
   - Typespecs
   - Configuration options

4. **Integration Guide**
   - How to create candidate models
   - How to start a Controller
   - How to process batches
   - How to read voxel metadata

5. **Telemetry**
   - All events emitted
   - Metrics to track
   - Grafana dashboard config

6. **Mathematical Details**
   - SLA update equations
   - Distance formulas
   - Convergence proofs (references to paper)

7. **Examples**
   - 2-Gaussian test case walkthrough
   - Real-world use case (text embeddings)

---

## Integration with Existing Pipeline

### Event Flow

```
system.ingest.classified (Magika)
          ↓
system.ml.features.extracted (spaCy)
          ↓
[NEW] Controller.process_batch
          ↓
system.ml.model_selection.updated (SLA choice)
          ↓
system.voxel.created (with mixture_meta)
          ↓
Thundergrid DAG
```

### Broadway Consumer

Create new consumer: `lib/thunderline/thunderflow/ml_controller_consumer.ex`

```elixir
defmodule Thunderline.Thunderflow.MLControllerConsumer do
  use Broadway
  
  # Subscribe to system.ml.features.extracted
  # Process batches through Controller
  # Emit system.ml.model_selection.updated
end
```

---

## Telemetry Events

### New Events

1. `[:ml, :controller, :update, :start]`
   - Measurements: `%{}`
   - Metadata: `%{pac_id, zone_id, feature_family}`

2. `[:ml, :controller, :update, :stop]`
   - Measurements: `%{duration, distance, reward, iteration}`
   - Metadata: `%{pac_id, zone_id, feature_family}`

3. `[:ml, :controller, :model_changed]`
   - Measurements: `%{}`
   - Metadata: `%{pac_id, old_model, new_model, probabilities}`

4. `[:ml, :controller, :converged]`
   - Measurements: `%{iterations}`
   - Metadata: `%{pac_id, best_model, best_probability}`

5. `[:ml, :parzen, :fit, :start]`
6. `[:ml, :parzen, :fit, :stop]` - measurements: `%{duration, samples}`
7. `[:ml, :distance, :compute, :start]`
8. `[:ml, :distance, :compute, :stop]` - measurements: `%{duration, metric, value}`

---

## Configuration

Add to `config/config.exs`:

```elixir
config :thunderline, Thunderline.ML.Controller,
  default_parzen_opts: [
    window_size: 300,
    bins: 20,
    dims: 2
  ],
  default_sla_opts: [
    alpha: 0.1,  # Reward learning rate
    v: 0.05      # Penalty learning rate
  ],
  default_distance_metric: :kl,  # :kl | :cross_entropy | :hellinger | :js
  enable_telemetry: true

config :thunderline, Thunderline.ML.ControllerRegistry,
  max_controllers: 1000,  # Max concurrent controller processes
  idle_shutdown: :timer.hours(1)  # Shutdown idle controllers after 1 hour
```

---

## Acceptance Criteria

Phase 3 is complete when:

- ✅ All 4 modules created with full typespecs and docs
- ✅ Parzen MVP implements histogram-based density estimation
- ✅ SLA implements paper's reward/penalty update rules
- ✅ Distance module provides KL + 3 other metrics
- ✅ Controller orchestrates full SLA loop
- ✅ Voxel schema extended with `mixture_meta`
- ✅ Integration test passes (2-Gaussian convergence to k=2)
- ✅ All telemetry events emitting correctly
- ✅ Documentation complete (SLA_PARZEN_ARCHITECTURE.md)
- ✅ Event `system.ml.model_selection.updated` published on every update
- ✅ No compilation warnings
- ✅ Test coverage > 85% for new modules

---

## Timeline

**Day 1**: Module skeletons + Parzen MVP + Distance metrics
**Day 2**: SLA core implementation + tests
**Day 3**: Controller implementation + integration test
**Day 4**: Voxel extension + documentation + polish

---

## Next Phase After 3

**Phase 2.3: Nx.Serving Supervision** (NOW makes sense)

Once SLA + Parzen is working, wrap the Controller in Nx.Serving:

```elixir
serving = Nx.Serving.new(fn batch ->
  # Controller.process_batch returns {outputs, metadata}
  # Nx.Serving handles batching, queuing, supervision
end)
```

This gives us:
- Automatic batching
- Queue management
- Health probes
- Resource monitoring
- Graceful degradation

But ONLY after the intelligence layer (Phase 3) is built.

---

## Questions for Implementation

1. **Model Histogram Conversion**: How do we convert ONNX model outputs (e.g., cluster probabilities) into a histogram comparable to Parzen? 
   - **Answer**: For clustering models, use cluster assignment probabilities as histogram bins. For density models, discretize into same bins as Parzen.

2. **Candidate Model Storage**: Where do we store the 3 ONNX models for the 2-Gaussian test?
   - **Answer**: `test/fixtures/models/gaussian_k{1,2,3}.onnx`, generated by extending `generate_demo_model.py`.

3. **Controller Registry**: Do we need a registry for multiple Controllers (one per PAC/zone/feature_family)?
   - **Answer**: Yes, create `Thunderline.ML.ControllerRegistry` using `DynamicSupervisor` + `Registry`.

4. **Parzen Window Persistence**: Should we persist the full sliding window to disk, or just the histogram?
   - **Answer**: MVP: just histogram + summary stats. Full window can be added later for reproducibility.

---

## References

- Paper: "An Improved Adaptive Parzen Window Approach Based on Stochastic Learning Automata" (2007)
- Learning Automata theory: Narendra & Thathachar (1989)
- Parzen Windows: Parzen (1962)
- KL Divergence: Kullback & Leibler (1951)

---

**Ready to ship.** This is the architecture that makes Thunderline **alive**.
