defmodule Thundervine.TAKChunkEvent do
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshResource]

  postgres do
    table "tak_chunk_events"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :zone_id, :string, allow_nil?: false
    attribute :chunk_coords, {:array, :integer}, allow_nil?: false
    attribute :tick_id, :integer, allow_nil?: false
    attribute :diffs, :map, allow_nil?: false
    attribute :rule_hash, :string, allow_nil?: false
    attribute :meta, :map
    create_timestamp :inserted_at
  end

  identities do
    identity :by_zone_tick, [:zone_id, :chunk_coords, :tick_id]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:zone_id, :chunk_coords, :tick_id, :diffs, :rule_hash, :meta]
    end
  end
end
