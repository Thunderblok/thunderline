#!/usr/bin/env elixir

# ================================================================================
# Quick NAS Trigger (Requires Phoenix Server Running)
# ================================================================================
#
# Prerequisites:
#   1. Start Phoenix server: iex -S mix phx.server
#   2. In that IEx session, run: Code.eval_file("scripts/trigger_nas_quick.exs")
#
# Or just copy-paste the commands section below into IEx
# ================================================================================

# Check if Oban is running
unless Oban.Registry.whereis(Oban) do
  IO.puts """

  ❌ ERROR: Oban is not running!

  You need to start the Phoenix server first:

    iex -S mix phx.server

  Then in that IEx session, run:

    Code.eval_file("scripts/trigger_nas_quick.exs")

  ================================================================================
  """
  System.halt(1)
end

IO.puts """
================================================================================
Triggering NAS Run
================================================================================
"""

alias Thunderline.Thunderbolt.CerebrosBridge

spec = %{
  "dataset_id" => "quick_test",
  "objective" => "accuracy",
  "search_space" => %{
    "layers" => [32, 64, 128],
    "activation" => ["relu", "tanh"]
  }
}

opts = [
  run_id: "quick_nas_#{:os.system_time(:second)}",
  budget: %{"max_trials" => 5, "population_size" => 20},
  parameters: %{"mutation_rate" => 0.1, "crossover_rate" => 0.8}
]

IO.puts "Spec:"
IO.inspect(spec, pretty: true)
IO.puts "\nOptions:"
IO.inspect(opts, pretty: true)
IO.puts "\nEnqueuing..."

case CerebrosBridge.enqueue_run(spec, opts) do
  {:ok, job} ->
    IO.puts """

    ✅ SUCCESS!

    Job ID: #{job.id}
    State: #{job.state}
    Run ID: #{job.args["run_id"]}

    📊 Monitor: http://localhost:4000/admin/oban
    🔍 Watch logs for Python output
    📁 Artifacts: /tmp/cerebros/#{job.args["run_id"]}/

    """

    {:ok, job}

  {:error, reason} ->
    IO.puts "\n❌ ERROR!"
    IO.inspect(reason, pretty: true)
    {:error, reason}
end
