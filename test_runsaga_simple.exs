# Simple test for RunSaga
# Usage: Run this while server is running on port 5001

# The spec should be a keyword list, not a map
spec = [
  dataset: "mnist",
  trials: 3,
  objective: "accuracy"
]

IO.puts("\n=== Testing RunSaga ===")
IO.puts("Spec: #{inspect(spec)}")
IO.puts("Note: Make sure the server is running on port 5001")

# Test via the running application
try do
  # Call RunSaga with correct arguments
  result = Thunderline.Thunderbolt.CerebrosBridge.RunSaga.run(spec, [])

  IO.puts("\n✅ SUCCESS!")
  IO.puts("Result: #{inspect(result, pretty: true)}")
rescue
  error ->
    IO.puts("\n❌ ERROR: #{inspect(error)}")
    IO.puts("\nStacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end
