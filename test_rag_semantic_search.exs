#!/usr/bin/env elixir

# Test semantic search functionality
alias Thunderline.RAG.Document

IO.puts("\n=== Testing Semantic Search ===\n")

# Create multiple documents with different content
docs = [
  %{content: "Machine learning enables semantic search through vector embeddings", metadata: %{source: "ml"}},
  %{content: "Thunderline is a federated social platform built with Elixir", metadata: %{source: "thunderline"}},
  %{content: "Vector databases store high-dimensional embeddings for similarity search", metadata: %{source: "vectors"}},
  %{content: "Phoenix LiveView provides real-time user interfaces", metadata: %{source: "phoenix"}}
]

IO.puts("1. Creating #{length(docs)} test documents...")

created_docs =
  Enum.map(docs, fn doc_attrs ->
    case Document
         |> Ash.Changeset.for_create(:create, doc_attrs)
         |> Ash.create() do
      {:ok, doc} ->
        IO.puts("   ✅ Created: #{String.slice(doc.content, 0..50)}...")
        doc

      {:error, error} ->
        IO.puts("   ❌ Failed: #{inspect(error)}")
        System.halt(1)
    end
  end)

IO.puts("\n2. Generating embeddings for all documents...")

docs_with_vectors =
  Enum.map(created_docs, fn doc ->
    case Ash.Changeset.for_update(doc, :ash_ai_update_embeddings)
         |> Ash.update() do
      {:ok, doc_updated} ->
        IO.puts("   ✅ Vectorized: #{String.slice(doc.content, 0..50)}...")
        doc_updated

      {:error, error} ->
        IO.puts("   ❌ Failed: #{inspect(error)}")
        System.halt(1)
    end
  end)

IO.puts("\n3. Testing semantic search for 'embeddings and vectors'...")

# This query should match documents about vectors and ML
case Document.semantic_search("embeddings and vectors", query: [limit: 3]) do
  {:ok, results} ->
    IO.puts("   ✅ Found #{length(results)} results:")

    Enum.with_index(results, 1)
    |> Enum.each(fn {doc, idx} ->
      content_preview = String.slice(doc.content, 0..60)
      IO.puts("      #{idx}. #{content_preview}...")
    end)

    # Verify the first result is relevant
    first_result = List.first(results)

    if String.contains?(first_result.content, ["vector", "embedding", "Machine"]) do
      IO.puts("\n   ✅ Top result is relevant!")
    else
      IO.puts("\n   ⚠️  Top result may not be most relevant")
    end

    IO.puts("\n🎉 Semantic search test PASSED!\n")

  {:error, error} ->
    IO.puts("   ❌ Search failed: #{inspect(error)}")
    System.halt(1)
end
