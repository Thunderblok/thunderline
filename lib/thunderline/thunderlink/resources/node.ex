defmodule Thunderline.Thunderlink.Resources.Node do
  @moduledoc """
  Node resource representing any participant in the Thunderline deployment.

  Tracks both:
  - BEAM nodes in the cluster (cluster_type: :in_cluster)
  - Out-of-cluster edge nodes (Hotline peers, devices) (cluster_type: :out_of_cluster)

  Status lifecycle:
  - :disconnected (initial/offline)
  - :connecting (handshake in progress)
  - :online (fully connected and healthy)
  - :degraded (connected but experiencing issues)
  - :offline (failed/disconnected)

  Used by Thunderlink Registry to provide topology visibility and coordination.
  """

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :role,
             :domain,
             :status,
             :cluster_type,
             :hotline_peer_id,
             :did,
             :last_seen_at,
             :last_heartbeat_at,
             :meta,
             :inserted_at,
             :updated_at
           ]}

  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "thunderlink_nodes"
    repo Thunderline.Repo

    references do
      reference :heartbeats, on_delete: :delete
      reference :link_sessions, on_delete: :delete
    end
  end

  graphql do
    type :thunderlink_node

    queries do
      get :get_node, :read
      list :list_nodes, :read
    end

    mutations do
      create :register_node, :register
      update :update_node_status, :update_status
    end
  end

  code_interface do
    define :register, args: [:name]
    define :by_name, args: [:name]
    define :online_nodes
    define :by_domain, args: [:domain]
    define :update_status, args: [:status]
    define :mark_online
    define :mark_degraded
    define :mark_offline
    define :heartbeat
  end

  actions do
    defaults [:read, :destroy]

    read :by_name do
      description "Find node by name"
      get_by :name
    end

    read :online_nodes do
      description "List all online nodes"
      filter expr(status == :online)
    end

    read :by_domain do
      description "List nodes by domain"

      argument :domain, :atom do
        allow_nil? false
      end

      filter expr(domain == ^arg(:domain))
    end

    create :register do
      description "Register a new node or update existing"
      upsert? true
      upsert_identity :unique_name
      accept [:name, :role, :domain, :cluster_type, :hotline_peer_id, :did, :meta]

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :status, :connecting)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :update_status do
      description "Update node status"
      accept [:status, :last_seen_at, :meta]

      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:connecting, :online, :degraded, :disconnected, :offline]
      end

      change fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :status)

        changeset
        |> Ash.Changeset.change_attribute(:status, status)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :mark_online do
      description "Mark node as online with link metadata"
      accept [:meta]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :online)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :mark_degraded do
      description "Mark node as degraded"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :degraded)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :mark_offline do
      description "Mark node as offline"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :offline)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :heartbeat do
      description "Update last_seen_at timestamp"

      change fn changeset, _context ->
        now = DateTime.utc_now()

        changeset
        |> Ash.Changeset.force_change_attribute(:last_seen_at, now)
        |> Ash.Changeset.force_change_attribute(:last_heartbeat_at, now)
      end
    end
  end

  policies do
    # Allow internal Ash system interactions (for Registry module)
    bypass always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Node name: 'thunderline@host' for BEAM nodes, 'crumb-01' for edge devices"
    end

    attribute :role, :atom do
      allow_nil? false
      default :worker
      public? true
      constraints one_of: [:controller, :worker, :edge, :gateway, :relay]
      description "Node role in the deployment"
    end

    attribute :domain, :atom do
      allow_nil? false
      default :thunderlink
      public? true

      constraints one_of: [
                    :thunderlink,
                    :thunderbolt,
                    :thunderflow,
                    :thunderprism,
                    :thundergrid,
                    :thunderblock,
                    :thunderchief,
                    :thundergate
                  ]

      description "Primary domain this node serves"
    end

    attribute :status, :atom do
      allow_nil? false
      default :disconnected
      public? true
      constraints one_of: [:connecting, :online, :degraded, :disconnected, :offline]
      description "Current connectivity status"
    end

    attribute :cluster_type, :atom do
      allow_nil? false
      default :in_cluster
      public? true
      constraints one_of: [:in_cluster, :out_of_cluster]
      description "Whether this is a BEAM cluster node or external peer"
    end

    attribute :hotline_peer_id, :string do
      public? true
      description "Hotline peer ID for out-of-cluster nodes"
    end

    attribute :did, :string do
      public? true
      description "Web5 DID if present"
    end

    attribute :last_seen_at, :utc_datetime_usec do
      public? true
      description "Last heartbeat or activity timestamp"
    end

    attribute :last_heartbeat_at, :utc_datetime_usec do
      public? true
      description "Timestamp of the most recent heartbeat"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Free-form metadata: region, version, tags, capabilities, etc."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :heartbeats, Thunderline.Thunderlink.Resources.Heartbeat do
      public? true
    end

    has_many :outgoing_sessions, Thunderline.Thunderlink.Resources.LinkSession do
      destination_attribute :node_id
      public? true
    end

    has_many :incoming_sessions, Thunderline.Thunderlink.Resources.LinkSession do
      destination_attribute :remote_node_id
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
