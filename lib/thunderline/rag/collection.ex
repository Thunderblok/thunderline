defmodule Thunderline.RAG.Collection do
  @moduledoc """
  Ash.Resource wrapper for RAG operations.

  Provides high-level actions for document ingestion and querying
  through the Ash Framework, integrating with RAG.Ingest and RAG.Query.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded

  require Logger

  actions do
    # No default actions needed - we define custom ones
    defaults []

    @doc """
    Ingest a document into the RAG system.

    ## Parameters
    - text: The document text to ingest
    - metadata: Optional metadata to attach (source, author, etc.)

    ## Returns
    - {:ok, resource} with ingestion results
    - {:error, error} if ingestion fails
    """
    create :ingest do
      accept [:text, :metadata]

      change fn changeset, _context ->
        text = Ash.Changeset.get_attribute(changeset, :text)
        metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

        Logger.info("[RAG.Collection] Starting document ingestion")

        case Thunderline.RAG.Ingest.ingest_document(text, metadata) do
          {:ok, result} ->
            Logger.info(
              "[RAG.Collection] Successfully ingested #{result.chunks} chunks into #{result.collection}"
            )

            changeset
            |> Ash.Changeset.force_change_attribute(:result, result)
            |> Ash.Changeset.force_change_attribute(:status, "completed")

          {:error, reason} ->
            Logger.error("[RAG.Collection] Ingestion failed: #{inspect(reason)}")
            Ash.Changeset.add_error(changeset, reason)
        end
      end
    end

    @doc """
    Query the RAG system.

    ## Parameters
    - query: The question to ask
    - top_k: Number of context chunks to retrieve (default: 5)
    - max_tokens: Maximum tokens in generated response (default: 512)

    ## Returns
    - {:ok, results} with response, sources, and context
    - {:error, error} if query fails
    """
    read :ask do
      argument :query, :string, allow_nil?: false
      argument :top_k, :integer, allow_nil?: true
      argument :max_tokens, :integer, allow_nil?: true

      prepare fn query, _context ->
        query_string = query.arguments[:query]
        top_k = query.arguments[:top_k] || 5
        max_tokens = query.arguments[:max_tokens] || 512

        Logger.info("[RAG.Collection] Processing query: #{query_string}")

        case Thunderline.RAG.Query.ask(query_string, top_k: top_k, max_tokens: max_tokens) do
          {:ok, result} ->
            Logger.info("[RAG.Collection] Query successful, found #{length(result.sources)} sources")

            # Convert RAG result to Ash resource format
            resource = %__MODULE__{
              query: query_string,
              response: result.response,
              sources: result.sources,
              context: result.context,
              status: "completed"
            }

            Ash.Query.after_action(query, fn _query, _results ->
              {:ok, [resource]}
            end)

          {:error, reason} ->
            Logger.error("[RAG.Collection] Query failed: #{inspect(reason)}")
            Ash.Query.add_error(query, reason)
        end
      end
    end
  end

  attributes do
    # For ingestion
    attribute :text, :string do
      allow_nil? true
      description "Document text to ingest"
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      description "Metadata to attach to ingested document (source, author, etc.)"
    end

    # For queries
    attribute :query, :string do
      allow_nil? true
      description "The query string"
    end

    attribute :response, :string do
      allow_nil? true
      description "Generated response from RAG system"
    end

    attribute :sources, {:array, :map} do
      allow_nil? true
      default []
      description "Source references with relevance scores"
    end

    attribute :context, :map do
      allow_nil? true
      default %{}
      description "Retrieved context chunks and metadata"
    end

    # Common
    attribute :result, :map do
      allow_nil? true
      description "Ingestion result (chunks count, collection name)"
    end

    attribute :status, :string do
      allow_nil? true
      default "pending"
      description "Operation status (pending, completed, failed)"
    end
  end
end
