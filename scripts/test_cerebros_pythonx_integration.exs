#!/usr/bin/env elixir
#
# Integration test for Thunderline CerebrosBridge with Pythonx
#
# Tests the full integration chain:
# - CerebrosBridge.Client → PythonxInvoker → cerebros_service.py → response
#

Mix.install([
  {:pythonx, "~> 0.1"},
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.0"}
])

# Define minimal modules for test
defmodule Thunderline.Thunderflow.ErrorClass do
  defstruct [:origin, :class, :severity, :visibility, :context]
end

# Start task supervisor
{:ok, _} = Task.Supervisor.start_link(name: Thunderline.TaskSupervisor)

# Load the actual PythonxInvoker code
Code.require_file("../lib/thunderline/thunderbolt/cerebros_bridge/pythonx_invoker.ex", __DIR__)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing CerebrosBridge Pythonx Integration")
IO.puts(String.duplicate("=", 80) <> "\n")

# Initialize Pythonx
IO.puts("Initializing Pythonx environment...")
System.put_env("UV_PYTHON_DOWNLOADS", "automatic")

pyproject = """
[project]
name = "thunderline-cerebros"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = [
  "numpy>=2.0",
  "torch>=2.0"
]
"""

case Pythonx.uv_init(pyproject) do
  :ok -> 
    IO.puts("✅ Pythonx initialized")
  {:error, reason} ->
    IO.puts("❌ Pythonx initialization failed: #{inspect(reason)}")
    System.halt(1)
end

# Add thunderhelm to Python path and import cerebros_service
IO.puts("\nLoading cerebros_service module...")
thunderhelm_path = Path.expand("../thunderhelm", __DIR__)

python_setup = """
import sys
sys.path.insert(0, '#{thunderhelm_path}')
import cerebros_service
'ok'
"""

{result_obj, _globals} = Pythonx.eval(python_setup, %{})
result_str = Pythonx.decode(result_obj)

if result_str == "ok" do
  IO.puts("✅ cerebros_service module loaded")
else
  IO.puts("⚠️  Unexpected result: #{inspect(result_str)}")
  IO.puts("✅ cerebros_service module loaded anyway")
end

# Mock configuration
Application.put_env(:thunderline, :cerebros_bridge, [
  enabled: true,
  invoker: :pythonx,
  python_path: ["thunderhelm"],
  invoke: %{
    default_timeout_ms: 30000
  }
])

# Mock Client module
defmodule Thunderline.Thunderbolt.CerebrosBridge.Client do
  def enabled?, do: true
  def config do
    %{
      invoke: %{
        default_timeout_ms: 30000
      }
    }
  end
end

# Test the PythonxInvoker
IO.puts("\nTesting PythonxInvoker.invoke(:start_run, ...)...")

call_spec = %{
  spec: %{
    dataset_id: "integration_test",
    objective: "accuracy",
    search_space: %{
      layers: [64, 128, 256],
      activation: ["relu", "tanh"]
    }
  },
  opts: %{
    run_id: "pythonx_integration_test",
    budget: %{
      max_trials: 5,
      population_size: 20
    },
    parameters: %{
      mutation_rate: 0.15,
      crossover_rate: 0.7
    }
  }
}

IO.puts("\nCall spec:")
IO.inspect(call_spec, pretty: true, limit: :infinity)

case Thunderline.Thunderbolt.CerebrosBridge.PythonxInvoker.invoke(:start_run, call_spec) do
  {:ok, result} ->
    IO.puts("\n✅ SUCCESS!\n")
    IO.puts("Response:")
    IO.inspect(result, pretty: true, limit: :infinity)
    
    # Verify structure
    parsed = Map.get(result, :parsed, %{})
    
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Validation:")
    IO.puts(String.duplicate("=", 80))
    
    checks = [
      {"Return code is 0", result.returncode == 0},
      {"Has parsed result", is_map(parsed) and map_size(parsed) > 0},
      {"Status is success", Map.get(parsed, "status") == "success"},
      {"Has best_model", is_map(Map.get(parsed, "best_model"))},
      {"Has best_metric", is_number(Map.get(parsed, "best_metric"))},
      {"Has completed_trials", is_integer(Map.get(parsed, "completed_trials"))},
      {"Has population_history", is_list(Map.get(parsed, "population_history"))},
      {"Has artifacts", is_list(Map.get(parsed, "artifacts"))},
      {"Has metadata", is_map(Map.get(parsed, "metadata"))}
    ]
    
    all_pass = Enum.all?(checks, fn {_, pass} -> pass end)
    
    Enum.each(checks, fn {check, pass} ->
      IO.puts("  #{if pass, do: "✅", else: "❌"} #{check}")
    end)
    
    IO.puts("\n" <> String.duplicate("=", 80))
    if all_pass do
      IO.puts("🎉 ALL CHECKS PASSED - Integration test successful!")
    else
      IO.puts("⚠️  SOME CHECKS FAILED - Review output above")
    end
    IO.puts(String.duplicate("=", 80))
    
    System.halt(if all_pass, do: 0, else: 1)
    
  {:error, error} ->
    IO.puts("\n❌ FAILED!\n")
    IO.puts("Error:")
    IO.inspect(error, pretty: true, limit: :infinity)
    System.halt(1)
end
