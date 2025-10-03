defmodule Thunderline.Thunderbolt.Resources.UpmAdapter do
  @moduledoc """
  Unified Persistent Model adapter registry. Tracks agent-side sync state for
  distributing UPM snapshots into ThunderBlock agents and services.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "upm_adapters"
    repo Thunderline.Repo
  end

  json_api do
    type "upm_adapters"
  end

  code_interface do
    define :register, action: :register
    define :mark_syncing, action: :mark_syncing
    define :mark_synced, action: :mark_synced
    define :mark_errored, action: :mark_errored
  end

  actions do
    defaults [:read]

    create :register do
      accept [:adapter_key, :mode, :tenant_id, :metadata, :snapshot_id]

      change fn changeset, _context ->
        changeset
        |> ensure_mode()
        |> ensure_status(:pending)
      end
    end

    update :mark_syncing do
      accept [:metadata, :snapshot_id]

      change fn changeset, _context ->
        changeset
        |> ensure_mode()
        |> Ash.Changeset.change_attribute(:status, :syncing)
      end
    end

    update :mark_synced do
      accept [:metadata, :snapshot_id]

      change fn changeset, _context ->
        changeset
        |> ensure_mode()
        |> Ash.Changeset.change_attribute(:status, :synced)
        |> Ash.Changeset.change_attribute(:last_synced_at, DateTime.utc_now())
      end
    end

    update :mark_errored do
      accept [:metadata]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :errored)
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :adapter_key, :string do
      allow_nil? false
      description "Stable identifier for the adapter/agent consuming UPM snapshots"
    end

    attribute :tenant_id, :uuid do
      description "Optional tenant scope for adapter registration"
    end

    attribute :mode, :atom do
      allow_nil? false
      default :shadow
      constraints one_of: [:shadow, :canary, :active]
      description "Rollout mode under which this adapter currently operates"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :syncing, :synced, :errored]
      description "Synchronization state for the adapter"
    end

    attribute :last_synced_at, :utc_datetime_usec do
      description "Timestamp of the last successful sync"
    end

    attribute :metadata, :map do
      default %{}
      description "Additional metadata (e.g., region, capabilities)"
    end

    timestamps()
  end

  relationships do
    belongs_to :snapshot, Thunderline.Thunderbolt.Resources.UpmSnapshot do
      attribute_type :uuid
      allow_nil? false
    end
  end

  identities do
    identity :adapter_key_per_tenant, [:adapter_key, :tenant_id]
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

      value when value in [:pending, :syncing, :synced, :errored] ->
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
