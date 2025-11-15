defmodule Thunderline.Thunderflow.MLEventsTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderflow.MLEvents
  alias Thunderline.Event

  describe "emit_run_start/1" do
    test "creates valid ml.run.start event with required fields" do
      attrs = %{
        model_run_id: "550e8400-e29b-41d4-a716-446655440000",
        requested_trials: 10,
        search_space_version: 2
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_run_start(attrs)
      assert event.name == "ml.run.start"
      assert event.source == :bolt
      assert event.priority == :high
      assert event.payload.model_run_id == "550e8400-e29b-41d4-a716-446655440000"
      assert event.payload.requested_trials == 10
      assert event.payload.search_space_version == 2
      assert is_binary(event.payload.started_at)
    end

    test "includes optional fields when provided" do
      attrs = %{
        model_run_id: "test-run",
        requested_trials: 5,
        search_space_version: 1,
        max_params: 1_000_000,
        metadata: %{experiment: "test"},
        correlation_id: "corr-123",
        actor: %{id: "user-1", type: :user}
      }

      assert {:ok, event} = MLEvents.emit_run_start(attrs)
      assert event.payload.max_params == 1_000_000
      assert event.payload.metadata == %{experiment: "test"}
      assert event.correlation_id == "corr-123"
      assert event.actor == %{id: "user-1", type: :user}
    end

    test "returns error when missing required fields" do
      assert {:error, {:missing_required_fields, missing}} =
               MLEvents.emit_run_start(%{model_run_id: "test"})

      assert :requested_trials in missing
      assert :search_space_version in missing
    end

    test "validates positive integer for requested_trials" do
      attrs = %{
        model_run_id: "test",
        requested_trials: 0,
        search_space_version: 1
      }

      assert {:error, {:invalid_positive_integer, :requested_trials}} =
               MLEvents.emit_run_start(attrs)
    end
  end

  describe "emit_run_stop/1" do
    test "creates valid ml.run.stop event" do
      attrs = %{
        model_run_id: "test-run",
        state: "completed",
        completed_trials: 10,
        best_metric: 0.95,
        best_trial_id: "trial_007"
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_run_stop(attrs)
      assert event.name == "ml.run.stop"
      assert event.source == :bolt
      assert event.payload.state == "completed"
      assert event.payload.completed_trials == 10
      assert event.payload.best_metric == 0.95
    end

    test "validates state must be valid" do
      attrs = %{
        model_run_id: "test",
        state: "invalid_state",
        completed_trials: 5
      }

      assert {:error, {:invalid_state, _}} = MLEvents.emit_run_stop(attrs)
    end

    test "accepts valid states: completed, failed, cancelled" do
      for state <- ["completed", "failed", "cancelled"] do
        attrs = %{model_run_id: "test", state: state, completed_trials: 0}
        assert {:ok, _} = MLEvents.emit_run_stop(attrs)
      end
    end
  end

  describe "emit_run_metric/1" do
    test "creates valid ml.run.metric event" do
      attrs = %{
        model_run_id: "test-run",
        trial_id: "trial_003",
        metric_name: "val_accuracy",
        metric_value: 0.8765,
        step: 42,
        spectral_norm: true
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_run_metric(attrs)
      assert event.name == "ml.run.metric"
      assert event.source == :bolt
      assert event.priority == :normal
      assert event.payload.metric_name == "val_accuracy"
      assert event.payload.metric_value == 0.8765
      assert event.payload.step == 42
      assert event.payload.spectral_norm == true
      assert event.meta.pipeline == :realtime
    end

    test "defaults spectral_norm to false when not provided" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        metric_name: "loss",
        metric_value: 0.5
      }

      assert {:ok, event} = MLEvents.emit_run_metric(attrs)
      assert event.payload.spectral_norm == false
    end

    test "validates metric_value must be numeric" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        metric_name: "accuracy",
        metric_value: "not_a_number"
      }

      assert {:error, {:invalid_number, :metric_value}} = MLEvents.emit_run_metric(attrs)
    end
  end

  describe "emit_trial_start/1" do
    test "creates valid ml.trial.start event with spectral_norm" do
      attrs = %{
        model_run_id: "test-run",
        trial_id: "trial_003",
        spectral_norm: true,
        mlflow_run_id: "mlflow_abc",
        parameters: %{hidden_size: 128}
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_trial_start(attrs)
      assert event.name == "ml.trial.start"
      assert event.source == :bolt
      assert event.payload.spectral_norm == true
      assert event.payload.mlflow_run_id == "mlflow_abc"
      assert event.payload.parameters == %{hidden_size: 128}
    end

    test "requires spectral_norm field" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1"
      }

      assert {:error, {:missing_required_fields, missing}} = MLEvents.emit_trial_start(attrs)
      assert :spectral_norm in missing
    end

    test "validates spectral_norm must be boolean" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        spectral_norm: "not_boolean"
      }

      assert {:error, {:invalid_boolean, :spectral_norm}} = MLEvents.emit_trial_start(attrs)
    end
  end

  describe "emit_trial_complete/1" do
    test "creates valid ml.trial.complete event with all fields" do
      attrs = %{
        model_run_id: "test-run",
        trial_id: "trial_007",
        spectral_norm: true,
        mlflow_run_id: "mlflow_abc123",
        metrics: %{accuracy: 0.95, loss: 0.05},
        parameters: %{hidden_size: 256, num_layers: 4},
        artifact_uri: "s3://models/trial_007",
        duration_ms: 45_000,
        rank: 3,
        warnings: ["low_memory"],
        candidate_id: "optuna_candidate_5",
        pulse_id: "pulse_123"
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_trial_complete(attrs)
      assert event.name == "ml.trial.complete"
      assert event.source == :bolt
      assert event.priority == :high
      assert event.payload.trial_id == "trial_007"
      assert event.payload.spectral_norm == true
      assert event.payload.mlflow_run_id == "mlflow_abc123"
      assert event.payload.metrics == %{accuracy: 0.95, loss: 0.05}
      assert event.payload.parameters == %{hidden_size: 256, num_layers: 4}
      assert event.payload.artifact_uri == "s3://models/trial_007"
      assert event.payload.duration_ms == 45_000
      assert event.payload.rank == 3
      assert event.payload.warnings == ["low_memory"]
      assert event.payload.status == "succeeded"
      assert is_binary(event.payload.completed_at)
    end

    test "requires model_run_id, trial_id, spectral_norm, and metrics" do
      assert {:error, {:missing_required_fields, missing}} = MLEvents.emit_trial_complete(%{})
      assert :model_run_id in missing
      assert :trial_id in missing
      assert :spectral_norm in missing
      assert :metrics in missing
    end

    test "validates metrics must be a map" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        spectral_norm: true,
        metrics: "not_a_map"
      }

      assert {:error, {:invalid_map, :metrics}} = MLEvents.emit_trial_complete(attrs)
    end

    test "defaults optional fields to empty values" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        spectral_norm: false,
        metrics: %{loss: 0.1}
      }

      assert {:ok, event} = MLEvents.emit_trial_complete(attrs)
      assert event.payload.parameters == %{}
      assert event.payload.warnings == []
      assert event.payload.bridge_payload == %{}
    end
  end

  describe "emit_trial_failed/1" do
    test "creates valid ml.trial.failed event" do
      attrs = %{
        model_run_id: "test-run",
        trial_id: "trial_013",
        error_message: "CUDA out of memory",
        error_type: "OOM",
        spectral_norm: false,
        metadata: %{allocated_memory_gb: 14.5}
      }

      assert {:ok, %Event{} = event} = MLEvents.emit_trial_failed(attrs)
      assert event.name == "ml.trial.failed"
      assert event.source == :bolt
      assert event.priority == :high
      assert event.payload.trial_id == "trial_013"
      assert event.payload.error_message == "CUDA out of memory"
      assert event.payload.error_type == "OOM"
      assert event.payload.spectral_norm == false
      assert event.payload.status == "failed"
      assert is_binary(event.payload.failed_at)
    end

    test "requires model_run_id, trial_id, and error_message" do
      assert {:error, {:missing_required_fields, missing}} = MLEvents.emit_trial_failed(%{})
      assert :model_run_id in missing
      assert :trial_id in missing
      assert :error_message in missing
    end

    test "spectral_norm is optional for failed trials" do
      attrs = %{
        model_run_id: "test",
        trial_id: "trial_1",
        error_message: "Something went wrong"
      }

      assert {:ok, event} = MLEvents.emit_trial_failed(attrs)
      assert event.payload.spectral_norm == nil
    end
  end

  describe "event integration with EventBus" do
    test "events can be published to EventBus" do
      attrs = %{
        model_run_id: "test-run",
        trial_id: "trial_001",
        spectral_norm: true,
        metrics: %{accuracy: 0.9}
      }

      assert {:ok, event} = MLEvents.emit_trial_complete(attrs)

      # Event should be valid for EventBus
      assert {:ok, _published_event} = Thunderline.Thunderflow.EventBus.publish_event(event)
    end
  end
end
