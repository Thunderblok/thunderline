#!/usr/bin/env elixir

# Manual Cerebros Integration Test Script
# Run with: elixir --cookie $(cat ~/.erlang.cookie) --name test@127.0.0.1 --remsh thunderline@127.0.0.1 scripts/manual_cerebros_test.exs

IO.puts("\n========================================")
IO.puts("Cerebros Integration Manual Test")
IO.puts("========================================\n")

alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain
require Ash.Query

# Step 1: Create Dataset
IO.puts("Step 1: Creating training dataset...")

{:ok, dataset} = TrainingDataset.create(%{
  name: "Manual Test - Shakespeare Corpus",
  description: "Integration test corpus for Cerebros workflow",
  status: :collecting
}, domain: Domain)

IO.puts("✓ Dataset created: #{dataset.id}")

# Step 2: Simulate document uploads
IO.puts("\nStep 2: Simulating document uploads...")

{:ok, dataset} = dataset
  |> Ash.Changeset.for_update(:update, %{
    stage_1_count: 10,
    stage_2_count: 15,
    stage_3_count: 8,
    stage_4_count: 5,
    total_chunks: 1500
  })
  |> Ash.update(domain: Domain)

IO.puts("✓ Document counts updated")

# Step 3: Freeze dataset
IO.puts("\nStep 3: Freezing dataset...")

{:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)

IO.puts("✓ Dataset frozen - Status: #{dataset.status}")

# Step 4: Create corpus file
IO.puts("\nStep 4: Generating corpus file...")

corpus_path = "/tmp/cerebros_test_corpus_#{System.system_time(:second)}.jsonl"

corpus_content = """
{"text": "To be, or not to be, that is the question: Whether 'tis nobler in the mind to suffer"}
{"text": "All the world's a stage, and all the men and women merely players"}
{"text": "Romeo, Romeo, wherefore art thou Romeo? Deny thy father and refuse thy name"}
{"text": "Now is the winter of our discontent made glorious summer by this sun of York"}
{"text": "If music be the food of love, play on; Give me excess of it"}
{"text": "The course of true love never did run smooth"}
{"text": "Shall I compare thee to a summer's day? Thou art more lovely and more temperate"}
{"text": "Friends, Romans, countrymen, lend me your ears; I come to bury Caesar, not to praise him"}
{"text": "Double, double toil and trouble; Fire burn, and caldron bubble"}
{"text": "Out, out, brief candle! Life's but a walking shadow"}
"""

File.write!(corpus_path, corpus_content)

IO.puts("✓ Corpus file created: #{corpus_path}")
IO.puts("  Lines: #{String.split(corpus_content, "\n") |> Enum.reject(&(&1 == "")) |> length()}")

# Step 5: Set corpus path
IO.puts("\nStep 5: Setting corpus path on dataset...")

{:ok, dataset} = TrainingDataset.set_corpus_path(dataset, corpus_path, domain: Domain)

IO.puts("✓ Corpus path set: #{dataset.corpus_path}")

# Step 6: Create training job
IO.puts("\nStep 6: Creating training job...")

{:ok, job} = CerebrosTrainingJob.create(%{
  training_dataset_id: dataset.id,
  model_id: "gpt-4o-mini",
  hyperparameters: %{
    "n_epochs" => 3,
    "batch_size" => 32,
    "learning_rate" => 0.0001,
    "optimizer" => "adam"
  }
}, domain: Domain)

IO.puts("✓ Training job created!")
IO.puts("  Job ID: #{job.id}")
IO.puts("  Status: #{job.status}")
IO.puts("  Dataset ID: #{job.training_dataset_id}")
IO.puts("  Model: #{job.model_id}")

# Step 7: Verify job is queryable
IO.puts("\nStep 7: Verifying job appears in queue...")

queued_jobs = CerebrosTrainingJob.list(
  query: Ash.Query.filter(CerebrosTrainingJob, status == :queued),
  domain: Domain
)

IO.puts("✓ Queued jobs found: #{length(queued_jobs)}")

if length(queued_jobs) > 0 do
  IO.puts("\nQueued Job Details:")
  job_from_list = List.first(queued_jobs)
  IO.puts("  ID: #{job_from_list.id}")
  IO.puts("  Status: #{job_from_list.status}")
  IO.puts("  Model: #{job_from_list.model_id}")
end

# Step 8: Print API test commands
IO.puts("\n========================================")
IO.puts("Next: Test API Endpoints")
IO.puts("========================================\n")

IO.puts("Run these curl commands in a separate terminal:\n")

IO.puts("# 1. Poll for jobs (should return the job we just created)")
IO.puts("curl -s http://localhost:5001/api/jobs/poll | jq\n")

IO.puts("# 2. Get corpus data")
IO.puts("curl -s http://localhost:5001/api/datasets/#{dataset.id}/corpus | jq\n")

IO.puts("# 3. Start training")
IO.puts("curl -X PATCH http://localhost:5001/api/jobs/#{job.id}/status \\")
IO.puts("  -H 'Content-Type: application/json' \\")
IO.puts("  -d '{\"status\": \"running\"}' | jq\n")

IO.puts("# 4. Report metrics (Phase 1)")
IO.puts("curl -X PATCH http://localhost:5001/api/jobs/#{job.id}/metrics \\")
IO.puts("  -H 'Content-Type: application/json' \\")
IO.puts("  -d '{\"metrics\": {\"loss\": 2.5, \"accuracy\": 0.45}, \"phase\": 1}' | jq\n")

IO.puts("# 5. Upload checkpoint (Phase 1)")
IO.puts("curl -X POST http://localhost:5001/api/jobs/#{job.id}/checkpoints \\")
IO.puts("  -H 'Content-Type: application/json' \\")
IO.puts("  -d '{\"checkpoint_url\": \"s3://models/shakespeare-p1.keras\", \"phase\": 1}' | jq\n")

IO.puts("# 6. Complete training")
IO.puts("curl -X PATCH http://localhost:5001/api/jobs/#{job.id}/status \\")
IO.puts("  -H 'Content-Type: application/json' \\")
IO.puts("  -d '{\"status\": \"completed\", \"final_model_id\": \"shakespeare-v1\"}' | jq\n")

IO.puts("========================================")
IO.puts("Test Data Summary")
IO.puts("========================================")
IO.puts("Dataset ID: #{dataset.id}")
IO.puts("Job ID: #{job.id}")
IO.puts("Corpus Path: #{corpus_path}")
IO.puts("Status: READY FOR API TESTING")
IO.puts("========================================\n")
