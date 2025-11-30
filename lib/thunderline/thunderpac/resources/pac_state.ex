defmodule Thunderline.Thunderpac.Resources.PACState do
  @moduledoc """
  PAC State snapshots for persistence and recovery.

  State snapshots capture the full PAC state at a point in time.
  Used for:
  - Cross-session recovery
  - Rollback to previous states
  - Audit trail of PAC evolution
  - Memory export/import

  ## Snapshot Types

  - `:checkpoint` - Regular interval snapshot
  - `:milestone` - User-triggered or significant event
  - `:emergency` - Pre-shutdown or error state capture
  - `:export` - Full export for transfer

  ## State Components

  The `state_data` map captures:
  - Active memories (compressed)
  - Current personality state
  - Trait values
  - Active intents
  - Energy/trust levels
  - Any transient context
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "thunderpac_states"
    repo Thunderline.Repo

    custom_indexes do
      index [:pac_id], name: "pac_states_pac_idx"
      index [:snapshot_type], name: "pac_states_type_idx"
      index [:inserted_at], name: "pac_states_time_idx"
    end
  end

  admin do
    form do
      field :snapshot_type
      field :version
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :snapshot_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:checkpoint, :milestone, :emergency, :export]
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      public? true
      description "State schema version for migration"
    end

    attribute :state_data, :map do
      allow_nil? false
      default %{}
      public? true
      description "Full PAC state at snapshot time"
    end

    attribute :compressed, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether state_data is compressed"
    end

    attribute :checksum, :string do
      allow_nil? true
      public? true
      description "SHA256 hash of state_data for integrity"
    end

    attribute :size_bytes, :integer do
      allow_nil? true
      public? true
      description "Size of state_data in bytes"
    end

    attribute :trigger, :string do
      allow_nil? true
      public? true
      description "What triggered this snapshot"
    end

    attribute :notes, :string do
      allow_nil? true
      public? true
      constraints max_length: 1000
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :pac, Thunderline.Thunderpac.Resources.PAC do
      allow_nil? false
      attribute_writable? true
    end
  end

  calculations do
    calculate :age_seconds, :integer, expr(
      fragment("EXTRACT(EPOCH FROM (NOW() - ?))", inserted_at)
    )
  end

  actions do
    defaults [:read, :destroy]

    create :checkpoint do
      description "Create a checkpoint snapshot"
      accept [:state_data, :trigger, :notes, :metadata]
      argument :pac_id, :uuid, allow_nil?: false

      change set_attribute(:snapshot_type, :checkpoint)
      change manage_relationship(:pac_id, :pac, type: :append)
      change Thunderline.Thunderpac.Changes.ComputeChecksum
    end

    create :milestone do
      description "Create a milestone snapshot"
      accept [:state_data, :trigger, :notes, :metadata]
      argument :pac_id, :uuid, allow_nil?: false

      change set_attribute(:snapshot_type, :milestone)
      change manage_relationship(:pac_id, :pac, type: :append)
      change Thunderline.Thunderpac.Changes.ComputeChecksum
    end

    create :emergency do
      description "Create an emergency state capture"
      accept [:state_data, :trigger, :notes, :metadata]
      argument :pac_id, :uuid, allow_nil?: false

      change set_attribute(:snapshot_type, :emergency)
      change manage_relationship(:pac_id, :pac, type: :append)
      change Thunderline.Thunderpac.Changes.ComputeChecksum
    end

    create :export do
      description "Create a full export snapshot"
      accept [:state_data, :notes, :metadata]
      argument :pac_id, :uuid, allow_nil?: false

      change set_attribute(:snapshot_type, :export)
      change set_attribute(:trigger, "manual_export")
      change manage_relationship(:pac_id, :pac, type: :append)
      change Thunderline.Thunderpac.Changes.ComputeChecksum
    end

    read :latest_for_pac do
      description "Get the latest state snapshot for a PAC"
      argument :pac_id, :uuid, allow_nil?: false

      filter expr(pac_id == ^arg(:pac_id))
      prepare build(sort: [inserted_at: :desc], limit: 1)
    end

    read :checkpoints_for_pac do
      description "Get checkpoint snapshots for a PAC"
      argument :pac_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 10

      filter expr(pac_id == ^arg(:pac_id) and snapshot_type == :checkpoint)
      prepare build(sort: [inserted_at: :desc])
    end

    read :milestones_for_pac do
      description "Get milestone snapshots for a PAC"
      argument :pac_id, :uuid, allow_nil?: false

      filter expr(pac_id == ^arg(:pac_id) and snapshot_type == :milestone)
      prepare build(sort: [inserted_at: :desc])
    end
  end

  code_interface do
    define :checkpoint
    define :milestone
    define :emergency
    define :export
    define :latest_for_pac, args: [:pac_id]
    define :checkpoints_for_pac, args: [:pac_id]
    define :milestones_for_pac, args: [:pac_id]
  end
end
