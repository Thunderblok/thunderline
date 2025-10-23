defmodule Thunderline.RAG.Ingest do
  @moduledoc """
  Document ingestion pipeline for RAG system.

  Flow: text → chunk → embed → store in Chroma

  ## Chunking Strategy (MVP)

  Simple sentence-based chunking:
  - Split text by sentence boundaries
  - Group 5 sentences per chunk
  - No overlap (can add in Phase 2)
  - Preserves semantic coherence better than fixed token windows

  ## Storage

  Stores chunks with embeddings in Chroma vector database via HTTP API.
  Collection name: `thunderline_docs`

  ## Usage

      # Ingest a document
      {:ok, result} = Thunderline.RAG.Ingest.ingest_document(
        File.read!("README.md"),
        %{source: "README.md", type: "documentation"}
      )

      # Result
      %{
        collection: "thunderline_docs",
        chunks_stored: 42,
        chunk_ids: ["chunk_1", "chunk_2", ...]
      }
  """

  require Logger

  alias Thunderline.RAG.Serving

  @default_collection "thunderline_docs"
  @sentences_per_chunk 5

  @doc """
  Ingests a document into the RAG system.

  ## Parameters
  - `text` - Document text to ingest
  - `metadata` - Optional metadata (source, type, author, etc.)
  - `opts` - Options
    - `:collection` - Collection name (default: "thunderline_docs")
    - `:chunk_size` - Sentences per chunk (default: 5)

  ## Returns
  - `{:ok, result}` - Success with stats
  - `{:error, reason}` - Failure reason

  ## Examples

      iex> Thunderline.RAG.Ingest.ingest_document(
      ...>   "ThunderBolt handles ML compute. ThunderGate handles auth.",
      ...>   %{source: "example.txt"}
      ...> )
      {:ok, %{collection: "thunderline_docs", chunks_stored: 1, ...}}
  """
  def ingest_document(text, metadata \\ %{}, opts \\ []) when is_binary(text) do
    collection = Keyword.get(opts, :collection, @default_collection)
    chunk_size = Keyword.get(opts, :chunk_size, @sentences_per_chunk)

    Logger.info("[RAG.Ingest] Starting ingestion: #{byte_size(text)} bytes")

    with {:ok, collection_id} <- ensure_collection(collection),
         {:ok, chunks} <- chunk_text(text, chunk_size),
         {:ok, embeddings} <- embed_chunks(chunks),
         {:ok, result} <- store_in_chroma(collection_id, chunks, embeddings, metadata) do
      Logger.info("[RAG.Ingest] Success: #{length(chunks)} chunks stored")
      {:ok, Map.put(result, :collection, collection)}
    else
      {:error, reason} = err ->
        Logger.error("[RAG.Ingest] Failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Ensures a Chroma collection exists, creating it if necessary

  ## Parameters
  - `collection` - Collection name

  ## Returns
  - `{:ok, collection_id}` - Collection exists or was created, returns UUID
  - `{:error, reason}` - Failed to create
  """
  def ensure_collection(collection) do
    base_url = chroma_base_url()

    # Check if collection exists (V1 API)
    # Note: V1 API returns 500 with ValueError when collection doesn't exist
    case Req.get("#{base_url}/api/v1/collections/#{collection}") do
      {:ok, %{status: 200, body: body}} ->
        Logger.debug("[RAG.Ingest] Collection exists: #{collection}")
        {:ok, body["id"]}

      # V1 API returns 500 with ValueError when collection doesn't exist
      {:ok, %{status: 500, body: %{"error" => error}}} when is_binary(error) ->
        if String.contains?(error, "does not exist") do
          # Create collection
          Logger.info("[RAG.Ingest] Creating collection: #{collection}")

          case Req.post("#{base_url}/api/v1/collections",
                 json: %{
                   name: collection,
                   metadata: %{
                     description: "Thunderline codebase documentation and knowledge",
                     embedding_model: "jinaai/jina-embeddings-v2-base-code",
                     dimensions: 768
                   }
                 }
               ) do
            {:ok, %{status: status, body: body}} when status in [200, 201] ->
              Logger.info("[RAG.Ingest] Collection created: #{collection}")
              {:ok, body["id"]}

            {:ok, %{status: status, body: body}} ->
              {:error, "Failed to create collection: HTTP #{status}, #{inspect(body)}"}

            {:error, reason} ->
              {:error, "HTTP request failed: #{inspect(reason)}"}
          end
        else
          {:error, "Unexpected error: #{error}"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Unexpected response: HTTP #{status}, #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Private Helpers
  # ---------------------------------------------------------------------------

  defp chunk_text(text, sentences_per_chunk) do
    # Split by sentence boundaries (simple heuristic)
    sentences =
      text
      |> String.split(~r/\.[\s\n]+/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Group into chunks
    chunks =
      sentences
      |> Enum.chunk_every(sentences_per_chunk)
      |> Enum.map(fn sentence_group ->
        Enum.join(sentence_group, ". ") <> "."
      end)

    Logger.debug("[RAG.Ingest] Chunked #{length(sentences)} sentences into #{length(chunks)} chunks")

    {:ok, chunks}
  end

  defp embed_chunks(chunks) do
    Logger.debug("[RAG.Ingest] Embedding #{length(chunks)} chunks...")

    # Batch embed all chunks
    case Serving.embed_batch(chunks) do
      {:ok, embeddings} ->
        # Convert Nx tensors to lists for JSON serialization
        embedding_lists = Enum.map(embeddings, &Nx.to_flat_list/1)
        {:ok, embedding_lists}

      {:error, reason} = err ->
        Logger.error("[RAG.Ingest] Embedding failed: #{inspect(reason)}")
        err
    end
  end

  defp store_in_chroma(collection_id, chunks, embeddings, metadata) do
    base_url = chroma_base_url()

    # Generate UUIDs for chunks (Chroma 0.4.24 requires UUID format)
    chunk_ids = Enum.map(1..length(chunks), fn _ -> Ash.UUID.generate() end)

    # Prepare metadata for each chunk (same metadata + chunk index)
    metadatas =
      Enum.with_index(chunks, 1)
      |> Enum.map(fn {_chunk, idx} ->
        Map.merge(metadata, %{
          chunk_index: idx,
          total_chunks: length(chunks),
          ingested_at: System.system_time(:millisecond)
        })
      end)

    # Store in Chroma using collection ID (UUID)
    case Req.post("#{base_url}/api/v1/collections/#{collection_id}/add",
           json: %{
             ids: chunk_ids,
             embeddings: embeddings,
             documents: chunks,
             metadatas: metadatas
           }
         ) do
      {:ok, %{status: status}} when status in [200, 201] ->
        {:ok,
         %{
           chunks: length(chunks),
           chunks_stored: length(chunks),
           chunk_ids: chunk_ids
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, "Chroma storage failed: HTTP #{status}, #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp chroma_base_url do
    System.get_env("CHROMA_URL", "http://localhost:8000")
  end
end
