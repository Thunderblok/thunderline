#!/usr/bin/env elixir

# Test script for ModelServer

alias Thunderline.Thunderbolt.ML.ModelServer

IO.puts("=== ModelServer Test ===\n")

# Check if ModelServer is already started (running via app supervision)
case Process.whereis(ModelServer) do
  nil ->
    # Start ModelServer manually if not running
    {:ok, pid} = ModelServer.start_link([])
    IO.puts("ModelServer started: #{inspect(pid)}")
    
  pid ->
    IO.puts("ModelServer already running: #{inspect(pid)}")
end

# Check stats
stats = ModelServer.stats()
IO.inspect(stats, label: "Initial stats")

# Load a model
IO.puts("\nLoading cerebros_trained.onnx...")

case ModelServer.get_session("cerebros_trained.onnx") do
  {:ok, session} ->
    IO.puts("[OK] Model loaded successfully")
    # Don't inspect the session directly due to Ortex inspect bug
    IO.puts("Session type: #{inspect(session.__struct__)}")

    # Check stats again
    stats2 = ModelServer.stats()
    IO.inspect(stats2, label: "Stats after load")

    # Try inference
    IO.puts("\nRunning inference...")
    # Create a 40-element input tensor (matching model input shape)
    input = Nx.tensor([[1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]], type: :s64)

    case Ortex.run(session, input) do
      {output} ->
        IO.puts("[OK] Inference successful")
        IO.puts("Output shape: #{inspect(Nx.shape(output))}")
        IO.puts("Output sample: #{inspect(Nx.to_flat_list(output) |> Enum.take(5))}...")

      other ->
        IO.inspect(other, label: "Inference result")
    end

  {:error, reason} ->
    IO.puts("[ERROR] Failed to load: #{inspect(reason)}")
end

# Test cache hit
IO.puts("\nTesting cache hit performance...")
t1 = System.monotonic_time(:microsecond)
{:ok, _} = ModelServer.get_session("cerebros_trained.onnx")
t2 = System.monotonic_time(:microsecond)
IO.puts("[OK] Cache hit in #{t2 - t1} microseconds")

# Load another model
IO.puts("\nLoading cerebros_mini.onnx...")
case ModelServer.get_session("cerebros_mini.onnx") do
  {:ok, _session} ->
    IO.puts("[OK] Second model loaded successfully")
  {:error, reason} ->
    IO.puts("[ERROR] Failed to load second model: #{inspect(reason)}")
end

# List loaded models
models = ModelServer.list_models()
IO.inspect(models, label: "All loaded models")

# Final stats
final_stats = ModelServer.stats()
IO.puts("\nFinal loaded models: #{final_stats.loaded_models}")

IO.puts("\n=== Test Complete ===")

# Load a model
IO.puts("\nLoading cerebros_trained.onnx...")

case ModelServer.get_session("cerebros_trained.onnx") do
  {:ok, session} ->
    IO.puts("[OK] Model loaded successfully")
    IO.inspect(session, label: "Session")

    # Check stats again
    stats2 = ModelServer.stats()
    IO.inspect(stats2, label: "Stats after load")

    # Try inference
    IO.puts("\nRunning inference...")
    # Create a 40-element input tensor (matching model input shape)
    input = Nx.tensor([[1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]], type: :s64)

    case Ortex.run(session, input) do
      {output} ->
        IO.puts("[OK] Inference successful")
        IO.puts("Output shape: #{inspect(Nx.shape(output))}")
        IO.puts("Output: #{inspect(Nx.to_flat_list(output) |> Enum.take(5))}...")

      error ->
        IO.inspect(error, label: "Inference result")
    end

  {:error, reason} ->
    IO.puts("[ERROR] Failed to load: #{inspect(reason)}")
end

# Test cache hit
IO.puts("\nTesting cache hit...")
t1 = System.monotonic_time(:microsecond)
{:ok, _} = ModelServer.get_session("cerebros_trained.onnx")
t2 = System.monotonic_time(:microsecond)
IO.puts("[OK] Cache hit in #{t2 - t1} microseconds")

# List loaded models
models = ModelServer.list_models()
IO.inspect(models, label: "Loaded models")

IO.puts("\n=== Test Complete ===")
