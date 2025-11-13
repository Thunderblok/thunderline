defmodule Thunderline.ML.Controller do
  @moduledoc """
  Orchestrator GenServer for SLA + Parzen adaptive model selection.

  The Controller implements the 10-step adaptive selection loop that integrates
  Parzen density estimation, ONNX model execution, distance measurement, and
  SLA-based learning.

  ## Architecture

  **One Controller per (PAC, zone, feature_family) tuple**.

  Controllers are spawned by `Thunderline.ML.ControllerSupervisor` and registered
  in a `Registry` for lookup.

  ## 10-Step Process Flow

  When `process_batch/3` is called:

  1. **Update Parzen**: Fit density estimator with new batch
  2. **Choose Model**: SLA selects candidate based on P(u_j)
  3. **Run ONNX**: Execute inference via `Thunderline.ML.KerasONNX`
  4. **Model → Histogram**: Convert ONNX outputs to density
  5. **Compute Distance**: Measure Parzen vs model (KL/Hellinger/etc)
  6. **Calculate Reward**: 1 if distance improved, 0 otherwise
  7. **Update SLA**: Adjust probabilities using reward/penalty
  8. **Build Metadata**: Prepare voxel embedding data
  9. **Emit Event**: Publish `system.ml.model_selection.updated`
  10. **Return**: Forward ONNX outputs + metadata downstream

  ## State Management

  Controller state includes:

  - `parzen`: Parzen density estimator
  - `sla`: SLA selector
  - `candidate_models`: List of ONNX model specs
  - `distance_metric`: Which metric to use (:kl, :hellinger, etc)
  - `last_chosen_model`: Previous model ID
  - `iteration`: Batch counter

  ## Telemetry

  Emits the following events:

  - `[:ml, :controller, :update, :start]` - Batch processing started
  - `[:ml, :controller, :update, :stop]` - Measurements: duration, distance, reward
  - `[:ml, :controller, :model_changed]` - Best model switched
  - `[:ml, :controller, :converged]` - SLA probabilities stabilized

  ## Usage

  ```elixir
  # Start controller for a specific (PAC, zone, feature_family)
  {:ok, pid} = Controller.start_link(
    pac_id: "pac_001",
    zone_id: "zone_alpha",
    feature_family: :network_traffic,
    candidate_models: [
      %{id: :model_k1, onnx_path: "path/to/k1.onnx"},
      %{id: :model_k2, onnx_path: "path/to/k2.onnx"},
      %{id: :model_k3, onnx_path: "path/to/k3.onnx"}
    ],
    parzen_opts: [window_size: 300, bins: 20, dims: 2],
    sla_opts: [alpha: 0.1, v: 0.05],
    distance_metric: :kl
  )

  # Process batch
  batch = Nx.tensor([[1.0, 2.0], [3.0, 4.0], ...])
  {:ok, result} = Controller.process_batch(pid, batch, %{request_id: "req_123"})

  # Result contains:
  # %{
  #   outputs: #Nx.Tensor<...>,          # ONNX model outputs
  #   metadata: %{
  #     chosen_model: :model_k2,
  #     distance: 0.023,
  #     reward: 1,
  #     sla_probabilities: %{...},
  #     iteration: 47
  #   }
  # }

  # Get current state snapshot
  state = Controller.get_state(pid)
  ```

  ## Integration with Broadway

  Controllers are invoked by `Thunderline.ML.ControllerConsumer` (Broadway consumer)
  which routes batches based on (PAC, zone, feature_family) extracted from events.

  ## Voxel Embedding

  Metadata from Controller.process_batch/3 is embedded into
  `Thunderline.Thunderblock.Voxel.mixture_meta` field, creating a persistent
  record of the learning state at each iteration.

  ## References

  - Li et al. (2007). "An Improved Adaptive Parzen Window Approach Based on SLA"
  - See also: `Thunderline.ML.Parzen`, `Thunderline.ML.SLASelector`, `Thunderline.ML.Distance`
  """

  use GenServer
  require Logger

  alias Thunderline.ML.{Parzen, SLASelector, Distance, KerasONNX}

  @typedoc """
  Controller state.

  Fields:
  - `pac_id`: PAC identifier
  - `zone_id`: Zone identifier
  - `feature_family`: Feature family atom
  - `parzen`: Parzen density estimator
  - `sla`: SLA selector
  - `candidate_models`: List of model specs %{id: atom(), onnx_path: String.t()}
  - `distance_metric`: Distance metric to use
  - `last_chosen_model`: Previously selected model
  - `iteration`: Batch counter
  - `telemetry_enabled?`: Whether to emit telemetry
  """
  @type state :: %{
          pac_id: String.t(),
          zone_id: String.t(),
          feature_family: atom(),
          parzen: Parzen.t(),
          sla: SLASelector.t(),
          candidate_models: [%{id: atom(), onnx_path: String.t()}],
          distance_metric: Distance.metric(),
          last_chosen_model: atom() | nil,
          iteration: non_neg_integer(),
          telemetry_enabled?: boolean()
        }

  ## Public API

  @doc """
  Start a Controller GenServer.

  ## Options

  - `:pac_id` - PAC identifier (required)
  - `:zone_id` - Zone identifier (required)
  - `:feature_family` - Feature family atom (required)
  - `:candidate_models` - List of model specs (required)
  - `:parzen_opts` - Options for Parzen.init/1 (default: [])
  - `:sla_opts` - Options for SLASelector.init/2 (default: [])
  - `:distance_metric` - Distance metric (:kl, :hellinger, etc) (default: :kl)
  - `:telemetry_enabled?` - Emit telemetry events? (default: true)
  - `:name` - Process name (default: via Registry)

  ## Returns

  `{:ok, pid}` or `{:error, reason}`.

  ## Examples

      {:ok, pid} = Controller.start_link(
        pac_id: "pac_001",
        zone_id: "zone_alpha",
        feature_family: :network_traffic,
        candidate_models: [
          %{id: :model_k1, onnx_path: "path/to/k1.onnx"},
          %{id: :model_k2, onnx_path: "path/to/k2.onnx"}
        ]
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    raise "Not implemented - Phase 3.5"
  end

  @doc """
  Process a batch of data through the 10-step adaptive selection loop.

  ## Algorithm

  1. Update Parzen with new batch
  2. SLA chooses candidate model
  3. Run ONNX inference via chosen model
  4. Convert model outputs to histogram
  5. Compute distance (Parzen vs model)
  6. Calculate reward (distance improved?)
  7. Update SLA probabilities
  8. Build metadata for voxel
  9. Emit telemetry event
  10. Return model outputs + metadata

  ## Arguments

  - `controller` - Controller PID or registered name
  - `batch` - Nx tensor of shape {batch_size, features}
  - `context` - Request context map (optional)

  ## Returns

  `{:ok, result}` where result is:

      %{
        outputs: Nx.Tensor.t(),
        metadata: %{
          chosen_model: atom(),
          distance: float(),
          reward: 0 | 1,
          sla_probabilities: %{atom() => float()},
          parzen_snapshot: map(),
          iteration: integer(),
          convergence: float() | nil
        }
      }

  Or `{:error, reason}`.

  ## Examples

      batch = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])
      {:ok, result} = Controller.process_batch(pid, batch, %{request_id: "req_123"})

      # Access results
      outputs = result.outputs
      chosen_model = result.metadata.chosen_model
      distance = result.metadata.distance
  """
  @spec process_batch(GenServer.server(), Nx.Tensor.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def process_batch(controller, batch, context \\ %{})
      when is_struct(batch, Nx.Tensor) do
    raise "Not implemented - Phase 3.5"
  end

  @doc """
  Get current Controller state snapshot.

  ## Arguments

  - `controller` - Controller PID or registered name

  ## Returns

  Map with:
  - `:pac_id`, `:zone_id`, `:feature_family` - Identifiers
  - `:iteration` - Current iteration
  - `:last_chosen_model` - Most recent model
  - `:sla_state` - SLA probabilities and stats
  - `:parzen_state` - Parzen histogram summary
  - `:candidate_models` - List of available models

  ## Examples

      state = Controller.get_state(pid)
      # => %{
      #   pac_id: "pac_001",
      #   zone_id: "zone_alpha",
      #   feature_family: :network_traffic,
      #   iteration: 47,
      #   last_chosen_model: :model_k2,
      #   sla_state: %{...},
      #   parzen_state: %{...},
      #   candidate_models: [...]
      # }
  """
  @spec get_state(GenServer.server()) :: map()
  def get_state(controller) do
    raise "Not implemented - Phase 3.5"
  end

  @doc """
  Create a full state snapshot for persistence.

  Includes complete Parzen and SLA snapshots suitable for embedding in voxel
  or checkpointing to disk.

  ## Arguments

  - `controller` - Controller PID or registered name

  ## Returns

  Map with full serializable state.

  ## Examples

      snapshot = Controller.snapshot(pid)
      # Can be embedded in Voxel.mixture_meta field
  """
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(controller) do
    raise "Not implemented - Phase 3.5"
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    raise "Not implemented - Phase 3.5"
  end

  @impl true
  def handle_call({:process_batch, batch, context}, _from, state) do
    raise "Not implemented - Phase 3.5"
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    raise "Not implemented - Phase 3.5"
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    raise "Not implemented - Phase 3.5"
  end

  ## Private Helpers

  # These will be implemented in Phase 3.5

  defp do_process_batch(batch, state) do
    raise "Not implemented - Phase 3.5"
  end

  defp update_parzen(state, batch) do
    raise "Not implemented - Phase 3.5"
  end

  defp choose_model(state) do
    raise "Not implemented - Phase 3.5"
  end

  defp run_inference(state, model_id, batch) do
    raise "Not implemented - Phase 3.5"
  end

  defp outputs_to_histogram(outputs, bins) do
    raise "Not implemented - Phase 3.5"
  end

  defp compute_distance(state, parzen_hist, model_hist) do
    raise "Not implemented - Phase 3.5"
  end

  defp calculate_reward(state, current_distance) do
    raise "Not implemented - Phase 3.5"
  end

  defp update_sla(state, model_id, reward, distance) do
    raise "Not implemented - Phase 3.5"
  end

  defp build_metadata(state, model_id, distance, reward) do
    raise "Not implemented - Phase 3.5"
  end

  defp emit_telemetry(state, metadata, duration) do
    raise "Not implemented - Phase 3.5"
  end

  defp emit_model_changed_event(state, old_model, new_model) do
    raise "Not implemented - Phase 3.5"
  end

  defp emit_convergence_event(state) do
    raise "Not implemented - Phase 3.5"
  end
end
