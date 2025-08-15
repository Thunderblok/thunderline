defmodule Thunderline.Thunderblock.Resources.VaultCacheEntry do
  @moduledoc """
  CacheEntry Resource - High-Performance Caching Layer

  Manages cached data for improved performance across the Thunderline federation.
  Provides TTL-based expiration, cache invalidation, and hit/miss statistics.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  attributes do
    uuid_primary_key :id

    attribute :cache_key, :string do
      allow_nil? false
      description "Unique cache key"
      constraints max_length: 500
    end

    attribute :cache_value, :map do
      allow_nil? false
      description "Cached data"
      default %{}
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? true
      description "Cache expiration timestamp"
    end

    attribute :hit_count, :integer do
      allow_nil? false
      description "Number of cache hits"
      default 0
      constraints min: 0
    end

    attribute :last_hit_at, :utc_datetime do
      allow_nil? true
      description "Last cache hit timestamp"
    end

    attribute :cache_tags, {:array, :string} do
      allow_nil? false
      description "Tags for bulk cache invalidation"
      default []
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :set do
      description "Set cache entry"
      accept [:cache_key, :cache_value, :expires_at, :cache_tags]

      upsert? true
      upsert_identity :unique_cache_key
    end

    read :get do
      description "Get cache entry by key"
      argument :key, :string, allow_nil?: false
      filter expr(cache_key == ^arg(:key) and (is_nil(expires_at) or expires_at > now()))

      prepare fn query, _context ->
        Ash.Query.limit(query, 1)
      end
    end

    update :hit do
      description "Record cache hit"
      accept [:hit_count, :last_hit_at]
      require_atomic? false

      change fn changeset, _context ->
        current_hits = Ash.Changeset.get_attribute(changeset, :hit_count) || 0

        changeset
        |> Ash.Changeset.change_attribute(:hit_count, current_hits + 1)
        |> Ash.Changeset.change_attribute(:last_hit_at, DateTime.utc_now())
      end
    end

    destroy :clear_expired do
      description "Remove expired cache entries"
      filter expr(expires_at < now())
    end

    destroy :clear_by_tags do
      description "Remove cache entries by tags"
      argument :tags, {:array, :string}, allow_nil?: false
      filter expr(fragment("? && ?", cache_tags, ^arg(:tags)))
    end
  end

  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end
  #
  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  code_interface do
    define :set
    define :get, args: [:key]
    define :hit
    define :clear_expired, action: :clear_expired
    define :clear_by_tags, args: [:tags]
  end

  identities do
    identity :unique_cache_key, [:cache_key]
  end

  postgres do
    table "thunderblock_cache_entries"
    repo Thunderline.Repo

    custom_indexes do
      index [:cache_key], unique: true, name: "cache_entries_key_idx"
      index [:expires_at], name: "cache_entries_expires_idx"
      index "USING GIN (cache_tags)", name: "cache_entries_tags_idx"
    end
  end
end
