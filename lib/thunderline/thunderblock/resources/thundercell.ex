defmodule Thunderline.Thunderblock.Resources.Thundercell do
  @moduledoc """
  Thundercell Ash Resource - Universal Data Chunk for Automata Substrate

  Thundercells are the atomic units of data that Thunderbits operate on.
  They represent parsed, normalized chunks from any data source:
  - Files (text, logs, JSON, code)
  - Datasets (rows, batches)
  - Embeddings (vector blocks)
  - CA lattice cells

  ## Architecture

  ```
  Thunderforge (crawl/parse/encode)
       │
       ▼
  Thundercell (persisted here)
       │
       ▼
  Thunderbolt (Thunderbits bound to cells)
       │
       ▼
  Automata swarm (doctrine-driven rules)
  ```

  ## Relationship to Thunderbit

  - Thundercell = raw data chunk (what the data IS)
  - Thunderbit = automata cell (what we're DOING with the data)
  - One Thunderbit binds to one or more Thundercells
  - Many Thundercells can be grouped into zones

  ## Reference

  - HC Orders: Thunderforge-lite MVP
  - See: `Thunderline.Thunderbit.Thundercell` for the struct version
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "thundercells"
    repo Thunderline.Repo

    custom_indexes do
      index [:source], name: "thundercells_source_idx"
      index [:kind], name: "thundercells_kind_idx"
      index [:content_hash], unique: true, name: "thundercells_hash_idx"
      index [:zone_id], name: "thundercells_zone_idx"
      index "USING GIN (labels)", name: "thundercells_labels_idx"
      index "USING GIN (structure)", name: "thundercells_structure_idx"
    end
  end

  graphql do
    type :thundercell

    queries do
      get :get_thundercell, :read
      list :list_thundercells, :read
      list :thundercells_by_source, :by_source
      list :thundercells_by_kind, :by_kind
      list :thundercells_by_zone, :by_zone
    end
  end

  code_interface do
    define :create
    define :get, args: [:id], action: :read
    define :by_source, args: [:source_pattern]
    define :by_kind, args: [:kind]
    define :by_zone, args: [:zone_id]
    define :upsert_by_hash, args: [:content_hash]
    define :update_labels, args: [:id, :labels]
    define :update_features, args: [:id, :features]
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination keyset?: true, default_limit: 50, max_page_size: 200
    end

    create :create do
      accept [
        :source,
        :kind,
        :span,
        :raw,
        :content_hash,
        :structure,
        :features,
        :labels,
        :zone_id,
        :meta
      ]

      change fn changeset, _context ->
        # Auto-compute hash if not provided
        raw = Ash.Changeset.get_attribute(changeset, :raw)
        hash = Ash.Changeset.get_attribute(changeset, :content_hash)

        if raw && !hash do
          computed_hash = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
          Ash.Changeset.change_attribute(changeset, :content_hash, computed_hash)
        else
          changeset
        end
      end
    end

    create :upsert_by_hash do
      description "Create or update Thundercell by content hash (deduplication)"
      upsert? true
      upsert_identity :unique_hash

      accept [
        :source,
        :kind,
        :span,
        :raw,
        :content_hash,
        :structure,
        :features,
        :labels,
        :zone_id,
        :meta
      ]
    end

    update :update_labels do
      description "Update cell labels (tags from automata)"
      accept [:labels]
    end

    update :update_features do
      description "Update cell feature vector (from encoder)"
      accept [:features]
    end

    update :update_structure do
      description "Update parsed structure"
      accept [:structure]
    end

    read :by_source do
      description "Find cells by source path pattern"
      argument :source_pattern, :string, allow_nil?: false

      filter expr(contains(source, ^arg(:source_pattern)))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_kind do
      description "Find cells by kind"
      argument :kind, :atom, allow_nil?: false

      filter expr(kind == ^arg(:kind))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_zone do
      description "Find cells in a zone"
      argument :zone_id, :uuid, allow_nil?: false

      filter expr(zone_id == ^arg(:zone_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :unlabeled do
      description "Find cells without labels (need processing)"
      filter expr(is_nil(labels) or labels == [])
      prepare build(sort: [inserted_at: :asc], limit: 100)
    end

    read :unembedded do
      description "Find cells without feature vectors"
      filter expr(is_nil(features) or features == [])
      prepare build(sort: [inserted_at: :asc], limit: 100)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :string do
      allow_nil? false
      public? true
      description "Origin path/URI (file path, URL, etc.)"
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      description "Cell type"
      constraints one_of: [:text, :markdown, :log, :json, :code, :blob, :embedding, :ca_cell]
    end

    attribute :span, :map do
      public? true
      default %{}
      description "Location within source: {line, byte_range, page, etc.}"
    end

    attribute :raw, :string do
      public? true
      description "Raw text content (nil for binary/blob types)"
    end

    attribute :content_hash, :string do
      allow_nil? false
      public? true
      description "SHA256 hash for deduplication"
    end

    attribute :structure, :map do
      public? true
      default %{}
      description "Parsed structure (AST, schema, parsed log fields)"
    end

    attribute :features, {:array, :float} do
      public? true
      default []
      description "Feature vector (embedding or computed features)"
    end

    attribute :labels, {:array, :atom} do
      public? true
      default []
      description "Tags applied by automata (important, archived, needs_review, etc.)"
    end

    attribute :zone_id, :uuid do
      public? true
      description "Zone this cell belongs to (for swarm grouping)"
    end

    attribute :meta, :map do
      public? true
      default %{}
      description "Extensible metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_hash, [:content_hash]
  end

  calculations do
    calculate :has_features, :boolean, expr(not is_nil(features) and features != [])
    calculate :has_labels, :boolean, expr(not is_nil(labels) and labels != [])
    calculate :feature_dim, :integer, expr(fragment("COALESCE(array_length(?, 1), 0)", features))
  end
end
