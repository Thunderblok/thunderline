defmodule Thunderline.Thunderbolt.RAG.Query do
  @moduledoc """
  Query processing and retrieval for RAG (Retrieval-Augmented Generation).

  Handles semantic search, context retrieval, and LLM-augmented responses.

  ## Usage

      # Ask a question with RAG
      {:ok, response, sources} = Thunderline.Thunderbolt.RAG.Query.ask(
        "What is the ThunderBolt domain responsible for?",
        top_k: 3,
        max_tokens: 500
      )

      # Build a prompt manually
      {:ok, prompt} = Thunderline.Thunderbolt.RAG.Query.build_prompt(
        "What is ThunderBolt?",
        ["ThunderBolt handles ML compute...", "ThunderBolt uses Nx..."],
        system: "You are a helpful assistant."
      )
  """

  require Logger
  alias Thunderline.Thunderbolt.RAG.Serving

  @default_top_k 3
  @default_max_tokens 1000
  @default_collection "documents"

  @doc """
  Checks if RAG system is enabled.
  """
  def enabled? do
    Thunderline.Features.enabled?(:rag_enabled)
  end

  @doc """
  Asks a question using RAG retrieval and generation.

  ## Process

  1. Checks if RAG is enabled
  2. Embeds the query
  3. Retrieves top-k most relevant chunks from vector DB
  4. Builds prompt with retrieved context
  5. Generates response using LLM
  6. Extracts source references

  ## Options

    * `:top_k` - Number of chunks to retrieve (default: 3)
    * `:max_tokens` - Maximum tokens in response (default: 1000)
    * `:collection` - Vector DB collection to search (default: "documents")
    * `:system_prompt` - Custom system prompt

  ## Returns

    * `{:ok, response, sources}` - Generated response and source metadata
    * `{:error, :rag_disabled}` - RAG system is not enabled
    * `{:error, reason}` - Processing error
  """
  def ask(query, opts \\ []) do
    if not enabled?() do
      {:error, :rag_disabled}
    else
      top_k = Keyword.get(opts, :top_k, @default_top_k)
      max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
      collection = Keyword.get(opts, :collection, @default_collection)
      system_prompt = Keyword.get(opts, :system_prompt, default_system_prompt())

      with {:ok, query_embedding} <- Serving.embed(query),
           {:ok, results} <- search_vector_db(query_embedding, top_k, collection),
           contexts <- extract_contexts(results),
           {:ok, prompt} <- build_prompt(query, contexts, system: system_prompt),
           {:ok, response} <- generate_response(prompt, max_tokens),
           sources <- extract_sources(results) do
        Logger.info("RAG query completed",
          query: String.slice(query, 0, 50),
          chunks_retrieved: length(results)
        )

        :telemetry.execute(
          [:thunderline, :rag, :query],
          %{chunks: length(results), tokens: String.length(response)},
          %{collection: collection}
        )

        {:ok, response, sources}
      end
    end
  end

  @doc """
  Builds a prompt from query and retrieved contexts.

  ## Options

    * `:system` - System prompt (default: helpful assistant)
    * `:format` - Prompt format (default: :chat)

  ## Examples

      iex> Thunderline.Thunderbolt.RAG.Query.build_prompt(
      ...>   "What is Elixir?",
      ...>   ["Elixir is a functional language...", "Elixir runs on BEAM..."]
      ...> )
      {:ok, "Context:\\n1. Elixir is a functional language...\\n\\nQuestion: What is Elixir?"}
  """
  def build_prompt(query, contexts, opts \\ []) do
    system = Keyword.get(opts, :system, default_system_prompt())

    context_section =
      contexts
      |> Enum.with_index(1)
      |> Enum.map(fn {context, idx} -> "#{idx}. #{context}" end)
      |> Enum.join("\n")

    prompt = """
    #{system}

    Context:
    #{context_section}

    Question: #{query}

    Please provide a detailed answer based on the context above. If the context doesn't contain relevant information, acknowledge that.
    """

    {:ok, String.trim(prompt)}
  end

  @doc """
  Extracts source references from search results.

  Returns a list of source metadata maps.

  ## Examples

      iex> Thunderline.Thunderbolt.RAG.Query.extract_sources([
      ...>   %{metadata: %{source: "docs/README.md", chunk_index: 0}}
      ...> ])
      [%{source: "docs/README.md", chunk_index: 0}]
  """
  def extract_sources(results) do
    results
    |> Enum.map(fn result ->
      Map.get(result, :metadata, %{})
    end)
    |> Enum.reject(&(&1 == %{}))
  end

  # Private functions

  defp default_system_prompt do
    """
    You are a helpful AI assistant for Thunderline, a distributed application platform.
    Provide accurate, concise answers based on the provided context.
    If you don't know something or the context doesn't contain the information, say so clearly.
    """
  end

  defp search_vector_db(_query_embedding, top_k, collection) do
    # In a real implementation, this would query Chroma or similar
    # For now, simulate retrieval with empty results
    Logger.debug("Searching vector DB",
      collection: collection,
      top_k: top_k
    )

    # Simulated results
    results = []

    {:ok, results}
  end

  defp extract_contexts(results) do
    Enum.map(results, fn result ->
      Map.get(result, :text, "")
    end)
  end

  defp generate_response(prompt, max_tokens) do
    case Serving.generate(prompt, max_length: max_tokens) do
      {:ok, response} ->
        # Extract generated text from response
        text = extract_generated_text(response)
        {:ok, text}

      {:error, reason} ->
        Logger.error("Failed to generate response", error: reason)
        {:error, reason}
    end
  end

  defp extract_generated_text(response) when is_binary(response) do
    response
  end

  defp extract_generated_text(response) when is_map(response) do
    # Handle different response formats from Bumblebee
    response
    |> Map.get(:results, [])
    |> List.first()
    |> case do
      nil -> ""
      result when is_binary(result) -> result
      result when is_map(result) -> Map.get(result, :text, "")
    end
  end

  defp extract_generated_text(_), do: ""
end
