defmodule Thunderline.Thunderbolt.CerebrosFacade.Bridge do
  @moduledoc """
  Unified entry point for all Cerebros ML operations.

  This module serves as the **canonical facade** for Cerebros interactions,
  enforcing the HC-20 boundary specification. All Cerebros operations from
  Thunderline MUST go through this module.

  ## Direct Ortex calls outside this namespace are forbidden.

  See `documentation/architecture/CEREBROS_BRIDGE_BOUNDARY.md` for details.

  ## Features

  - **Model Loading**: Load ONNX models via ModelServer (cached sessions)
  - **Inference**: Run predictions through loaded models
  - **Training Bridge**: Start/record/finalize Cerebros training runs
  - **Events**: Emit canonical events for all operations
  - **Health**: Check bridge status and configuration

  ## Usage

      # Load and run inference
      {:ok, result} = Cerebros.Bridge.infer("cerebros_trained.onnx", input_tensor)

      # Check bridge health
      {:ok, health} = Cerebros.Bridge.health()

      # Start a training run (via CerebrosBridge.Client)
      {:ok, run} = Cerebros.Bridge.start_training(%{dataset: "mnist", epochs: 10})

  ## Events Emitted

  - `cerebros.model.loaded` - Model loaded into cache
  - `cerebros.model.evicted` - Model removed from cache
  - `cerebros.inference.completed` - Inference succeeded
  - `cerebros.inference.failed` - Inference failed

  Training events are delegated to `CerebrosBridge.Client`:
  - `ml.run.start` / `ml.run.stop` / `ml.run.trial` / `ml.run.exception`
  """

  require Logger

  alias Thunderline.Event
  alias Thunderline.EventBus
  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.ML.{ModelServer, KerasONNX}
  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts}

  @feature_flag :ml_nas

  # ─────────────────────────────────────────────────────────────
  # Model Loading & Session Management
  # ─────────────────────────────────────────────────────────────

  @doc """
  Load a model by name, returning a session reference for inference.

  Uses ModelServer for caching - subsequent calls return cached session.

  ## Options

  - `:server` - ModelServer name (default: `ModelServer`)
  - `:timeout` - Load timeout in ms (default: 30_000)

  ## Examples

      {:ok, session} = Bridge.load_model("cerebros_trained.onnx")
      # Session is now cached, fast on next call
  """
  @spec load_model(String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def load_model(model_name, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, session} <- ModelServer.get_session(model_name, opts) do
      emit_event("cerebros.model.loaded", %{model: model_name, cached: true})
      {:ok, session}
    else
      {:error, reason} = err ->
        Logger.warning("[Cerebros.Bridge] load_model failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Run inference on a loaded session.

  ## Options

  - `:output_names` - Specific output tensors to return (default: all)

  ## Examples

      {:ok, output} = Bridge.run_inference(session, input_tensor)
  """
  @spec run_inference(reference(), Nx.Tensor.t(), keyword()) ::
          {:ok, Nx.Tensor.t() | tuple()} | {:error, term()}
  def run_inference(session, input, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    case KerasONNX.infer(session, input, opts) do
      {:ok, _output} = result ->
        duration_us = System.monotonic_time(:microsecond) - start_time

        emit_event("cerebros.inference.completed", %{
          duration_us: duration_us,
          input_shape: Nx.shape(input)
        })

        result

      {:error, reason} = err ->
        emit_event("cerebros.inference.failed", %{reason: inspect(reason)})
        err
    end
  end

  @doc """
  Convenience function: load model and run inference in one call.

  Combines `load_model/2` and `run_inference/3`. The model session is
  cached by ModelServer, so repeated calls are fast.

  ## Options

  - `:server` - ModelServer name
  - `:output_names` - Specific outputs to return

  ## Examples

      input = Nx.tensor([[1.0, 2.0, 3.0]])
      {:ok, %{output: tensor, model: name, duration_us: time}} =
        Bridge.infer("cerebros_trained.onnx", input)
  """
  @spec infer(String.t(), Nx.Tensor.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def infer(model_name, input, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    with {:ok, session} <- load_model(model_name, opts),
         {:ok, output} <- run_inference(session, input, opts) do
      duration_us = System.monotonic_time(:microsecond) - start_time

      {:ok,
       %{
         output: output,
         model: model_name,
         duration_us: duration_us,
         input_shape: Nx.shape(input)
       }}
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Model Management
  # ─────────────────────────────────────────────────────────────

  @doc """
  List all loaded models in the ModelServer cache.

  Returns a list of maps with model metadata.

  ## Examples

      {:ok, models} = Bridge.list_models()
      # [%{name: "cerebros_trained.onnx", loaded_at: ~U[...], access_count: 42}]
  """
  @spec list_models(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_models(opts \\ []) do
    with :ok <- check_enabled() do
      models = ModelServer.list_models(opts)
      {:ok, models}
    end
  end

  @doc """
  Get metadata for a specific model.

  ## Examples

      {:ok, meta} = Bridge.get_model_metadata("cerebros_trained.onnx")
      # %{name: "...", path: "...", size_bytes: 1234, loaded: true}
  """
  @spec get_model_metadata(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_model_metadata(model_name, opts \\ []) do
    with :ok <- check_enabled() do
      case ModelServer.get_model_info(model_name, opts) do
        {:ok, info} -> {:ok, info}
        {:error, :not_found} -> {:error, {:model_not_found, model_name}}
        error -> error
      end
    end
  end

  @doc """
  Preload a model into the ModelServer cache.

  Useful for warming up the cache at startup or before expected load.

  ## Examples

      :ok = Bridge.preload("cerebros_trained.onnx")
  """
  @spec preload(String.t(), keyword()) :: :ok | {:error, term()}
  def preload(model_name, opts \\ []) do
    with :ok <- check_enabled(),
         :ok <- ModelServer.preload(model_name, opts) do
      emit_event("cerebros.model.loaded", %{model: model_name, preload: true})
      :ok
    end
  end

  @doc """
  Evict a model from the ModelServer cache.

  Frees memory but requires reload on next access.

  ## Examples

      :ok = Bridge.evict("old_model.onnx")
  """
  @spec evict(String.t(), keyword()) :: :ok | {:error, term()}
  def evict(model_name, opts \\ []) do
    with :ok <- check_enabled(),
         :ok <- ModelServer.evict(model_name, opts) do
      emit_event("cerebros.model.evicted", %{model: model_name})
      :ok
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Training Bridge (delegates to CerebrosBridge.Client)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Start a Cerebros training run.

  Delegates to `CerebrosBridge.Client.start_run/2`.

  ## Parameters

  - `params` - Training parameters (dataset, epochs, etc.)
  - `opts` - Options passed to Client

  ## Examples

      {:ok, run} = Bridge.start_training(%{
        dataset: "mnist",
        epochs: 10,
        batch_size: 32
      })
  """
  @spec start_training(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_training(params, opts \\ []) when is_map(params) do
    with :ok <- check_enabled() do
      contract = build_run_started_contract(params)
      Client.start_run(contract, opts)
    end
  end

  @doc """
  Record a trial result from a Cerebros training run.

  Delegates to `CerebrosBridge.Client.record_trial/2`.

  ## Examples

      {:ok, _} = Bridge.record_trial(%{
        run_id: "run-123",
        trial_id: "trial-456",
        status: :completed,
        metrics: %{accuracy: 0.95, loss: 0.05}
      })
  """
  @spec record_trial(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def record_trial(params, opts \\ []) when is_map(params) do
    with :ok <- check_enabled() do
      contract = build_trial_reported_contract(params)
      Client.record_trial(contract, opts)
    end
  end

  @doc """
  Finalize a Cerebros training run.

  Delegates to `CerebrosBridge.Client.finalize_run/2`.

  ## Examples

      {:ok, _} = Bridge.finalize_training(%{
        run_id: "run-123",
        status: :completed,
        final_metrics: %{best_accuracy: 0.97}
      })
  """
  @spec finalize_training(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def finalize_training(params, opts \\ []) when is_map(params) do
    with :ok <- check_enabled() do
      contract = build_run_finalized_contract(params)
      Client.finalize_run(contract, opts)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Health & Status
  # ─────────────────────────────────────────────────────────────

  @doc """
  Check if the Cerebros bridge is enabled and healthy.

  Returns a map with status information.

  ## Examples

      {:ok, %{
        enabled: true,
        model_server: :running,
        loaded_models: 3,
        config: %{...}
      }} = Bridge.health()
  """
  @spec health() :: {:ok, map()} | {:error, term()}
  def health do
    config = Client.config()
    model_server_status = check_model_server()
    loaded_models = ModelServer.list_models() |> length()

    status = %{
      enabled: enabled?(),
      feature_flag: Feature.enabled?(@feature_flag, default: false),
      config_enabled: config.enabled?,
      model_server: model_server_status,
      loaded_models: loaded_models,
      config: %{
        repo_path: config.repo_path,
        model_dir: model_dir(),
        max_models: max_models()
      }
    }

    {:ok, status}
  end

  @doc """
  Returns true if the Cerebros bridge is enabled.

  Checks both the feature flag (`:ml_nas`) and runtime configuration.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Client.enabled?()
  end

  @doc """
  Get the Cerebros repository version if available.
  """
  @spec version() :: {:ok, String.t()} | {:error, :version_unavailable}
  def version do
    Client.version()
  end

  # ─────────────────────────────────────────────────────────────
  # Internal Helpers
  # ─────────────────────────────────────────────────────────────

  defp check_enabled do
    if enabled?() do
      :ok
    else
      {:error, :cerebros_bridge_disabled}
    end
  end

  defp check_model_server do
    case Process.whereis(ModelServer) do
      nil -> :not_running
      _pid -> :running
    end
  end

  defp model_dir do
    Application.get_env(:thunderline, ModelServer, [])
    |> Keyword.get(:model_dir, "priv/models")
  end

  defp max_models do
    Application.get_env(:thunderline, ModelServer, [])
    |> Keyword.get(:max_models, 10)
  end

  defp emit_event(name, payload) do
    attrs = [
      name: name,
      source: :bolt,
      payload: payload,
      meta: %{pipeline: :realtime}
    ]

    case Event.new(attrs) do
      {:ok, event} ->
        _ = EventBus.publish_event(event)
        :ok

      {:error, reason} ->
        Logger.warning("[Cerebros.Bridge] Failed to emit #{name}: #{inspect(reason)}")
        :ok
    end
  end

  # Contract builders for CerebrosBridge.Client

  defp build_run_started_contract(params) do
    %Contracts.RunStartedV1{
      run_id: params[:run_id] || Thunderline.UUID.v7(),
      correlation_id: params[:correlation_id],
      pulse_id: params[:pulse_id],
      dataset_id: params[:dataset_id],
      search_space: params[:search_space] || %{},
      objective: params[:objective] || "accuracy",
      budget: params[:budget] || %{},
      parameters: params[:parameters] || params[:config] || %{},
      tau: params[:tau],
      timestamp: DateTime.utc_now(),
      extra: params[:extra] || %{}
    }
  end

  defp build_trial_reported_contract(params) do
    %Contracts.TrialReportedV1{
      run_id: params[:run_id],
      trial_id: params[:trial_id] || Thunderline.UUID.v7(),
      pulse_id: params[:pulse_id],
      candidate_id: params[:candidate_id],
      status: params[:status] || :succeeded,
      metrics: params[:metrics] || %{},
      parameters: params[:hyperparams] || params[:parameters] || %{},
      artifact_uri: params[:artifact_uri],
      duration_ms: params[:duration_ms],
      rank: params[:rank],
      warnings: params[:warnings] || [],
      spectral_norm: params[:spectral_norm] || false,
      mlflow_run_id: params[:mlflow_run_id]
    }
  end

  defp build_run_finalized_contract(params) do
    %Contracts.RunFinalizedV1{
      run_id: params[:run_id],
      pulse_id: params[:pulse_id],
      status: params[:status] || :succeeded,
      metrics: params[:final_metrics] || params[:metrics] || %{},
      best_trial_id: params[:best_trial_id],
      duration_ms: params[:duration_ms],
      returncode: params[:returncode],
      artifact_refs: params[:artifacts] || params[:artifact_refs] || [],
      warnings: params[:warnings] || [],
      stdout_excerpt: params[:stdout_excerpt],
      payload: params[:payload] || %{}
    }
  end
end
