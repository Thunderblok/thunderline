#!/usr/bin/env elixir

# Quick RAG test for ash_ai integration
alias Thunderline.RAG.Document

IO.puts("\n=== Testing ash_ai RAG ===\n")

# Test 1: Create document
IO.puts("1. Creating document...")

case Document
     |> Ash.Changeset.for_create(:create, %{
       content: "Thunderline is a federated social platform",
       metadata: %{source: "test"}
     })
     |> Ash.create() do
  {:ok, doc} ->
    IO.puts("   ✅ Created: #{doc.id}")

    # Test 2: Generate embeddings
    IO.puts("\n2. Generating embeddings (may take 10s for model load)...")

    case Ash.Changeset.for_update(doc, :ash_ai_update_embeddings)
         |> Ash.update() do
      {:ok, doc_updated} ->
        IO.puts("   ✅ Embeddings generated")

        # Test 3: Verify vector
        IO.puts("\n3. Verifying vector...")
        doc_loaded = Ash.load!(doc_updated, :full_text_vector)

        if doc_loaded.full_text_vector do
          vector_list = Ash.Vector.to_list(doc_loaded.full_text_vector)
          vector_len = length(vector_list)
          IO.puts("   ✅ Vector length: #{vector_len}")
          IO.puts("   ✅ First 5: #{inspect(Enum.take(vector_list, 5))}")
          IO.puts("\n🎉 ash_ai RAG test PASSED!\n")
        else
          IO.puts("   ❌ Vector is nil")
          System.halt(1)
        end

      {:error, error} ->
        IO.puts("   ❌ Failed to update embeddings: #{inspect(error)}")
        System.halt(1)
    end

  {:error, error} ->
    IO.puts("   ❌ Failed to create document: #{inspect(error)}")
    System.halt(1)
end
