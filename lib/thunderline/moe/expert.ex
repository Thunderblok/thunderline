defmodule Thunderline.MoE.Expert do
  @moduledoc "Model expert metadata for MoE routing & lifecycle."
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "experts"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :version, :string, allow_nil?: false
    attribute :status, :atom, allow_nil?: false, default: :active, constraints: [one_of: [:active, :shadow, :retired, :error]]
    attribute :latency_budget_ms, :integer
    attribute :metrics, :map, allow_nil?: false, default: %{}
    attribute :model_artifact_ref, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
    create :register do
      accept [:name, :version, :status, :latency_budget_ms, :metrics, :model_artifact_ref]
    end
    update :update_metrics do
      accept [:metrics, :status]
    end
  end

  policies do
    policy action([:register, :update_metrics]) do
      authorize_if expr(not is_nil(actor(:id)))
    end
    policy action(:read) do
      authorize_if expr(not is_nil(actor(:id)))
    end
  end

  code_interface do
    define :register
    define :update_metrics
    define :read
  end
end
