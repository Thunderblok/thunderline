defmodule Thunderline.Thunderpac.Resources.PAC do
  @moduledoc """
  Core PAC (Personal Autonomous Construct) resource.

  A PAC is a stateful agent entity that persists across sessions and evolves
  through interactions. It is the fundamental unit of agency in Thunderline.

  ## Lifecycle States

  ```
  :seed → :dormant → :active → :suspended → :archived
           ↑                          ↓
           └──────────────────────────┘ (reactivate)
  ```

  - `:seed` - Initial state, awaiting ignition from IdentityKernel
  - `:dormant` - Inactive but ready to activate
  - `:active` - Running, processing intents, generating events
  - `:suspended` - Temporarily paused (preserves state)
  - `:archived` - Soft-deleted, state preserved but immutable

  ## Fields

  - `name` - Human-readable PAC identifier
  - `persona` - Behavioral configuration/personality
  - `memory_state` - Persistent memory map
  - `trait_vector` - Numerical trait representation
  - `intent_queue` - Pending intents
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  require Logger

  postgres do
    table "thunderpac_pacs"
    repo Thunderline.Repo

    references do
      reference :identity_kernel, on_delete: :nilify, on_update: :update
      reference :active_role, on_delete: :nilify, on_update: :update
    end

    custom_indexes do
      index [:status], name: "pacs_status_idx"
      index [:identity_kernel_id], name: "pacs_identity_idx"
      index [:active_role_id], name: "pacs_role_idx"
      index [:last_active_at], name: "pacs_last_active_idx"
      index "USING GIN (persona)", name: "pacs_persona_idx"
      index "USING GIN (memory_state)", name: "pacs_memory_idx"
      index "USING GIN (trait_vector)", name: "pacs_traits_idx"
    end
  end

  admin do
    form do
      field :name
      field :status
      field :persona
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # STATE MACHINE - PAC LIFECYCLE
  # ═══════════════════════════════════════════════════════════════

  state_machine do
    initial_states [:seed]
    default_initial_state :seed

    transitions do
      transition :ignite, from: [:seed], to: :dormant
      transition :activate, from: [:dormant, :suspended], to: :active
      transition :suspend, from: [:active], to: :suspended
      transition :archive, from: [:dormant, :active, :suspended], to: :archived
      transition :reactivate, from: [:archived], to: :dormant
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Human-readable PAC name"
      constraints min_length: 1, max_length: 100
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :seed
      constraints one_of: [:seed, :dormant, :active, :suspended, :archived]
    end

    attribute :persona, :map do
      allow_nil? false
      default %{}
      public? true
      description "Behavioral configuration and personality traits"
    end

    attribute :memory_state, :map do
      allow_nil? false
      default %{}
      public? true
      description "Persistent memory state across sessions"
    end

    attribute :trait_vector, {:array, :float} do
      allow_nil? false
      default []
      public? true
      description "Numerical trait representation for ML"
    end

    attribute :intent_queue, {:array, :map} do
      allow_nil? false
      default []
      public? true
      description "Queue of pending intents"
    end

    attribute :capabilities, {:array, :string} do
      allow_nil? false
      default []
      public? true
      description "List of enabled capabilities"
    end

    attribute :last_active_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "Last activity timestamp"
    end

    attribute :total_active_ticks, :integer do
      allow_nil? false
      default 0
      public? true
      description "Total ticks spent in active state"
    end

    attribute :session_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of activation sessions"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
      description "Additional PAC metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    belongs_to :identity_kernel, Thunderline.Thundercore.Resources.IdentityKernel do
      allow_nil? true
      public? true
      attribute_writable? true
      description "Origin identity kernel (seedpoint)"
    end

    belongs_to :active_role, Thunderline.Thunderpac.Resources.PACRole do
      allow_nil? true
      public? true
      attribute_writable? true
      description "Currently active role"
    end

    has_many :intents, Thunderline.Thunderpac.Resources.PACIntent do
      destination_attribute :pac_id
    end

    has_many :state_snapshots, Thunderline.Thunderpac.Resources.PACState do
      destination_attribute :pac_id
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # IDENTITIES
  # ═══════════════════════════════════════════════════════════════

  identities do
    identity :unique_name, [:name]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :spawn do
      description "Spawn a new PAC from an identity kernel"
      accept [:name, :persona, :capabilities, :metadata]
      argument :kernel_id, :uuid, allow_nil?: true

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :seed)
        |> maybe_set_kernel()
      end
    end

    update :ignite do
      description "Ignite PAC - transition from seed to dormant"
      accept []
      require_atomic? false

      change transition_state(:dormant)

      change after_action(fn _changeset, pac, _context ->
        emit_lifecycle_event(pac, :ignited)
        {:ok, pac}
      end)
    end

    update :activate do
      description "Activate PAC - transition to active state"
      accept []
      require_atomic? false

      change transition_state(:active)

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:last_active_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:session_count,
             (Ash.Changeset.get_attribute(changeset, :session_count) || 0) + 1)
      end

      change after_action(fn _changeset, pac, _context ->
        emit_lifecycle_event(pac, :activated)
        {:ok, pac}
      end)
    end

    update :suspend do
      description "Suspend PAC - preserve state but stop processing"
      accept []
      require_atomic? false
      argument :reason, :string, allow_nil?: true

      change transition_state(:suspended)

      change after_action(fn _changeset, pac, context ->
        reason = Map.get(context.arguments, :reason, "manual suspension")
        emit_lifecycle_event(pac, :suspended, %{reason: reason})
        {:ok, pac}
      end)
    end

    update :archive do
      description "Archive PAC - soft delete with state preservation"
      accept []
      require_atomic? false

      change transition_state(:archived)

      change after_action(fn _changeset, pac, _context ->
        emit_lifecycle_event(pac, :archived)
        {:ok, pac}
      end)
    end

    update :reactivate do
      description "Reactivate an archived PAC"
      accept []
      require_atomic? false

      change transition_state(:dormant)

      change after_action(fn _changeset, pac, _context ->
        emit_lifecycle_event(pac, :reactivated)
        {:ok, pac}
      end)
    end

    update :update_memory do
      description "Update PAC memory state"
      accept [:memory_state]
      require_atomic? false

      change after_action(fn _changeset, pac, _context ->
        emit_state_event(pac, :memory_updated)
        {:ok, pac}
      end)
    end

    update :push_intent do
      description "Add intent to PAC queue"
      argument :intent, :map, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        intent = context.arguments.intent
        current_queue = Ash.Changeset.get_attribute(changeset, :intent_queue) || []

        intent_with_id = Map.put_new(intent, "id", Ash.UUID.generate())
        |> Map.put_new("queued_at", DateTime.utc_now() |> DateTime.to_iso8601())

        Ash.Changeset.change_attribute(changeset, :intent_queue, current_queue ++ [intent_with_id])
      end
    end

    update :pop_intent do
      description "Remove and return first intent from queue"
      accept []
      require_atomic? false

      change fn changeset, _context ->
        current_queue = Ash.Changeset.get_attribute(changeset, :intent_queue) || []

        case current_queue do
          [_head | tail] ->
            Ash.Changeset.change_attribute(changeset, :intent_queue, tail)

          [] ->
            changeset
        end
      end
    end

    update :set_role do
      description "Set the active role for this PAC"
      argument :role_id, :uuid, allow_nil?: true
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.change_attribute(changeset, :active_role_id, context.arguments.role_id)
      end
    end

    update :tick do
      description "Process a system tick for active PAC"
      accept []
      require_atomic? false

      change fn changeset, _context ->
        current_ticks = Ash.Changeset.get_attribute(changeset, :total_active_ticks) || 0
        status = Ash.Changeset.get_attribute(changeset, :status)

        if status == :active do
          changeset
          |> Ash.Changeset.change_attribute(:total_active_ticks, current_ticks + 1)
          |> Ash.Changeset.change_attribute(:last_active_at, DateTime.utc_now())
        else
          changeset
        end
      end
    end

    read :active_pacs do
      description "List all active PACs"
      filter expr(status == :active)
      prepare build(sort: [last_active_at: :desc])
    end

    read :by_status do
      description "Find PACs by status"
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    read :by_kernel do
      description "Find PAC by identity kernel"
      argument :kernel_id, :uuid, allow_nil?: false
      filter expr(identity_kernel_id == ^arg(:kernel_id))
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :spawn, args: [:name, {:optional, :persona}, {:optional, :kernel_id}]
    define :ignite
    define :activate
    define :suspend, args: [{:optional, :reason}]
    define :archive
    define :reactivate
    define :update_memory, args: [:memory_state]
    define :push_intent, args: [:intent]
    define :pop_intent
    define :set_role, args: [:role_id]
    define :tick
    define :active_pacs, action: :active_pacs
    define :by_status, args: [:status]
    define :by_kernel, args: [:kernel_id]
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp maybe_set_kernel(changeset) do
    kernel_id = Ash.Changeset.get_argument(changeset, :kernel_id)

    if kernel_id do
      Ash.Changeset.change_attribute(changeset, :identity_kernel_id, kernel_id)
    else
      changeset
    end
  end

  defp emit_lifecycle_event(pac, event_type, extra \\ %{}) do
    event = %{
      type: :"pac_lifecycle_#{event_type}",
      domain: :pac,
      source: "Thunderpac.PAC",
      correlation_id: Thunderline.UUID.v7(),
      payload: Map.merge(%{
        pac_id: pac.id,
        pac_name: pac.name,
        status: pac.status,
        timestamp: DateTime.utc_now()
      }, extra)
    }

    # Broadcast to PAC-specific channel
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "pac:lifecycle:#{pac.id}",
      {:pac_lifecycle, event}
    )

    # Broadcast to global PAC state channel (for UPM PACTrainingBridge)
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "pac.state.changed",
      %{name: "pac.state.changed", payload: %{pac_id: pac.id, status: pac.status, event_type: event_type}}
    )

    :telemetry.execute(
      [:thunderline, :pac, :lifecycle, event_type],
      %{count: 1},
      %{pac_id: pac.id, status: pac.status}
    )

    :ok
  end

  defp emit_state_event(pac, event_type) do
    # Broadcast to UPM training bridge
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "pac.state.changed",
      %{name: "pac.state.changed", payload: %{pac_id: pac.id, event_type: event_type}}
    )

    :telemetry.execute(
      [:thunderline, :pac, :state, event_type],
      %{count: 1},
      %{pac_id: pac.id}
    )

    :ok
  end
end
