defmodule Thunderline.Thunderblock.Resources.VaultMemoryRecord do
  @moduledoc """
  MemoryRecord Resource - Consolidated from Thunderline.Memory.Record

  Individual memory records with full context and metadata.
  ThunderBlock Vault memory record (unified memory & knowledge management; migrated from legacy Thundervault naming).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  postgres do
    table "memories"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :store_memory do
      description "Store a new memory for an agent"

      accept [
        :summary,
        :full_content,
        :memory_type,
        :context_data,
        :sensory_data,
        :emotional_data,
        :vividness,
        :accessibility,
        :importance,
        :memory_tags
      ]

      argument :agent_id, :uuid do
        allow_nil? false
        description "ID of the agent storing the memory"
      end

      argument :memory_node_id, :uuid do
        description "ID of the associated memory node"
      end

      change manage_relationship(:agent_id, :agent, type: :append_and_remove)

      change manage_relationship(:memory_node_id, :memory_node,
               type: :append_and_remove,
               on_no_match: :ignore
             )
    end

    update :access_memory do
      description "Mark memory as accessed and update accessibility"

      change fn changeset, _context ->
        now = DateTime.utc_now()
        current_count = Ash.Changeset.get_attribute(changeset, :times_accessed) || 0
        current_accessibility = Ash.Changeset.get_attribute(changeset, :accessibility) || 1.0

        # Accessing memory strengthens it slightly
        new_accessibility = min(1.0, current_accessibility * 1.05)

        changeset
        |> Ash.Changeset.change_attribute(:times_accessed, current_count + 1)
        |> Ash.Changeset.change_attribute(:last_accessed_at, now)
        |> Ash.Changeset.change_attribute(:accessibility, new_accessibility)
      end

      require_atomic? false
    end

    update :fade_memory do
      description "Reduce memory vividness and accessibility over time"

      argument :fade_factor, :float do
        default 0.95
        constraints min: 0.1, max: 1.0
        description "Factor to reduce memory strength by"
      end

      change fn changeset, _context ->
        fade_factor = Ash.Changeset.get_argument(changeset, :fade_factor) || 0.95
        current_vividness = Ash.Changeset.get_attribute(changeset, :vividness) || 1.0
        current_accessibility = Ash.Changeset.get_attribute(changeset, :accessibility) || 1.0

        changeset
        |> Ash.Changeset.change_attribute(:vividness, max(0.1, current_vividness * fade_factor))
        |> Ash.Changeset.change_attribute(
          :accessibility,
          max(0.1, current_accessibility * fade_factor)
        )
      end

      require_atomic? false
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate match(:summary, ~r/.{10,}/) do
      message "Memory summary must be at least 10 characters"
    end

    validate match(:full_content, ~r/.{20,}/) do
      message "Memory content must be at least 20 characters"
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :summary, :string do
      allow_nil? false
      constraints max_length: 500
      description "Brief memory summary"
    end

    attribute :full_content, :string do
      allow_nil? false
      description "Complete memory details"
    end

    attribute :memory_type, :atom do
      allow_nil? false
      constraints one_of: [:episodic, :semantic, :procedural, :emotional]
      description "Type of memory stored"
    end

    attribute :context_data, :map do
      default %{}
      description "Environmental context when memory formed"
    end

    attribute :sensory_data, :map do
      default %{}
      description "Sensory information captured"
    end

    attribute :emotional_data, :map do
      default %{}
      description "Emotional state and reactions"
    end

    # Memory strength and accessibility
    attribute :vividness, :float do
      default 1.0
      constraints min: 0.0, max: 1.0
      description "How vivid/clear this memory is"
    end

    attribute :accessibility, :float do
      default 1.0
      constraints min: 0.0, max: 1.0
      description "How easily this memory can be recalled"
    end

    attribute :importance, :float do
      default 0.5
      constraints min: 0.0, max: 1.0
      description "Subjective importance of this memory"
    end

    # Memory lifecycle
    attribute :times_accessed, :integer do
      default 0
      description "How many times this memory has been accessed"
    end

    attribute :last_accessed_at, :utc_datetime do
      description "When this memory was last accessed"
    end

    attribute :memory_tags, {:array, :string} do
      default []
      description "Tags for categorization and search"
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Thunderline.Thunderblock.Resources.VaultAgent do
      allow_nil? false
      attribute_writable? true
      description "Agent that owns this memory"
    end

    belongs_to :memory_node, Thunderline.Thunderblock.Resources.VaultMemoryNode do
      allow_nil? true
      attribute_writable? true
      description "Associated memory node for graph relationships"
    end

    has_many :embedding_vectors, Thunderline.Thunderblock.Resources.VaultEmbeddingVector do
      destination_attribute :memory_record_id
      description "Vector embeddings for similarity search"
    end
  end

  calculations do
    calculate :memory_strength, :float, expr(vividness * accessibility * importance) do
      description "Overall strength of the memory"
    end

    calculate :age_in_days,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (NOW() - inserted_at)) / 86400")) do
      description "Age of memory in days"
    end
  end
end
