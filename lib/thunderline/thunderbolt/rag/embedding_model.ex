defmodule Thunderline.Thunderbolt.RAG.EmbeddingModel do
  @moduledoc """
  Adapter implementing AshAi.EmbeddingModel behavior.

  Wraps our Bumblebee-based RAG.Serving to work with ash_ai's vectorization.
  Uses sentence-transformers/all-MiniLM-L6-v2 model (384 dimensions).

  ## Usage

      # In a resource with vectorization:
      vectorize do
        embedding_model Thunderline.Thunderbolt.RAG.EmbeddingModel
        # ...
      end
  """
  use AshAi.EmbeddingModel
  require Logger

  @impl true
  def dimensions(_opts), do: 384

  @impl true
  def generate(texts, _opts) when is_list(texts) do
    if Thunderline.Feature.enabled?(:rag_enabled) do
      case Thunderline.Thunderbolt.RAG.Serving.embed_batch(texts) do
        {:ok, tensors} ->
          # Convert Nx.Tensor to list of floats for pgvector
          vectors = Enum.map(tensors, &Nx.to_flat_list/1)
          {:ok, vectors}

        {:error, reason} ->
          Logger.error("[RAG.EmbeddingModel] Failed to generate embeddings: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # If RAG is disabled, return dummy vectors (won't be used in production)
      Logger.warning("[RAG.EmbeddingModel] RAG disabled, returning dummy embeddings")
      dummy_vector = List.duplicate(0.0, 384)
      {:ok, List.duplicate(dummy_vector, length(texts))}
    end
  end
end
