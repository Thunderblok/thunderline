defmodule Thunderline.Thunderbolt.Resources.UpmTrainer do
  @moduledoc """
  Unified Persistent Model trainer registry. Tracks online training loops that
  ingest ThunderFlow feature windows and emit shared model updates.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "upm_trainers"
    repo Thunderline.Repo
  end

  json_api do
    type "upm_trainers"
  end

  code_interface do
    define :register, action: :register
    define :update_metrics, action: :update_metrics
    define :transition_mode, action: :transition_mode
  end

  actions do
    defaults [:read]

    create :register do
      accept [:name, :mode, :tenant_id, :metadata]

      change fn changeset, _context ->
        ensure_mode(changeset)
      end

      change fn changeset, _context ->
        ensure_status(changeset, :idle)
      end
    end

    update :update_metrics do
      accept [
        :status,
        :last_window_id,
        :last_window_fetched_at,
        :last_loss,
        :drift_score,
        :metadata
      ]

      change fn changeset, _context ->
        ensure_mode(changeset)
      end
    end

    update :transition_mode do
      accept [:mode]

      change fn changeset, _context ->
        ensure_mode(changeset)
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

    attribute :name, :string do
      allow_nil? false
      description "Logical identifier for this trainer instance"
    end

    attribute :tenant_id, :uuid do
      description "Optional tenant scope for multi-tenant rollouts"
    end

    attribute :mode, :atom do
      allow_nil? false
      default :shadow
      constraints one_of: [:shadow, :canary, :active]
      description "Operational rollout mode for this trainer"
    end

    attribute :status, :atom do
      allow_nil? false
      default :idle
      constraints one_of: [:idle, :training, :paused, :errored]
      description "Current lifecycle status of the trainer"
    end

    attribute :last_window_id, :uuid do
      description "Most recent feature window processed"
    end

    attribute :last_window_fetched_at, :utc_datetime_usec do
      description "Timestamp when the last feature window was consumed"
    end

    attribute :last_loss, :float do
      description "Latest loss observed during online training"
    end

    attribute :drift_score, :float do
      default 0.0
      description "Aggregate drift score derived from shadow comparisons"
    end

    attribute :metadata, :map do
      default %{}
      description "Free-form metadata captured for observability/debugging"
    end

    timestamps()
  end

  relationships do
    has_many :snapshots, Thunderline.Thunderbolt.Resources.UpmSnapshot do
      destination_attribute :trainer_id
    end

    has_many :drift_windows, Thunderline.Thunderbolt.Resources.UpmDriftWindow do
      destination_attribute :trainer_id
    end
  end

  identities do
    identity :name_per_tenant, [:name, :tenant_id]
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

      value when value in [:idle, :training, :paused, :errored] ->
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
