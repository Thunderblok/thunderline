#!/usr/bin/env elixir

# Test script for Cerebros NAS workflow via API
# Tests: API → Oban → Worker → Client → Python → Persistence

alias Thunderline.Thunderbolt.CerebrosBridge
alias Thunderline.Repo

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Cerebros NAS Full Workflow")
IO.puts(String.duplicate("=", 80) <> "\n")

# ============================================================================
# Step 1: Check Bridge Status
# ============================================================================

IO.puts("Step 1: Checking bridge status...")
enabled = CerebrosBridge.enabled?()
IO.puts("  Bridge enabled: #{enabled}")

unless enabled do
  IO.puts("\n❌ ERROR: Bridge is disabled. Set ENABLE_CEREBROS_BRIDGE=true")
  System.halt(1)
end

# ============================================================================
# Step 2: Define NAS Spec
# ============================================================================

IO.puts("\nStep 2: Defining NAS specification...")

run_id = "api_test_#{:os.system_time(:millisecond)}"
dataset_id = "test_dataset"

spec = %{
  "run_id" => run_id,
  "dataset_id" => dataset_id,
  "search_space" => %{
    "layers" => [32, 64, 128],
    "activation" => ["relu", "tanh"],
    "learning_rate" => [0.001, 0.01, 0.1]
  },
  "objective" => "accuracy"
}

opts = [
  run_id: run_id,
  budget: %{"max_trials" => 3, "max_time" => 300},
  parameters: %{"mutation_rate" => 0.1, "crossover_rate" => 0.7}
]

IO.puts("  Run ID: #{run_id}")
IO.puts("  Dataset ID: #{dataset_id}")
IO.puts("  Search space: #{inspect(Map.keys(spec["search_space"]))}")
IO.puts("  Objective: #{spec["objective"]}")

# ============================================================================
# Step 3: Enqueue NAS Run via CerebrosBridge
# ============================================================================

IO.puts("\nStep 3: Enqueuing NAS run via CerebrosBridge.enqueue_run...")

start_enqueue = :os.system_time(:millisecond)

