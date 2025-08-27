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

  use Ash.Domain, extensions: [AshOban.Domain, AshGraphql.Domain]

  resources do
    # Support → ThunderLink (social/community features)
    resource Thunderline.Thunderlink.Resources.Ticket

    # ThunderCom → ThunderLink (communication)
    resource Thunderline.Thunderlink.Resources.Channel
    resource Thunderline.Thunderlink.Resources.Community
    resource Thunderline.Thunderlink.Resources.FederationSocket
    resource Thunderline.Thunderlink.Resources.Message
    resource Thunderline.Thunderlink.Resources.Role

  # Voice/WebRTC (migrated from Thundercom – Phase A)
  resource Thunderline.Thunderlink.Voice.Room
  resource Thunderline.Thunderlink.Voice.Participant
  resource Thunderline.Thunderlink.Voice.Device

    # Commented out until WebRTC implementation is available
    # resource Thunderlink.Resources.PeerConnection
    # resource Thunderlink.Resources.MediaStream
    # resource Thunderlink.Resources.SignalingChannel
    # resource Thunderlink.Resources.CallSession
    # resource Thunderlink.Resources.MediaDevice
    # resource Thunderlink.Resources.StreamRecording
  end

  authorization do
    # Enable authorization by default
    authorize :by_default
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
end
