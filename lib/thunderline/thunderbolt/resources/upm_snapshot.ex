defmodule Thunderline.Thunderbolt.Resources.UpmSnapshot do
  @moduledoc """
  Unified Persistent Model snapshot metadata. Persists model versions, rollout
  status, and attachment details for ThunderBlock vault storage.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  alias Thunderline.UUID

  postgres do
    table "upm_snapshots"
    repo Thunderline.Repo
  end

  json_api do
    type "upm_snapshots"
  end

  code_interface do
    define :record, action: :record
    define :activate, action: :activate
    define :rollback, action: :rollback
    define :deactivate, action: :deactivate
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :version,
        :mode,
        :status,
        :checksum,
        :size_bytes,
        :storage_path,
        :metadata,
        :tenant_id,
        :trainer_id
      ]

      change fn changeset, _context ->
        changeset
        |> ensure_version()
        |> ensure_mode()
        |> ensure_status(:created)
      end
    end

    update :activate do
      accept [:mode, :metadata]

      change fn changeset, _context ->
        changeset
        |> ensure_mode()
        |> Ash.Changeset.change_attribute(:status, :activated)
        |> Ash.Changeset.change_attribute(:activated_at, DateTime.utc_now())
      end
    end

    update :rollback do
      accept [:metadata]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :activated)
        |> Ash.Changeset.change_attribute(:activated_at, DateTime.utc_now())
      end
    end

    update :deactivate do
      accept [:metadata]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :rolled_back)
        |> Ash.Changeset.change_attribute(:activated_at, nil)
      end
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :string do
      allow_nil? false
      description "Version identifier (UUID or semantic) for this snapshot"
    end

    attribute :tenant_id, :uuid do
      description "Optional tenant scope for the snapshot"
    end

    attribute :mode, :atom do
      allow_nil? false
      default :shadow
      constraints one_of: [:shadow, :canary, :active]
      description "Deployment mode in which this snapshot was produced"
    end

    attribute :status, :atom do
      allow_nil? false
      default :created
      constraints one_of: [:created, :activated, :rolled_back, :archived]
      description "Lifecycle status tracking activation and rollback events"
    end

    attribute :checksum, :string do
      description "Integrity checksum for stored model artifact"
    end

    attribute :size_bytes, :integer do
      description "Artifact size when persisted to ThunderBlock vault"
    end

    attribute :storage_path, :string do
      description "Storage path or URI pointing to persisted snapshot"
    end

    attribute :activated_at, :utc_datetime_usec do
      description "Timestamp when snapshot entered active service"
    end

    attribute :metadata, :map do
      default %{}
      description "Auxiliary metadata captured during snapshot creation"
    end

    timestamps()
  end

  relationships do
    belongs_to :trainer, Thunderline.Thunderbolt.Resources.UpmTrainer do
      attribute_type :uuid
      allow_nil? false
    end

    has_many :adapters, Thunderline.Thunderbolt.Resources.UpmAdapter do
      destination_attribute :snapshot_id
    end

    has_many :drift_windows, Thunderline.Thunderbolt.Resources.UpmDriftWindow do
      destination_attribute :snapshot_id
    end
  end

  identities do
    identity :unique_version_per_trainer, [:trainer_id, :version]
  end

  defp ensure_version(changeset) do
    case Ash.Changeset.get_attribute(changeset, :version) do
      nil -> Ash.Changeset.change_attribute(changeset, :version, UUID.v7())
      _ -> changeset
    end
  end

  defp ensure_mode(changeset) do
    case Ash.Changeset.get_attribute(changeset, :mode) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :mode, :shadow)

      value when value in [:shadow, :canary, :active] ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :mode,
          message: "unsupported mode #{inspect(value)}"
        )
    end
  end

  defp ensure_status(changeset, default) do
    case Ash.Changeset.get_attribute(changeset, :status) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :status, default)

      value when value in [:created, :activated, :rolled_back, :archived] ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :status,
          message: "unsupported status #{inspect(value)}"
        )
    end
  end
end
