#!/bin/bash
# Test Client.start_run via IEx

cd /home/mo/DEV/Thunderline

iex -S mix <<'ELIXIR'
alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts}

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Client.start_run with Cerebros Integration")
IO.puts(String.duplicate("=", 80) <> "\n")

# Create test contract
contract = %Contracts.RunStartedV1{
  run_id: "iex_test_#{:os.system_time(:millisecond)}",
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

IO.puts("Contract: run_id=#{contract.run_id}, dataset_id=#{contract.dataset_id}")

IO.puts("\nCalling Client.start_run...")

case Client.start_run(contract) do
  {:ok, data} ->
    IO.puts("\n✅ SUCCESS!\n")
    if data[:result] do
      nas = data[:result]
      IO.puts("Status: #{nas["status"]}")
      IO.puts("Best metric: #{nas["best_metric"]}")
      IO.puts("Trials: #{nas["completed_trials"]}")
      IO.puts("Model: #{inspect(nas["best_model"])}")
    end
    
  {:error, error} ->
    IO.puts("\n❌ ERROR\n")
    IO.inspect(error, pretty: true)
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Done - Press Ctrl+C twice to exit")
IO.puts(String.duplicate("=", 80))
ELIXIR
