defmodule Thunderline.Thunderpac.Resources.PACIntent do
  @moduledoc """
  PAC Intent management.

  Intents represent pending goals, desires, or actions a PAC wants to accomplish.
  They are queued, prioritized, and executed based on energy/trust/role constraints.

  ## Intent States

  - `:pending` - Queued, awaiting execution
  - `:active` - Currently being executed
  - `:blocked` - Waiting on external dependency
  - `:completed` - Successfully accomplished
  - `:failed` - Execution failed
  - `:cancelled` - Manually or system cancelled

  ## Intent Types

  - `:action` - Direct action to perform
  - `:query` - Information retrieval
  - `:communication` - Message/interaction intent
  - `:learning` - Knowledge acquisition
  - `:maintenance` - Self-care, memory cleanup, etc.
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  postgres do
    table "thunderpac_intents"
    repo Thunderline.Repo

    custom_indexes do
      index [:pac_id], name: "pac_intents_pac_idx"
      index [:state], name: "pac_intents_state_idx"
      index [:priority], name: "pac_intents_priority_idx"
      index [:intent_type], name: "pac_intents_type_idx"
      index [:scheduled_at], name: "pac_intents_scheduled_idx"
    end
  end

  admin do
    form do
      field :intent_type
      field :priority
      field :payload
    end
  end

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:start, from: [:pending], to: :active)
      transition(:block, from: [:active], to: :blocked)
      transition(:unblock, from: [:blocked], to: :active)
      transition(:complete, from: [:active], to: :completed)
      transition(:fail, from: [:active, :blocked], to: :failed)
      transition(:cancel, from: [:pending, :active, :blocked], to: :cancelled)
      transition(:retry, from: [:failed], to: :pending)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :active, :blocked, :completed, :failed, :cancelled]
    end

    attribute :intent_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:action, :query, :communication, :learning, :maintenance, :custom]
    end

    attribute :priority, :integer do
      allow_nil? false
      default 50
      public? true
      description "Intent priority (0-100, higher = more urgent)"
      constraints min: 0, max: 100
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
      public? true
      description "Intent parameters and context"
    end

    attribute :result, :map do
      allow_nil? true
      public? true
      description "Execution result when completed"
    end

    attribute :error, :string do
      allow_nil? true
      public? true
      description "Error message if failed"
    end

    attribute :retry_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :max_retries, :integer do
      allow_nil? false
      default 3
      public? true
    end

    attribute :energy_cost, :integer do
      allow_nil? false
      default 1
      public? true
      description "Energy required to execute this intent"
      constraints min: 0, max: 100
    end

    attribute :scheduled_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When to execute (nil = ASAP)"
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :timeout_ms, :integer do
      allow_nil? false
      default 30_000
      public? true
      description "Execution timeout in milliseconds"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :pac, Thunderline.Thunderpac.Resources.PAC do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :role, Thunderline.Thunderpac.Resources.PACRole do
      allow_nil? true
      attribute_writable? true
      description "Role context for this intent"
    end

    belongs_to :parent_intent, __MODULE__ do
      allow_nil? true
      attribute_writable? true
      description "Parent intent if this is a sub-intent"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new intent"
      accept [:intent_type, :priority, :payload, :energy_cost, :scheduled_at, :timeout_ms, :max_retries, :metadata]
      argument :pac_id, :uuid, allow_nil?: false
      argument :role_id, :uuid, allow_nil?: true
      argument :parent_intent_id, :uuid, allow_nil?: true

      change manage_relationship(:pac_id, :pac, type: :append)
      change manage_relationship(:role_id, :role, type: :append)
      change manage_relationship(:parent_intent_id, :parent_intent, type: :append)
    end

    update :start do
      description "Begin executing this intent"
      require_atomic? false
      change transition_state(:active)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :block do
      description "Mark intent as blocked on external dependency"
      accept [:metadata]
      require_atomic? false
      change transition_state(:blocked)
    end

    update :unblock do
      description "Resume blocked intent"
      require_atomic? false
      change transition_state(:active)
    end

    update :complete do
      description "Mark intent as successfully completed"
      accept [:result]
      require_atomic? false
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      description "Mark intent as failed"
      accept [:error]
      require_atomic? false
      change transition_state(:failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      description "Cancel this intent"
      require_atomic? false
      change transition_state(:cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :retry do
      description "Retry a failed intent"
      require_atomic? false
      change transition_state(:pending)
      change increment(:retry_count)
      change set_attribute(:error, nil)
      change set_attribute(:started_at, nil)
      change set_attribute(:completed_at, nil)
    end

    read :pending_for_pac do
      description "Get pending intents for a PAC"
      argument :pac_id, :uuid, allow_nil?: false

      filter expr(pac_id == ^arg(:pac_id) and state == :pending)
      prepare build(sort: [priority: :desc, inserted_at: :asc])
    end

    read :active_for_pac do
      description "Get currently active intents for a PAC"
      argument :pac_id, :uuid, allow_nil?: false

      filter expr(pac_id == ^arg(:pac_id) and state == :active)
    end

    read :ready_to_execute do
      description "Get intents ready for execution"
      filter expr(
        state == :pending and
        (is_nil(scheduled_at) or scheduled_at <= ^DateTime.utc_now())
      )
      prepare build(sort: [priority: :desc, inserted_at: :asc])
    end
  end

  code_interface do
    define :create
    define :start
    define :block
    define :unblock
    define :complete
    define :fail
    define :cancel
    define :retry
    define :pending_for_pac, args: [:pac_id]
    define :active_for_pac, args: [:pac_id]
    define :ready_to_execute
  end
end
