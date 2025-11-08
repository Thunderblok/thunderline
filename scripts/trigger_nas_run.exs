#!/usr/bin/env elixir
# Script to manually trigger a Cerebros NAS run

Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"}
])

defmodule TriggerNASRun do
  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Manually Triggering Cerebros NAS Run")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Define the NAS run specification
    spec = %{
      "dataset_id" => "manual_test_dataset",
      "objective" => "accuracy",
      "search_space" => %{
        "layers" => [32, 64, 128, 256],
        "activation" => ["relu", "tanh", "sigmoid"],
        "learning_rate" => [0.001, 0.01, 0.1]
      }
    }

    opts = [
      run_id: "manual_nas_run_#{:os.system_time(:second)}",
      budget: %{
        "max_trials" => 10,
        "population_size" => 30,
        "max_generations" => 5
      },
      parameters: %{
        "mutation_rate" => 0.1,
        "crossover_rate" => 0.8,
        "selection_strategy" => "tournament"
      },
      meta: %{
        "triggered_by" => "manual_script",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    ]

    IO.puts("Run Specification:")
    IO.inspect(spec, pretty: true, limit: :infinity)
    IO.puts("\nRun Options:")
    IO.inspect(opts, pretty: true, limit: :infinity)

    # You have two options to trigger the run:

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Option 1: Via Elixir API (requires running app)")
    IO.puts(String.duplicate("=", 80))
    IO.puts("""

    # In IEx or your application:
    alias Thunderline.Thunderbolt.CerebrosBridge

    {:ok, job} = CerebrosBridge.enqueue_run(
      %{
        "dataset_id" => "manual_test_dataset",
        "objective" => "accuracy",
        "search_space" => %{
          "layers" => [32, 64, 128, 256],
          "activation" => ["relu", "tanh", "sigmoid"]
        }
      },
      [
        run_id: "manual_nas_run",
        budget: %{
          "max_trials" => 10,
          "population_size" => 30
        },
        parameters: %{
          "mutation_rate" => 0.1,
          "crossover_rate" => 0.8
        }
      ]
    )

    # Check job status
    IO.inspect(job)

    # Or watch the job in Oban Web UI
    # Navigate to: http://localhost:4000/admin/oban
    """)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Option 2: Via HTTP API (if API endpoint exists)")
    IO.puts(String.duplicate("=", 80))
    IO.puts("""

    curl -X POST http://localhost:4000/api/cerebros/runs \\
      -H "Content-Type: application/json" \\
      -d '{
        "spec": {
          "dataset_id": "manual_test_dataset",
          "objective": "accuracy",
          "search_space": {
            "layers": [32, 64, 128, 256],
            "activation": ["relu", "tanh", "sigmoid"]
          }
        },
        "opts": {
          "run_id": "manual_nas_run",
          "budget": {
            "max_trials": 10,
            "population_size": 30
          },
          "parameters": {
            "mutation_rate": 0.1,
            "crossover_rate": 0.8
          }
        }
      }'
    """)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Option 3: Direct IEx Commands (simplest)")
    IO.puts(String.duplicate("=", 80))
    IO.puts("""

    # Start IEx with your application:
    iex -S mix

    # Then run these commands:
    alias Thunderline.Thunderbolt.CerebrosBridge

    # Simple run with minimal config
    {:ok, job} = CerebrosBridge.enqueue_run(%{
      "dataset_id" => "test",
      "objective" => "accuracy",
      "search_space" => %{"layers" => [32, 64, 128]}
    })

    # Check the job
    job.id

    # Monitor via Oban Web at http://localhost:4000/admin/oban
    """)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Where to Monitor Results")
    IO.puts(String.duplicate("=", 80))
    IO.puts("""

    1. Oban Web UI: http://localhost:4000/admin/oban
       - View job queue
       - See job status (scheduled/executing/completed/failed)
       - View job errors

    2. Application logs:
       - Watch for Cerebros NAS output
       - Python service logs
       - PythonX execution logs

    3. Database:
       # Check Oban jobs table
       Thunderline.Repo.query("SELECT * FROM oban_jobs WHERE worker = 'Thunderline.Thunderbolt.CerebrosBridge.RunWorker' ORDER BY inserted_at DESC LIMIT 5")

    4. Results artifacts:
       - Check /tmp/cerebros/<run_id>/ for model files
       - Look for stub_model.h5 or actual model artifacts
    """)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("✅ Run specification prepared!")
    IO.puts("   Choose one of the options above to trigger the NAS run.")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end
end

TriggerNASRun.run()
