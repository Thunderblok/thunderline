#!/usr/bin/env elixir

# ================================================================================
# Standalone NAS Run Trigger (No Phoenix Server Required)
# ================================================================================
#
# This script temporarily enables Oban and runs a NAS job without needing
# the Phoenix server running.
#
# Usage:
#   elixir scripts/trigger_nas_standalone.exs
#
# Or with custom parameters:
#   DATABASE_URL=... elixir scripts/trigger_nas_standalone.exs
# ================================================================================

IO.puts """
================================================================================
Triggering Standalone NAS Run
================================================================================
"""

# Ensure application is compiled
Mix.install([], system_env: %{"MIX_ENV" => "dev"})

# Load the application
Application.load(:thunderline)

# Get database URL from environment or use default
database_url = System.get_env("DATABASE_URL") || 
  "ecto://postgres:postgres@localhost/thunderline_dev"

IO.puts "Database: #{database_url}"

# Override Oban config to enable it
Application.put_env(:thunderline, Oban,
  repo: Thunderline.Repo,
  queues: [cerebros_training: 10],
  plugins: []
)

IO.puts "Starting application dependencies..."

# Start required applications
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto)
{:ok, _} = Application.ensure_all_started(:ecto_sql)

# Start the repo
{:ok, _} = Thunderline.Repo.start_link()

# Start Oban
{:ok, _} = Oban.start_link(Application.get_env(:thunderline, Oban))

IO.puts "✅ Application ready\n"

# Define the NAS run spec
spec = %{
  "dataset_id" => "standalone_test",
  "objective" => "accuracy",
  "search_space" => %{
    "layers" => [32, 64, 128],
    "activation" => ["relu", "tanh"]
  }
}

opts = [
  run_id: "standalone_nas_#{:os.system_time(:second)}",
  budget: %{
    "max_trials" => 5,
    "population_size" => 20
  },
  parameters: %{
    "mutation_rate" => 0.1,
    "crossover_rate" => 0.8
  }
]

IO.puts "Spec:"
IO.inspect(spec, pretty: true)

IO.puts "\nOptions:"
IO.inspect(opts, pretty: true)

IO.puts "\nEnqueuing NAS run..."

# Trigger the run
alias Thunderline.Thunderbolt.CerebrosBridge

case CerebrosBridge.enqueue_run(spec, opts) do
  {:ok, job} ->
    IO.puts """
    
    ================================================================================
    ✅ SUCCESS! NAS run enqueued
    ================================================================================
    
    Job ID: #{job.id}
    Worker: #{job.worker}
    State: #{job.state}
    Queue: #{job.queue}
    
    Run ID: #{job.args["run_id"]}
    
    ================================================================================
    Monitoring:
    ================================================================================
    
    1. Check Oban jobs table:
       psql #{database_url} -c "SELECT id, state, worker, attempted_at FROM oban_jobs WHERE id = #{job.id};"
    
    2. Check for results in logs (when job processes)
    
    3. Artifacts will be in: /tmp/cerebros/#{job.args["run_id"]}/
    
    ================================================================================
    Note: Job will process when Oban worker picks it up.
          Start Phoenix server to process: iex -S mix phx.server
    ================================================================================
    """
    
  {:error, :bridge_disabled} ->
    IO.puts """
    
    ❌ ERROR: Cerebros bridge is disabled!
    
    Enable it by setting environment variable:
      export TL_ENABLE_CEREBROS_BRIDGE=1
    
    Or in config/dev.exs:
      config :thunderline, :cerebros_bridge, enabled: true
    """
    
  {:error, reason} ->
    IO.puts "\n❌ ERROR: Failed to enqueue job"
    IO.inspect(reason, pretty: true, label: "Error")
end
