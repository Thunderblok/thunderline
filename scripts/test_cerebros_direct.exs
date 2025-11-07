#!/usr/bin/env elixir

# Direct test of cerebros_service via System.cmd (proof of concept)

Mix.install([
  {:jason, "~> 1.2"}
])

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Cerebros Service via System.cmd")
IO.puts(String.duplicate("=", 80) <> "\n")

# Test data
spec = %{
  "dataset_id" => "test_dataset",
  "search_space" => %{"layers" => [32, 64, 128]},
  "objective" => "accuracy"
}

opts = %{
  "run_id" => "direct_test_001",
  "budget" => %{"max_trials" => 3, "population_size" => 10},
  "parameters" => %{"mutation_rate" => 0.1}
}

# Create Python script that calls cerebros_service
python_script = """
import sys
import json
sys.path.insert(0, './thunderhelm')
import cerebros_service

spec = #{Jason.encode!(spec)}
opts = #{Jason.encode!(opts)}

result = cerebros_service.run_nas(spec, opts)
print(json.dumps(result))
"""

# Write script to temp file
script_path = "/tmp/test_cerebros.py"
File.write!(script_path, python_script)

IO.puts("Calling cerebros_service.run_nas via subprocess...")
python_path = Path.expand(".venv/bin/python")
IO.puts("Python: #{python_path}")

case System.cmd(python_path, [script_path], stderr_to_stdout: true) do
  {output, 0} ->
    IO.puts("\n✅ Python execution succeeded!")

    # Output contains both log lines and JSON - extract the JSON line
    json_line = output
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "{"))

    case json_line && Jason.decode(json_line) do
      {:ok, result} ->
        IO.puts("\n✅ SUCCESS! JSON parsed successfully")
        IO.puts("\nDecoded result:")
        IO.inspect(result, pretty: true, limit: :infinity)

        if is_map(result) and Map.get(result, "status") == "success" do
          IO.puts("\n✅ NAS run completed successfully")
          IO.puts("Best metric: #{Map.get(result, "best_metric")}")
          IO.puts("Completed trials: #{Map.get(result, "completed_trials")}")
          IO.puts("Best model: #{inspect(Map.get(result, "best_model"))}")
        end

      nil ->
        IO.puts("\n❌ No JSON found in output")
        IO.puts("Raw output:")
        IO.puts(output)

      {:error, reason} ->
        IO.puts("\n❌ JSON decode error: #{inspect(reason)}")
        IO.puts("Attempted to parse: #{json_line}")
        IO.puts("\nFull output:")
        IO.puts(output)
    end

  {output, exit_code} ->
    IO.puts("\n❌ Python execution failed with exit code #{exit_code}")
    IO.puts("Output:")
    IO.puts(output)
end

# Cleanup
File.rm(script_path)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Test Complete")
IO.puts(String.duplicate("=", 80))
