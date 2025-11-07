#!/usr/bin/env elixir

# Quick test of Client.start_run with our new Translator integration
# This validates the complete flow: Client -> Translator -> Invoker -> cerebros_service

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Client.start_run with Cerebros Integration")
IO.puts(String.duplicate("=", 80) <> "\n")

# Add thunderline to code path
Code.append_path("_build/dev/lib/thunderline/ebin")
Code.append_path("_build/dev/lib/ash/ebin")
Code.append_path("_build/dev/lib/spark/ebin")

# Load modules
Code.ensure_loaded!(Thunderline.Thunderbolt.CerebrosBridge.Client)
Code.ensure_loaded!(Thunderline.Thunderbolt.CerebrosBridge.Contracts)

alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts}

# Create test contract
contract = %Contracts.RunStartedV1{
  run_id: "client_test_#{:os.system_time(:millisecond)}",
  dataset_id: "test_dataset",
  search_space: %{
    "layers" => [32, 64, 128],
    "activation" => ["relu", "tanh"]
  },
  objective: "accuracy",
  budget: %{"max_trials" => 3},
  parameters: %{},
  correlation_id: "test_correlation",
  pulse_id: "test_pulse"
}

IO.puts("Created contract:")
IO.puts("  run_id: #{contract.run_id}")
IO.puts("  dataset_id: #{contract.dataset_id}")
IO.puts("  search_space: #{inspect(contract.search_space)}")
IO.puts("")

IO.puts("Calling Client.start_run...")
IO.puts("")

result =
  try do
    Client.start_run(contract)
  rescue
    e ->
      IO.puts("❌ Exception raised: #{inspect(e)}")
      IO.puts("\nStacktrace:")
      IO.puts(Exception.format_stacktrace(__STACKTRACE__))
      {:error, :exception}
  end

case result do
  {:ok, data} ->
    IO.puts("✅ SUCCESS! Client.start_run completed\n")
    IO.puts("Result keys: #{inspect(Map.keys(data))}")

    if data[:result] do
      nas = data[:result]
      IO.puts("\nNAS Results:")
      IO.puts("  Status: #{nas["status"]}")
      IO.puts("  Best metric: #{nas["best_metric"]}")
      IO.puts("  Completed trials: #{nas["completed_trials"]}")
      IO.puts("  Best model: #{inspect(nas["best_model"])}")

      if nas["population_history"] do
        IO.puts("\n  Population history:")
        Enum.each(nas["population_history"], fn gen ->
          IO.puts("    Gen #{gen["generation"]}: fitness=#{gen["best_fitness"]}")
        end)
      end
    end

  {:error, error} ->
    IO.puts("❌ ERROR: Client.start_run failed\n")
    IO.inspect(error, pretty: true, limit: :infinity)
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Test Complete")
IO.puts(String.duplicate("=", 80))
