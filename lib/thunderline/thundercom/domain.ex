defmodule Thunderline.Thundercom.Domain do
  @moduledoc """
  Thundercom Ash Domain - Community Infrastructure & Social Features

  Manages community building, social interaction, messaging, and collaborative
  features for the Thunderline ecosystem. Provides the social layer that makes
  Thunderblock instances feel like living, breathing communities.

  Core responsibilities:
  - Community management and governance
  - Channel organization and messaging
  - Role-based permissions and access control
  - Social features and user interaction
  - Cross-community federation and communication
  - Personal and collaborative spaces (PAC Homes)
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    # Voice / WebRTC MVP resources
    resource Thunderline.Thundercom.Resources.VoiceRoom
    resource Thunderline.Thundercom.Resources.VoiceParticipant
    resource Thunderline.Thundercom.Resources.VoiceDevice
  end
end
