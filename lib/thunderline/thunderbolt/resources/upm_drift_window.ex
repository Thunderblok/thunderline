defmodule Thunderline.Thunderbolt.Resources.UpmDriftWindow do
  @moduledoc """
  Unified Persistent Model drift monitoring window. Captures shadow vs. ground
  truth comparisons and governs quarantine workflows when drift exceeds
  thresholds.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "upm_drift_windows"
    repo Thunderline.Repo
  end

  json_api do
    type "upm_drift_windows"
  end

  code_interface do
    define :open, action: :open
    define :quarantine, action: :quarantine
    define :resolve, action: :resolve
    define :close, action: :close
  end

  actions do
    defaults [:read]

    create :open do
      accept [
        :tenant_id,
        :score_p95,
        :threshold,
        :sample_count,
        :metadata,
        :snapshot_id,
        :trainer_id
      ]

      change fn changeset, _context ->
        changeset
        |> ensure_status(:open)
        |> ensure_threshold()
        |> ensure_score()
        |> ensure_sample_count()
        |> Ash.Changeset.change_attribute(:window_started_at, DateTime.utc_now())
      end
    end

    update :quarantine do
      accept [:metadata]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :quarantined)
      end
    end

    update :resolve do
      accept [:score_p95, :threshold, :sample_count, :metadata]

      change fn changeset, _context ->
        changeset
        |> ensure_score()
        |> ensure_threshold()
        |> ensure_sample_count()
        |> Ash.Changeset.change_attribute(:status, :resolved)
        |> Ash.Changeset.change_attribute(:window_closed_at, DateTime.utc_now())
      end
    end

    update :close do
      accept [:metadata]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :closed)
        |> Ash.Changeset.change_attribute(:window_closed_at, DateTime.utc_now())
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

    attribute :tenant_id, :uuid do
      description "Optional tenant scope for the drift evaluation"
    end

    attribute :status, :atom do
      allow_nil? false
      default :open
      constraints one_of: [:open, :quarantined, :resolved, :closed]
      description "Lifecycle state of the drift window"
    end

    attribute :score_p95, :float do
      allow_nil? false
      default 0.0
      constraints min: 0.0
      description "95th percentile drift score observed in the window"
    end

    attribute :threshold, :float do
      allow_nil? false
      default 0.2
      constraints min: 0.0
      description "Configured drift threshold for quarantine activation"
    end

    attribute :sample_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Number of comparisons captured within the window"
    end

    attribute :window_started_at, :utc_datetime_usec do
      description "Timestamp when drift measurement window opened"
    end

    attribute :window_closed_at, :utc_datetime_usec do
      description "Timestamp when drift measurement window closed"
    end

    attribute :metadata, :map do
      default %{}
      description "Supplemental metrics or diagnostic notes"
    end

    timestamps()
  end

  relationships do
    belongs_to :snapshot, Thunderline.Thunderbolt.Resources.UpmSnapshot do
      attribute_type :uuid
      allow_nil? false
    end

    belongs_to :trainer, Thunderline.Thunderbolt.Resources.UpmTrainer do
      attribute_type :uuid
      allow_nil? false
    end
  end

  defp ensure_status(changeset, default) do
    case Ash.Changeset.get_attribute(changeset, :status) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :status, default)

      value when value in [:open, :quarantined, :resolved, :closed] ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :status,
          message: "unsupported status #{inspect(value)}"
        )
    end
  end

  defp ensure_threshold(changeset) do
    case Ash.Changeset.get_attribute(changeset, :threshold) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :threshold, 0.2)

      value when is_number(value) and value >= 0.0 ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :threshold,
          message: "invalid threshold #{inspect(value)}"
        )
    end
  end

  defp ensure_score(changeset) do
    case Ash.Changeset.get_attribute(changeset, :score_p95) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :score_p95, 0.0)

      value when is_number(value) and value >= 0.0 ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :score_p95,
          message: "invalid score #{inspect(value)}"
        )
    end
  end

  defp ensure_sample_count(changeset) do
    case Ash.Changeset.get_attribute(changeset, :sample_count) do
      nil ->
        Ash.Changeset.change_attribute(changeset, :sample_count, 0)

      value when is_integer(value) and value >= 0 ->
        changeset

      value ->
        Ash.Changeset.add_error(
          changeset,
          field: :sample_count,
          message: "invalid sample count #{inspect(value)}"
        )
    end
  end
end
