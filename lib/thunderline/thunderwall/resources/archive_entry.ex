defmodule Thunderline.Thunderwall.Resources.ArchiveEntry do
  @moduledoc """
  Archived resource entries for long-term storage.

  ArchiveEntries represent resources that have been archived (not destroyed)
  for potential future retrieval. Unlike DecayRecords which are ephemeral,
  ArchiveEntries are intended for longer-term retention.

  ## Use Cases

  - User-requested archival of PACs
  - Snapshot preservation for compliance
  - Debug snapshots of problematic states
  - Historical record keeping
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderwall.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "archive_entries"
    repo Thunderline.Repo
  end

  admin do
    form do
      field :resource_type, type: :default
      field :resource_id, type: :default
      field :archive_reason, type: :default
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :string do
      allow_nil? false
      public? true
      description "Original resource module/type name"
    end

    attribute :resource_id, :string do
      allow_nil? false
      public? true
      description "Original resource primary key (stringified)"
    end

    attribute :archive_reason, :atom do
      allow_nil? false
      public? true
      description "Reason for archival"
      constraints one_of: [:user_requested, :compliance, :debug, :migration, :system]
      default :system
    end

    attribute :snapshot, :map do
      allow_nil? false
      public? true
      description "Complete snapshot of archived resource"
    end

    attribute :archived_at_tick, :integer do
      allow_nil? true
      public? true
      description "System tick when archival occurred"
    end

    attribute :retention_days, :integer do
      allow_nil? true
      public? true
      description "How long to retain this archive (nil = forever)"
    end

    attribute :tags, {:array, :string} do
      default []
      public? true
      description "Tags for categorization and search"
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "Additional archive metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_archive, [:resource_type, :resource_id]
  end

  actions do
    defaults [:read, :destroy]

    create :archive do
      description "Archive a resource"
      accept [:resource_type, :resource_id, :archive_reason, :snapshot, :retention_days, :tags, :metadata]

      change fn changeset, _context ->
        tick =
          try do
            Thunderline.Thundercore.TickEmitter.current_tick()
          rescue
            _ -> nil
          catch
            :exit, _ -> nil
          end

        if tick do
          Ash.Changeset.change_attribute(changeset, :archived_at_tick, tick)
        else
          changeset
        end
      end
    end

    update :update_tags do
      description "Update archive tags"
      accept [:tags]
    end

    read :by_type do
      description "Find archives by resource type"
      argument :resource_type, :string, allow_nil?: false
      argument :limit, :integer, default: 100

      filter expr(resource_type == ^arg(:resource_type))

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 100

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :by_tag do
      description "Find archives by tag"
      argument :tag, :string, allow_nil?: false
      argument :limit, :integer, default: 100

      filter expr(^arg(:tag) in tags)

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 100

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :find_archive do
      description "Find specific archived resource"
      argument :resource_type, :string, allow_nil?: false
      argument :resource_id, :string, allow_nil?: false

      filter expr(resource_type == ^arg(:resource_type) and resource_id == ^arg(:resource_id))
    end
  end

  code_interface do
    define :archive
    define :update_tags
    define :by_type, args: [:resource_type, {:optional, :limit}]
    define :by_tag, args: [:tag, {:optional, :limit}]
    define :find_archive, args: [:resource_type, :resource_id]
  end
end
