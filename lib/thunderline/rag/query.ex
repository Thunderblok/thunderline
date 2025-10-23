defmodule Thunderline.RAG.Query do
  @moduledoc """
  RAG query pipeline: embed → retrieve → generate

  Complete retrieval-augmented generation pipeline:
  1. Embed user query
  2. Retrieve similar chunks from Chroma
  3. Build prompt with context
  4. Generate response via LLM
  5. Return answer + source citations

  ## Usage

      {:ok, result} = Thunderline.RAG.Query.ask(
        "What domains does Thunderline have?",
        collection: "thunderline_docs"
      )

      result.answer
      # => "Thunderline has several domains: ThunderBolt handles ML compute..."

      result.sources
      # => [
      #   %{chunk: "ThunderBolt is responsible for...", score: 0.92, metadata: %{source: "README.md"}},
      #   ...
      # ]
  """

  require Logger

  alias Thunderline.RAG.Serving

  @default_collection "thunderline_docs"
  @default_top_k 5
  @default_max_tokens 512
  @default_temperature 0.7

  @doc """
  Asks a question using RAG.

  ## Parameters
  - `query` - Natural language question
  - `opts` - Options
    - `:collection` - Chroma collection (default: "thunderline_docs")
    - `:top_k` - Number of chunks to retrieve (default: 5)
    - `:max_tokens` - Max tokens to generate (default: 512)
    - `:temperature` - Sampling temperature (default: 0.7)

  ## Returns
  - `{:ok, result}` - Success with answer + sources
  - `{:error, reason}` - Failure reason

  ## Result Structure

      %{
        answer: "Thunderline has several domains...",
        sources: [
          %{
            chunk: "Text content...",
            score: 0.92,  # Cosine similarity
            metadata: %{source: "README.md", chunk_index: 1, ...}
          },
          ...
        ],
        query: "What domains does Thunderline have?",
        timing: %{
          embed_ms: 45,
          retrieve_ms: 12,
          generate_ms: 890,
          total_ms: 947
        }
      }

  ## Examples

      iex> Thunderline.RAG.Query.ask("What is ThunderBolt?")
      {:ok, %{
        answer: "ThunderBolt is the domain handling ML compute and Cerebros integration.",
        sources: [...],
        ...
      }}
  """
  def ask(query, opts \\ []) when is_binary(query) do
    collection = Keyword.get(opts, :collection, @default_collection)
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(opts, :temperature, @default_temperature)

    start_time = System.monotonic_time(:millisecond)

    Logger.info("[RAG.Query] Question: #{String.slice(query, 0..100)}")

    with {:ok, collection_id} <- get_collection_id(collection),
         {:ok, query_embedding, t1} <- embed_query(query),
         {:ok, sources, t2} <- retrieve_similar(collection_id, query_embedding, top_k),
         {:ok, context} <- build_context(sources),
         {:ok, answer, t3} <- generate_answer(query, context, max_tokens, temperature) do
      total_time = System.monotonic_time(:millisecond) - start_time

      result = %{
        answer: answer,
        sources: sources,
        query: query,
        timing: %{
          embed_ms: t1,
          retrieve_ms: t2,
          generate_ms: t3,
          total_ms: total_time
        }
      }

      Logger.info("[RAG.Query] Success: #{total_time}ms total, #{length(sources)} sources")

      {:ok, result}
    else
      {:error, reason} = err ->
        Logger.error("[RAG.Query] Failed: #{inspect(reason)}")
        err
    end
  end

  # Private Helpers
  # ---------------------------------------------------------------------------

  defp get_collection_id(collection_name) do
    base_url = chroma_base_url()

    case Req.get("#{base_url}/api/v1/collections/#{collection_name}") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body["id"]}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get collection: HTTP #{status}, #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp embed_query(query) do
    start_time = System.monotonic_time(:millisecond)

    case Serving.embed(query) do
      {:ok, embedding} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        # Convert to list for JSON
        embedding_list = Nx.to_flat_list(embedding)
        {:ok, embedding_list, elapsed}

      {:error, reason} = err ->
        Logger.error("[RAG.Query] Embedding failed: #{inspect(reason)}")
        err
    end
  end

  defp retrieve_similar(collection_id, query_embedding, top_k) do
    start_time = System.monotonic_time(:millisecond)
    base_url = chroma_base_url()

    # Query Chroma using collection ID (UUID)
    case Req.post("#{base_url}/api/v1/collections/#{collection_id}/query",
           json: %{
             query_embeddings: [query_embedding],
             n_results: top_k,
             include: ["documents", "metadatas", "distances"]
           }
         ) do
      {:ok, %{status: 200, body: body}} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        # Parse Chroma response
        sources = parse_chroma_results(body)

        Logger.debug("[RAG.Query] Retrieved #{length(sources)} chunks in #{elapsed}ms")

        {:ok, sources, elapsed}

      {:ok, %{status: 404}} ->
        Logger.warning("[RAG.Query] Collection not found: #{collection_id}")
        {:error, :collection_not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, "Chroma query failed: HTTP #{status}, #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp parse_chroma_results(%{"documents" => [docs], "metadatas" => [metadatas], "distances" => [distances]}) do
    # Chroma returns nested lists: [[doc1, doc2, ...]]
    # Distances are cosine distances (lower = more similar)
    docs
    |> Enum.zip(metadatas)
    |> Enum.zip(distances)
    |> Enum.map(fn {{doc, metadata}, distance} ->
      %{
        chunk: doc,
        # Convert distance to similarity score (0-1 range)
        score: max(0.0, 1.0 - distance),
        metadata: metadata
      }
    end)
  end

  defp parse_chroma_results(response) do
    # Fallback for unexpected response structure
    Logger.warning("[RAG.Query] Unexpected Chroma response structure: #{inspect(response)}")
    []
  end

  defp build_context(sources) do
    # Concatenate source chunks with citations
    context =
      sources
      |> Enum.with_index(1)
      |> Enum.map(fn {source, idx} ->
        citation = format_citation(source.metadata, idx)
        "[#{idx}] #{source.chunk}\n#{citation}"
      end)
      |> Enum.join("\n\n---\n\n")

    {:ok, context}
  end

  defp format_citation(metadata, idx) do
    # Format source citation
    source = Map.get(metadata, "source", "unknown")
    chunk_idx = Map.get(metadata, "chunk_index", "?")
    "(Source: #{source}, Chunk #{chunk_idx})"
  end

  defp generate_answer(query, context, max_tokens, temperature) do
    start_time = System.monotonic_time(:millisecond)

    case Serving.generate(query, context,
           max_new_tokens: max_tokens,
           temperature: temperature
         ) do
      {:ok, answer} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        {:ok, answer, elapsed}

      {:error, reason} = err ->
        Logger.error("[RAG.Query] Generation failed: #{inspect(reason)}")
        err
    end
  end

  defp chroma_base_url do
    System.get_env("CHROMA_URL", "http://localhost:8000")
  end
end
