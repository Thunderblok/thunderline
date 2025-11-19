defmodule Thunderline.Thunderlink.Domain do
  @moduledoc """
  ThunderLink Ash Domain - Communication & Networking

  **Boundary**: "Link does delivery, not meaning" - No transformations beyond envelope/serialization

  Consolidated from: ThunderCom (communication), ThunderWave (wave processing)

  Core responsibilities:
  - Protocol bus, broadcast, and federation
  - Real-time communication infrastructure
  - Message routing and delivery
  - Channel and community management
  - WebRTC peer connections and real-time media
  - Cross-realm federation and networking
  - Voice/video chat infrastructure
  - P2P communication protocols
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain, AshOban.Domain, AshGraphql.Domain, AshTypescript.Rpc]

  admin do
    show? true
  end

  graphql do
    queries do
      # Create a field called `get_ticket` that uses the `read` action to fetch a single ticket
      get Thunderline.Thunderlink.Resources.Ticket, :get_ticket, :read

      # Create a field called `list_tickets` that uses the `read` action to fetch a list of tickets
      list Thunderline.Thunderlink.Resources.Ticket, :list_tickets, :read
    end

    mutations do
      # Create a new ticket
      create Thunderline.Thunderlink.Resources.Ticket, :create_ticket, :open

      # Close an existing ticket
      update Thunderline.Thunderlink.Resources.Ticket, :close_ticket, :close

      # Process a ticket (manual trigger)
      update Thunderline.Thunderlink.Resources.Ticket, :process_ticket, :process

      # Escalate a ticket (manual trigger)
      update Thunderline.Thunderlink.Resources.Ticket, :escalate_ticket, :escalate
    end
  end

  # Expose a minimal, least-privilege surface for ash_typescript RPC
  # This allows generating a type-safe client for selected actions only.
  typescript_rpc do
    resource Thunderline.Thunderlink.Resources.Ticket do
      # Read a list of tickets (no pagination/sort beyond what's supported by the action)
      rpc_action(:list_tickets, :read)
      # Open a new ticket
      rpc_action(:create_ticket, :open)
    end
  end

  resources do
    # Support → ThunderLink
    resource Thunderline.Thunderlink.Resources.Ticket
    # ThunderCom → ThunderLink
    resource Thunderline.Thunderlink.Resources.Channel
    resource Thunderline.Thunderlink.Resources.Community
    resource Thunderline.Thunderlink.Resources.FederationSocket
    resource Thunderline.Thunderlink.Resources.Message
    resource Thunderline.Thunderlink.Resources.Role

    # Voice/WebRTC
    resource Thunderline.Thunderlink.Voice.Room
    resource Thunderline.Thunderlink.Voice.Participant
    resource Thunderline.Thunderlink.Voice.Device

    # Node Registry & Cluster Topology
    resource Thunderline.Thunderlink.Resources.Node do
      # Code interfaces for Registry facade
      define :register_node, action: :register, args: [:name]
      define :mark_node_online, action: :mark_online
      define :mark_node_offline, action: :mark_offline
      define :mark_node_status, action: :update_status, args: [:status]
      define :online_nodes, action: :online_nodes
      define :nodes_by_status, action: :read
      define :nodes_by_role, action: :read
      define :heartbeat_node, action: :heartbeat
    end

    resource Thunderline.Thunderlink.Resources.Heartbeat do
      define :record_heartbeat, action: :record, args: [:node_id, :status]
      define :recent_heartbeats, action: :recent, args: [{:optional, :minutes}]
    end

    resource Thunderline.Thunderlink.Resources.LinkSession do
      define :active_link_sessions, action: :active_sessions
      define :establish_link_session, action: :mark_established
      define :update_link_session_metrics, action: :update_metrics
      define :close_link_session, action: :close
    end

    resource Thunderline.Thunderlink.Resources.NodeCapability do
      define :node_capabilities_by_capability, action: :read
    end

    resource Thunderline.Thunderlink.Resources.NodeGroup
    resource Thunderline.Thunderlink.Resources.NodeGroupMembership
  end

  authorization do
    # Enable authorization by default
    authorize :by_default
  end
end
