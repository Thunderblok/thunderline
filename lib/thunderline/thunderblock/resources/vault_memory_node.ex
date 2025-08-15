defmodule Thunderline.Thunderblock.Resources.VaultMemoryNode do
  @moduledoc """
  MemoryNode Resource - Migrated from lib/thunderline/memory/resources/memory_node

  Networked storage for agent memories with vector search capabilities.
  Consolidated into Thundervault for persistence and federation coordination.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "memory_nodes"
    repo Thunderline.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :store_memory do
      accept [
        :agent_id,
        :title,
        :content,
        :content_type,
        :importance,
        :emotional_valence,
        :confidence,
        :tags,
        :context,
        :parent_memory_id
      ]

      change set_attribute(:access_count, 0)
      change set_attribute(:is_archived, false)
    end

    update :access_memory do
      accept []

      change increment(:access_count)
      change set_attribute(:last_accessed_at, &DateTime.utc_now/0)
    end

    update :update_importance do
      argument :new_importance, :decimal, allow_nil?: false
      require_atomic? false

      change set_attribute(:importance, arg(:new_importance))

      validate fn changeset, context ->
        importance = context.arguments.new_importance

        if Decimal.compare(importance, 0) >= 0 and Decimal.compare(importance, 1) <= 0 do
          :ok
        else
          {:error, "Importance must be between 0.0 and 1.0"}
        end
      end
    end

    update :add_tags do
      argument :new_tags, {:array, :string}, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        current_tags = Ash.Changeset.get_attribute(changeset, :tags) || []
        new_tags = context.arguments.new_tags || []
        updated_tags = Enum.uniq(current_tags ++ new_tags)
        Ash.Changeset.change_attribute(changeset, :tags, updated_tags)
      end
    end

    update :archive do
      accept []

      change set_attribute(:is_archived, true)
    end

    update :unarchive do
      accept []

      change set_attribute(:is_archived, false)
    end

    update :decay_memory do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        current_importance =
          Ash.Changeset.get_attribute(changeset, :importance) || Decimal.new("0.5")

        decay_rate = Ash.Changeset.get_attribute(changeset, :decay_rate) || Decimal.new("0.01")

        # Apply decay: new_importance = current_importance * (1 - decay_rate)
        decay_factor = Decimal.sub(Decimal.new("1.0"), decay_rate)
        new_importance = Decimal.mult(current_importance, decay_factor)

        Ash.Changeset.change_attribute(changeset, :importance, new_importance)
      end
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
      prepare build(sort: [importance: :desc, last_accessed_at: :desc])
    end

    read :by_content_type do
      argument :content_type, :atom, allow_nil?: false
      filter expr(content_type == ^arg(:content_type))
    end

    read :important_memories do
      argument :min_importance, :decimal, default: Decimal.new("0.7")
      filter expr(importance >= ^arg(:min_importance))
      prepare build(sort: [importance: :desc])
    end

    read :recent_memories do
      argument :hours, :integer, default: 24
      filter expr(inserted_at > ago(^arg(:hours), :hour))
      prepare build(sort: [inserted_at: :desc])
    end

    read :frequently_accessed do
      argument :min_access_count, :integer, default: 5
      filter expr(access_count >= ^arg(:min_access_count))
      prepare build(sort: [access_count: :desc])
    end

    read :by_tags do
      argument :tags, {:array, :string}, allow_nil?: false
      filter expr(exists(tags, ^arg(:tags)))
      prepare build(sort: [importance: :desc])
    end

    read :emotional_memories do
      argument :min_valence, :decimal, default: Decimal.new("0.5")
      filter expr(abs(emotional_valence) >= ^arg(:min_valence))
      prepare build(sort: [emotional_valence: :desc])
    end

    read :active_memories do
      filter expr(is_archived == false)
      prepare build(sort: [importance: :desc, last_accessed_at: :desc])
    end

    read :archived_memories do
      filter expr(is_archived == true)
      prepare build(sort: [updated_at: :desc])
    end

    read :semantic_search_content do
      argument :query_embedding, {:array, :float}, allow_nil?: false
      argument :similarity_threshold, :float, default: 0.7
      argument :limit, :integer, default: 10

      filter expr(not is_nil(content_embedding))

      # pgvector similarity search using cosine distance
      prepare fn query, context ->
        query_vec = context.arguments.query_embedding
        threshold = context.arguments.similarity_threshold
        limit = context.arguments.limit

        # This would use pgvector operations in a real implementation
        # For now, we'll sort by importance as a placeholder
        query
        |> Ash.Query.sort(importance: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :semantic_search_title do
      argument :query_embedding, {:array, :float}, allow_nil?: false
      argument :similarity_threshold, :float, default: 0.7
      argument :limit, :integer, default: 10

      filter expr(not is_nil(title_embedding))

      prepare fn query, context ->
        limit = context.arguments.limit

        query
        |> Ash.Query.sort(importance: :desc)
        |> Ash.Query.limit(limit)
      end
    end
  end

  preparations do
    prepare build(load: [:agent])
  end

  validations do
    validate present([:agent_id, :title, :content, :content_type])
    validate string_length(:title, min: 1, max: 200)
    validate string_length(:content, min: 1)
    validate numericality(:importance, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)

    validate numericality(:emotional_valence,
               greater_than_or_equal_to: -1,
               less_than_or_equal_to: 1
             )

    validate numericality(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    validate numericality(:decay_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    validate numericality(:access_count, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      constraints max_length: 200
      description "Memory title or summary"
    end

    attribute :content, :string do
      allow_nil? false
      description "Memory content"
    end

    attribute :content_type, :atom do
      allow_nil? false
      default :observation
      description "Type of memory content"
    end

    attribute :importance, :decimal do
      allow_nil? false
      default Decimal.new("0.5")
      constraints min: 0, max: 1
      description "Importance score (0.0 to 1.0)"
    end

    attribute :emotional_valence, :decimal do
      allow_nil? false
      default Decimal.new("0.0")
      constraints min: -1, max: 1
      description "Emotional valence (-1.0 negative to 1.0 positive)"
    end

    attribute :confidence, :decimal do
      allow_nil? false
      default Decimal.new("0.5")
      constraints min: 0, max: 1
      description "Confidence in memory accuracy"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      description "Memory tags for categorization"
    end

    attribute :context, :map do
      allow_nil? false
      default %{}
      description "Contextual information and metadata"
    end

    attribute :access_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Number of times memory was accessed"
    end

    attribute :last_accessed_at, :utc_datetime do
      allow_nil? true
      description "Last access timestamp"
    end

    attribute :decay_rate, :decimal do
      allow_nil? false
      default Decimal.new("0.01")
      constraints min: 0, max: 1
      description "Memory decay rate over time"
    end

    attribute :is_archived, :boolean do
      allow_nil? false
      default false
      description "Whether memory is archived"
    end

    # pgvector embeddings for semantic search
    attribute :content_embedding, {:array, :float} do
      allow_nil? true
      description "Vector embedding of memory content for semantic search"
    end

    attribute :title_embedding, {:array, :float} do
      allow_nil? true
      description "Vector embedding of memory title for semantic search"
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Thunderline.Thunderblock.Resources.VaultAgent do
      allow_nil? false
      attribute_writable? true
      description "Agent that owns this memory"
    end

    has_many :embedding_vectors, Thunderline.Thunderblock.Resources.VaultEmbeddingVector do
      destination_attribute :memory_node_id
      description "Vector embeddings for this memory"
    end

    belongs_to :parent_memory, __MODULE__ do
      allow_nil? true
      attribute_writable? true
      description "Parent memory for hierarchical relationships"
    end

    has_many :child_memories, __MODULE__ do
      destination_attribute :parent_memory_id
      description "Child memories linked to this one"
    end
  end

  calculations do
    calculate :memory_strength,
              :decimal,
              expr(importance * (1.0 + access_count * 0.1) * confidence) do
      description "Combined memory strength score"
    end

    calculate :is_recent, :boolean, expr(inserted_at > ago(7, :day)) do
      description "Whether memory was created in last 7 days"
    end

    calculate :days_since_access,
              :integer,
              expr(fragment("EXTRACT(DAY FROM ? - ?)", now(), last_accessed_at)) do
      description "Days since last accessed"
    end

    calculate :has_embeddings, :boolean, expr(exists(embedding_vectors, true))

    calculate :emotional_intensity, :decimal, expr(abs(emotional_valence)) do
      description "Absolute emotional intensity"
    end
  end

  aggregates do
    count :child_memory_count, :child_memories

    avg :child_importance_avg, :child_memories, :importance do
      authorize? false
    end

    count :embedding_count, :embedding_vectors
  end

  # TODO: Re-enable policies once AshAuthentication is properly configured
  # policies do
  #   policy action_type(:read) do
  #     # Agents can read their own memories
  #     authorize_if relates_to_actor_via([:agent, :created_by_user])
  #     # System agents can read all memories
  #     authorize_if actor_attribute_equals(:role, :system)
  #     # Admins can read all memories
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end

  #   policy action_type([:create, :update]) do
  #     # Agents can manage their own memories
  #     authorize_if relates_to_actor_via([:agent, :created_by_user])
  #     # System agents can manage all memories
  #     authorize_if actor_attribute_equals(:role, :system)
  #     # Admins can manage all memories
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end

  #   policy action_type(:destroy) do
  #     # Only admins and memory owners can delete
  #     authorize_if relates_to_actor_via([:agent, :created_by_user])
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
