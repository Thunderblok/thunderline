defmodule Thunderline.Lineage.Edge do
  @moduledoc "Directed provenance edge between artifacts (raw→feature→decision→label)."
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lineage_edges"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :from_id, :uuid, allow_nil?: false
    attribute :to_id, :uuid, allow_nil?: false
    attribute :edge_type, :string, allow_nil?: false
    attribute :day_bucket, :date, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
    create :connect do
      accept [:from_id, :to_id, :edge_type, :day_bucket]
    end
  end

  policies do
    policy action([:connect, :read]) do
      authorize_if expr(not is_nil(actor(:id)))
    end
  end

  code_interface do
    define :connect
    define :read
  end
end
