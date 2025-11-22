defmodule ThunderlineWeb.CerebrosJobsControllerTest do
  use ThunderlineWeb.ConnCase
  alias Thunderline.Thunderbolt.Resources.{CerebrosTrainingJob, TrainingDataset}
  alias Thunderline.Thunderbolt.Domain

  setup do
    # Create a test dataset
    {:ok, dataset} =
      TrainingDataset.create(
        %{
          name: "Test Dataset",
          description: "Test dataset for Cerebros",
          status: :frozen,
          corpus_path: "/tmp/test_corpus.jsonl"
        },
        domain: Domain
      )

    # Create a test file for corpus
    File.write!("/tmp/test_corpus.jsonl", ~s({"text": "test data"}\n))

    # Create a test job
    {:ok, job} =
      CerebrosTrainingJob.create(
        %{
          training_dataset_id: dataset.id,
          model_id: "gpt-4o-mini",
          hyperparameters: %{
            "n_epochs" => 3,
            "learning_rate_multiplier" => 1.0
          }
        },
        domain: Domain
      )

    on_exit(fn ->
      File.rm("/tmp/test_corpus.jsonl")
    end)

    %{dataset: dataset, job: job}
  end

  describe "poll/2" do
    test "returns queued job when available", %{conn: conn, job: job} do
      conn = get(conn, ~p"/api/jobs/poll")

      assert response = json_response(conn, 200)
      assert response["id"] == job.id
      assert response["status"] == "queued"
    end

    test "returns 204 when no jobs available", %{conn: conn, job: job} do
      # Mark job as running first
      {:ok, _} = CerebrosTrainingJob.start(job, domain: Domain)

      conn = get(conn, ~p"/api/jobs/poll")
      assert response(conn, 204)
    end
  end

  describe "update_status/2" do
    test "updates job to running status", %{conn: conn, job: job} do
      conn =
        patch(conn, ~p"/api/jobs/#{job.id}/status", %{
          "status" => "running"
        })

      assert json_response(conn, 200)

      # Verify job was updated
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.status == :running
      assert updated_job.started_at != nil
    end

    test "updates job to completed status", %{conn: conn, job: job} do
      # Start the job first
      {:ok, job} = CerebrosTrainingJob.start(job, domain: Domain)

      conn =
        patch(conn, ~p"/api/jobs/#{job.id}/status", %{
          "status" => "completed",
          "checkpoint_urls" => ["s3://bucket/checkpoint1.keras"],
          "metrics" => %{"loss" => 0.5}
        })

      assert json_response(conn, 200)

      # Verify job was updated
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.status == :completed
      assert updated_job.completed_at != nil
    end

    test "updates job to failed status with error message", %{conn: conn, job: job} do
      conn =
        patch(conn, ~p"/api/jobs/#{job.id}/status", %{
          "status" => "failed",
          "error_message" => "Training failed due to OOM"
        })

      assert json_response(conn, 200)

      # Verify job was updated
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.status == :failed
      assert updated_job.error_message == "Training failed due to OOM"
    end
  end

  describe "update_metrics/2" do
    test "updates job metrics", %{conn: conn, job: job} do
      conn =
        patch(conn, ~p"/api/jobs/#{job.id}/metrics", %{
          "metrics" => %{"loss" => 0.8, "perplexity" => 2.5},
          "phase" => 1
        })

      assert json_response(conn, 200)

      # Verify metrics were updated
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.metrics["loss"] == 0.8
      assert updated_job.metrics["perplexity"] == 2.5
      assert updated_job.phase == 1
    end

    test "merges new metrics with existing", %{conn: conn, job: job} do
      # Set initial metrics
      {:ok, job} =
        job
        |> Ash.Changeset.for_update(:update, %{metrics: %{"loss" => 1.0}})
        |> Ash.update(domain: Domain)

      conn =
        patch(conn, ~p"/api/jobs/#{job.id}/metrics", %{
          "metrics" => %{"perplexity" => 3.0}
        })

      assert json_response(conn, 200)

      # Verify both metrics exist
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert updated_job.metrics["loss"] == 1.0
      assert updated_job.metrics["perplexity"] == 3.0
    end
  end

  describe "add_checkpoint/2" do
    test "adds checkpoint URL to job", %{conn: conn, job: job} do
      checkpoint_url = "s3://bucket/checkpoint_phase1.keras"

      conn =
        post(conn, ~p"/api/jobs/#{job.id}/checkpoints", %{
          "checkpoint_url" => checkpoint_url,
          "phase" => 1
        })

      assert json_response(conn, 200)

      # Verify checkpoint was added
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert checkpoint_url in updated_job.checkpoint_urls
      assert updated_job.current_checkpoint_url == checkpoint_url
      assert updated_job.phase == 1
    end

    test "appends to existing checkpoints", %{conn: conn, job: job} do
      # Add first checkpoint
      {:ok, job} =
        CerebrosTrainingJob.update_checkpoint(job, 1, "s3://bucket/checkpoint1.keras",
          domain: Domain
        )

      # Add second checkpoint
      conn =
        post(conn, ~p"/api/jobs/#{job.id}/checkpoints", %{
          "checkpoint_url" => "s3://bucket/checkpoint2.keras",
          "phase" => 2
        })

      assert json_response(conn, 200)

      # Verify both checkpoints exist
      {:ok, updated_job} =
        CerebrosTrainingJob
        |> Ash.Query.filter(id == ^job.id)
        |> Ash.read_one(domain: Domain)

      assert length(updated_job.checkpoint_urls) == 2
      assert "s3://bucket/checkpoint1.keras" in updated_job.checkpoint_urls
      assert "s3://bucket/checkpoint2.keras" in updated_job.checkpoint_urls
    end
  end

  describe "get_corpus/2" do
    test "returns corpus path for dataset", %{conn: conn, dataset: dataset} do
      conn = get(conn, ~p"/api/datasets/#{dataset.id}/corpus")

      assert response = json_response(conn, 200)
      assert response["corpus_path"] == "/tmp/test_corpus.jsonl"
      assert response["dataset_id"] == dataset.id
      assert response["dataset_name"] == "Test Dataset"
    end

    test "returns error when corpus file missing", %{conn: conn} do
      {:ok, dataset} =
        TrainingDataset.create(
          %{
            name: "Missing Corpus",
            corpus_path: "/tmp/nonexistent.jsonl"
          },
          domain: Domain
        )

      conn = get(conn, ~p"/api/datasets/#{dataset.id}/corpus")

      assert response = json_response(conn, 500)
      assert response["error"] =~ "not found"
    end

    test "returns error when corpus not generated yet", %{conn: conn} do
      {:ok, dataset} =
        TrainingDataset.create(%{name: "No Corpus"}, domain: Domain)

      conn = get(conn, ~p"/api/datasets/#{dataset.id}/corpus")

      assert response = json_response(conn, 500)
      assert response["error"] =~ "not generated"
    end
  end
end
