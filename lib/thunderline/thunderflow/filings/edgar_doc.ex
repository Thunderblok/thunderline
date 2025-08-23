defmodule Thunderline.Filings.EDGARDoc do
  @moduledoc """
  Raw EDGAR filing (immutable).

  Domain Placement: Thunderflow (multi-source event & document ingestion) rather than Gate.
  Downstream feature windows & decision traces rely on this ingestion boundary.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "raw_edgar_docs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :cik, :string, allow_nil?: false
    attribute :form, :string, allow_nil?: false
    attribute :filing_time, :utc_datetime, allow_nil?: false
    attribute :period_end, :date
    attribute :sections, :map, allow_nil?: false, default: %{}
    attribute :xbrl, :map, allow_nil?: false, default: %{}
    attribute :hash, :binary, allow_nil?: false
    attribute :sections_redacted, :boolean, allow_nil?: false, default: false
    attribute :xbrl_hash, :binary
  end

  actions do
    defaults [:read]
    create :ingest do
      accept [:tenant_id, :cik, :form, :filing_time, :period_end, :sections, :xbrl, :hash, :sections_redacted, :xbrl_hash]
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  policies do
    policy action([:ingest, :read]) do
      authorize_if expr(tenant_id == actor(:tenant_id))
      authorize_if expr(actor(:role) == :system and actor(:scope) in [:maintenance])
    end
  end

  code_interface do
    define :ingest
    define :read
  end
end
