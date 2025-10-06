defmodule Thunderline.Thunderflow.MLEvents do
  @moduledoc """
  Phase 2: ML Training Event Schemas for Spectral Norm Integration.

  This module provides smart constructors for canonical ML training events that flow
  between Cerebros (Python training pipeline) and Thunderline (Elixir orchestration).

  ## Event Taxonomy

  All ML events follow the naming pattern: `ml.<entity>.<action>`

  - `ml.run.start` - Training run initiated (search space + trials config)
  - `ml.run.stop` - Training run completed (summary metrics + best trial)
  - `ml.run.metric` - Intermediate metric update during training
  - `ml.trial.start` - Individual trial started (includes spectral_norm flag)
  - `ml.trial.complete` - Trial finished (final metrics + artifacts)
  - `ml.trial.failed` - Trial failed (error details)

  ## Spectral Norm Integration

  All trial events include `spectral_norm: boolean` in the payload to track whether
  spectral normalization constraints were applied to the model architecture.

  ## MLflow Integration

  Events include `mlflow_run_id` for cross-referencing with MLflow experiment tracking.

  ## Usage

      # Training run started
      {:ok, event} = MLEvents.emit_run_start(%{
        model_run_id: "uuid",
        search_space_version: 2,
        requested_trials: 10,
        max_params: 2_000_000
      })

      # Trial completed with spectral norm
      {:ok, event} = MLEvents.emit_trial_complete(%{
        model_run_id: "uuid",
        trial_id: "trial_001",
        spectral_norm: true,
        mlflow_run_id: "mlflow_abc123",
        metrics: %{accuracy: 0.95, loss: 0.05},
        parameters: %{hidden_size: 128, num_layers: 3},
        duration_ms: 45000
      })

      # Publish event to ThunderFlow
      Thunderline.Thunderflow.EventBus.publish_event(event)

  ## Event Flow Architecture

  ```
  Cerebros (Python) → ThunderGate API → ThunderFlow EventBus → Broadway Pipeline
       ↓                                         ↓
  Optuna/MLflow                          Mnesia Event Store
                                                 ↓
                                         ThunderBolt ModelTrial.log()
                                                 ↓
                                          PostgreSQL (cerebros_model_trials)
  ```

  ## Anti-Corruption Layer

  The CerebrosBridge acts as a translator between Python dict payloads and
  Elixir canonical events, preserving clean domain boundaries.
  """

  alias Thunderline.Event

  @source :bolt
  @taxonomy_version 1

  # ============================================================================
  # Training Run Events
  # ============================================================================

  @doc """
  Emit a training run start event.

  ## Required Fields
  - `model_run_id` (string/UUID) - Unique identifier for the training run
  - `requested_trials` (integer) - Number of trials to execute
  - `search_space_version` (integer) - Version of the NAS search space

  ## Optional Fields
  - `max_params` (integer) - Maximum model parameters allowed
  - `metadata` (map) - Additional context (user_id, experiment_name, etc.)
  - `correlation_id` (string) - For tracing across systems
  - `actor` (map) - Actor who initiated the run (%{id: string, type: atom})

  ## Example

      iex> MLEvents.emit_run_start(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   requested_trials: 10,
      ...>   search_space_version: 2,
      ...>   max_params: 2_000_000,
      ...>   metadata: %{experiment: "spectral_norm_ablation"}
      ...> })
      {:ok, %Event{name: "ml.run.start", source: :bolt, ...}}
  """
  @spec emit_run_start(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_run_start(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :requested_trials, :search_space_version]),
         :ok <- validate_positive_integer(attrs, :requested_trials),
         :ok <- validate_positive_integer(attrs, :search_space_version) do
      Event.new(
        name: "ml.run.start",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          requested_trials: attrs.requested_trials,
          search_space_version: attrs.search_space_version,
          max_params: attrs[:max_params],
          metadata: attrs[:metadata] || %{},
          started_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        actor: attrs[:actor],
        priority: :high,
        taxonomy_version: @taxonomy_version,
        event_version: 1
      )
    end
  end

  @doc """
  Emit a training run stop event.

  ## Required Fields
  - `model_run_id` (string/UUID) - Training run identifier
  - `state` (string) - Final state: "completed", "failed", "cancelled"
  - `completed_trials` (integer) - Number of trials completed

  ## Optional Fields
  - `best_metric` (float) - Best metric achieved across all trials
  - `best_trial_id` (string) - Trial ID that achieved best metric
  - `error_message` (string) - Error details if state is "failed"
  - `metadata` (map) - Summary statistics, timing info, etc.

  ## Example

      iex> MLEvents.emit_run_stop(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   state: "completed",
      ...>   completed_trials: 10,
      ...>   best_metric: 0.9234,
      ...>   best_trial_id: "trial_007",
      ...>   metadata: %{
      ...>     total_duration_ms: 450_000,
      ...>     spectral_norm_trials: 5,
      ...>     unconstrained_trials: 5
      ...>   }
      ...> })
      {:ok, %Event{name: "ml.run.stop", source: :bolt, ...}}
  """
  @spec emit_run_stop(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_run_stop(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :state, :completed_trials]),
         :ok <- validate_state(attrs.state),
         :ok <- validate_non_negative_integer(attrs, :completed_trials) do
      Event.new(
        name: "ml.run.stop",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          state: attrs.state,
          completed_trials: attrs.completed_trials,
          best_metric: attrs[:best_metric],
          best_trial_id: attrs[:best_trial_id],
          error_message: attrs[:error_message],
          metadata: attrs[:metadata] || %{},
          finished_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        actor: attrs[:actor],
        priority: :high,
        taxonomy_version: @taxonomy_version,
        event_version: 1
      )
    end
  end

  @doc """
  Emit an intermediate metric update during training.

  Used for real-time progress monitoring and live dashboards.

  ## Required Fields
  - `model_run_id` (string/UUID) - Training run identifier
  - `trial_id` (string) - Current trial identifier
  - `metric_name` (string) - Name of the metric (e.g., "val_accuracy", "loss")
  - `metric_value` (float) - Current metric value

  ## Optional Fields
  - `step` (integer) - Training step/epoch number
  - `spectral_norm` (boolean) - Whether spectral norm is applied (default: false)
  - `metadata` (map) - Additional context (learning_rate, batch_size, etc.)

  ## Example

      iex> MLEvents.emit_run_metric(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   trial_id: "trial_003",
      ...>   metric_name: "val_accuracy",
      ...>   metric_value: 0.8765,
      ...>   step: 42,
      ...>   spectral_norm: true,
      ...>   metadata: %{learning_rate: 0.001}
      ...> })
      {:ok, %Event{name: "ml.run.metric", source: :bolt, ...}}
  """
  @spec emit_run_metric(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_run_metric(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :trial_id, :metric_name, :metric_value]),
         :ok <- validate_number(attrs, :metric_value) do
      Event.new(
        name: "ml.run.metric",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          trial_id: attrs.trial_id,
          metric_name: attrs.metric_name,
          metric_value: attrs.metric_value,
          step: attrs[:step],
          spectral_norm: attrs[:spectral_norm] || false,
          metadata: attrs[:metadata] || %{},
          recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        priority: :normal,
        taxonomy_version: @taxonomy_version,
        event_version: 1,
        meta: %{pipeline: :realtime}
      )
    end
  end

  # ============================================================================
  # Trial Events
  # ============================================================================

  @doc """
  Emit a trial start event.

  ## Required Fields
  - `model_run_id` (string/UUID) - Parent training run identifier
  - `trial_id` (string) - Unique trial identifier
  - `spectral_norm` (boolean) - Whether spectral norm constraint is applied

  ## Optional Fields
  - `mlflow_run_id` (string) - MLflow run ID for cross-referencing
  - `parameters` (map) - Hyperparameters for this trial
  - `candidate_id` (string) - Optuna candidate identifier
  - `metadata` (map) - Additional context

  ## Example

      iex> MLEvents.emit_trial_start(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   trial_id: "trial_003",
      ...>   spectral_norm: true,
      ...>   mlflow_run_id: "mlflow_abc123",
      ...>   parameters: %{
      ...>     hidden_size: 128,
      ...>     num_layers: 3,
      ...>     dropout: 0.2
      ...>   }
      ...> })
      {:ok, %Event{name: "ml.trial.start", source: :bolt, ...}}
  """
  @spec emit_trial_start(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_trial_start(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :trial_id, :spectral_norm]),
         :ok <- validate_boolean(attrs, :spectral_norm) do
      Event.new(
        name: "ml.trial.start",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          trial_id: attrs.trial_id,
          spectral_norm: attrs.spectral_norm,
          mlflow_run_id: attrs[:mlflow_run_id],
          parameters: attrs[:parameters] || %{},
          candidate_id: attrs[:candidate_id],
          metadata: attrs[:metadata] || %{},
          started_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        actor: attrs[:actor],
        priority: :normal,
        taxonomy_version: @taxonomy_version,
        event_version: 1
      )
    end
  end

  @doc """
  Emit a trial complete event (Phase 1 primary event).

  This is the key event that triggers `ModelTrial.log()` in ThunderBolt,
  persisting trial results with spectral norm tracking to PostgreSQL.

  ## Required Fields
  - `model_run_id` (string/UUID) - Parent training run identifier
  - `trial_id` (string) - Unique trial identifier
  - `spectral_norm` (boolean) - Whether spectral norm constraint was applied
  - `metrics` (map) - Final trial metrics (accuracy, loss, etc.)

  ## Optional Fields
  - `mlflow_run_id` (string) - MLflow run ID for experiment tracking
  - `parameters` (map) - Hyperparameters used in this trial
  - `artifact_uri` (string) - Path to saved model artifacts
  - `duration_ms` (integer) - Trial execution time in milliseconds
  - `rank` (integer) - Optuna trial rank/priority
  - `warnings` (list[string]) - Any warnings generated during trial
  - `candidate_id` (string) - Optuna candidate identifier
  - `pulse_id` (string) - Pulse/heartbeat identifier
  - `bridge_payload` (map) - Raw payload from CerebrosBridge for debugging

  ## Example

      iex> MLEvents.emit_trial_complete(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   trial_id: "trial_007",
      ...>   spectral_norm: true,
      ...>   mlflow_run_id: "mlflow_abc123",
      ...>   metrics: %{
      ...>     val_accuracy: 0.9234,
      ...>     val_loss: 0.0876,
      ...>     test_accuracy: 0.9187
      ...>   },
      ...>   parameters: %{
      ...>     hidden_size: 256,
      ...>     num_layers: 4,
      ...>     dropout: 0.3,
      ...>     spectral_norm_coeff: 1.0
      ...>   },
      ...>   artifact_uri: "s3://thunderline-models/run_123/trial_007",
      ...>   duration_ms: 45_000,
      ...>   rank: 3
      ...> })
      {:ok, %Event{name: "ml.trial.complete", source: :bolt, ...}}
  """
  @spec emit_trial_complete(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_trial_complete(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :trial_id, :spectral_norm, :metrics]),
         :ok <- validate_boolean(attrs, :spectral_norm),
         :ok <- validate_map(attrs, :metrics) do
      Event.new(
        name: "ml.trial.complete",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          trial_id: attrs.trial_id,
          spectral_norm: attrs.spectral_norm,
          mlflow_run_id: attrs[:mlflow_run_id],
          metrics: attrs.metrics,
          parameters: attrs[:parameters] || %{},
          artifact_uri: attrs[:artifact_uri],
          duration_ms: attrs[:duration_ms],
          rank: attrs[:rank],
          warnings: attrs[:warnings] || [],
          candidate_id: attrs[:candidate_id],
          pulse_id: attrs[:pulse_id],
          bridge_payload: attrs[:bridge_payload] || %{},
          status: "succeeded",
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        actor: attrs[:actor],
        priority: :high,
        taxonomy_version: @taxonomy_version,
        event_version: 1
      )
    end
  end

  @doc """
  Emit a trial failed event.

  ## Required Fields
  - `model_run_id` (string/UUID) - Parent training run identifier
  - `trial_id` (string) - Failed trial identifier
  - `error_message` (string) - Error description

  ## Optional Fields
  - `spectral_norm` (boolean) - Whether spectral norm was attempted
  - `mlflow_run_id` (string) - MLflow run ID
  - `error_type` (string) - Error classification (e.g., "OOM", "timeout", "nan_loss")
  - `stacktrace` (string) - Full error stacktrace for debugging
  - `metadata` (map) - Additional context

  ## Example

      iex> MLEvents.emit_trial_failed(%{
      ...>   model_run_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   trial_id: "trial_013",
      ...>   error_message: "CUDA out of memory",
      ...>   error_type: "OOM",
      ...>   spectral_norm: false,
      ...>   metadata: %{allocated_memory_gb: 14.5}
      ...> })
      {:ok, %Event{name: "ml.trial.failed", source: :bolt, ...}}
  """
  @spec emit_trial_failed(map()) :: {:ok, Event.t()} | {:error, term()}
  def emit_trial_failed(%{} = attrs) do
    with :ok <- validate_required(attrs, [:model_run_id, :trial_id, :error_message]) do
      Event.new(
        name: "ml.trial.failed",
        source: @source,
        payload: %{
          model_run_id: to_string(attrs.model_run_id),
          trial_id: attrs.trial_id,
          spectral_norm: attrs[:spectral_norm],
          mlflow_run_id: attrs[:mlflow_run_id],
          error_message: attrs.error_message,
          error_type: attrs[:error_type],
          stacktrace: attrs[:stacktrace],
          metadata: attrs[:metadata] || %{},
          status: "failed",
          failed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        correlation_id: attrs[:correlation_id],
        actor: attrs[:actor],
        priority: :high,
        taxonomy_version: @taxonomy_version,
        event_version: 1
      )
    end
  end

  # ============================================================================
  # Validation Helpers
  # ============================================================================

  defp validate_required(attrs, keys) do
    missing = Enum.filter(keys, &(not Map.has_key?(attrs, &1)))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_positive_integer(attrs, key) do
    case Map.get(attrs, key) do
      val when is_integer(val) and val > 0 -> :ok
      _ -> {:error, {:invalid_positive_integer, key}}
    end
  end

  defp validate_non_negative_integer(attrs, key) do
    case Map.get(attrs, key) do
      val when is_integer(val) and val >= 0 -> :ok
      _ -> {:error, {:invalid_non_negative_integer, key}}
    end
  end

  defp validate_number(attrs, key) do
    case Map.get(attrs, key) do
      val when is_number(val) -> :ok
      _ -> {:error, {:invalid_number, key}}
    end
  end

  defp validate_boolean(attrs, key) do
    case Map.get(attrs, key) do
      val when is_boolean(val) -> :ok
      _ -> {:error, {:invalid_boolean, key}}
    end
  end

  defp validate_map(attrs, key) do
    case Map.get(attrs, key) do
      val when is_map(val) -> :ok
      _ -> {:error, {:invalid_map, key}}
    end
  end

  defp validate_state(state) when state in ["completed", "failed", "cancelled"], do: :ok
  defp validate_state(_), do: {:error, {:invalid_state, "must be completed, failed, or cancelled"}}
end
