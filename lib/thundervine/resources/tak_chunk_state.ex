defmodule Thundervine.TAKChunkState do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshResource]

  postgres do
    table "tak_chunk_states"
    repo Thundervine.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :zone_id, :string, allow_nil?: false
    attribute :chunk_coords, {:array, :integer}, allow_nil?: false
    attribute :tick_id, :integer, allow_nil?: false
    attribute :state_snapshot, :map, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :by_zone_chunk, [:zone_id, :chunk_coords]
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
