defmodule Thunderline.Thunderbolt.ML.Controller do
  @moduledoc """
  Phase 3.5: Pure ML Control Loop Orchestration.

  Integrates Parzen + Distance + SLASelector into a single adaptive model selection
  controller. This is the **brainstem** of the ML system - where distributions meet
  decisions, where learning becomes action.

  ## Purpose

  Accept batches of model outputs + targets → Update Parzen density estimates →
  Compute distance metrics → Feed rewards/penalties to SLA → Select next best model.

  ## State Structure

  ```elixir
  %__MODULE__{
    models: [:model_a, :model_b, :model_c],
    parzen: %{model_a => ParzenState, model_b => ParzenState, ...},
    sla: SLASelectorState,
    distance_metric: :js | :kl | :hellinger | :cross_entropy,
    window_size: 300,
    last_reward: float() | nil,
    iteration: non_neg_integer(),
    meta: %{} # free-form metadata for later integration
  }
  ```

  ## Batch Format

  ```elixir
  %{
    model_outputs: %{
      model_a => Nx.tensor([0.7, 0.3]),  # probability distributions
      model_b => Nx.tensor([0.4, 0.6]),
      model_c => Nx.tensor([0.5, 0.5])
    },
    target_dist: Nx.tensor([0.8, 0.2]),  # expected distribution
    context: %{correlation_id: "req_123", zone: "alpha"}  # optional
  }
  ```

  ## Process Flow (handle_call :process_batch)

  1. **Validate Input** - Check all models present, compatible shapes
  2. **Update Parzen** - Fit each model's density estimator with its output
  3. **Compute Distances** - Compare each model's Parzen histogram to target
  4. **Derive Reward** - Best model (lowest distance) gets reward, others penalty
  5. **Update SLA** - Adjust probabilities based on feedback
  6. **Choose Next** - SLA selects model for next iteration
  7. **Emit Telemetry** - Duration, distances, probabilities, convergence
  8. **Return Response** - chosen_model, probabilities, distances, iteration

  ## Telemetry Events

  - `[:thunderline, :ml, :controller, :process_batch, :start]`
  - `[:thunderline, :ml, :controller, :process_batch, :stop]`
  - `[:thunderline, :ml, :controller, :process_batch, :error]`

  Measurements: :batch_size, :num_models, :duration_ms, :avg_distance

  ## Phase 3.5 Scope

  **IN SCOPE:**
  - Pure ML orchestration loop
  - GenServer with state management
  - Snapshot/restore for persistence
  - Comprehensive tests proving convergence

  **OUT OF SCOPE:**
  - Broadway/EventBus integration
  - ONNX runtime execution
  - Voxel/DAG persistence
  - Magika/Thundergate wiring

  Those come in Phase 3.6+.

  ## References

  - Li et al. (2007) "An Improved Adaptive Parzen Window Approach Based on SLA"
  - Phase 3 spec: documentation/thunderline/phase_3_*.md
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.ML.{Parzen, SLASelector, Distance}

  defstruct [
    :models,
    :parzen,
    :sla,
    :distance_metric,
    :window_size,
    :last_reward,
    :iteration,
    :meta
  ]

  @type t :: %__MODULE__{
          models: [atom()],
          parzen: %{atom() => Parzen.t()},
          sla: SLASelector.t(),
          distance_metric: Distance.metric(),
          window_size: pos_integer(),
          last_reward: float() | nil,
          iteration: non_neg_integer(),
          meta: map()
        }

  ## Public API

  @doc """
  Start a Controller GenServer.

  ## Options (Phase 3.5 simplified)

  - `:models` - List of model identifiers (required, non-empty)
  - `:distance_metric` - Distance metric (:js, :kl, :hellinger, :cross_entropy) (default: :js)
  - `:window_size` - Parzen window size (default: 300)
  - `:alpha` - SLA learning rate (default: 0.1)
  - `:v` - SLA penalty rate (default: 0.05)
  - `:name` - Process registration name (optional)

  ## Returns

  `{:ok, pid}` or `{:error, reason}`.

  ## Examples

      {:ok, pid} = Controller.start_link(
        models: [:model_a, :model_b, :model_c],
        distance_metric: :js,
        window_size: 300
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Process a batch through the adaptive selection loop.

  ## Batch Format

  ```elixir
  %{
    model_outputs: %{
      model_a => Nx.tensor([0.7, 0.3]),
      model_b => Nx.tensor([0.4, 0.6])
    },
    target_dist: Nx.tensor([0.8, 0.2]),
    context: %{correlation_id: "req_123"}  # optional
  }
  ```

  ## Returns

  ```elixir
  {:ok, %{
    chosen_model: :model_a,
    probabilities: %{model_a: 0.6, model_b: 0.4},
    distances: %{model_a: 0.023, model_b: 0.156},
    iteration: 47,
    reward_model: :model_a
  }}
  ```

  Or `{:error, reason}` if validation fails.

  ## Examples

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.8, 0.2])
        },
        target_dist: Nx.tensor([0.75, 0.25])
      }

      {:ok, result} = Controller.process_batch(pid, batch)
  """
  @spec process_batch(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def process_batch(controller, batch) when is_map(batch) do
    GenServer.call(controller, {:process_batch, batch})
  end

  @doc """
  Get current controller state (for inspection/debugging).

  Returns the full state struct.

  ## Examples

      state = Controller.state(pid)
      # => %Thunderline.Thunderbolt.ML.Controller{
      #   models: [:model_a, :model_b],
      #   iteration: 47,
      #   ...
      # }
  """
  @spec state(GenServer.server()) :: t()
  def state(controller) do
    GenServer.call(controller, :state)
  end

  @doc """
  Create a serializable snapshot for persistence.

  ## Returns

  Map with:
  - `:models` - List of model IDs
  - `:parzen` - Map of {model_id => Parzen.snapshot()}
  - `:sla` - SLASelector.snapshot()
  - `:distance_metric`, `:window_size`, `:iteration`, `:last_reward`, `:meta`

  ## Examples

      snap = Controller.snapshot(pid)
      # Later: restore via from_snapshot/1
  """
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(controller) do
    GenServer.call(controller, :snapshot)
  end

  @doc """
  Restore controller state from a snapshot.

  Does NOT create a process - just reconstructs the state struct.
  Use with `start_link/1` or for testing.

  ## Examples

      snap = Controller.snapshot(pid)
      restored_state = Controller.from_snapshot(snap)
      # Can pass to GenServer.init or manual testing
  """
  @spec from_snapshot(map()) :: t()
  def from_snapshot(snapshot) do
    %__MODULE__{
      models: snapshot.models,
      parzen:
        Enum.into(snapshot.parzen, %{}, fn {model_id, parzen_snap} ->
          {model_id, Parzen.from_snapshot(parzen_snap)}
        end),
      sla: SLASelector.from_snapshot(snapshot.sla),
      distance_metric: snapshot.distance_metric,
      window_size: snapshot.window_size,
      last_reward: snapshot[:last_reward],
      iteration: snapshot.iteration,
      meta: snapshot[:meta] || %{}
    }
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Validate and extract options
    models = Keyword.fetch!(opts, :models)

    unless is_list(models) and models != [] do
      raise ArgumentError, "models must be a non-empty list, got: #{inspect(models)}"
    end

    window_size = Keyword.get(opts, :window_size, 300)
    distance_metric = Keyword.get(opts, :distance_metric, :js)
    alpha = Keyword.get(opts, :alpha, 0.1)
    v = Keyword.get(opts, :v, 0.05)

    # Initialize Parzen map (one per model)
    parzen =
      Enum.into(models, %{}, fn model_id ->
        {model_id,
         Parzen.init(
           pac_id: "controller_#{model_id}",
           feature_family: :probability_distribution,
           window_size: window_size
         )}
      end)

    # Initialize SLA (single for all models)
    sla = SLASelector.init(models, alpha: alpha, v: v)

    state = %__MODULE__{
      models: models,
      parzen: parzen,
      sla: sla,
      distance_metric: distance_metric,
      window_size: window_size,
      last_reward: nil,
      iteration: 0,
      meta: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_batch, batch}, _from, state) do
    start_time = System.monotonic_time()

    # Emit start telemetry
    emit_telemetry(:start, %{num_models: length(state.models)}, %{})

    case do_process_batch(batch, state) do
      {:ok, response, new_state} ->
        # Emit success telemetry
        duration = System.monotonic_time() - start_time

        emit_telemetry(
          :stop,
          %{
            duration_ns: duration,
            num_models: length(state.models),
            iteration: new_state.iteration
          },
          %{
            chosen_model: response.chosen_model,
            reward_model: response.reward_model,
            distances: response.distances
          }
        )

        {:reply, {:ok, response}, new_state}

      {:error, reason} = error ->
        # Emit error telemetry
        emit_telemetry(:error, %{}, %{reason: reason})
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      models: state.models,
      parzen:
        Enum.into(state.parzen, %{}, fn {model_id, parzen_state} ->
          {model_id, Parzen.snapshot(parzen_state)}
        end),
      sla: SLASelector.snapshot(state.sla),
      distance_metric: state.distance_metric,
      window_size: state.window_size,
      last_reward: state.last_reward,
      iteration: state.iteration,
      meta: state.meta
    }

    {:reply, snapshot, state}
  end

  ## Private Helpers

  # Core 8-step orchestration logic
  defp do_process_batch(batch, state) do
    with :ok <- validate_batch(batch, state),
         {:ok, new_parzen} <- update_all_parzen(batch, state),
         {:ok, distances} <- compute_all_distances(batch, new_parzen, state),
         {:ok, reward_model} <- determine_best_model(distances),
         {:ok, new_sla} <- update_sla_for_all_models(reward_model, distances, state),
         {:ok, final_sla, chosen_model} <- choose_next_model(new_sla) do
      # Build response
      response = %{
        chosen_model: chosen_model,
        probabilities: SLASelector.probabilities(final_sla),
        distances: distances,
        iteration: final_sla.iteration,
        reward_model: reward_model
      }

      # Update state
      new_state = %{
        state
        | parzen: new_parzen,
          sla: final_sla,
          last_reward: -distances[reward_model],
          iteration: state.iteration + 1
      }

      {:ok, response, new_state}
    else
      {:error, _reason} = error -> error
    end
  end

  # Step 1: Validate batch structure
  defp validate_batch(%{model_outputs: outputs, target_dist: target}, state)
       when is_map(outputs) do
    # Check all models have outputs
    missing_models = state.models -- Map.keys(outputs)

    if missing_models != [] do
      {:error, {:missing_model_output, missing_models}}
    else
      # Check target is a tensor
      if is_struct(target, Nx.Tensor) do
        # Check all outputs are tensors with compatible shapes
        validate_output_shapes(outputs, target)
      else
        {:error, :invalid_target}
      end
    end
  end

  defp validate_batch(_batch, _state) do
    {:error, :invalid_batch_format}
  end

  defp validate_output_shapes(outputs, target) do
    target_shape = Nx.shape(target)
    target_dims = tuple_size(target_shape)

    # Target should be 1D (classes) or 2D (batch, classes)
    if target_dims in [1, 2] do
      # Get expected shape from target
      expected_shape =
        case target_dims do
          1 -> target_shape
          2 -> elem(target_shape, 1)
        end

      # Check each output
      Enum.reduce_while(outputs, :ok, fn {model_id, tensor}, _acc ->
        unless is_struct(tensor, Nx.Tensor) do
          {:halt, {:error, {:invalid_output, model_id, "not a tensor"}}}
        else
          shape = Nx.shape(tensor)
          dims = tuple_size(shape)

          # Output should match target dimensionality
          cond do
            dims != target_dims ->
              {:halt, {:error, {:shape_mismatch, model_id, shape, target_shape}}}

            dims == 1 and shape != expected_shape ->
              {:halt, {:error, {:shape_mismatch, model_id, shape, expected_shape}}}

            dims == 2 and elem(shape, 1) != expected_shape ->
              {:halt, {:error, {:shape_mismatch, model_id, shape, target_shape}}}

            true ->
              {:cont, :ok}
          end
        end
      end)
    else
      {:error, {:invalid_target_shape, target_shape}}
    end
  end

  # Step 2: Update Parzen estimators
  defp update_all_parzen(%{model_outputs: outputs}, state) do
    new_parzen =
      Enum.into(state.models, %{}, fn model_id ->
        model_output = outputs[model_id]
        current_parzen = state.parzen[model_id]

        # Ensure model_output is 2D for Parzen.fit
        # Parzen expects shape {batch_size, feature_dim}
        # If 1D {classes}, reshape to {1, classes}
        # If already 2D {batch_size, classes}, use as-is
        batch =
          case Nx.shape(model_output) do
            {_batch_size, _feature_dim} ->
              # Already 2D, use directly
              model_output

            {_feature_dim} ->
              # 1D, add batch dimension
              Nx.new_axis(model_output, 0)
          end

        # Fit Parzen with this model's output
        updated_parzen = Parzen.fit(current_parzen, batch)

        {model_id, updated_parzen}
      end)

    {:ok, new_parzen}
  end

  # Step 3: Compute distances
  defp compute_all_distances(%{model_outputs: outputs, target_dist: target}, _new_parzen, state) do
    distances =
      Enum.into(state.models, %{}, fn model_id ->
        model_output = outputs[model_id]

        # Compute distance between model output and target distribution directly
        # (not through Parzen - the Parzen tracks density over time but comparison is direct)
        distance_value =
          case state.distance_metric do
            :js -> Distance.js_divergence(model_output, target)
            :kl -> Distance.kl_divergence(model_output, target)
            :hellinger -> Distance.hellinger(model_output, target)
            :cross_entropy -> Distance.cross_entropy(model_output, target)
          end

        {model_id, Nx.to_number(distance_value)}
      end)

    {:ok, distances}
  end

  # Step 4: Determine best model (minimum distance)
  defp determine_best_model(distances) do
    {best_model, _min_distance} = Enum.min_by(distances, fn {_k, v} -> v end)
    {:ok, best_model}
  end

  # Step 5: Update SLA with reward signals
  defp update_sla_for_all_models(reward_model, distances, state) do
    # Update SLA for each model
    new_sla =
      Enum.reduce(state.models, state.sla, fn model_id, sla_acc ->
        # Best model gets reward (1), others get penalty (0)
        # SLASelector.update/4 expects 0 or 1, not :reward/:penalty atoms
        reward = if model_id == reward_model, do: 1, else: 0
        distance = distances[model_id]

        # Pass distance as optional metadata in keyword list
        SLASelector.update(sla_acc, model_id, reward, distance: distance)
      end)

    {:ok, new_sla}
  end

  # Step 6: Choose next model via SLA
  defp choose_next_model(sla) do
    # SLASelector.choose_action/2 returns {updated_sla, chosen_action}
    # We need both: updated SLA has incremented iteration counter
    {updated_sla, chosen} = SLASelector.choose_action(sla, strategy: :sample)
    {:ok, updated_sla, chosen}
  end

  # Telemetry emission
  defp emit_telemetry(event_type, measurements, metadata) do
    :telemetry.execute(
      [:thunderline, :ml, :controller, :process_batch, event_type],
      measurements,
      metadata
    )
  end

  # Unused helpers (for Phase 3.6+ ONNX integration)
  defp update_parzen(_state, _batch), do: raise("Use update_all_parzen/2")
  defp choose_model(_state), do: raise("Use choose_next_model/1")
  defp run_inference(_state, _model_id, _batch), do: raise("Phase 3.6+ ONNX")
  defp outputs_to_histogram(_outputs, _bins), do: raise("Use Parzen.histogram/1")
  defp compute_distance(_state, _p_hist, _m_hist), do: raise("Use compute_all_distances/3")
  defp calculate_reward(_state, _distance), do: raise("Use determine_best_model/1")
  defp update_sla(_state, _model_id, _reward, _dist), do: raise("Use update_sla_for_all_models/3")

  defp build_metadata(_state, _model_id, _dist, _reward),
    do: raise("Response built in do_process_batch/2")

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
