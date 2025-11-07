# Simple wrapper to run the Cerebros test directly
alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts}

run_id = "iex_test_#{:os.system_time(:millisecond)}"

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Client.start_run with Cerebros Integration")
IO.puts(String.duplicate("=", 80) <> "\n")

# Create contract with all required fields
contract = %Contracts.RunStartedV1{
  run_id: run_id,
  dataset_id: "test_dataset",
  search_space: %{
    "layers" => [32, 64, 128],
    "activation" => ["relu", "tanh"],
    "learning_rate" => [0.001, 0.01, 0.1]
  },
  objective: "accuracy",
  budget: %{
    "max_trials" => 3,
    "max_time" => 300
  },
  parameters: %{
    "mutation_rate" => 0.1,
    "crossover_rate" => 0.7
  },
  correlation_id: "test_correlation",
  pulse_id: "test_pulse",
  timestamp: DateTime.utc_now()
}

IO.puts("Contract created:")
IO.puts("  run_id: #{contract.run_id}")
IO.puts("  dataset_id: #{contract.dataset_id}")
IO.puts("  objective: #{contract.objective}")
IO.puts("")

# Call Client.start_run (with timing)
IO.puts("Calling Client.start_run...")
start_time = :os.system_time(:millisecond)

try do
  {:ok, result} = Client.start_run(contract)
  elapsed = :os.system_time(:millisecond) - start_time

  IO.puts("\n✅ SUCCESS! Client.start_run completed in #{elapsed}ms\n")

  IO.puts("Response structure:")
  IO.puts("  Keys: #{inspect(Map.keys(result))}")
  IO.puts("")

  # Display NAS results if available
  if Map.has_key?(result, :result) && is_map(result.result) do
    nas_result = result.result
    IO.puts("NAS Results:")
    IO.puts("  Status: #{Map.get(nas_result, "status")}")
    IO.puts("  Best metric: #{Map.get(nas_result, "best_metric")}")
    IO.puts("  Completed trials: #{Map.get(nas_result, "completed_trials")}")
    IO.puts("")

    if best_model = Map.get(nas_result, "best_model") do
      IO.puts("  Best model:")
      Enum.each(best_model, fn {k, v} ->
        IO.puts("    #{k}: #{inspect(v)}")
      end)
      IO.puts("")
    end

    if pop_history = Map.get(nas_result, "population_history") do
      IO.puts("  Population evolution (#{length(pop_history)} generations):")
      Enum.each(pop_history, fn gen ->
        gen_num = Map.get(gen, "generation", "?")
        best = Map.get(gen, "best_fitness", "?")
        mean = Map.get(gen, "mean_fitness", "?")
        IO.puts("    Gen #{gen_num}: best=#{best}, mean=#{mean}")
      end)
      IO.puts("")
    end

    if artifacts = Map.get(nas_result, "artifacts") do
      IO.puts("  Artifacts generated:")
      Enum.each(artifacts, fn artifact ->
        IO.puts("    #{artifact}")
      end)
      IO.puts("")
    end
  end

  # Check for script path in meta
  if Map.has_key?(result, :meta) && is_map(result.meta) do
    if script_path = Map.get(result.meta, :script_path) do
      IO.puts("  Temp script created: #{script_path}")
    end
  end

  IO.puts("\n" <> String.duplicate("=", 80))
  IO.puts("✅ Test completed successfully!")
  IO.puts(String.duplicate("=", 80) <> "\n")

  System.halt(0)
rescue
  error ->
    elapsed = :os.system_time(:millisecond) - start_time
    IO.puts("\n❌ FAILED after #{elapsed}ms\n")
    IO.puts("Error: #{inspect(error)}")
    IO.puts("\nStacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
    System.halt(1)
end
