#!/usr/bin/env elixir

# Test RunSaga integration
Mix.install([])

# Load the application environment
Application.load(:thunderline)

# Test specification
spec = %{
  dataset: "mnist",
  trials: 3,
  objective: "accuracy"
}

IO.puts("\n=== Testing RunSaga ML Integration ===")
IO.puts("Spec: #{inspect(spec)}\n")

# Execute RunSaga
try do
  result = Thunderline.Thunderbolt.CerebrosBridge.RunSaga.run(spec, %{})

  IO.puts("✅ SUCCESS!")
  IO.puts("Result: #{inspect(result, pretty: true)}")
rescue
  error ->
    IO.puts("❌ ERROR: #{inspect(error)}")
    IO.puts("Stacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end
