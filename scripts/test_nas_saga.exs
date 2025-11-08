# Test script for NAS run saga
#
# Usage: mix run scripts/test_nas_saga.exs

alias Thunderline.Thunderbolt.CerebrosBridge

# Quick NAS spec
spec = %{
  "dataset_id" => "mnist",
  "objective" => "accuracy",
  "search_space" => %{
    "layers" => [1, 2, 3],
    "neurons" => [32, 64, 128]
  },
  "budget" => %{
    "max_trials" => 3,
    "timeout_seconds" => 60
  }
}

IO.puts("Testing NAS run saga...")
IO.puts("Bridge enabled: #{CerebrosBridge.enabled?()}")

# Enqueue the run
case CerebrosBridge.enqueue_run(spec, budget: %{"max_trials" => 3}) do
  {:ok, job} ->
    IO.puts("\n✓ Job enqueued successfully!")
    IO.puts("  Job ID: #{job.id}")
    IO.puts("  Queue: #{job.queue}")
    IO.puts("  Scheduled: #{job.scheduled_at}")
    IO.puts("  Inserted: #{job.inserted_at}")
    IO.puts("\nMonitor with: SELECT * FROM oban_jobs WHERE id = #{job.id};")

  {:error, :bridge_disabled} ->
    IO.puts("\n⚠ Bridge is disabled - enable via TL_ENABLE_CEREBROS_BRIDGE=true")

  {:error, reason} ->
    IO.puts("\n✗ Failed to enqueue: #{inspect(reason)}")
end
