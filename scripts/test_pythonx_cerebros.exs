#!/usr/bin/env elixir

# Test script for Pythonx integration with Cerebros

Mix.install([
  {:pythonx, "~> 0.4.0"},
  {:jason, "~> 1.2"}
])

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Testing Pythonx + Cerebros Integration")
IO.puts(String.duplicate("=", 80) <> "\n")

# Initialize Python interpreter
IO.puts("Initializing Python interpreter...")

# Set UV_PYTHON_DOWNLOADS to automatic for this script
System.put_env("UV_PYTHON_DOWNLOADS", "automatic")

# First, ensure uv has Python 3.13 installed
IO.puts("Ensuring Python 3.13 is installed via uv...")
case System.cmd("uv", ["python", "install", "3.13"], stderr_to_stdout: true) do
  {_output, 0} ->
    IO.puts("✅ Python 3.13 installed/verified")
  {output, _} ->
    IO.puts("Note: #{String.trim(output)}")
end

# Now initialize with uv
pyproject = """
[project]
name = "thunderline-test"
version = "0.0.0"
requires-python = ">=3.13"
dependencies = [
  "numpy",
  "torch"
]
"""

Pythonx.uv_init(pyproject)
IO.puts("✅ Python interpreter initialized")

# Add thunderhelm to Python path and import cerebros_service
thunderhelm_path = Path.expand("./thunderhelm")
IO.puts("Adding to Python path: #{thunderhelm_path}")

# Initialize Python path and import module
python_setup = """
import sys
sys.path.insert(0, '#{thunderhelm_path}')
import cerebros_service
cerebros_service
"""

{cerebros_module, _} = Pythonx.eval(python_setup, %{})
IO.puts("✅ cerebros_service module loaded")

# Helper function to normalize Elixir data for Python
# Converts atoms to strings, ensures string keys
defmodule PythonHelper do
  def normalize(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), normalize(v)} end)
  end

  def normalize(list) when is_list(list) do
    Enum.map(list, &normalize/1)
  end

  def normalize(atom) when is_atom(atom) and not is_nil(atom) and atom not in [true, false] do
    to_string(atom)
  end

  def normalize(value), do: value
end

# Test data - kept as Elixir maps
spec = %{
  "dataset_id" => "test_dataset",
  "search_space" => %{"layers" => [32, 64, 128]},
  "objective" => "accuracy"
}

opts = %{
  "run_id" => "pythonx_test_001",
  "budget" => %{"max_trials" => 3, "population_size" => 10},
  "parameters" => %{"mutation_rate" => 0.1}
}

# Call Python using proper Pythonx data passing
# Pass Elixir data through globals - Pythonx handles encoding
python_code = """
# spec and opts come from Elixir via globals
# Pythonx automatically converts them to Python dicts
result = cerebros_service.run_nas(spec, opts)
result
"""

IO.puts("\nCalling cerebros_service.run_nas via Pythonx...")
IO.puts("Spec: #{inspect(spec)}")
IO.puts("Opts: #{inspect(opts)}")

try do
  # Normalize data for Python - ensure string keys
  normalized_spec = PythonHelper.normalize(spec)
  normalized_opts = PythonHelper.normalize(opts)

  # Pass data through globals map - Pythonx.Encoder protocol handles conversion
  # Also pass the imported cerebros_service module
  {result_object, _globals} = Pythonx.eval(python_code, %{
    "cerebros_service" => cerebros_module,
    "spec" => normalized_spec,
    "opts" => normalized_opts
  })

  IO.puts("\n✅ Python execution succeeded!")
  IO.puts("\nPython object:")
  IO.inspect(result_object, pretty: true)

  # Decode the Python dict to Elixir map
  result = Pythonx.decode(result_object)

  IO.puts("\n✅ SUCCESS!")
  IO.puts("\nDecoded result:")
  IO.inspect(result, pretty: true, limit: :infinity)

  if is_map(result) and Map.get(result, "status") == "success" do
    IO.puts("\n✅ NAS run completed successfully")
    IO.puts("Best metric: #{Map.get(result, "best_metric")}")
    IO.puts("Completed trials: #{Map.get(result, "completed_trials")}")
    IO.puts("Best model: #{inspect(Map.get(result, "best_model"))}")
  end
rescue
  e in Pythonx.Error ->
    IO.puts("\n❌ Python ERROR!")
    IO.puts(Exception.message(e))

  e ->
    IO.puts("\n❌ Elixir ERROR!")
    IO.inspect(e, pretty: true)
    reraise e, __STACKTRACE__
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("Test Complete")
IO.puts(String.duplicate("=", 80))
