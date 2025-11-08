# Test script for RunWorker Reactor saga
#
# Usage:
#   mix run scripts/test_run_saga.exs

alias Thunderline.Thunderbolt.Cerebros.RunSaga
alias Thunderline.UUID

# Create a test context
context = %{
  worker_id: UUID.v7(),
  requested_by: "test_script"
}

# Test inputs with varying complexity
test_cases = [
  %{
    name: "simple_run",
    inputs: %{
      worker_id: UUID.v7(),
      model_name: "simple_model",
      dataset_name: "test_dataset",
      config_path: "/tmp/simple_config.yaml"
    }
  },
  %{
    name: "run_with_checkpoints",
    inputs: %{
      worker_id: UUID.v7(),
      model_name: "checkpoint_model",
      dataset_name: "checkpoint_dataset",
      config_path: "/tmp/checkpoint_config.yaml",
      checkpoint_interval: 100
    }
  }
]

IO.puts("\n🧪 Testing Cerebros RunSaga\n")
IO.puts(String.duplicate("=", 60))

for test_case <- test_cases do
  IO.puts("\n📝 Test Case: #{test_case.name}")
  IO.puts(String.duplicate("-", 60))
  
  case Reactor.run(RunSaga, test_case.inputs, context) do
    {:ok, result} ->
      IO.puts("✅ Success!")
      IO.puts("   Worker ID: #{result.worker_id}")
      IO.puts("   Status: #{result.status}")
      if result[:metrics], do: IO.puts("   Metrics: #{inspect(result.metrics, limit: 3)}")
      
    {:error, error} ->
      IO.puts("❌ Failed!")
      IO.puts("   Error: #{inspect(error, pretty: true)}")
      
    {:halted, state} ->
      IO.puts("⏸️  Halted!")
      IO.puts("   State: #{inspect(state, pretty: true, limit: 5)}")
  end
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("✨ Saga testing complete!\n")
