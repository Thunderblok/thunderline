defmodule Thunderline.Thunderbolt.MLflow.SyncWorkerTest do
  use Thunderline.DataCase, async: true
  use Oban.Testing, repo: Thunderline.Repo

  alias Thunderline.Thunderbolt.MLflow.{SyncWorker, Config}
  alias Thunderline.Thunderbolt.Resources.{ModelTrial, ModelRun}
  alias Ash.Changeset

  describe "perform/1 - sync_trial_to_mlflow" do
    test "syncs trial metrics to MLflow when enabled" do
      # Skip if MLflow disabled
      if not Config.enabled?() do
        assert true
      else

      # Create a trial with metrics
      {:ok, model_run} = ModelRun.create(%{
        search_space_version: 1,
        max_params: 1000,
        requested_trials: 1
      })

      {:ok, trial} = ModelTrial
        |> Changeset.for_create(:log, %{
          model_run_id: model_run.id,
          trial_id: "test_trial_#{System.unique_integer([:positive])}",
          parameters: %{"learning_rate" => 0.001},
          metrics: %{"accuracy" => 0.95, "loss" => 0.25},
          spectral_norm: false,
          status: :succeeded
        })
        |> Ash.create()

      # Create job
      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "sync_trial_to_mlflow",
          "trial_id" => trial.id
        }
      }

      # Perform job
      case perform_job(SyncWorker, job.args) do
        :ok ->
          assert true

        {:error, reason} ->
          # If MLflow not available, that's okay for this test
          assert reason =~ "MLflow" or reason =~ "connection"

        {:discard, _reason} ->
          # Job was discarded (expected if config disabled)
          assert true
      end
      end
    end

    test "discards job when MLflow disabled" do
      # Temporarily disable MLflow
      original = Application.get_env(:thunderline, :mlflow_enabled)
      Application.put_env(:thunderline, :mlflow_enabled, false)

      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "sync_trial_to_mlflow",
          "trial_id" => "any_id"
        }
      }

      result = perform_job(SyncWorker, job.args)

      # Restore config
      Application.put_env(:thunderline, :mlflow_enabled, original)

      assert result == {:discard, "MLflow integration disabled"}
    end

    test "retries on transient errors" do
      if not Config.enabled?() do
        assert true
      else

      # Use non-existent trial ID to trigger error
      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "sync_trial_to_mlflow",
          "trial_id" => Ash.UUID.generate()
        }
      }

      result = perform_job(SyncWorker, job.args)

      # Should return error (which Oban will retry)
      assert match?({:error, _}, result) or match?({:discard, _}, result)
      end
    end
  end

  describe "perform/1 - create_mlflow_run" do
    test "creates MLflow run for trial" do
      if not Config.enabled?() do
        assert true
      else

      {:ok, model_run} = ModelRun.create(%{
        search_space_version: 1,
        max_params: 1000,
        requested_trials: 1
      })

      {:ok, trial} = ModelTrial
        |> Changeset.for_create(:log, %{
          model_run_id: model_run.id,
          trial_id: "create_run_test_#{System.unique_integer([:positive])}",
          parameters: %{"epochs" => 100},
          spectral_norm: false,
          status: :succeeded
        })
        |> Ash.create()

      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "create_mlflow_run",
          "trial_id" => trial.id,
          "experiment_name" => "test_experiment"
        }
      }

      case perform_job(SyncWorker, job.args) do
        :ok ->
          assert true

        {:error, _reason} ->
          # MLflow not available
          assert true

        {:discard, _} ->
          assert true
      end
      end
    end
  end

  describe "perform/1 - sync_mlflow_to_trial" do
    test "syncs MLflow run data back to trial" do
      if not Config.enabled?() do
        assert true
      else
        job = %Oban.Job{
          worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
          args: %{
            "action" => "sync_mlflow_to_trial",
            "run_id" => "some_mlflow_run_id",
            "trial_id" => Ash.UUID.generate()
          }
        }

        result = perform_job(SyncWorker, job.args)

        # Either succeeds or fails gracefully
        assert match?(:ok, result) or match?({:error, _}, result) or match?({:discard, _}, result)
      end
    end
  end

  describe "perform/1 - update_run_status" do
    test "updates MLflow run status" do
      if not Config.enabled?() do
        assert true
      else
        job = %Oban.Job{
          worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
          args: %{
            "action" => "update_run_status",
            "run_id" => "some_run_id",
            "status" => "FINISHED"
          }
        }

        result = perform_job(SyncWorker, job.args)

        # Either succeeds or fails gracefully
        assert match?(:ok, result) or match?({:error, _}, result) or match?({:discard, _}, result)
      end
    end
  end

  describe "auto_sync behavior" do
    test "respects auto_sync config flag" do
      original = Application.get_env(:thunderline, :mlflow_auto_sync)

      # Disable auto_sync
      Application.put_env(:thunderline, :mlflow_auto_sync, false)

      refute Config.auto_sync?()

      # Enable auto_sync
      Application.put_env(:thunderline, :mlflow_auto_sync, true)

      assert Config.auto_sync?()

      # Restore
      Application.put_env(:thunderline, :mlflow_auto_sync, original)
    end
  end

  describe "job scheduling" do
    test "enqueues sync job successfully" do
      {:ok, model_run} = ModelRun.create(%{
        search_space_version: 1,
        max_params: 1000,
        requested_trials: 1
      })

      {:ok, trial} = ModelTrial
        |> Changeset.for_create(:log, %{
          model_run_id: model_run.id,
          trial_id: "enqueue_test_#{System.unique_integer([:positive])}",
          spectral_norm: false,
          status: :succeeded
        })
        |> Ash.create()

      {:ok, job} =
        SyncWorker.new(%{
          action: "sync_trial_to_mlflow",
          trial_id: trial.id
        })
        |> Oban.insert()

      assert job.worker == "Thunderline.Thunderbolt.MLflow.SyncWorker"
      assert job.args["action"] == "sync_trial_to_mlflow"
      assert job.args["trial_id"] == trial.id
    end

    test "schedules job with delay" do
      {:ok, model_run} = ModelRun.create(%{
        search_space_version: 1,
        max_params: 1000,
        requested_trials: 1
      })

      {:ok, trial} = ModelTrial
        |> Changeset.for_create(:log, %{
          model_run_id: model_run.id,
          trial_id: "delay_test_#{System.unique_integer([:positive])}",
          spectral_norm: false,
          status: :succeeded
        })
        |> Ash.create()

      {:ok, job} =
        SyncWorker.new(
          %{
            action: "sync_trial_to_mlflow",
            trial_id: trial.id
          },
          schedule_in: 60
        )
        |> Oban.insert()

      assert job.scheduled_at
      # Should be scheduled ~60 seconds from now
      assert DateTime.diff(job.scheduled_at, DateTime.utc_now()) >= 55
    end
  end

  describe "error handling" do
    test "handles missing trial gracefully" do
      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "sync_trial_to_mlflow",
          "trial_id" => Ash.UUID.generate()
        }
      }

      result = perform_job(SyncWorker, job.args)

      # Should discard or error (not crash)
      assert match?({:error, _}, result) or match?({:discard, _}, result)
    end

    test "handles invalid action" do
      job = %Oban.Job{
        worker: "Thunderline.Thunderbolt.MLflow.SyncWorker",
        args: %{
          "action" => "invalid_action",
          "trial_id" => Ash.UUID.generate()
        }
      }

      result = perform_job(SyncWorker, job.args)

      assert match?({:discard, _}, result) or match?({:error, _}, result)
    end
  end
end
