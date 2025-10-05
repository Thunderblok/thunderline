defmodule Thunderline.Thunderbolt.Resources.ModelTrial do
  @moduledoc """
  Persists individual NAS trial results emitted by the Cerebros bridge.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cerebros_model_trials"
    repo Thunderline.Repo
  end

  json_api do
    type "model_trials"
  end

  actions do
    defaults [:read]

    create :log do
      accept [
        :model_run_id,
        :trial_id,
        :status,
        :metrics,
        :parameters,
        :spectral_norm,
        :mlflow_run_id,
        :artifact_uri,
        :duration_ms,
        :rank,
        :warnings,
        :candidate_id,
        :pulse_id,
        :bridge_payload
      ]
    end

    update :record do
      accept [
        :status,
        :metrics,
        :parameters,
        :spectral_norm,
        :mlflow_run_id,
        :artifact_uri,
        :duration_ms,
        :rank,
        :warnings,
        :candidate_id,
        :pulse_id,
        :bridge_payload
      ]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :trial_id, :string do
      allow_nil? false
    end

    attribute :status, :atom do
      allow_nil? false
      default :succeeded
      constraints one_of: [:succeeded, :failed, :skipped, :cancelled]
    end

    attribute :metrics, :map do
      default %{}
    end

    attribute :parameters, :map do
      default %{}
    end

    # 🔥 SPECTRAL NORM INTEGRATION - Phase 1
    attribute :spectral_norm, :boolean do
      allow_nil? false
      default false
      description "Whether spectral normalization constraint was applied to linear layers"
    end

    # MLflow cross-reference for bidirectional lookup
    attribute :mlflow_run_id, :string do
      description "MLflow run ID for cross-referencing with experiment tracking"
    end

    attribute :artifact_uri, :string
    attribute :duration_ms, :integer
    attribute :rank, :integer

    attribute :warnings, {:array, :string} do
      default []
    end

    attribute :candidate_id, :string
    attribute :pulse_id, :string

    attribute :bridge_payload, :map do
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :model_run, Thunderline.Thunderbolt.Resources.ModelRun do
      allow_nil? false
    end
  end
end
