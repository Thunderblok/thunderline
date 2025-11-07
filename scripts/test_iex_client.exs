# IEx test script for Client.start_run
# Run with: iex -S mix -r scripts/test_iex_client.exs

defmodule CerebrosTest do
  def run_client_test do
    alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts}

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Testing Client.start_run with Cerebros Integration")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Create test contract
    run_id = "iex_test_#{:os.system_time(:millisecond)}"

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

    IO.puts("Calling Client.start_run...")
    IO.puts("(This will generate Python script, execute cerebros_service, parse results)")
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    result = Client.start_run(contract)

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    case result do
      {:ok, data} ->
        IO.puts("✅ SUCCESS! Client.start_run completed in #{duration_ms}ms\n")

        IO.puts("Response structure:")
        IO.puts("  Keys: #{inspect(Map.keys(data))}")
        IO.puts("")

        if data[:result] do
          nas = data[:result]

          IO.puts("NAS Results:")
          IO.puts("  Status: #{nas["status"]}")
          IO.puts("  Best metric: #{nas["best_metric"]}")
          IO.puts("  Completed trials: #{nas["completed_trials"]}")
          IO.puts("")

          IO.puts("  Best model:")
          IO.puts("    Layers: #{inspect(nas["best_model"]["layers"])}")
          IO.puts("    Activation: #{nas["best_model"]["activation"]}")
          IO.puts("    Learning rate: #{nas["best_model"]["learning_rate"]}")
          IO.puts("    Optimizer: #{nas["best_model"]["optimizer"]}")
          IO.puts("")

          if nas["population_history"] do
            IO.puts("  Population evolution (#{length(nas["population_history"])} generations):")
            Enum.each(nas["population_history"], fn gen ->
              IO.puts("    Gen #{gen["generation"]}: best=#{Float.round(gen["best_fitness"], 4)}, mean=#{Float.round(gen["mean_fitness"], 4)}")
            end)
            IO.puts("")
          end

          if nas["artifacts"] do
            IO.puts("  Artifacts generated:")
            Enum.each(nas["artifacts"], fn artifact ->
              IO.puts("    #{artifact}")
            end)
            IO.puts("")
          end

          if nas["metadata"] do
            IO.puts("  Metadata:")
            IO.puts("    Mode: #{nas["metadata"]["mode"]}")
            IO.puts("    Timestamp: #{nas["metadata"]["timestamp"]}")
            IO.puts("")
          end

          # Check if temp script was created
          temp_dir = Path.join(System.tmp_dir!(), "cerebros_scripts")
          if File.exists?(temp_dir) do
            scripts = File.ls!(temp_dir) |> Enum.filter(&String.contains?(&1, run_id))
            if scripts != [] do
              IO.puts("  Temp script created: #{hd(scripts)}")
            end
          end
        end

        {:ok, data}

      {:error, error} ->
        IO.puts("❌ ERROR: Client.start_run failed after #{duration_ms}ms\n")
        IO.puts("Error structure:")
        IO.inspect(error, pretty: true, limit: :infinity)
        IO.puts("")

        if is_map(error) do
          if Map.has_key?(error, :message) do
            IO.puts("Message: #{error.message}")
          end
          if Map.has_key?(error, :type) do
            IO.puts("Type: #{error.type}")
          end
          if Map.has_key?(error, :details) do
            IO.puts("Details: #{inspect(error.details)}")
          end
        end

        {:error, error}
    end
  end
end

IO.puts("\nTest module loaded. Run with: CerebrosTest.run_client_test()")
IO.puts("")
