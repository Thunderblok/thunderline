defmodule ThunderlineWeb.CerebrosIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the Cerebros training workflow.

  Tests the complete lifecycle:
  1. Dataset creation and corpus generation
  2. Training job queuing
  3. Cerebros service polling for jobs
  4. Job status updates (queued -> running -> completed)
  5. Metrics reporting during training
  6. Checkpoint upload and tracking
  7. Final model retrieval

  This simulates what the Python Cerebros service does.
  """
  use ThunderlineWeb.ConnCase
  alias Thunderline.Thunderbolt.Resources.{CerebrosTrainingJob, TrainingDataset}
  alias Thunderline.Thunderbolt.Domain
  require Ash.Query

  @moduletag :integration

  describe "Full Cerebros Training Workflow" do
    test "complete end-to-end training flow", %{conn: conn} do
      # Step 1: Create and freeze a training dataset
      {:ok, dataset} =
        TrainingDataset.create(
          %{
            name: "Shakespeare Corpus",
            description: "Complete works of Shakespeare for language modeling",
            status: :collecting
          },
          domain: Domain
        )

      # Simulate document uploads
      {:ok, dataset} =
        dataset
        |> Ash.Changeset.for_update(:update, %{
          stage_1_count: 10,
          stage_2_count: 15,
          stage_3_count: 8,
          stage_4_count: 5,
          total_chunks: 1500
        })
        |> Ash.update(domain: Domain)

      # Generate corpus file
      corpus_path = "/tmp/test_shakespeare_corpus.jsonl"

      corpus_data = [
        ~s({"text": "To be, or not to be, that is the question"}),
        ~s({"text": "All the world's a stage"}),
        ~s({"text": "The course of true love never did run smooth"})
      ]

      File.write!(corpus_path, Enum.join(corpus_data, "\n") <> "\n")

      {:ok, dataset} =
        dataset
        |> Ash.Changeset.for_update(:set_corpus_path, %{corpus_path: corpus_path})
        |> Ash.update(domain: Domain)

      # Freeze dataset for training
      {:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)
      assert dataset.status == :frozen

      # Step 2: Create a training job
      {:ok, job} =
        CerebrosTrainingJob.create(
          %{
            training_dataset_id: dataset.id,
            model_id: "gpt-4o-mini",
            hyperparameters: %{
              "n_epochs" => 3,
              "learning_rate_multiplier" => 1.8,
              "batch_size" => 64
            },
            metadata: %{
              "experiment" => "shakespeare_test",
              "notes" => "Integration test run"
            }
          },
          domain: Domain
        )

      assert job.status == :queued
      assert job.hyperparameters["n_epochs"] == 3

      # Step 3: Simulate Cerebros service polling for jobs
      conn = get(conn, ~p"/api/jobs/poll")
      assert %{"id" => job_id} = json_response(conn, 200)
      assert job_id == job.id

      # Verify we get the full job details
      response = json_response(conn, 200)
      assert response["status"] == "queued"
      assert response["model_id"] == "gpt-4o-mini"
      assert response["hyperparameters"]["n_epochs"] == 3

      # Step 4: Get corpus path for training
      conn = get(build_conn(), ~p"/api/datasets/#{dataset.id}/corpus")
      corpus_response = json_response(conn, 200)
      assert corpus_response["corpus_path"] == corpus_path
      assert corpus_response["dataset_name"] == "Shakespeare Corpus"
      assert File.exists?(corpus_response["corpus_path"])

      # Step 5: Start training (Cerebros service marks job as running)
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/status", %{
          "status" => "running"
        })

      assert json_response(conn, 200)

      # Verify job is now running
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.status == :running
      assert updated_job.started_at != nil

      # Step 6: Report metrics during training (Phase 1)
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/metrics", %{
          "metrics" => %{
            "loss" => 2.45,
            "perplexity" => 11.6,
            "epoch" => 1
          },
          "phase" => 1
        })

      assert json_response(conn, 200)

      # Step 7: Upload checkpoint after Phase 1
      checkpoint_1 = "s3://cerebros-models/shakespeare_phase1_#{job.id}.keras"

      conn =
        post(build_conn(), ~p"/api/jobs/#{job.id}/checkpoints", %{
          "checkpoint_url" => checkpoint_1,
          "phase" => 1
        })

      assert json_response(conn, 200)

      # Step 8: Report metrics for Phase 2
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/metrics", %{
          "metrics" => %{
            "loss" => 1.89,
            "perplexity" => 6.6,
            "epoch" => 2
          },
          "phase" => 2
        })

      assert json_response(conn, 200)

      # Step 9: Upload checkpoint after Phase 2
      checkpoint_2 = "s3://cerebros-models/shakespeare_phase2_#{job.id}.keras"

      conn =
        post(build_conn(), ~p"/api/jobs/#{job.id}/checkpoints", %{
          "checkpoint_url" => checkpoint_2,
          "phase" => 2
        })

      assert json_response(conn, 200)

      # Step 10: Final metrics for Phase 3
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/metrics", %{
          "metrics" => %{
            "loss" => 1.23,
            "perplexity" => 3.4,
            "epoch" => 3,
            "final_accuracy" => 0.87
          },
          "phase" => 3
        })

      assert json_response(conn, 200)

      # Step 11: Upload final checkpoint
      checkpoint_3 = "s3://cerebros-models/shakespeare_final_#{job.id}.keras"

      conn =
        post(build_conn(), ~p"/api/jobs/#{job.id}/checkpoints", %{
          "checkpoint_url" => checkpoint_3,
          "phase" => 3
        })

      assert json_response(conn, 200)

      # Step 12: Mark job as completed
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/status", %{
          "status" => "completed",
          "fine_tuned_model" => "ft-shakespeare-#{job.id}"
        })

      assert json_response(conn, 200)

      # Step 13: Verify final state
      {:ok, final_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert final_job.status == :completed
      assert final_job.started_at != nil
      assert final_job.completed_at != nil
      assert final_job.fine_tuned_model == "ft-shakespeare-#{job.id}"

      # Verify all checkpoints were recorded
      assert length(final_job.checkpoint_urls) == 3
      assert checkpoint_1 in final_job.checkpoint_urls
      assert checkpoint_2 in final_job.checkpoint_urls
      assert checkpoint_3 in final_job.checkpoint_urls
      assert final_job.current_checkpoint_url == checkpoint_3

      # Verify metrics were merged correctly
      assert final_job.metrics["loss"] == 1.23
      assert final_job.metrics["perplexity"] == 3.4
      assert final_job.metrics["epoch"] == 3
      assert final_job.metrics["final_accuracy"] == 0.87

      # Verify phase tracking
      assert final_job.phase == 3

      # Step 14: Verify no more jobs in queue
      conn = get(build_conn(), ~p"/api/jobs/poll")
      assert response(conn, 204)

      # Cleanup
      File.rm(corpus_path)
    end

    test "handles training failure gracefully", %{conn: conn} do
      # Create minimal dataset and job
      corpus_path = "/tmp/test_failure_corpus.jsonl"
      File.write!(corpus_path, ~s({"text": "test data"}\n))

      {:ok, dataset} =
        TrainingDataset.create(
          %{
            name: "Failure Test Dataset",
            corpus_path: corpus_path,
            status: :frozen
          },
          domain: Domain
        )

      {:ok, job} =
        CerebrosTrainingJob.create(
          %{
            training_dataset_id: dataset.id,
            model_id: "test-model"
          },
          domain: Domain
        )

      # Start the job
      conn = patch(conn, ~p"/api/jobs/#{job.id}/status", %{"status" => "running"})
      assert json_response(conn, 200)

      # Simulate a training failure
      conn =
        patch(build_conn(), ~p"/api/jobs/#{job.id}/status", %{
          "status" => "failed",
          "error_message" => "CUDA out of memory: Tried to allocate 2.5 GB"
        })

      assert json_response(conn, 200)

      # Verify failure was recorded
      {:ok, failed_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert failed_job.status == :failed
      assert failed_job.error_message == "CUDA out of memory: Tried to allocate 2.5 GB"
      assert failed_job.completed_at != nil

      # Cleanup
      File.rm(corpus_path)
    end

    test "handles multiple concurrent jobs", %{conn: conn} do
      # Create 3 datasets and jobs
      jobs =
        for i <- 1..3 do
          corpus_path = "/tmp/test_concurrent_#{i}.jsonl"
          File.write!(corpus_path, ~s({"text": "data #{i}"}\n))

          {:ok, dataset} =
            TrainingDataset.create(
              %{
                name: "Concurrent Dataset #{i}",
                corpus_path: corpus_path,
                status: :frozen
              },
              domain: Domain
            )

          {:ok, job} =
            CerebrosTrainingJob.create(
              %{
                training_dataset_id: dataset.id,
                model_id: "test-model-#{i}"
              },
              domain: Domain
            )

          {corpus_path, job}
        end

      # Poll should return first queued job
      conn = get(conn, ~p"/api/jobs/poll")
      response = json_response(conn, 200)
      first_job = elem(Enum.at(jobs, 0), 1)
      assert response["id"] == first_job.id

      # Start the first job
      conn =
        patch(build_conn(), ~p"/api/jobs/#{first_job.id}/status", %{
          "status" => "running"
        })

      assert json_response(conn, 200)

      # Poll again should return second job
      conn = get(build_conn(), ~p"/api/jobs/poll")
      response = json_response(conn, 200)
      second_job = elem(Enum.at(jobs, 1), 1)
      assert response["id"] == second_job.id

      # Complete first job
      conn =
        patch(build_conn(), ~p"/api/jobs/#{first_job.id}/status", %{
          "status" => "completed"
        })

      assert json_response(conn, 200)

      # Verify first job is completed
      {:ok, completed_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^first_job.id)
        |> Ash.read_one(domain: Domain)

      assert completed_job.status == :completed

      # Cleanup
      for {corpus_path, _job} <- jobs do
        File.rm(corpus_path)
      end
    end

    test "validates corpus file exists before training", %{conn: conn} do
      # Create dataset with non-existent corpus
      {:ok, dataset} =
        TrainingDataset.create(
          %{
            name: "Invalid Corpus Dataset",
            corpus_path: "/tmp/nonexistent_corpus.jsonl",
            status: :frozen
          },
          domain: Domain
        )

      # Try to get corpus - should fail
      conn = get(conn, ~p"/api/datasets/#{dataset.id}/corpus")
      response = json_response(conn, 500)
      assert response["error"] =~ "not found"
    end

    test "requires corpus path to be set", %{conn: conn} do
      # Create dataset without corpus
      {:ok, dataset} =
        TrainingDataset.create(
          %{
            name: "No Corpus Dataset",
            status: :frozen
          },
          domain: Domain
        )

      # Try to get corpus - should fail
      conn = get(conn, ~p"/api/datasets/#{dataset.id}/corpus")
      response = json_response(conn, 500)
      assert response["error"] =~ "not generated"
    end
  end

  describe "Cerebros Service Behavior Simulation" do
    test "service polls at regular intervals", %{conn: conn} do
      # No jobs available
      conn = get(conn, ~p"/api/jobs/poll")
      assert response(conn, 204)

      # Create a job
      corpus_path = "/tmp/test_polling.jsonl"
      File.write!(corpus_path, ~s({"text": "test"}\n))

      {:ok, dataset} =
        TrainingDataset.create(
          %{name: "Poll Test", corpus_path: corpus_path, status: :frozen},
          domain: Domain
        )

      {:ok, job} =
        CerebrosTrainingJob.create(
          %{training_dataset_id: dataset.id, model_id: "test"},
          domain: Domain
        )

      # Now polling returns a job
      conn = get(build_conn(), ~p"/api/jobs/poll")
      response = json_response(conn, 200)
      assert response["id"] == job.id

      # Start the job
      patch(build_conn(), ~p"/api/jobs/#{job.id}/status", %{"status" => "running"})

      # Polling again returns 204 (no more queued jobs)
      conn = get(build_conn(), ~p"/api/jobs/poll")
      assert response(conn, 204)

      # Cleanup
      File.rm(corpus_path)
    end

    test "service reports incremental progress", %{conn: conn} do
      corpus_path = "/tmp/test_progress.jsonl"
      File.write!(corpus_path, ~s({"text": "test"}\n))

      {:ok, dataset} =
        TrainingDataset.create(
          %{name: "Progress Test", corpus_path: corpus_path, status: :frozen},
          domain: Domain
        )

      {:ok, job} =
        CerebrosTrainingJob.create(
          %{training_dataset_id: dataset.id, model_id: "test"},
          domain: Domain
        )

      # Start job
      patch(conn, ~p"/api/jobs/#{job.id}/status", %{"status" => "running"})

      # Simulate progress updates
      progress_updates = [
        %{"loss" => 3.5, "epoch" => 0, "step" => 100},
        %{"loss" => 2.8, "epoch" => 0, "step" => 200},
        %{"loss" => 2.2, "epoch" => 1, "step" => 100},
        %{"loss" => 1.9, "epoch" => 1, "step" => 200}
      ]

      for {metrics, phase} <- Enum.with_index(progress_updates, 1) do
        conn =
          patch(build_conn(), ~p"/api/jobs/#{job.id}/metrics", %{
            "metrics" => metrics,
            "phase" => phase
          })

        assert json_response(conn, 200)
      end

      # Verify final metrics
      {:ok, final_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert final_job.metrics["loss"] == 1.9
      assert final_job.metrics["epoch"] == 1
      assert final_job.metrics["step"] == 200
      assert final_job.phase == 4

      # Cleanup
      File.rm(corpus_path)
    end
  end
end
