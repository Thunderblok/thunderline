# Test script for CerebrosBridge RunSaga (Reactor-based NAS orchestration)
#
# Usage:
#   mix run scripts/test_run_saga.exs

alias Thunderline.Thunderbolt.CerebrosBridge.RunSaga
alias Thunderline.Thunderbolt.CerebrosBridge

# Test cases with varying complexity
test_cases = [
  %{
    name: "mnist_simple",
    spec: %{
      "dataset_id" => "mnist",
      "objective" => "accuracy",
      "search_space" => %{
        "layers" => [1, 2],
        "neurons" => [32, 64]
      },
      "budget" => %{
        "max_trials" => 2,
        "timeout_seconds" => 30
      }
    },
    opts: [budget: %{"max_trials" => 2}]
  },
  %{
    name: "cifar10_advanced",
    spec: %{
      "dataset_id" => "cifar10",
      "objective" => "f1_score",
      "search_space" => %{
        "layers" => [2, 3, 4],
        "neurons" => [64, 128, 256],
        "dropout" => [0.1, 0.2, 0.3]
      },
      "budget" => %{
        "max_trials" => 3,
        "timeout_seconds" => 60
      }
    },
    opts: [
      budget: %{"max_trials" => 3},
      parameters: %{"early_stopping" => true}
    ]
  }
]

IO.puts("\n🧪 Testing CerebrosBridge RunSaga\n")
IO.puts(String.duplicate("=", 60))
IO.puts("Bridge enabled: #{CerebrosBridge.enabled?()}")
IO.puts(String.duplicate("=", 60))

for test_case <- test_cases do
  IO.puts("\n📝 Test Case: #{test_case.name}")
  IO.puts(String.duplicate("-", 60))

  # Test direct saga execution (bypasses Oban)
  case RunSaga.run(test_case.spec, test_case.opts) do
    {:ok, result} ->
      IO.puts("✅ Success!")
      IO.puts("   Run ID: #{result[:run_id]}")
      IO.puts("   Status: #{result[:status] || "completed"}")
      if result[:result], do: IO.puts("   Result: #{inspect(result[:result], limit: 3)}")

    {:error, :bridge_disabled} ->
      IO.puts("⚠️  Skipped - Bridge is disabled")
      IO.puts("   Set TL_ENABLE_CEREBROS_BRIDGE=true to enable")

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
