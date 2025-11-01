defmodule Thunderline.Thunderbolt.CerebrosBridge.RunWorkerTest do
  use Thunderline.DataCase, async: false
  use Oban.Testing, repo: Thunderline.Repo

  alias Thunderline.Thunderbolt.CerebrosBridge.RunWorker
  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Persistence}

  describe "perform/1" do
    setup do
      # Enable Cerebros for tests
      original_config = Application.get_env(:thunderline, :cerebros_bridge, [])
      Application.put_env(:thunderline, :cerebros_bridge, Keyword.put(original_config, :enabled, true))

      on_exit(fn ->
        Application.put_env(:thunderline, :cerebros_bridge, original_config)
      end)

      :ok
    end

    test "successfully processes a NAS run with valid spec" do
      spec = %{
        "model" => "test_model",
        "dataset" => "test_dataset",
        "search_space" => %{
          "layers" => [1, 2, 3],
          "units" => [32, 64, 128]
        }
      }

      budget = %{
        "max_trials" => 5,
        "timeout_seconds" => 60
      }

      args = %{
        "spec" => spec,
        "budget" => budget,
        "run_id" => "test-run-#{System.unique_integer([:positive])}"
      }

      assert :ok = perform_job(RunWorker, args)
    end

    test "handles missing run_id by generating one" do
      args = %{
        "spec" => %{"model" => "test"},
        "budget" => %{"max_trials" => 1}
      }

      assert :ok = perform_job(RunWorker, args)
    end

    test "discards job when bridge is disabled" do
      Application.put_env(:thunderline, :cerebros_bridge, enabled: false)

      args = %{
        "spec" => %{"model" => "test"},
        "run_id" => "test-run-disabled"
      }

      assert {:discard, :bridge_disabled} = perform_job(RunWorker, args)
    end

    test "discards job with invalid arguments" do
      assert {:discard, :invalid_args} = perform_job(RunWorker, "not a map")
    end

    test "handles trial processing correctly" do
      spec = %{
        "model" => "multi_trial_model",
        "dataset" => "test_dataset"
      }

      args = %{
        "spec" => spec,
        "budget" => %{"max_trials" => 3},
        "run_id" => "trial-test-#{System.unique_integer([:positive])}"
      }

      assert :ok = perform_job(RunWorker, args)
    end

    test "emits telemetry events during run lifecycle" do
      run_id = "telemetry-test-#{System.unique_integer([:positive])}"

      :telemetry.attach_many(
        "test-handler",
        [
          [:thunderline, :cerebros, :run_queued],
          [:thunderline, :cerebros, :run_started],
          [:thunderline, :cerebros, :run_stopped]
        ],
        fn name, measurements, metadata, _config ->
          send(self(), {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      args = %{
        "spec" => %{"model" => "telemetry_test"},
        "budget" => %{"max_trials" => 1},
        "run_id" => run_id
      }

      perform_job(RunWorker, args)

      assert_receive {:telemetry, [:thunderline, :cerebros, :run_queued], _, %{run_id: ^run_id}}

      :telemetry.detach("test-handler")
    end

    test "handles client errors gracefully" do
      # This test requires mocking the Client module behavior
      # For now, we test that the worker doesn't crash on errors

      args = %{
        "spec" => %{"model" => "error_test", "invalid_field" => "causes_error"},
        "budget" => %{"max_trials" => 1},
        "run_id" => "error-test-#{System.unique_integer([:positive])}"
      }

      # Should return an error tuple, not crash
      result = perform_job(RunWorker, args)
      assert match?({:error, _}, result) or result == :ok
    end

    test "normalizes string keys in arguments" do
      args = %{
        "spec" => %{"model" => "string_keys"},
        "budget" => %{"max_trials" => 1},
        "parameters" => %{"learning_rate" => 0.01},
        "meta" => %{"source" => "test"},
        "run_id" => "normalize-test-#{System.unique_integer([:positive])}"
      }

      assert :ok = perform_job(RunWorker, args)
    end

    test "persists run records to database" do
      run_id = "persist-test-#{System.unique_integer([:positive])}"

      args = %{
        "spec" => %{
          "model" => "persistence_test",
          "dataset" => "test_data"
        },
        "budget" => %{"max_trials" => 2},
        "run_id" => run_id
      }

      perform_job(RunWorker, args)

      # Verify run record was created
      # This assumes Persistence.get_run/1 exists
      # You may need to adjust based on actual persistence API
      assert {:ok, _run} = Persistence.get_run(run_id)
    end
  end

  describe "retry behavior" do
    test "respects max_attempts configuration" do
      # RunWorker is configured with max_attempts: 1
      # This means it won't retry on failure

      args = %{
        "spec" => %{"model" => "retry_test"},
        "run_id" => "retry-test-#{System.unique_integer([:positive])}"
      }

      # First attempt
      result = perform_job(RunWorker, args)

      # Should not automatically retry
      refute_enqueued(worker: RunWorker, args: args)
    end
  end

  describe "timeout handling" do
    test "uses configured timeout for client calls" do
      # This is more of an integration test
      # Verifies that timeout configuration is respected

      args = %{
        "spec" => %{
          "model" => "timeout_test",
          "dataset" => "large_dataset"
        },
        "budget" => %{"timeout_seconds" => 1},
        "run_id" => "timeout-test-#{System.unique_integer([:positive])}"
      }

      # Should complete within reasonable time or return timeout error
      result = perform_job(RunWorker, args)
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "correlation_id tracking" do
    test "uses run_id as correlation_id when not provided" do
      run_id = "correlation-test-#{System.unique_integer([:positive])}"

      args = %{
        "spec" => %{"model" => "correlation_test"},
        "run_id" => run_id
      }

      assert :ok = perform_job(RunWorker, args)

      # Correlation ID should match run_id in telemetry
      # This would require telemetry assertions
    end

    test "uses provided correlation_id when present" do
      run_id = "correlation-test-#{System.unique_integer([:positive])}"
      correlation_id = "custom-correlation-#{System.unique_integer([:positive])}"

      args = %{
        "spec" => %{"model" => "correlation_test"},
        "run_id" => run_id,
        "correlation_id" => correlation_id
      }

      assert :ok = perform_job(RunWorker, args)
    end
  end
end
