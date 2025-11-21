# TAK GPU Benchmark Script
# Run with: mix run scripts/benchmark_tak.exs

alias Thunderline.Thunderbolt.TAK.GPUStepper

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🎸 TAK GPU BENCHMARK - PHASE 2 VALIDATION 🎸")
IO.puts(String.duplicate("=", 60))

# Check GPU backend info
IO.puts("\n📊 GPU Backend Configuration:")
gpu_info = GPUStepper.gpu_info()
IO.inspect(gpu_info, pretty: true)

# 2D Conway's Game of Life Benchmark (100x100 grid)
IO.puts("\n" <> String.duplicate("-", 60))
IO.puts("🎯 2D Conway Benchmark (100x100, B3/S23)")
IO.puts(String.duplicate("-", 60))

result_2d = GPUStepper.benchmark(
  {100, 100}, 
  [3],        # born
  [2, 3],     # survive
  generations: 1000,
  warmup: 10
)

IO.puts("Results:")
IO.puts("  Gen/sec: #{result_2d.gen_per_sec}")
IO.puts("  Avg time: #{result_2d.avg_time_ms} ms")
IO.puts("  Target met (>1000): #{result_2d.target_met?}")

# 3D Conway Benchmark (50x50x50 grid)
IO.puts("\n" <> String.duplicate("-", 60))
IO.puts("🎯 3D Conway Benchmark (50x50x50, B567/S456)")
IO.puts(String.duplicate("-", 60))

result_3d = GPUStepper.benchmark(
  {50, 50, 50}, 
  [5, 6, 7],  # born
  [4, 5, 6],  # survive
  generations: 100,
  warmup: 10
)

IO.puts("Results:")
IO.puts("  Gen/sec: #{result_3d.gen_per_sec}")
IO.puts("  Avg time: #{result_3d.avg_time_ms} ms")
IO.puts("  Target met (>1000): #{result_3d.target_met?}")

# Large 2D Grid Stress Test (200x200)
IO.puts("\n" <> String.duplicate("-", 60))
IO.puts("🔥 Stress Test (200x200)")
IO.puts(String.duplicate("-", 60))

result_large = GPUStepper.benchmark(
  {200, 200}, 
  [3], 
  [2, 3],
  generations: 500,
  warmup: 10
)

IO.puts("Results:")
IO.puts("  Gen/sec: #{result_large.gen_per_sec}")
IO.puts("  Avg time: #{result_large.avg_time_ms} ms")
IO.puts("  Target met (>1000): #{result_large.target_met?}")

# Summary
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("📈 BENCHMARK SUMMARY")
IO.puts(String.duplicate("=", 60))
IO.puts("Backend: #{gpu_info.backend}")
IO.puts("\n2D (100×100):  #{result_2d.gen_per_sec} gen/sec")
IO.puts("3D (50³):      #{result_3d.gen_per_sec} gen/sec")
IO.puts("2D (200×200):  #{result_large.gen_per_sec} gen/sec")

phase2_complete = result_2d.target_met? || result_3d.target_met?
IO.puts("\n🎸 PHASE 2 STATUS: #{if phase2_complete, do: "✅ COMPLETE", else: "⚠️  CPU MODE (Need GPU)"}")
IO.puts(String.duplicate("=", 60) <> "\n")
