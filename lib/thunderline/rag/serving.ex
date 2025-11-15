defmodule Thunderline.Thunderbolt.RAG.Serving do
  @moduledoc """
  Manages Nx.Serving processes for RAG (Retrieval-Augmented Generation).

  Starts and supervises two Bumblebee model servings:
  - **Embedding Model**: Jina v2 base-code (code-optimized embeddings, 768 dims)
  - **Generation Model**: Phi-3.5 Mini Instruct (3.8B params, efficient CPU inference)

  Models run with EXLA compilation for performance.

  ## Configuration

  Models are downloaded from HuggingFace on first use (cached in ~/.cache/huggingface):
  - Jina: jinaai/jina-embeddings-v2-base-code
  - Phi: microsoft/Phi-3.5-mini-instruct

  Set `RAG_ENABLED=false` to disable startup.

  ## Usage

      # Embed text (returns 768-dim vector)
      {:ok, embedding} = Thunderline.Thunderbolt.RAG.Serving.embed("def hello_world")

      # Generate response with context
      {:ok, response} = Thunderline.Thunderbolt.RAG.Serving.generate(
        "What domains does Thunderline have?",
        "ThunderBolt handles ML/compute, ThunderGate handles auth..."
      )
  """

  use GenServer
  require Logger

  @embed_serving_name __MODULE__.Embed
  @generate_serving_name __MODULE__.Generate

  # Embedding model: sentence-transformers/all-MiniLM-L6-v2 (lightweight, 384 dims, well-supported)
  # This is a popular, fast model that works well with Bumblebee
  @embed_model_repo "sentence-transformers/all-MiniLM-L6-v2"

  # Generation model: Phi-3.5 Mini Instruct (3.8B params, efficient)
  @generate_model_repo "microsoft/Phi-3.5-mini-instruct"

  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RAG serving manager.

  Automatically starts if `:rag_enabled` feature flag is true.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Embeds a text string into a 768-dimensional vector.

  ## Examples

      iex> Thunderline.Thunderbolt.RAG.Serving.embed("def hello_world(): pass")
      {:ok, #Nx.Tensor<f32[768]>[0.123, -0.456, ...]>}
  """
  def embed(text) when is_binary(text) do
    try do
      result = Nx.Serving.batched_run(@embed_serving_name, text)
      {:ok, result.embedding}
    rescue
      e ->
        Logger.error("Embedding failed: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Embeds multiple texts in a batch (more efficient).

  ## Examples

      iex> Thunderline.Thunderbolt.RAG.Serving.embed_batch(["text 1", "text 2"])
      {:ok, [#Nx.Tensor<...>, #Nx.Tensor<...>]}
  """
  def embed_batch(texts) when is_list(texts) do
    try do
      results = Enum.map(texts, &Nx.Serving.batched_run(@embed_serving_name, &1))
      embeddings = Enum.map(results, & &1.embedding)
      {:ok, embeddings}
    rescue
      e ->
        Logger.error("Batch embedding failed: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Generates text response given a query and context.

  ## Parameters
  - `query`: User question
  - `context`: Retrieved context chunks (concatenated)
  - `opts`: Options
    - `:max_new_tokens` - Max tokens to generate (default: 512)
    - `:temperature` - Sampling temperature (default: 0.7)

  ## Examples

      iex> Thunderline.Thunderbolt.RAG.Serving.generate(
      ...>   "What is ThunderBolt?",
      ...>   "ThunderBolt handles ML compute and Cerebros integration."
      ...> )
      {:ok, "ThunderBolt is the domain responsible for..."}
  """
  def generate(query, context, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_new_tokens, 512)
    temperature = Keyword.get(opts, :temperature, 0.7)

    prompt = build_prompt(query, context)

    try do
      result =
        Nx.Serving.batched_run(@generate_serving_name, prompt,
          max_new_tokens: max_tokens,
          temperature: temperature
        )

      {:ok, extract_response(result)}
    rescue
      e ->
        Logger.error("Generation failed: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    if Thunderline.Feature.enabled?(:rag_enabled) do
      Logger.info("[RAG.Serving] Starting Bumblebee model servings...")

      # Start servings synchronously - init will block until models are loaded
      # This ensures the serving is fully ready when start_link returns
      start_embed_serving()

      # TODO: Generation model (Phi-3.5 mini) is 5GB and slow to download (15+ min)
      # For MVP, we only need embeddings for ingest/query (vector search)
      # Uncomment when Q&A generation features are needed:
      # start_generate_serving()

      {:ok, %{started_at: System.system_time(:millisecond)}}
    else
      Logger.info("[RAG.Serving] Disabled (rag_enabled=false)")
      {:ok, %{disabled: true}}
    end
  end

  # Private Helpers
  # ---------------------------------------------------------------------------

  defp start_embed_serving do
    Logger.info("[RAG.Serving] Loading embedding model: #{@embed_model_repo}")

    # Load the model (sentence-transformers models work out of the box with Bumblebee)
    {:ok, model_info} = Bumblebee.load_model({:hf, @embed_model_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @embed_model_repo})

    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        defn_options: [compiler: EXLA],
        compile: [batch_size: 1, sequence_length: 512]
      )

    Nx.Serving.start_link(name: @embed_serving_name, serving: serving)

    Logger.info("[RAG.Serving] Embedding serving ready: #{inspect(@embed_serving_name)}")
  end

  defp start_generate_serving do
    Logger.info("[RAG.Serving] Loading generation model: #{@generate_model_repo}")

    {:ok, model_info} = Bumblebee.load_model({:hf, @generate_model_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @generate_model_repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, @generate_model_repo})

    serving =
      Bumblebee.Text.generation(model_info, tokenizer, generation_config,
        defn_options: [compiler: EXLA],
        compile: [batch_size: 1, sequence_length: 1024]
      )

    Nx.Serving.start_link(name: @generate_serving_name, serving: serving)

    Logger.info("[RAG.Serving] Generation serving ready: #{inspect(@generate_serving_name)}")
  end

  defp build_prompt(query, context) do
    """
    You are a helpful assistant answering questions about the Thunderline codebase.

    Context:
    #{context}

    Question: #{query}

    Answer concisely and accurately based on the context provided. If the context doesn't contain enough information, say so.

    Answer:
    """
  end

  defp extract_response(%{results: [%{text: text}]}) do
    # Remove the prompt from response (Phi sometimes includes it)
    text
    |> String.split("Answer:")
    |> List.last()
    |> String.trim()
  end

  defp extract_response(result) do
    # Fallback if structure differs
    inspect(result)
  end
end
