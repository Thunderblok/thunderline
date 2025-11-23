#!/usr/bin/env elixir
#
# Script to process all queued Cerebros training jobs
# Tests parallel execution with Snex GIL-free runtime
#
# Usage:
#   Run in IEx with server running:
#   IEx.Helpers.c("scripts/process_queued_jobs.exs")
#

require Ash.Query
import Ash.Expr

alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
alias Thunderline.Thunderbolt.CerebrosBridge.RunSaga
require Logger

defmodule QueuedJobsProcessor do
  @moduledoc """
  Process all queued Cerebros training jobs sequentially or in parallel
  """

  def list_queued_jobs do
    CerebrosTrainingJob
    |> Ash.Query.filter(expr(status == :queued))
    |> Ash.read!()
  end

  def process_job_sync(job) do
    Logger.info("Processing job #{job.id} - #{job.metadata["experiment_name"]}")

    spec = %{
      model_id: job.model_id,
      dataset_id: job.training_dataset_id,
      hyperparameters: job.hyperparameters
    }

    case RunSaga.run(spec) do
      {:ok, result} ->
        Logger.info("Job #{job.id} completed successfully")
        Logger.info("  Best fitness: #{result["best_metric"]}")
        Logger.info("  Trials: #{result["completed_trials"]}")
        {:ok, job.id, result}

      {:error, reason} ->
        Logger.error("Job #{job.id} failed: #{inspect(reason)}")
        {:error, job.id, reason}
    end
  end

  def process_all_sequentially do
    jobs = list_queued_jobs()

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Found #{length(jobs)} queued jobs")
    IO.puts(String.duplicate("=", 80) <> "\n")

    start_time = System.monotonic_time(:millisecond)

    results = Enum.map(jobs, fn job ->
      job_start = System.monotonic_time(:millisecond)
      result = process_job_sync(job)
      job_end = System.monotonic_time(:millisecond)

      {result, job_end - job_start}
    end)

    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time

    print_results(results, total_time, "Sequential")
    results
  end

  def process_all_parallel(max_concurrency \\ 3) do
    jobs = list_queued_jobs()

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Found #{length(jobs)} queued jobs")
    IO.puts("Processing with max concurrency: #{max_concurrency}")
    IO.puts(String.duplicate("=", 80) <> "\n")

    start_time = System.monotonic_time(:millisecond)

    results =
      jobs
      |> Task.async_stream(
        fn job ->
          job_start = System.monotonic_time(:millisecond)
          result = process_job_sync(job)
          job_end = System.monotonic_time(:millisecond)

          {result, job_end - job_start}
        end,
        max_concurrency: max_concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {{:error, :unknown, reason}, 0}
      end)

    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time

    print_results(results, total_time, "Parallel (concurrency=#{max_concurrency})")
    results
  end

  defp print_results(results, total_time, mode) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Results - #{mode}")
    IO.puts(String.duplicate("=", 80))

    successful = Enum.count(results, fn {{status, _, _}, _} -> status == :ok end)
    failed = Enum.count(results, fn {{status, _, _}, _} -> status == :error end)

    job_times = Enum.map(results, fn {_, time} -> time end)
    avg_job_time = if length(job_times) > 0, do: Enum.sum(job_times) / length(job_times), else: 0

    IO.puts("Total jobs: #{length(results)}")
    IO.puts("Successful: #{successful}")
    IO.puts("Failed: #{failed}")
    IO.puts("Total time: #{total_time}ms")
    IO.puts("Average job time: #{Float.round(avg_job_time, 2)}ms")
    IO.puts("Throughput: #{Float.round(length(results) / (total_time / 1000), 2)} jobs/sec")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  def compare_execution_modes do
    IO.puts("\n" <> String.duplicate("#", 80))
    IO.puts("# GIL-Free Parallel Execution Comparison Test")
    IO.puts(String.duplicate("#", 80) <> "\n")

    jobs = list_queued_jobs()

    if length(jobs) == 0 do
      IO.puts("⚠️  No queued jobs found. Cannot run comparison test.")
      :no_jobs
    else
      IO.puts("Testing with #{length(jobs)} jobs...\n")

      # Sequential baseline
      IO.puts("🔹 Running SEQUENTIAL execution...")
      seq_results = process_all_sequentially()

      # Give system time to stabilize
      Process.sleep(2000)

      # Parallel execution
      IO.puts("\n🔹 Running PARALLEL execution (concurrency=3)...")
      par_results = process_all_parallel(3)

      IO.puts("\n" <> String.duplicate("#", 80))
      IO.puts("# Comparison Complete")
      IO.puts(String.duplicate("#", 80))

      {seq_results, par_results}
    end
  end
end

# Auto-run if this script is executed
# Otherwise, functions are available for manual use in IEx

if System.get_env("AUTO_RUN") == "true" do
  QueuedJobsProcessor.compare_execution_modes()
else
  IO.puts("""

  ✨ Queued Jobs Processor Loaded

  Available functions:

    QueuedJobsProcessor.list_queued_jobs()
      - List all queued training jobs

    QueuedJobsProcessor.process_all_sequentially()
      - Process all jobs one at a time (baseline)

    QueuedJobsProcessor.process_all_parallel(max_concurrency \\\\ 3)
      - Process jobs in parallel (tests GIL-free execution)

    QueuedJobsProcessor.compare_execution_modes()
      - Run both sequential and parallel, compare results

  Example:
    iex> QueuedJobsProcessor.compare_execution_modes()

  """)
end
