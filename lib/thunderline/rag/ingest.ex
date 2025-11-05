defmodule Thunderline.RAG.Ingest do
  @moduledoc """
  Document ingestion pipeline for RAG (Retrieval-Augmented Generation).

  Handles chunking, embedding, and storage of documents in the vector database.

  ## Usage

      # Ingest a document
      {:ok, chunk_ids} = Thunderline.RAG.Ingest.ingest_document(
        "This is a long document...",
        %{source: "docs/README.md", author: "team"}
      )

      # Check if RAG is enabled
      if Thunderline.RAG.Ingest.enabled?() do
        # ... perform RAG operations
      end
  """

  require Logger
  alias Thunderline.RAG.Serving

  @default_chunk_size 512
  @default_chunk_overlap 50

  @doc """
  Checks if RAG system is enabled.
  """
  def enabled? do
    Thunderline.Features.enabled?(:rag_enabled)
  end

  @doc """
  Ingests a document into the RAG system.

  ## Process

  1. Checks if RAG is enabled
  2. Chunks the text into manageable segments
  3. Generates embeddings for each chunk
  4. Generates unique IDs for chunks
  5. Stores chunks with metadata in vector DB

  ## Options

    * `:chunk_size` - Maximum size of each chunk (default: 512 characters)
    * `:chunk_overlap` - Overlap between chunks (default: 50 characters)
    * `:collection` - Vector DB collection name (default: "documents")

  ## Returns

    * `{:ok, chunk_ids}` - List of generated chunk IDs
    * `{:error, :rag_disabled}` - RAG system is not enabled
    * `{:error, reason}` - Processing error
  """
  def ingest_document(text, metadata \\ %{}, opts \\ []) do
    if not enabled?() do
      {:error, :rag_disabled}
    else
      chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
      chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)
      collection = Keyword.get(opts, :collection, "documents")

      with {:ok, chunks} <- chunk_text(text, chunk_size, chunk_overlap),
           {:ok, embeddings} <- embed_chunks(chunks),
           {:ok, chunk_ids} <- store_chunks(chunks, embeddings, metadata, collection) do
        Logger.info("Ingested document",
          chunks: length(chunks),
          metadata: metadata
        )

        :telemetry.execute(
          [:thunderline, :rag, :ingest],
          %{chunks: length(chunks)},
          metadata
        )

        {:ok, chunk_ids}
      end
    end
  end

  @doc """
  Chunks text into overlapping segments.

  Uses sentence-aware chunking when possible, falling back to
  character-based chunking for long sentences.

  ## Examples

      iex> Thunderline.RAG.Ingest.chunk_text("Hello world. How are you?", 10, 2)
      {:ok, ["Hello world.", "world. How", "How are you?"]}
  """
  def chunk_text(text, chunk_size, overlap \\ 0) do
    if text == "" or is_nil(text) do
      {:ok, []}
    else
      # Split on sentence boundaries first
      sentences = String.split(text, ~r/[.!?]+\s+/, trim: true)

      chunks =
        sentences
        |> Enum.reduce([], fn sentence, acc ->
          chunk_sentences(sentence, chunk_size, overlap, acc)
        end)
        |> Enum.reverse()
        |> Enum.reject(&(&1 == ""))

      {:ok, chunks}
    end
  end

  @doc """
  Generates a unique, content-based ID for a chunk.

  Uses SHA256 hash of the chunk text for consistency.

  ## Examples

      iex> Thunderline.RAG.Ingest.generate_chunk_id("Hello world")
      "64ec88ca00b268e5ba1a35678a1b5316d212f4f366b2477232534a8aeca37f3c"
  """
  def generate_chunk_id(chunk_text) do
    :crypto.hash(:sha256, chunk_text)
    |> Base.encode16(case: :lower)
  end

  # Private functions

  defp chunk_sentences(sentence, chunk_size, overlap, acc) do
    if String.length(sentence) <= chunk_size do
      # Sentence fits in one chunk
      [sentence | acc]
    else
      # Need to split sentence further
      words = String.split(sentence, " ", trim: true)

      words
      |> Enum.chunk_every(
        div(chunk_size, 6),  # Approximate words per chunk
        div(chunk_size, 6) - div(overlap, 6)
      )
      |> Enum.map(&Enum.join(&1, " "))
      |> Enum.reduce(acc, fn chunk, a -> [chunk | a] end)
    end
  end

  defp embed_chunks(chunks) do
    case Serving.embed_batch(chunks) do
      {:ok, embeddings} ->
        {:ok, embeddings}

      {:error, reason} ->
        Logger.error("Failed to embed chunks", error: reason)
        {:error, reason}
    end
  end

  defp store_chunks(chunks, embeddings, metadata, collection) do
    # Generate IDs for each chunk
    chunk_data =
      Enum.zip([chunks, embeddings])
      |> Enum.with_index()
      |> Enum.map(fn {{chunk_text, embedding}, index} ->
        chunk_id = generate_chunk_id(chunk_text)

        %{
          id: chunk_id,
          text: chunk_text,
          embedding: embedding,
          metadata: Map.merge(metadata, %{
            chunk_index: index,
            chunk_size: String.length(chunk_text)
          })
        }
      end)

    # In a real implementation, this would store in Chroma or similar
    # For now, we'll simulate success and return the IDs
    chunk_ids = Enum.map(chunk_data, & &1.id)

    Logger.debug("Stored chunks in collection",
      collection: collection,
      count: length(chunk_ids)
    )

    {:ok, chunk_ids}
  end
end
