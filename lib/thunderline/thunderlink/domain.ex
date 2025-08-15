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

  use Ash.Domain

  resources do
    # ThunderCom → ThunderLink (communication)
    resource Thunderline.Thunderlink.Resources.Channel
    resource Thunderline.Thunderlink.Resources.Community
    resource Thunderline.Thunderlink.Resources.FederationSocket
    resource Thunderline.Thunderlink.Resources.Message
    resource Thunderline.Thunderlink.Resources.PACHome
    resource Thunderline.Thunderlink.Resources.Role

    # Commented out until WebRTC implementation is available
    # resource Thunderlink.Resources.PeerConnection
    # resource Thunderlink.Resources.MediaStream
    # resource Thunderlink.Resources.SignalingChannel
    # resource Thunderlink.Resources.CallSession
    # resource Thunderlink.Resources.MediaDevice
    # resource Thunderlink.Resources.StreamRecording
  end
end
