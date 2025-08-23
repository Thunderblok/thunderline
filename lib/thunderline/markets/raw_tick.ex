defmodule Thunderline.Markets.RawTick do
  @moduledoc "Raw normalized market tick (immutable)."
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "raw_market_ticks"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :symbol, :string, allow_nil?: false
    attribute :ts, :integer, allow_nil?: false
    attribute :vendor_seq, :integer
    attribute :payload, :map, allow_nil?: false
  end

  actions do
    defaults [:read]
    create :ingest do
      accept [:tenant_id, :symbol, :ts, :vendor_seq, :payload]
    end
  end

  policies do
    policy action([:ingest, :read]) do
      authorize_if expr(not is_nil(actor(:id)))
    end
  end

  code_interface do
    define :ingest
    define :read
  end
end
