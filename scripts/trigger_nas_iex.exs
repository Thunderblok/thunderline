# ================================================================================
# IEx Commands to Manually Trigger a NAS Run
# ================================================================================
#
# IMPORTANT: This script requires the full Phoenix application to be running!
#
# Start Phoenix server first (in another terminal):
#   iex -S mix phx.server
#
# Then in IEx, copy-paste these commands:
# ================================================================================

IO.puts """

================================================================================
⚠️  STOP! Read this first:
================================================================================

This script REQUIRES the full Phoenix application running with database!

1. In a separate terminal, start the server:

   iex -S mix phx.server

2. Once the server is running, copy the commands below into that IEx session

3. If you see "No Oban instance named Oban is running", you need to:
   - Make sure DATABASE_URL is set in your environment
   - Or start the Phoenix server instead of plain `iex -S mix`

================================================================================
Commands to copy-paste in IEx:
================================================================================

alias Thunderline.Thunderbolt.CerebrosBridge

# Simple NAS run
{:ok, job} = CerebrosBridge.enqueue_run(
  %{
    "dataset_id" => "manual_test",
    "objective" => "accuracy",
    "search_space" => %{
      "layers" => [32, 64, 128],
      "activation" => ["relu", "tanh"]
    }
  },
  [
    run_id: "manual_nas_#{:os.system_time(:second)}",
    budget: %{
      "max_trials" => 5,
      "population_size" => 20
    },
    parameters: %{
      "mutation_rate" => 0.1,
      "crossover_rate" => 0.8
    }
  ]
)

IO.puts "\\n✅ NAS run enqueued!"
IO.puts "Job ID: #{job.id}"
IO.puts "Worker: #{job.worker}"
IO.puts "State: #{job.state}"
IO.puts "\\n📊 Monitor at: http://localhost:4000/admin/oban"
IO.puts "🔍 Check logs for Python output"

================================================================================
"""