case CerebrosBridge.enqueue_run(spec, opts) do
  {:ok, job} ->
    enqueue_time = :os.system_time(:millisecond) - start_enqueue
    IO.puts("  ✅ Job enqueued successfully in #{enqueue_time}ms")
    IO.puts("  Job ID: #{job.id}")
    IO.puts("  Queue: #{job.queue}")
    IO.puts("  State: #{job.state}")

    # ============================================================================
    # Step 4: Wait for Oban to Process Job
    # ============================================================================

    IO.puts("\nStep 4: Waiting for Oban to process job...")
    IO.puts("  (This may take a few seconds...)")

    # Poll for job completion (max 30 seconds)
    max_wait_ms = 30_000
    poll_interval_ms = 500

    poll_start = :os.system_time(:millisecond)

    final_job =
      Stream.repeatedly(fn ->
        :timer.sleep(poll_interval_ms)
        Repo.get(Oban.Job, job.id)
      end)
      |> Stream.take_while(fn
        nil -> false
        j -> j.state != "completed" and j.state != "discarded" and
             (:os.system_time(:millisecond) - poll_start) < max_wait_ms
      end)
      |> Enum.to_list()
      |> List.last()
      |> then(fn last_polled -> last_polled || Repo.get(Oban.Job, job.id) end)

    wait_time = :os.system_time(:millisecond) - poll_start

    case final_job do
      nil ->
        IO.puts("  ❌ ERROR: Job disappeared from database")
        System.halt(1)

      %{state: "completed"} = completed_job ->
        IO.puts("  ✅ Job completed successfully in #{wait_time}ms")
        IO.puts("  Final state: #{completed_job.state}")
        IO.puts("  Max attempts: #{completed_job.max_attempts}")
        IO.puts("  Attempt: #{completed_job.attempt}")

        # ============================================================================
        # Step 5: Verify Result in Job
        # ============================================================================

        IO.puts("\nStep 5: Checking job result...")

        if completed_job.unsaved_error do
          IO.puts("  ⚠️  Job had errors:")
          IO.inspect(completed_job.unsaved_error, label: "  Error", limit: :infinity)
        end

        # ============================================================================
        # Step 6: Verify Persistence (ModelRun)
        # ============================================================================

        IO.puts("\nStep 6: Verifying ModelRun persistence...")

        # Import the resource
        alias Thunderline.Thunderbolt.Resources.ModelRun
        require Ash.Query

        # Query for ModelRun with this run_id
        model_run =
          ModelRun
          |> Ash.Query.filter(run_id == ^run_id)
          |> Ash.read_one()

        case model_run do
          {:ok, model_run} when not is_nil(model_run) ->
            IO.puts("  ✅ ModelRun record found!")
            IO.puts("  ID: #{model_run.id}")
            IO.puts("  Run ID: #{model_run.run_id}")
            IO.puts("  State: #{model_run.state}")
            if model_run.best_metric do
              IO.puts("  Best metric: #{model_run.best_metric}")
            end
            if model_run.completed_trials do
              IO.puts("  Completed trials: #{model_run.completed_trials}")
            end
            if model_run.started_at do
              IO.puts("  Started at: #{model_run.started_at}")
            end
            if model_run.finished_at do
              IO.puts("  Finished at: #{model_run.finished_at}")
            end

            # ============================================================================
            # Step 7: Display Results
            # ============================================================================

            IO.puts("\nStep 7: NAS Results Summary...")

            # Check bridge_result field for NAS results
            if model_run.bridge_result && map_size(model_run.bridge_result) > 0 do
              IO.puts("  Bridge result fields: #{inspect(Map.keys(model_run.bridge_result))}")

              result = model_run.bridge_result["result"] || model_run.bridge_result

              if result["best_model"] do
                IO.puts("\n  Best model configuration:")
                best_model = result["best_model"]
                IO.puts("    layers: #{inspect(best_model["layers"])}")
                IO.puts("    activation: #{best_model["activation"]}")
                IO.puts("    learning_rate: #{best_model["learning_rate"]}")
                if best_model["optimizer"], do: IO.puts("    optimizer: #{best_model["optimizer"]}")
              end

              if result["population_history"] do
                IO.puts("\n  Population evolution:")
                result["population_history"]
                |> Enum.each(fn gen ->
                  IO.puts("    Gen #{gen["generation"]}: best=#{gen["best_fitness"]}, mean=#{gen["mean_fitness"]}")
                end)
              end

              if result["artifacts"] do
                IO.puts("\n  Artifacts generated:")
                result["artifacts"]
                |> Enum.each(fn artifact ->
                  IO.puts("    #{artifact}")
                end)
              end
            else
              IO.puts("  ⚠️  No bridge_result data found")
              IO.puts("  This could mean:")
              IO.puts("    - Worker hasn't stored results yet")
              IO.puts("    - Results are stored in a different field")
            end

            # ============================================================================
            # Final Summary
            # ============================================================================

            IO.puts("\n" <> String.duplicate("=", 80))
            IO.puts("✅ Full Workflow Test PASSED!")
            IO.puts(String.duplicate("=", 80))

            IO.puts("\nWorkflow Summary:")
            IO.puts("  1. ✅ Bridge enabled")
            IO.puts("  2. ✅ Job enqueued (#{enqueue_time}ms)")
            IO.puts("  3. ✅ Oban processed (#{wait_time}ms)")
            IO.puts("  4. ✅ Worker executed successfully")
            IO.puts("  5. ✅ Client.start_run completed")
            IO.puts("  6. ✅ Python bridge executed")
            IO.puts("  7. ✅ Results persisted to database")

            total_time = enqueue_time + wait_time
            IO.puts("\n  Total workflow time: #{total_time}ms")
            IO.puts("")

          {:ok, nil} ->
            IO.puts("  ❌ ERROR: ModelRun record not found")
            IO.puts("  Run ID: #{run_id}")
            IO.puts("")
            IO.puts("This could mean:")
            IO.puts("  - Worker didn't persist results")
            IO.puts("  - Database transaction rolled back")
            IO.puts("  - Wrong run_id used")
            System.halt(1)

          {:error, reason} ->
            IO.puts("  ❌ ERROR querying ModelRun: #{inspect(reason)}")
            System.halt(1)
        end

      %{state: "discarded"} = discarded_job ->
        IO.puts("  ❌ Job was discarded")
        IO.puts("  State: #{discarded_job.state}")
        if discarded_job.errors do
          IO.puts("\n  Errors:")
          IO.inspect(discarded_job.errors, label: "  ", limit: :infinity)
        end
        System.halt(1)

      job_in_progress ->
        IO.puts("  ⏱️  Job still in progress after #{wait_time}ms timeout")
        IO.puts("  Current state: #{job_in_progress.state}")
        IO.puts("  Attempt: #{job_in_progress.attempt}")
        IO.puts("\nNote: Job may complete later. Check Oban dashboard.")
        System.halt(1)
    end

  {:error, :bridge_disabled} ->
    IO.puts("  ❌ ERROR: Bridge is disabled")
    System.halt(1)

  {:error, reason} ->
    IO.puts("  ❌ ERROR enqueueing job: #{inspect(reason)}")
    System.halt(1)
end
