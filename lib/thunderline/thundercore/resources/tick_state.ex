defmodule Thunderline.Thundercore.Resources.TickState do
  @moduledoc """
  Persisted tick state snapshots.

  TickState captures periodic snapshots of system tick state for:

  - Audit trails and debugging
  - Recovery after restarts
  - Cross-node synchronization (future)

  ## Retention

  TickState records are ephemeral and should be pruned by Thunderwall's
  decay processor. Default retention is ~1 hour of system ticks.
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundercore.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "tick_states"
    repo Thunderline.Repo
  end

  admin do
    form do
      field :tick_id, type: :default
      field :tick_type, type: :default
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tick_id, :integer do
      allow_nil? false
      public? true
      description "Tick sequence number"
    end

    attribute :tick_type, :atom do
      allow_nil? false
      public? true
      description "Type of tick: :system, :slow, :fast"
      constraints one_of: [:system, :slow, :fast]
      default :system
    end

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "Wall clock time when tick was emitted"
    end

    attribute :monotonic_ns, :integer do
      allow_nil? false
      public? true
      description "Monotonic nanoseconds at tick emission"
    end

    attribute :epoch_ms, :integer do
      allow_nil? false
      public? true
      description "Milliseconds since TickEmitter start"
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "Optional tick metadata"
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_tick, [:tick_id, :tick_type]
  end

  actions do
    defaults [:read, :destroy]

    create :snapshot do
      description "Capture a tick state snapshot"
      accept [:tick_id, :tick_type, :timestamp, :monotonic_ns, :epoch_ms, :metadata]
    end

    read :recent do
      description "Get recent tick states"
      argument :limit, :integer, default: 100

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 100

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :by_type do
      description "Get tick states by type"
      argument :tick_type, :atom, allow_nil?: false
      argument :limit, :integer, default: 100

      filter expr(tick_type == ^arg(:tick_type))

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 100

        query
        |> Ash.Query.sort(tick_id: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    # Action for Thunderwall to prune old states
    action :prune_before_tick, :integer do
      description "Delete tick states older than given tick_id"
      argument :tick_id, :integer, allow_nil?: false

      run fn input, _context ->
        tick_id = input.arguments.tick_id

        # Use Ecto for bulk delete
        import Ecto.Query

        {count, _} =
          Thunderline.Repo.delete_all(
            from(t in "tick_states", where: t.tick_id < ^tick_id)
          )

        {:ok, count}
      end
    end
  end

  code_interface do
    define :snapshot
    define :recent, args: [{:optional, :limit}]
    define :by_type, args: [:tick_type, {:optional, :limit}]
    define :prune_before_tick, args: [:tick_id]
  end
end
