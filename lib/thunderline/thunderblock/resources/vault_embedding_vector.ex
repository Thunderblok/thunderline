defmodule Thunderline.Thunderblock.Resources.VaultEmbeddingVector do
  @moduledoc """
  EmbeddingVector Resource - Vector embeddings for similarity search

  Stores high-dimensional vector representations of memories, knowledge,
  and other content for semantic similarity search and clustering.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  postgres do
    table "embedding_vectors"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :create, :destroy]

    update :update do
      primary? true
      require_atomic? false
      accept [:vector, :vector_model, :dimension, :content_hash, :embedding_type, :metadata]
    end

    create :create_embedding do
      description "Create a new vector embedding"
      accept [:vector, :vector_model, :dimension, :content_hash, :embedding_type, :metadata]

      argument :memory_record_id, :uuid
      argument :memory_node_id, :uuid
      argument :knowledge_node_id, :uuid
      argument :experience_id, :uuid

      change manage_relationship(:memory_record_id, :memory_record,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change manage_relationship(:memory_node_id, :memory_node,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change manage_relationship(:knowledge_node_id, :knowledge_node,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change manage_relationship(:experience_id, :experience,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change fn changeset, _context ->
        # Validate vector dimension matches declared dimension
        vector = Ash.Changeset.get_attribute(changeset, :vector)
        declared_dim = Ash.Changeset.get_attribute(changeset, :dimension)

        if vector && declared_dim && length(vector) != declared_dim do
          Ash.Changeset.add_error(changeset,
            field: :vector,
            message:
              "Vector length (#{length(vector)}) does not match declared dimension (#{declared_dim})"
          )
        else
          changeset
        end
      end
    end

    read :search_similar do
      description "Find similar vectors using cosine similarity"

      argument :query_vector, {:array, :float} do
        allow_nil? false
        description "Query vector to search for similar vectors"
      end

      argument :similarity_threshold, :float do
        default 0.7
        constraints min: 0.0, max: 1.0
        description "Minimum similarity score threshold"
      end

      argument :limit_results, :integer do
        default 10
        constraints min: 1, max: 100
        description "Maximum number of results to return"
      end

      argument :embedding_type_filter, :atom do
        constraints one_of: [:memory, :knowledge, :message, :experience, :decision]
        description "Filter by embedding type"
      end

      filter expr(
               if is_nil(^arg(:embedding_type_filter)) do
                 true
               else
                 embedding_type == ^arg(:embedding_type_filter)
               end
             )

      # Note: PostgreSQL vector similarity would require pgvector extension
      # For now, this is a placeholder that would need custom implementation
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate fn changeset, _context ->
      vector = Ash.Changeset.get_attribute(changeset, :vector)

      if vector do
        # Validate all vector components are finite numbers
        if Enum.all?(vector, &is_number/1) && Enum.all?(vector, &:math.is_finite/1) do
          :ok
        else
          {:error, "Vector must contain only finite numbers"}
        end
      else
        :ok
      end
    end

    validate fn changeset, _context ->
      dimension = Ash.Changeset.get_attribute(changeset, :dimension)

      if dimension && (dimension < 1 || dimension > 4096) do
        {:error, "Vector dimension must be between 1 and 4096"}
      else
        :ok
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :vector, {:array, :float} do
      allow_nil? false
      description "High-dimensional vector embedding"
    end

    attribute :vector_model, :string do
      allow_nil? false
      constraints max_length: 100
      description "Name/version of the model used to generate this vector"
    end

    attribute :dimension, :integer do
      allow_nil? false
      description "Dimensionality of the vector"
    end

    attribute :content_hash, :string do
      allow_nil? false
      constraints max_length: 64
      description "Hash of the source content for deduplication"
    end

    attribute :embedding_type, :atom do
      allow_nil? false
      constraints one_of: [:memory, :knowledge, :message, :experience, :decision]
      description "Type of content this vector represents"
    end

    attribute :metadata, :map do
      default %{}
      description "Additional metadata about the embedding"
    end

    timestamps()
  end

  relationships do
    belongs_to :memory_record, Thunderline.Thunderblock.Resources.VaultMemoryRecord do
      allow_nil? true
      attribute_writable? true
      description "Associated memory record"
    end

    belongs_to :memory_node, Thunderline.Thunderblock.Resources.VaultMemoryNode do
      allow_nil? true
      attribute_writable? true
      description "Associated memory node"
    end

    belongs_to :knowledge_node, Thunderline.Thunderblock.Resources.VaultKnowledgeNode do
      allow_nil? true
      attribute_writable? true
      description "Associated knowledge node"
    end

    belongs_to :experience, Thunderline.Thunderblock.Resources.VaultExperience do
      allow_nil? true
      attribute_writable? true
      description "Associated experience"
    end
  end

  calculations do
    calculate :vector_norm, :float, expr(fragment("sqrt(array_sum(array_pow(?, 2)))", vector)) do
      description "L2 norm of the vector"
    end
  end

  identities do
    identity :unique_content_hash_per_model, [:content_hash, :vector_model] do
      description "Prevent duplicate embeddings for the same content and model"
    end
  end
end
