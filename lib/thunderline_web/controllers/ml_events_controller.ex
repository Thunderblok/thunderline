defmodule ThunderlineWeb.MLEventsController do
  @moduledoc """
  Phase 2B: HTTP API endpoint for ML training events from Cerebros.

  This controller serves as the ThunderGate entry point for external ML training
  pipelines (Python/Cerebros) to publish canonical events into ThunderFlow.

  ## Endpoints

  - `POST /api/events/ml` - Publish ML training event

  ## Event Types Supported

  - `ml.run.start` - Training run initiated
  - `ml.run.stop` - Training run completed
  - `ml.run.metric` - Intermediate metric update
  - `ml.trial.start` - Trial started
  - `ml.trial.complete` - Trial completed (primary event)
  - `ml.trial.failed` - Trial failed

  ## Request Format

      POST /api/events/ml
      Content-Type: application/json

      {
        "event": "ml.trial.complete",
        "model_run_id": "550e8400-e29b-41d4-a716-446655440000",
        "trial_id": "trial_007",
        "spectral_norm": true,
        "mlflow_run_id": "mlflow_abc123",
        "metrics": {
          "accuracy": 0.95,
          "loss": 0.05
        },
        "parameters": {
          "hidden_size": 128,
          "num_layers": 3
        },
        "duration_ms": 45000
      }

  ## Response Format

  Success (202 Accepted):
      {
        "success": true,
        "event_id": "uuid",
        "event_name": "ml.trial.complete",
        "message": "Event accepted for processing"
      }

  Validation Error (400 Bad Request):
      {
        "success": false,
        "error": "invalid_payload",
        "details": ["missing required field: trial_id"]
      }

  Processing Error (422 Unprocessable Entity):
      {
        "success": false,
        "error": "event_construction_failed",
        "details": "reason"
      }

  ## Anti-Corruption Layer

  This controller acts as a translator between Python dict payloads and
  Elixir canonical events, preserving clean domain boundaries per the
  architecture specification.
  """

  use ThunderlineWeb, :controller
  require Logger

  alias Thunderline.Thunderflow.{MLEvents, EventBus}

  # Event type mapping to MLEvents functions
  @event_handlers %{
    "ml.run.start" => :emit_run_start,
    "ml.run.stop" => :emit_run_stop,
    "ml.run.metric" => :emit_run_metric,
    "ml.trial.start" => :emit_trial_start,
    "ml.trial.complete" => :emit_trial_complete,
    "ml.trial.failed" => :emit_trial_failed
  }

  @doc """
  POST /api/events/ml

  Accepts ML training events from external systems (Cerebros) and publishes
  them to ThunderFlow EventBus.

  ## Parameters

  - `event` (required) - Event type (e.g., "ml.trial.complete")
  - Additional fields depend on event type (see MLEvents module docs)

  ## Examples

      curl -X POST http://localhost:4000/api/events/ml \\
        -H "Content-Type: application/json" \\
        -d '{
          "event": "ml.trial.complete",
          "model_run_id": "test-run",
          "trial_id": "trial_001",
          "spectral_norm": true,
          "metrics": {"accuracy": 0.95}
        }'
  """
  def create(conn, params) do
    start_time = System.monotonic_time(:millisecond)
    event_type = params["event"]

    Logger.info("[MLEventsController] Received event: #{event_type}")
    Logger.debug("[MLEventsController] Payload: #{inspect(params)}")

    with {:ok, event_type} <- validate_event_type(event_type),
         {:ok, attrs} <- transform_payload(params, event_type),
         {:ok, event} <- construct_event(event_type, attrs),
         {:ok, published_event} <- publish_event(event) do
      duration_ms = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "[MLEventsController] Event published successfully: #{event.name} (#{duration_ms}ms)"
      )

      emit_telemetry(:success, event_type, duration_ms)

      conn
      |> put_status(:accepted)
      |> json(%{
        success: true,
        event_id: published_event.id,
        event_name: published_event.name,
        correlation_id: published_event.correlation_id,
        message: "Event accepted for processing"
      })
    else
      {:error, :unknown_event_type} ->
        emit_telemetry(:error, event_type, 0, :unknown_event_type)

        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: "unknown_event_type",
          details: "Supported events: #{Enum.join(Map.keys(@event_handlers), ", ")}",
          received: event_type
        })

      {:error, {:validation_failed, errors}} ->
        emit_telemetry(:error, event_type, 0, :validation_failed)

        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: "validation_failed",
          details: format_validation_errors(errors)
        })

      {:error, {:event_construction_failed, reason}} ->
        emit_telemetry(:error, event_type, 0, :construction_failed)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "event_construction_failed",
          details: inspect(reason)
        })

      {:error, {:publish_failed, reason}} ->
        emit_telemetry(:error, event_type, 0, :publish_failed)
        Logger.error("[MLEventsController] Event publish failed: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "publish_failed",
          details: "Event could not be published to event bus",
          reason: inspect(reason)
        })
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_event_type(nil), do: {:error, {:validation_failed, ["missing event field"]}}

  defp validate_event_type(event_type) when is_binary(event_type) do
    if Map.has_key?(@event_handlers, event_type) do
      {:ok, event_type}
    else
      {:error, :unknown_event_type}
    end
  end

  defp validate_event_type(_), do: {:error, {:validation_failed, ["event must be a string"]}}

  defp transform_payload(params, event_type) do
    # Convert string keys to atoms for MLEvents constructors
    # Remove "event" field as it's not part of the event payload
    attrs =
      params
      |> Map.drop(["event"])
      |> atomize_keys()

    # Validate required fields based on event type
    case validate_required_fields(attrs, event_type) do
      :ok -> {:ok, attrs}
      {:error, missing} -> {:error, {:validation_failed, missing}}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), atomize_keys(value)}
      {key, value} -> {key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(value), do: value

  defp validate_required_fields(attrs, "ml.run.start") do
    check_required(attrs, [:model_run_id, :requested_trials, :search_space_version])
  end

  defp validate_required_fields(attrs, "ml.run.stop") do
    check_required(attrs, [:model_run_id, :state, :completed_trials])
  end

  defp validate_required_fields(attrs, "ml.run.metric") do
    check_required(attrs, [:model_run_id, :trial_id, :metric_name, :metric_value])
  end

  defp validate_required_fields(attrs, "ml.trial.start") do
    check_required(attrs, [:model_run_id, :trial_id, :spectral_norm])
  end

  defp validate_required_fields(attrs, "ml.trial.complete") do
    check_required(attrs, [:model_run_id, :trial_id, :spectral_norm, :metrics])
  end

  defp validate_required_fields(attrs, "ml.trial.failed") do
    check_required(attrs, [:model_run_id, :trial_id, :error_message])
  end

  defp validate_required_fields(_, _), do: :ok

  defp check_required(attrs, required_fields) do
    missing = Enum.filter(required_fields, &(not Map.has_key?(attrs, &1)))

    case missing do
      [] -> :ok
      _ -> {:error, Enum.map(missing, &"missing required field: #{&1}")}
    end
  end

  defp construct_event(event_type, attrs) do
    handler = Map.fetch!(@event_handlers, event_type)

    case apply(MLEvents, handler, [attrs]) do
      {:ok, event} ->
        {:ok, event}

      {:error, reason} ->
        Logger.warning("[MLEventsController] Event construction failed: #{inspect(reason)}")
        {:error, {:event_construction_failed, reason}}
    end
  end

  defp publish_event(event) do
    case EventBus.publish_event(event) do
      {:ok, published_event} ->
        {:ok, published_event}

      {:error, reason} ->
        {:error, {:publish_failed, reason}}
    end
  end

  defp format_validation_errors(errors) when is_list(errors) do
    errors
  end

  defp format_validation_errors(error), do: [inspect(error)]

  defp emit_telemetry(status, event_type, duration_ms, error_reason \\ nil) do
    metadata = %{
      status: status,
      event_type: event_type,
      error_reason: error_reason
    }

    :telemetry.execute(
      [:thunderline, :api, :ml_events],
      %{duration: duration_ms, count: 1},
      metadata
    )
  end
end
