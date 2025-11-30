defmodule Thunderline.Thunderbolt.Cerebros.PACCompute do
  @moduledoc """
  PAC Compute Event Protocol for Cerebros-DiffLogic Integration (HC-39).

  Defines the event schemas and handlers for PAC (Probably Approximately Correct)
  compute requests that connect the DiffLogic CA to TPE (Tree Parzen Estimator)
  hyperparameter optimization.

  ## Event Flow

      PAC → PACComputeRequest → TPE (Python)
                                    ↓
      CA ← PACComputeResponse ←────┘
                ↓
      Grid ← CAVoxelUpdate events

  ## Event Types

  - `bolt.pac.compute.request` - Request CA evaluation with parameters
  - `bolt.pac.compute.response` - TPE-suggested parameters or fitness results
  - `bolt.pac.ca.voxel_update` - Individual voxel state changes
  - `bolt.pac.metrics.snapshot` - Criticality metrics from LoopMonitor

  ## Usage

      # Request CA evaluation
      {:ok, event} = PACCompute.request(%{
        rule_params: %{lambda: 0.7, bias: 0.3},
        grid_config: %{bounds: {32, 32, 8}},
        budget: %{max_ticks: 1000}
      })

      # Publish to EventBus
      EventBus.publish_event(event)
  """

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  require Logger

  @source :bolt

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type rule_params :: %{
          optional(:lambda) => float(),
          optional(:bias) => float(),
          optional(:gate_logits) => [float()],
          optional(:rule_id) => atom()
        }

  @type grid_config :: %{
          optional(:bounds) => {pos_integer(), pos_integer(), pos_integer()},
          optional(:sparse) => boolean(),
          optional(:seed_coords) => [{pos_integer(), pos_integer(), pos_integer()}],
          optional(:neighborhood_type) => :von_neumann | :moore | :extended
        }

  @type budget :: %{
          optional(:max_ticks) => pos_integer(),
          optional(:timeout_ms) => pos_integer(),
          optional(:target_metric) => atom()
        }

  @type compute_request :: %{
          required(:rule_params) => rule_params(),
          required(:grid_config) => grid_config(),
          required(:budget) => budget(),
          optional(:run_id) => String.t(),
          optional(:trial_id) => non_neg_integer(),
          optional(:correlation_id) => String.t()
        }

  @type criticality_metrics :: %{
          optional(:plv) => float(),
          optional(:entropy) => float(),
          optional(:lambda_hat) => float(),
          optional(:lyapunov) => float(),
          optional(:edge_of_chaos_score) => float()
        }

  @type compute_response :: %{
          required(:run_id) => String.t(),
          required(:trial_id) => non_neg_integer(),
          required(:status) => :ok | :timeout | :error,
          required(:fitness) => float(),
          required(:metrics) => criticality_metrics(),
          optional(:suggested_params) => rule_params() | nil,
          required(:elapsed_ms) => non_neg_integer()
        }

  @type voxel_update :: %{
          required(:coord) => {pos_integer(), pos_integer(), pos_integer()},
          optional(:state) => atom(),
          optional(:sigma_flow) => float(),
          optional(:phi_phase) => float(),
          optional(:lambda_sensitivity) => float(),
          optional(:tick) => non_neg_integer()
        }

  # ═══════════════════════════════════════════════════════════════
  # Request Events
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a PAC compute request event.

  ## Parameters

  - `rule_params` - DiffLogic gate parameters or rule configuration
  - `grid_config` - CA grid dimensions and topology
  - `budget` - Compute budget (ticks, timeout)

  ## Options

  - `:run_id` - Unique run identifier (auto-generated if not provided)
  - `:trial_id` - Trial number within a TPE optimization run
  - `:correlation_id` - For request-response correlation

  ## Examples

      {:ok, event} = PACCompute.request(%{
        rule_params: %{lambda: 0.7, bias: 0.3},
        grid_config: %{bounds: {32, 32, 8}},
        budget: %{max_ticks: 500}
      })
  """
  @spec request(compute_request()) :: {:ok, Event.t()} | {:error, term()}
  def request(params) when is_map(params) do
    run_id = Map.get(params, :run_id) || generate_run_id()
    trial_id = Map.get(params, :trial_id, 0)
    correlation_id = Map.get(params, :correlation_id) || run_id

    payload = %{
      run_id: run_id,
      trial_id: trial_id,
      rule_params: Map.get(params, :rule_params, %{}),
      grid_config: Map.get(params, :grid_config, %{bounds: {16, 16, 4}}),
      budget: Map.get(params, :budget, %{max_ticks: 100}),
      requested_at: System.system_time(:millisecond)
    }

    Event.new(
      name: "bolt.pac.compute.request",
      source: @source,
      payload: payload,
      meta: %{
        pipeline: :cerebros,
        correlation_id: correlation_id
      }
    )
  end

  @doc """
  Publishes a PAC compute request to the EventBus.

  Returns `{:ok, run_id}` on success.
  """
  @spec publish_request(compute_request()) :: {:ok, String.t()} | {:error, term()}
  def publish_request(params) do
    with {:ok, event} <- request(params),
         {:ok, _published} <- EventBus.publish_event(event) do
      {:ok, event.payload.run_id}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Response Events
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a PAC compute response event with evaluation results.

  ## Parameters

  - `run_id` - The run ID this response corresponds to
  - `trial_id` - Trial number
  - `status` - `:ok`, `:timeout`, or `:error`
  - `fitness` - Computed fitness value (higher = better)
  - `metrics` - Criticality metrics from LoopMonitor

  ## Options

  - `:suggested_params` - TPE-suggested parameters for next trial
  - `:elapsed_ms` - Computation time
  """
  @spec response(map()) :: {:ok, Event.t()} | {:error, term()}
  def response(params) when is_map(params) do
    run_id = Map.fetch!(params, :run_id)
    trial_id = Map.get(params, :trial_id, 0)
    correlation_id = Map.get(params, :correlation_id) || run_id

    payload = %{
      run_id: run_id,
      trial_id: trial_id,
      status: Map.get(params, :status, :ok),
      fitness: Map.get(params, :fitness, 0.0),
      metrics: Map.get(params, :metrics, %{}),
      suggested_params: Map.get(params, :suggested_params),
      elapsed_ms: Map.get(params, :elapsed_ms, 0),
      responded_at: System.system_time(:millisecond)
    }

    Event.new(
      name: "bolt.pac.compute.response",
      source: @source,
      payload: payload,
      meta: %{
        pipeline: :cerebros,
        correlation_id: correlation_id
      }
    )
  end

  @doc """
  Publishes a PAC compute response to the EventBus.
  """
  @spec publish_response(map()) :: {:ok, Event.t()} | {:error, term()}
  def publish_response(params) do
    with {:ok, event} <- response(params),
         {:ok, published} <- EventBus.publish_event(event) do
      {:ok, published}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Voxel Update Events
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a CA voxel update event for a single cell state change.

  Used for real-time visualization and metrics collection.
  """
  @spec voxel_update(String.t(), voxel_update()) :: {:ok, Event.t()} | {:error, term()}
  def voxel_update(run_id, update) when is_map(update) do
    payload = %{
      run_id: run_id,
      coord: Map.fetch!(update, :coord),
      state: Map.get(update, :state, :unknown),
      sigma_flow: Map.get(update, :sigma_flow, 0.0),
      phi_phase: Map.get(update, :phi_phase, 0.0),
      lambda_sensitivity: Map.get(update, :lambda_sensitivity, 0.0),
      tick: Map.get(update, :tick, 0)
    }

    Event.new(
      name: "bolt.pac.ca.voxel_update",
      source: @source,
      payload: payload,
      meta: %{pipeline: :realtime}
    )
  end

  @doc """
  Creates a batch of voxel update events (for efficiency).
  """
  @spec voxel_batch(String.t(), [voxel_update()], non_neg_integer()) ::
          {:ok, Event.t()} | {:error, term()}
  def voxel_batch(run_id, updates, tick) when is_list(updates) do
    payload = %{
      run_id: run_id,
      tick: tick,
      count: length(updates),
      updates:
        Enum.map(updates, fn u ->
          %{
            coord: Map.fetch!(u, :coord),
            state: Map.get(u, :state),
            sigma_flow: Map.get(u, :sigma_flow),
            phi_phase: Map.get(u, :phi_phase),
            lambda_sensitivity: Map.get(u, :lambda_sensitivity)
          }
        end)
    }

    Event.new(
      name: "bolt.pac.ca.voxel_batch",
      source: @source,
      payload: payload,
      meta: %{pipeline: :realtime}
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # Metrics Snapshot Events
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a criticality metrics snapshot event.

  Emitted periodically by LoopMonitor to track CA dynamics.
  """
  @spec metrics_snapshot(String.t(), non_neg_integer(), criticality_metrics()) ::
          {:ok, Event.t()} | {:error, term()}
  def metrics_snapshot(run_id, tick, metrics) when is_map(metrics) do
    payload = %{
      run_id: run_id,
      tick: tick,
      plv: Map.get(metrics, :plv, 0.0),
      entropy: Map.get(metrics, :entropy, 0.0),
      lambda_hat: Map.get(metrics, :lambda_hat, 0.0),
      lyapunov: Map.get(metrics, :lyapunov, 0.0),
      edge_of_chaos_score: compute_edge_score(metrics),
      sampled_at: System.system_time(:millisecond)
    }

    Event.new(
      name: "bolt.pac.metrics.snapshot",
      source: @source,
      payload: payload,
      meta: %{pipeline: :metrics}
    )
  end

  @doc """
  Publishes a metrics snapshot to the EventBus.
  """
  @spec publish_metrics(String.t(), non_neg_integer(), criticality_metrics()) ::
          {:ok, Event.t()} | {:error, term()}
  def publish_metrics(run_id, tick, metrics) do
    with {:ok, event} <- metrics_snapshot(run_id, tick, metrics),
         {:ok, published} <- EventBus.publish_event(event) do
      {:ok, published}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp generate_run_id do
    "pac_#{:os.system_time(:second)}_#{:rand.uniform(9999)}"
  end

  @doc """
  Computes edge-of-chaos score from criticality metrics.

  The score is maximized when the CA is at the phase transition
  between order (low entropy, high PLV) and chaos (high entropy, low PLV).

  Target zone: λ̂ ≈ 0.273 (Langton's critical parameter for 2-state CAs)
  """
  @spec compute_edge_score(criticality_metrics()) :: float()
  def compute_edge_score(metrics) do
    # Get metrics with defaults
    plv = Map.get(metrics, :plv, 0.5)
    entropy = Map.get(metrics, :entropy, 0.5)
    lambda_hat = Map.get(metrics, :lambda_hat, 0.5)
    lyapunov = Map.get(metrics, :lyapunov, 0.0)

    # Target: λ̂ ≈ 0.273 (critical parameter)
    lambda_target = 0.273
    lambda_distance = abs(lambda_hat - lambda_target)
    lambda_score = 1.0 - min(1.0, lambda_distance / 0.3)

    # Optimal entropy is intermediate (neither too ordered nor too chaotic)
    # Peak at entropy ≈ 0.5
    entropy_score = 1.0 - 2.0 * abs(entropy - 0.5)

    # PLV should be moderate (some synchronization but not rigid)
    # Peak at PLV ≈ 0.4
    plv_score = 1.0 - 2.0 * abs(plv - 0.4)

    # Lyapunov near 0 indicates edge of chaos
    # Positive = chaotic, Negative = ordered
    lyapunov_score = 1.0 - min(1.0, abs(lyapunov))

    # Weighted combination
    lambda_score * 0.35 + entropy_score * 0.25 + plv_score * 0.25 + lyapunov_score * 0.15
  end
end
