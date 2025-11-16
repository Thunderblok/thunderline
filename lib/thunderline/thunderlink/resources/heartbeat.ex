defmodule Thunderline.Thunderlink.Resources.Heartbeat do
  @moduledoc """
  Heartbeat resource - rolling record of node liveness and basic metrics.

  Created periodically by:
  - Registry.heartbeat/2 calls
  - Oban worker polling node health
  - Link layer when receiving keepalive packets

  Retention:
  - Full rows kept for configurable window (default: 24 hours)
  - Older records aggregated into per-node, per-interval summaries
  - Pruning handled by Oban compression job
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_heartbeats"
    repo Thunderline.Repo

    references do
      reference :node, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :node_id, :uuid do
      allow_nil? false
      public? true
      description "Node this heartbeat belongs to"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:online, :degraded, :offline]
      description "Node status at heartbeat time"
    end

    attribute :cpu_load, :float do
      public? true
      description "CPU load average (0.0 - 1.0+)"
    end

    attribute :mem_used_mb, :integer do
      public? true
      description "Memory used in megabytes"
    end

    attribute :latency_ms, :integer do
      public? true
      description "Network latency in milliseconds"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Additional metrics: disk usage, queue depth, etc."
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :node, Thunderline.Thunderlink.Resources.Node do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      description "Record a heartbeat"
      accept [:node_id, :status, :cpu_load, :mem_used_mb, :latency_ms, :meta]
    end

    read :for_node do
      description "Get heartbeats for a specific node"

      argument :node_id, :uuid do
        allow_nil? false
      end

      filter expr(node_id == ^arg(:node_id))
    end

    read :recent do
      description "Get heartbeats from the last N minutes (default 60)"
      argument :minutes, :integer, default: 60

      prepare before_action(fn query, _context ->
        cutoff = DateTime.add(DateTime.utc_now(), -query.arguments.minutes, :minute)
        require Ash.Query
        Ash.Query.filter(query, expr(inserted_at > ^cutoff))
      end)
    end

    read :old_heartbeats do
      description "Get heartbeats older than N hours for compression"

      argument :hours, :integer do
        allow_nil? false
        default 24
      end

      prepare before_action(fn query, _context ->
        cutoff =
          DateTime.utc_now()
          |> DateTime.add(-query.arguments.hours * 3600, :second)

        require Ash.Query
        Ash.Query.filter(query, expr(inserted_at < ^cutoff))
      end)
    end

    destroy :bulk_delete do
      description "Delete multiple heartbeats (for compression job)"
    end
  end

  policies do
    # Allow internal system access
    bypass always() do
      authorize_if always()
    end
  end

  code_interface do
    define :record, args: [:node_id, :status]
    define :for_node, args: [:node_id]
    define :recent, args: [:minutes]
    define :old_heartbeats, args: [:hours]
  end
end
