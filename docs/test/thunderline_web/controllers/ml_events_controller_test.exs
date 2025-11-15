defmodule ThunderlineWeb.MLEventsControllerTest do
  use ThunderlineWeb.ConnCase, async: true

  alias Thunderline.Thunderflow.EventBus

  @moduletag :capture_log

  describe "POST /api/events/ml - ml.trial.complete" do
    test "accepts valid trial complete event", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "550e8400-e29b-41d4-a716-446655440000",
        "trial_id" => "trial_007",
        "spectral_norm" => true,
        "mlflow_run_id" => "mlflow_abc123",
        "metrics" => %{
          "accuracy" => 0.95,
          "loss" => 0.05
        },
        "parameters" => %{
          "hidden_size" => 128,
          "num_layers" => 3
        },
        "duration_ms" => 45_000
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_id" => event_id,
               "event_name" => "ml.trial.complete",
               "correlation_id" => correlation_id,
               "message" => "Event accepted for processing"
             } = json_response(conn, 202)

      assert is_binary(event_id)
      assert is_binary(correlation_id)
    end

    test "accepts minimal trial complete event", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001",
        "spectral_norm" => false,
        "metrics" => %{"loss" => 0.1}
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{"success" => true, "event_name" => "ml.trial.complete"} =
               json_response(conn, 202)
    end

    test "returns 400 when missing required field", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run",
        "spectral_norm" => true
        # Missing trial_id and metrics
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "validation_failed",
               "details" => details
             } = json_response(conn, 400)

      assert "missing required field: trial_id" in details
      assert "missing required field: metrics" in details
    end

    test "returns 422 when metrics is not a map", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001",
        "spectral_norm" => true,
        "metrics" => "not_a_map"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "event_construction_failed"
             } = json_response(conn, 422)
    end
  end

  describe "POST /api/events/ml - ml.run.start" do
    test "accepts valid run start event", %{conn: conn} do
      payload = %{
        "event" => "ml.run.start",
        "model_run_id" => "550e8400-e29b-41d4-a716-446655440000",
        "requested_trials" => 10,
        "search_space_version" => 2,
        "max_params" => 2_000_000,
        "metadata" => %{"experiment" => "spectral_norm_ablation"}
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_name" => "ml.run.start"
             } = json_response(conn, 202)
    end

    test "validates positive integer for requested_trials", %{conn: conn} do
      payload = %{
        "event" => "ml.run.start",
        "model_run_id" => "test-run",
        "requested_trials" => 0,
        "search_space_version" => 1
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "event_construction_failed"
             } = json_response(conn, 422)
    end
  end

  describe "POST /api/events/ml - ml.run.stop" do
    test "accepts valid run stop event", %{conn: conn} do
      payload = %{
        "event" => "ml.run.stop",
        "model_run_id" => "test-run",
        "state" => "completed",
        "completed_trials" => 10,
        "best_metric" => 0.95,
        "best_trial_id" => "trial_007"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_name" => "ml.run.stop"
             } = json_response(conn, 202)
    end

    test "validates state must be valid", %{conn: conn} do
      payload = %{
        "event" => "ml.run.stop",
        "model_run_id" => "test-run",
        "state" => "invalid_state",
        "completed_trials" => 5
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "event_construction_failed"
             } = json_response(conn, 422)
    end

    test "accepts all valid states", %{conn: conn} do
      for state <- ["completed", "failed", "cancelled"] do
        payload = %{
          "event" => "ml.run.stop",
          "model_run_id" => "test-run-#{state}",
          "state" => state,
          "completed_trials" => 0
        }

        conn = post(conn, ~p"/api/events/ml", payload)

        assert %{"success" => true} = json_response(conn, 202)
      end
    end
  end

  describe "POST /api/events/ml - ml.run.metric" do
    test "accepts valid metric event", %{conn: conn} do
      payload = %{
        "event" => "ml.run.metric",
        "model_run_id" => "test-run",
        "trial_id" => "trial_003",
        "metric_name" => "val_accuracy",
        "metric_value" => 0.8765,
        "step" => 42,
        "spectral_norm" => true
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_name" => "ml.run.metric"
             } = json_response(conn, 202)
    end

    test "validates metric_value must be numeric", %{conn: conn} do
      payload = %{
        "event" => "ml.run.metric",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001",
        "metric_name" => "accuracy",
        "metric_value" => "not_a_number"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "event_construction_failed"
             } = json_response(conn, 422)
    end
  end

  describe "POST /api/events/ml - ml.trial.start" do
    test "accepts valid trial start event", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.start",
        "model_run_id" => "test-run",
        "trial_id" => "trial_003",
        "spectral_norm" => true,
        "mlflow_run_id" => "mlflow_abc",
        "parameters" => %{"hidden_size" => 128}
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_name" => "ml.trial.start"
             } = json_response(conn, 202)
    end

    test "requires spectral_norm field", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.start",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "validation_failed",
               "details" => details
             } = json_response(conn, 400)

      assert "missing required field: spectral_norm" in details
    end

    test "validates spectral_norm must be boolean", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.start",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001",
        "spectral_norm" => "not_boolean"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "event_construction_failed"
             } = json_response(conn, 422)
    end
  end

  describe "POST /api/events/ml - ml.trial.failed" do
    test "accepts valid trial failed event", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.failed",
        "model_run_id" => "test-run",
        "trial_id" => "trial_013",
        "error_message" => "CUDA out of memory",
        "error_type" => "OOM",
        "spectral_norm" => false
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_name" => "ml.trial.failed"
             } = json_response(conn, 202)
    end

    test "requires error_message", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.failed",
        "model_run_id" => "test-run",
        "trial_id" => "trial_001"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "validation_failed",
               "details" => details
             } = json_response(conn, 400)

      assert "missing required field: error_message" in details
    end
  end

  describe "POST /api/events/ml - error handling" do
    test "returns 400 when event type is missing", %{conn: conn} do
      payload = %{
        "model_run_id" => "test-run",
        "trial_id" => "trial_001"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "validation_failed",
               "details" => ["missing event field"]
             } = json_response(conn, 400)
    end

    test "returns 400 when event type is unknown", %{conn: conn} do
      payload = %{
        "event" => "ml.unknown.event",
        "model_run_id" => "test-run"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "unknown_event_type",
               "details" => details,
               "received" => "ml.unknown.event"
             } = json_response(conn, 400)

      assert details =~ "ml.run.start"
      assert details =~ "ml.trial.complete"
    end

    test "returns 400 when event is not a string", %{conn: conn} do
      payload = %{
        "event" => 123,
        "model_run_id" => "test-run"
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => false,
               "error" => "validation_failed",
               "details" => ["event must be a string"]
             } = json_response(conn, 400)
    end
  end

  describe "POST /api/events/ml - integration with EventBus" do
    test "published events can be retrieved from EventBus", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "integration-test",
        "trial_id" => "trial_999",
        "spectral_norm" => true,
        "metrics" => %{"accuracy" => 0.99}
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{
               "success" => true,
               "event_id" => event_id,
               "correlation_id" => correlation_id
             } = json_response(conn, 202)

      # Event should have been published to EventBus with proper structure
      assert is_binary(event_id)
      assert is_binary(correlation_id)
    end
  end

  describe "POST /api/events/ml - nested data structures" do
    test "handles nested metrics and parameters correctly", %{conn: conn} do
      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run",
        "trial_id" => "trial_nested",
        "spectral_norm" => true,
        "metrics" => %{
          "train" => %{"accuracy" => 0.98, "loss" => 0.02},
          "val" => %{"accuracy" => 0.95, "loss" => 0.05}
        },
        "parameters" => %{
          "architecture" => %{
            "hidden_sizes" => [128, 256, 128],
            "activation" => "relu"
          },
          "training" => %{
            "learning_rate" => 0.001,
            "batch_size" => 32
          }
        }
      }

      conn = post(conn, ~p"/api/events/ml", payload)

      assert %{"success" => true} = json_response(conn, 202)
    end
  end

  describe "POST /api/events/ml - telemetry" do
    test "emits telemetry on successful event", %{conn: conn} do
      test_pid = self()

      :telemetry.attach(
        "test-ml-events-success",
        [:thunderline, :api, :ml_events],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run",
        "trial_id" => "trial_telemetry",
        "spectral_norm" => true,
        "metrics" => %{"accuracy" => 0.95}
      }

      post(conn, ~p"/api/events/ml", payload)

      assert_receive {:telemetry, %{duration: duration, count: 1},
                      %{status: :success, event_type: "ml.trial.complete"}}

      assert is_integer(duration)

      :telemetry.detach("test-ml-events-success")
    end

    test "emits telemetry on validation error", %{conn: conn} do
      test_pid = self()

      :telemetry.attach(
        "test-ml-events-error",
        [:thunderline, :api, :ml_events],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_error, metadata})
        end,
        nil
      )

      payload = %{
        "event" => "ml.trial.complete",
        "model_run_id" => "test-run"
        # Missing required fields
      }

      post(conn, ~p"/api/events/ml", payload)

      assert_receive {:telemetry_error,
                      %{
                        status: :error,
                        event_type: "ml.trial.complete",
                        error_reason: :validation_failed
                      }}

      :telemetry.detach("test-ml-events-error")
    end
  end
end
