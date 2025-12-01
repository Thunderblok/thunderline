defmodule Thunderline.Thunderwall.Resources.DecayRecord do
  @moduledoc """
  Records of decayed/expired resources.

  DecayRecords track resources that have been marked for decay by the
  DecayProcessor. They serve as an audit trail and enable potential
  recovery of recently decayed data.

  ## Decay Lifecycle

  1. Resource exceeds TTL or is explicitly marked for decay
  2. DecayProcessor creates DecayRecord with original data
  3. Original resource is archived or deleted
  4. DecayRecord retained for configurable period
  5. GCScheduler prunes old DecayRecords

  ## Fields

  - `resource_type` - Original resource module name
  - `resource_id` - Original resource primary key
  - `decay_reason` - Why the resource was decayed
  - `snapshot` - JSON snapshot of resource at decay time
  - `decayed_at_tick` - System tick when decay occurred
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderwall.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "decay_records"
    repo Thunderline.Repo
  end

  admin do
    form do
      field :resource_type, type: :default
      field :resource_id, type: :default
      field :decay_reason, type: :default
    end
  end

  code_interface do
    define :record_decay
    define :by_type, args: [:resource_type, {:optional, :limit}]
    define :by_reason, args: [:decay_reason, {:optional, :limit}]
    define :prune_before, args: [:before]
  end

  actions do
    defaults [:read, :destroy]

    create :record_decay do
      description "Record a decayed resource"
      accept [:resource_type, :resource_id, :decay_reason, :snapshot, :metadata]

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
          Ash.Changeset.change_attribute(changeset, :decayed_at_tick, tick)
        else
          changeset
        end
      end
    end

    read :by_type do
      description "Find decay records by resource type"
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

    read :by_reason do
      description "Find decay records by reason"
      argument :decay_reason, :atom, allow_nil?: false
      argument :limit, :integer, default: 100

      filter expr(decay_reason == ^arg(:decay_reason))

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 100

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    action :prune_before, :integer do
      description "Prune decay records older than given datetime"
      argument :before, :utc_datetime, allow_nil?: false

      run fn input, _context ->
        before = input.arguments.before
        import Ecto.Query

        {count, _} =
          Thunderline.Repo.delete_all(from(d in "decay_records", where: d.inserted_at < ^before))

        {:ok, count}
      end
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

    attribute :decay_reason, :atom do
      allow_nil? false
      public? true
      description "Reason for decay"
      constraints one_of: [:ttl_expired, :explicit, :orphaned, :overflow, :gc, :system]
      default :ttl_expired
    end

    attribute :snapshot, :map do
      allow_nil? true
      public? true
      description "JSON snapshot of resource at decay time"
    end

    attribute :decayed_at_tick, :integer do
      allow_nil? true
      public? true
      description "System tick when decay occurred"
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "Additional decay metadata"
    end

    create_timestamp :inserted_at
  end
end
