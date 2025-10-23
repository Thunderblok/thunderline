# RAG MVP Acceptance Test
# Run with: iex -S mix
# Then: Code.require_file("test_rag_acceptance.exs")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("RAG MVP ACCEPTANCE TEST")
IO.puts(String.duplicate("=", 80) <> "\n")

# Check if RAG is enabled
unless Application.get_env(:thunderline, :features)[:rag_enabled] do
  IO.puts("❌ ERROR: RAG is not enabled!")
  IO.puts("In dev: should be enabled by default in config/dev.exs")
  IO.puts("In releases: set RAG_ENABLED=1")
  IO.puts("\nExample:")
  IO.puts("  export RAG_ENABLED=1")
  IO.puts("  mix run test_rag_acceptance.exs")
  IO.puts("")
  raise "RAG not enabled"
end

IO.puts("✓ RAG feature flag enabled")

# Start RAG serving
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Starting RAG serving (may take a minute to download models)...")
IO.puts(String.duplicate("-", 80))

case Thunderline.RAG.Serving.start_link() do
  {:ok, _pid} ->
    IO.puts("✓ RAG serving started and models loaded successfully")
  {:error, {:already_started, _pid}} ->
    IO.puts("✓ RAG serving already running")
  {:error, error} ->
    IO.puts("❌ FAILED to start RAG serving: #{inspect(error)}")
    raise "Failed to start serving"
end

# Test 1: Ingest README via Ash
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("TEST 1: Ingest README.md via Ash")
IO.puts(String.duplicate("-", 80))

readme_path = Path.join(__DIR__, "README.md")
readme = File.read!(readme_path)

result = Thunderline.RAG.Collection
|> Ash.Changeset.for_create(:ingest, %{
  text: readme,
  metadata: %{
    source: "README.md",
    ingested_at: DateTime.utc_now() |> DateTime.to_iso8601()
  }
})
|> Ash.create(authorize?: false)

case result do
  {:ok, collection} ->
    chunk_count = get_in(collection.result, [:chunks]) || 0
    IO.puts("✓ SUCCESS: Ingested #{chunk_count} chunks")
    IO.puts("  Status: #{collection.status}")
    IO.puts("  Collection: #{get_in(collection.result, [:collection])}")
  {:error, error} ->
    IO.puts("❌ FAILED: #{inspect(error)}")
    raise "Ingestion failed"
    Let me check the guide and the ash_ai library to understand the proper implementation approach:

    Auto approved for this workspace (Edit)

    Perfect! This guide is exactly what we need. Now let me check the ash_ai library:

    Summarized conversation history

    Excellent! ash_ai has exactly what we need - built-in vectorization support! Let me check if it's already installed:

    Perfect! It's already installed. Now I see the issue - we've been reinventing the wheel! ash_ai provides:

    Built-in vectorization via the vectorize DSL section
    Embedding model behavior we can implement
    Multiple strategies (after_action, ash_oban, manual)
    PostgreSQL vector support built-in
    Let me check what our RAG.Collection resource looks like:

    Read collection.ex

    Now I understand the issue! We've been building RAG from scratch when ash_ai provides vectorization for Ash resources. The approach should be:

    Create an Ash resource to store documents (with AshPostgres)
    Use ash_ai's vectorize DSL to automatically generate embeddings
    Use vector search queries built into ash_ai
    This is much cleaner than our current HTTP-to-Chroma approach. Let me propose the refactored approach:

    🎯 Recommendation: Refactor to Use ash_ai Built-in Vectorization
    Time estimate: 1-2 hours (much cleaner than fixing Chroma HTTP calls)

    Why This Is Better:
    ✅ No Chroma needed - Uses PostgreSQL's pgvector extension
    ✅ Native Ash integration - Resources get automatic vectorization
    ✅ No API version issues - Everything in-process
    ✅ Better for Thunderline - All data in same database
    ✅ Simpler code - ~200 LOC vs our current 580 LOC
    Proposed Architecture:
    What We Keep:
    ✅ RAG.Serving - Our Bumblebee embedding model (7s load)
    ✅ RAG.EmbeddingModel - Adapter to ash_ai's interface
    ✅ Feature flag system
    What We Replace:
    ❌ RAG.Ingest - Replace with Ash create action
    ❌ RAG.Query - Replace with semantic_search action
    ❌ RAG.Collection (embedded resource) - Replace with proper AshPostgres resource
    ❌ Chroma docker container - Use PostgreSQL pgvector
    ❌ All HTTP client code
    Migration Steps:
    Would you like me to:

    Option A) Full refactor to ash_ai (recommended, 1-2h):

    Create RAG.Document resource with vectorization
    Create RAG.EmbeddingModel adapter for Bumblebee
    Add pgvector extension to PostgreSQL
    Generate migration
    Update acceptance test
    Remove Chroma from docker-compose
    Option B) Quick fix with Chroma library (1-2h, stays with original plan):

    Add {:chroma, "~> 0.2"} to deps
    Refactor ingest/query to use Chroma.Collection API
    Keep current architecture
    Option C) Hybrid - ash_ai for storage, keep LLM generation separate (1.5-2h):

    Use ash_ai for document storage + vector search
    Keep current serving for embeddings
    Separate RAG.Response module for generation
    My recommendation: Option A - It's the cleanest, most maintainable, and aligns perfectly with your Ash-first architecture. Plus it removes external dependencies (Chroma).

    What do you think? Should we refactor to use ash_ai's built-in vectorization?

    Claude Sonnet 4.5 • 1x
    would hybrid increase performance?

    Summarized conversation history

    Looking at the performance characteristics, Hybrid (Option C) wouldn't significantly improve performance over full ash_ai (Option A). Here's why:

    Performance Analysis
    Current Bottleneck: Embedding Generation (7 seconds)
    All three options use the same Bumblebee serving for embeddings, so they have identical performance for this critical path.

    Performance Comparison

