defmodule Thunderline.Thunderpac.Resources.MemoryCell do
  @moduledoc """
  Memory cell resource for PAC episodic, semantic, and procedural memory.

  HC-Ω-9: Stores discrete memory units that can be consolidated, recalled,
  and naturally decay over time based on salience.

  ## Memory Types

  - `:episodic` - Event-based memories (what happened)
  - `:semantic` - Factual/knowledge memories (what is known)
  - `:procedural` - Skill/behavior memories (how to do)

  ## Salience Model

  Salience determines memory persistence:
  - High salience (> 0.8): Critical memories, slow decay
  - Medium salience (0.4-0.8): Normal memories, standard decay
  - Low salience (< 0.4): Peripheral memories, fast decay

  ## Decay Model

  Memories decay naturally based on:
  - Base decay rate (configurable per memory type)
  - Salience modifier (high salience = slower decay)
  - Access frequency (recalled memories boost salience)

  ## Events

  - `pac.memory.created` - New memory cell stored
  - `pac.memory.consolidated` - Memory strengthened/merged
  - `pac.memory.recalled` - Memory accessed
  - `pac.memory.decayed` - Memory fell below threshold
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  require Logger

  alias Thunderline.Thunderflow.EventBus

  postgres do
    table "thunderpac_memory_cells"
    repo Thunderline.Repo

    references do
      reference :pac, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:pac_id], name: "memory_cells_pac_idx"
      index [:memory_type], name: "memory_cells_type_idx"
      index [:salience], name: "memory_cells_salience_idx"
      index [:decay_at], name: "memory_cells_decay_idx"
      index [:pac_id, :salience], name: "memory_cells_pac_salience_idx"
      index [:pac_id, :memory_type, :salience], name: "memory_cells_pac_type_salience_idx"
      index "USING GIN (content)", name: "memory_cells_content_idx"
      index "USING GIN (tags)", name: "memory_cells_tags_idx"
    end
  end

  admin do
    form do
      field :memory_type
      field :salience
      field :content
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :store
    define :recall
    define :consolidate
    define :decay
    define :recall_salient, args: [:pac_id]
    define :expiring_soon
    define :by_tags, args: [:pac_id, :tags]
    define :for_pac, args: [:pac_id]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :store do
      description "Store a new memory cell for a PAC"

      accept [:memory_type, :content, :salience, :tags, :context]

      argument :pac_id, :uuid do
        allow_nil? false
        description "PAC this memory belongs to"
      end

      argument :base_decay_hours, :integer do
        allow_nil? true

        # 7 days default
        default 168
        description "Base hours until decay (modified by salience)"
      end

      change manage_relationship(:pac_id, :pac, type: :append)

      change fn changeset, _context ->
        # Calculate decay_at based on salience
        salience = Ash.Changeset.get_attribute(changeset, :salience) || 0.5
        base_hours = Ash.Changeset.get_argument(changeset, :base_decay_hours) || 168

        # High salience = longer decay

        # 0.5x to 2x
        decay_multiplier = 0.5 + salience * 1.5
        decay_hours = round(base_hours * decay_multiplier)

        decay_at = DateTime.add(DateTime.utc_now(), decay_hours, :hour)

        Ash.Changeset.force_change_attribute(changeset, :decay_at, decay_at)
      end

      change after_action(fn changeset, record, _context ->
               emit_memory_event(record, :created)
               {:ok, record}
             end)
    end

    update :recall do
      description "Record a memory recall, boosting salience and extending decay"

      change fn changeset, _context ->
        record = changeset.data
        new_count = (record.access_count || 0) + 1

        # Boost salience slightly on recall
        current_salience = record.salience || 0.5
        new_salience = min(1.0, current_salience + 0.02)

        # Extend decay_at
        new_decay_at = DateTime.add(record.decay_at, 24, :hour)

        changeset
        |> Ash.Changeset.force_change_attribute(:access_count, new_count)
        |> Ash.Changeset.force_change_attribute(:salience, new_salience)
        |> Ash.Changeset.force_change_attribute(:last_accessed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:decay_at, new_decay_at)
      end

      change after_action(fn _changeset, record, _context ->
               emit_memory_event(record, :recalled)
               {:ok, record}
             end)
    end

    update :consolidate do
      description "Consolidate multiple memories into this one, boosting salience"

      accept [:content, :tags, :context]

      argument :merged_memory_ids, {:array, :uuid} do
        allow_nil? false
        description "IDs of memories being merged into this one"
      end

      argument :salience_boost, :float do
        allow_nil? true
        default 0.1
        description "Amount to boost salience by"
      end

      change fn changeset, _context ->
        record = changeset.data
        merged_ids = Ash.Changeset.get_argument(changeset, :merged_memory_ids) || []
        boost = Ash.Changeset.get_argument(changeset, :salience_boost) || 0.1

        # Update consolidated_from
        existing = record.consolidated_from || []
        new_consolidated = Enum.uniq(existing ++ merged_ids)

        # Boost salience
        new_salience = min(1.0, (record.salience || 0.5) + boost)

        # Extend decay significantly
        new_decay_at = DateTime.add(record.decay_at, 72, :hour)

        changeset
        |> Ash.Changeset.force_change_attribute(:consolidated_from, new_consolidated)
        |> Ash.Changeset.force_change_attribute(:salience, new_salience)
        |> Ash.Changeset.force_change_attribute(:decay_at, new_decay_at)
      end

      change after_action(fn _changeset, record, _context ->
               emit_memory_event(record, :consolidated)
               {:ok, record}
             end)
    end

    update :decay do
      description "Mark memory as decayed, reducing salience"

      argument :decay_amount, :float do
        allow_nil? true
        default 0.3
        description "Amount to reduce salience"
      end

      change fn changeset, _context ->
        record = changeset.data
        decay_amount = Ash.Changeset.get_argument(changeset, :decay_amount) || 0.3

        new_salience = max(0.0, (record.salience || 0.5) - decay_amount)

        Ash.Changeset.force_change_attribute(changeset, :salience, new_salience)
      end

      change after_action(fn _changeset, record, _context ->
               emit_memory_event(record, :decayed)
               {:ok, record}
             end)
    end

    read :recall_salient do
      description "Recall top N salient memories for a PAC above threshold"

      argument :pac_id, :uuid do
        allow_nil? false
      end

      argument :threshold, :float do
        allow_nil? true
        default 0.3
      end

      argument :limit, :integer do
        allow_nil? true
        default 10
      end

      argument :memory_type, :atom do
        allow_nil? true
        constraints one_of: [:episodic, :semantic, :procedural]
      end

      prepare fn query, _context ->
        pac_id = Ash.Query.get_argument(query, :pac_id)
        threshold = Ash.Query.get_argument(query, :threshold) || 0.3
        limit = Ash.Query.get_argument(query, :limit) || 10
        memory_type = Ash.Query.get_argument(query, :memory_type)

        query =
          query
          |> Ash.Query.filter(pac_id == ^pac_id)
          |> Ash.Query.filter(salience >= ^threshold)
          |> Ash.Query.filter(decay_at > ^DateTime.utc_now())
          |> Ash.Query.sort(salience: :desc)
          |> Ash.Query.limit(limit)

        if memory_type do
          Ash.Query.filter(query, memory_type == ^memory_type)
        else
          query
        end
      end
    end

    read :expiring_soon do
      description "Find memories approaching decay within given hours"

      argument :hours, :integer do
        allow_nil? true
        default 24
      end

      argument :pac_id, :uuid do
        allow_nil? true
        description "Optional: filter by PAC"
      end

      prepare fn query, _context ->
        hours = Ash.Query.get_argument(query, :hours) || 24
        pac_id = Ash.Query.get_argument(query, :pac_id)

        cutoff = DateTime.add(DateTime.utc_now(), hours, :hour)

        query =
          query
          |> Ash.Query.filter(decay_at <= ^cutoff)
          |> Ash.Query.filter(decay_at > ^DateTime.utc_now())
          |> Ash.Query.sort(decay_at: :asc)

        if pac_id do
          Ash.Query.filter(query, pac_id == ^pac_id)
        else
          query
        end
      end
    end

    read :by_tags do
      description "Find memories matching any of the given tags"

      argument :pac_id, :uuid do
        allow_nil? false
      end

      argument :tags, {:array, :string} do
        allow_nil? false
      end

      prepare fn query, _context ->
        pac_id = Ash.Query.get_argument(query, :pac_id)
        tags = Ash.Query.get_argument(query, :tags) || []

        query
        |> Ash.Query.filter(pac_id == ^pac_id)
        |> Ash.Query.filter(fragment("? && ?", tags, ^tags))
        |> Ash.Query.filter(decay_at > ^DateTime.utc_now())
        |> Ash.Query.sort(salience: :desc)
      end
    end

    read :for_pac do
      description "List all active memories for a PAC"

      argument :pac_id, :uuid do
        allow_nil? false
      end

      prepare fn query, _context ->
        pac_id = Ash.Query.get_argument(query, :pac_id)

        query
        |> Ash.Query.filter(pac_id == ^pac_id)
        |> Ash.Query.filter(decay_at > ^DateTime.utc_now())
        |> Ash.Query.sort(inserted_at: :desc)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :memory_type, :atom do
      constraints one_of: [:episodic, :semantic, :procedural]
      allow_nil? false
      default :episodic
      public? true
      description "Type of memory: episodic (events), semantic (facts), procedural (skills)"
    end

    attribute :content, :map do
      allow_nil? false
      default %{}
      public? true
      description "Memory content as structured map"
    end

    attribute :salience, :float do
      allow_nil? false
      default 0.5
      public? true
      constraints min: 0.0, max: 1.0
      description "Memory importance/strength (0.0-1.0)"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      public? true
      description "Searchable tags for memory retrieval"
    end

    attribute :access_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of times this memory has been recalled"
    end

    attribute :last_accessed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "Timestamp of last recall"
    end

    attribute :decay_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When this memory will decay/expire"
    end

    attribute :consolidated_from, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
      description "IDs of memories that were merged into this one"
    end

    attribute :context, :map do
      allow_nil? false
      default %{}
      public? true
      description "Additional context: source event, related entities, etc."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    belongs_to :pac, Thunderline.Thunderpac.Resources.PAC do
      allow_nil? false
      public? true
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CALCULATIONS
  # ═══════════════════════════════════════════════════════════════

  calculations do
    calculate :is_decaying, :boolean do
      calculation fn records, _context ->
        now = DateTime.utc_now()

        Enum.map(records, fn record ->
          case record.decay_at do
            nil -> false
            decay_at -> DateTime.compare(decay_at, now) != :gt
          end
        end)
      end

      description "Whether this memory is past its decay point"
    end

    calculate :time_until_decay, :integer do
      calculation fn records, _context ->
        now = DateTime.utc_now()

        Enum.map(records, fn record ->
          case record.decay_at do
            nil -> 0
            decay_at -> DateTime.diff(decay_at, now, :second)
          end
        end)
      end

      description "Seconds until decay (negative if already decayed)"
    end

    calculate :effective_salience, :float do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          # Boost salience based on access frequency
          access_boost = min(0.2, record.access_count * 0.01)
          min(1.0, record.salience + access_boost)
        end)
      end

      description "Salience adjusted for access frequency"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp emit_memory_event(record, event_type) do
    event_attrs = %{
      type: :"pac.memory.#{event_type}",
      source: :pac,
      payload: %{
        memory_id: record.id,
        pac_id: record.pac_id,
        memory_type: record.memory_type,
        salience: record.salience,
        decay_at: record.decay_at
      },
      metadata: %{
        resource: __MODULE__,
        action: event_type
      }
    }

    with {:ok, ev} <- Thunderline.Event.new(event_attrs) do
      EventBus.publish_event(ev)
    else
      {:error, reason} ->
        Logger.warning("[MemoryCell] Failed to emit #{event_type} event: #{inspect(reason)}")
    end
  end
end
