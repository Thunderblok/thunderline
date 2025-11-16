defmodule Thunderline.Thunderlink.Resources.LinkSession do
  @moduledoc """
  LinkSession resource - represents connectivity path between nodes.

  Tracks:
  - BEAM node-to-node connections (cluster_type: :cluster)
  - Hotline/TOCP sessions to external peers (cluster_type: :hotline)
  - Service relationships (cluster_type: :service)

  Session lifecycle:
  - :establishing (handshake in progress)
  - :established (active connection)
  - :degraded (connection issues)
  - :closed (gracefully terminated)
  - :failed (error/timeout)

  Used by Registry to build the graph links for 3d-force-graph visualization.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_link_sessions"
    repo Thunderline.Repo

    references do
      reference :node, on_delete: :delete
      reference :remote_node, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :node_id, :uuid do
      allow_nil? false
      public? true
      description "Local node ID"
    end

    attribute :remote_node_id, :uuid do
      allow_nil? false
      public? true
      description "Remote node ID"
    end

    attribute :session_type, :atom do
      allow_nil? false
      default :cluster
      public? true
      constraints one_of: [:cluster, :hotline, :service, :tocp]
      description "Type of connection"
    end

    attribute :status, :atom do
      allow_nil? false
      default :establishing
      public? true
      constraints one_of: [:establishing, :established, :degraded, :closed, :failed]
      description "Session status"
    end

    attribute :weight, :float do
      default 1.0
      public? true
      description "Connection quality/importance (0.0 - 1.0)"
    end

    attribute :latency_ms, :integer do
      public? true
      description "Current latency in milliseconds"
    end

    attribute :bandwidth_mbps, :float do
      public? true
      description "Available bandwidth in Mbps"
    end

    attribute :established_at, :utc_datetime_usec do
      public? true
      description "When session was established"
    end

    attribute :last_activity_at, :utc_datetime_usec do
      public? true
      description "Last activity timestamp"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Session metadata: protocol version, cipher, peer info, etc."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :node, Thunderline.Thunderlink.Resources.Node do
      allow_nil? false
      public? true
    end

    belongs_to :remote_node, Thunderline.Thunderlink.Resources.Node do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :establish do
      description "Create a new link session"
      accept [:node_id, :remote_node_id, :session_type, :meta]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :establishing)
        |> Ash.Changeset.force_change_attribute(:last_activity_at, DateTime.utc_now())
      end
    end

    update :mark_established do
      description "Mark session as established"
      accept [:weight, :latency_ms, :bandwidth_mbps, :meta]

      change fn changeset, _context ->
        now = DateTime.utc_now()

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :established)
        |> Ash.Changeset.force_change_attribute(:established_at, now)
        |> Ash.Changeset.force_change_attribute(:last_activity_at, now)
      end
    end

    update :update_metrics do
      description "Update session metrics"
      accept [:weight, :latency_ms, :bandwidth_mbps]

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :last_activity_at, DateTime.utc_now())
      end
    end

    update :mark_degraded do
      description "Mark session as degraded"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :degraded)
        |> Ash.Changeset.force_change_attribute(:last_activity_at, DateTime.utc_now())
      end
    end

    update :close do
      description "Close session gracefully"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :closed)
        |> Ash.Changeset.force_change_attribute(:last_activity_at, DateTime.utc_now())
      end
    end

    update :mark_failed do
      description "Mark session as failed"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :failed)
        |> Ash.Changeset.force_change_attribute(:last_activity_at, DateTime.utc_now())
      end
    end

    read :for_node do
      description "Get all sessions for a node (outgoing and incoming)"

      argument :node_id, :uuid do
        allow_nil? false
      end

      filter expr(node_id == ^arg(:node_id) or remote_node_id == ^arg(:node_id))
    end

    read :active_sessions do
      description "Get all active (established) sessions"
      filter expr(status == :established)
    end
  end

  policies do
    # Allow internal system access
    bypass always() do
      authorize_if always()
    end
  end

  code_interface do
    define :establish, args: [:node_id, :remote_node_id, :session_type]
    define :mark_established
    define :update_metrics
    define :mark_degraded
    define :close
    define :mark_failed
    define :for_node, args: [:node_id]
    define :active_sessions
  end
end