end

# Give Chroma time to index
Process.sleep(1000)

# Test 2: Query via Ash - Domains question
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("TEST 2: Query via Ash - 'What domains does Thunderline have?'")
IO.puts(String.duplicate("-", 80))

result = Thunderline.RAG.Collection
|> Ash.Query.for_read(:ask, %{
  query: "What domains does Thunderline have?"
})
|> Ash.read(authorize?: false)

case result do
  {:ok, [response]} ->
    IO.puts("✓ SUCCESS")
    IO.puts("\nQuery: What domains does Thunderline have?")
    IO.puts("\nResponse:")
    IO.puts("  " <> String.replace(response.response, "\n", "\n  "))
    IO.puts("\nSources: #{length(response.sources)} chunks retrieved")
    IO.puts("  Status: #{response.status}")
  {:error, error} ->
    IO.puts("❌ FAILED: #{inspect(error)}")
    raise "Query failed"
end

# Test 3: Direct query - CA system
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("TEST 3: Direct Query - 'How does the CA system work?'")
IO.puts(String.duplicate("-", 80))

result = Thunderline.RAG.Query.ask("How does the CA system work?", top_k: 5)

case result do
  {:ok, result} ->
    IO.puts("✓ SUCCESS")
    IO.puts("\nQuery: How does the CA system work?")
    IO.puts("\nResponse:")
    IO.puts("  " <> String.replace(result.response, "\n", "\n  "))
    IO.puts("\nSources: #{length(result.sources)}")
    Enum.with_index(result.sources, 1)
    |> Enum.each(fn {source, idx} ->
      distance = source["distance"] || source[:distance]
      IO.puts("  #{idx}. Distance: #{Float.round(distance, 4)}")
    end)
  {:error, error} ->
    IO.puts("❌ FAILED: #{inspect(error)}")
    raise "Direct query failed"
end

# Test 4: Performance test
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("TEST 4: Performance - 'What is Thunderline?'")
IO.puts(String.duplicate("-", 80))

{time_μs, result} = :timer.tc(fn ->
  Thunderline.RAG.Query.ask("What is Thunderline?")
end)

time_ms = time_μs / 1000

case result do
  {:ok, _result} ->
    IO.puts("✓ SUCCESS")
    IO.puts("  Query time: #{Float.round(time_ms, 2)}ms")
    cond do
      time_ms < 500 -> IO.puts("  Performance: ⚡ EXCELLENT (< 500ms)")
      time_ms < 2000 -> IO.puts("  Performance: ✓ GOOD (< 2s)")
      true -> IO.puts("  Performance: ⚠️  SLOW (> 2s, but acceptable for first query)")
    end
  {:error, error} ->
    IO.puts("❌ FAILED: #{inspect(error)}")
    raise "Performance test failed"
end

# Test 5: Multi-query test
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("TEST 5: Multi-Query - Verify model stays loaded")
IO.puts(String.duplicate("-", 80))

queries = [
  "What is ThunderBolt?",
  "What is ThunderFlow?",
  "What is ThunderBlock?"
]

results = Enum.map(queries, fn q ->
  {time_μs, result} = :timer.tc(fn ->
    Thunderline.RAG.Query.ask(q, max_tokens: 256)
  end)
  {q, time_μs / 1000, result}
end)

all_successful = Enum.all?(results, fn {_q, _time, result} ->
  match?({:ok, _}, result)
end)

if all_successful do
  IO.puts("✓ SUCCESS: All queries completed")

  Enum.each(results, fn {query, time_ms, {:ok, result}} ->
    IO.puts("\n  Q: #{query}")
    preview = result.response |> String.slice(0..100) |> String.replace("\n", " ")
    IO.puts("  A: #{preview}...")
    IO.puts("  Time: #{Float.round(time_ms, 2)}ms | Sources: #{length(result.sources)}")
  end)

  avg_time = Enum.reduce(results, 0, fn {_q, t, _r}, acc -> acc + t end) / length(results)
  IO.puts("\n  Average query time: #{Float.round(avg_time, 2)}ms")
else
  IO.puts("❌ FAILED: Some queries failed")
  raise "Multi-query test failed"
end

# Summary
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("ACCEPTANCE TEST SUMMARY")
IO.puts(String.duplicate("=", 80))
IO.puts("✓ Test 1: README ingestion - PASSED")
IO.puts("✓ Test 2: Ash query interface - PASSED")
IO.puts("✓ Test 3: Direct query with sources - PASSED")
IO.puts("✓ Test 4: Performance measurement - PASSED")
IO.puts("✓ Test 5: Multi-query execution - PASSED")
IO.puts("\n🎉 ALL TESTS PASSED! RAG MVP IS COMPLETE! 🎉\n")
IO.puts(String.duplicate("=", 80) <> "\n")
